# 快速鍵綁定鍵盤裝置實作計畫

狀態：執行中
建立日期：2026-08-28
依據：[DEVICE_BOUND_SHORTCUTS_SPEC.md](./DEVICE_BOUND_SHORTCUTS_SPEC.md)
目標版本：`1.1.0`

## 執行原則

- 先完成 Phase 0 技術驗證，取得 Go 結論後才修改正式功能。
- 採測試先行，每個階段先補失敗測試，再加入最小實作。
- 既有快速鍵預設維持「所有鍵盤」，不得要求既有使用者重新設定。
- 裝置專用功能失敗時保守停用，不得擴大為所有鍵盤。
- 不做無上限的事件時間猜測。來源裝置只接受 `IOHIDManager` 回報，並在短時間窗口內與 macOS 最終 `CGEvent` 語意配對；配對不明確時不觸發。
- 所有鍵盤輸入只在記憶體中即時比對，不保存、不上傳，也不寫入日誌。
- 每個階段獨立 Commit，完成驗證後才進入下一階段。

## Non-scope

- 不處理藍牙配對或裝置連線管理。
- 不支援鍵盤以外的 HID 裝置。
- 不提供按鍵重新對映、鍵盤配置轉換或整組設定檔。
- 不增加依 App、網站或模式切換的裝置規則。
- 不新增資料庫、iCloud 同步、外部服務或第三方套件。
- 不改動無關的錄音、轉錄、AI 潤飾與貼上流程。
- 本計畫不包含 `1.1.0` 的 Tag、GitHub Release 或正式發布。
- 第一版只驗收內建與 USB 鍵盤。藍牙保留相容資料但標示尚未驗證，不列入本次發布阻擋條件。

## 依賴關係

```text
Phase 0 技術驗證
  → 資料模型與純邏輯
    → 儲存與 migration
      → HID 裝置監聽
        → 執行期整合
          → 錄製器與設定介面
            → 權限、在地化與診斷
              → 完整驗證與文件
```

Phase 0 是強制閘門。其餘階段依序執行，不平行修改共用快速鍵核心。

## Phase 0：IOHID 技術可行性驗證

### 目標

以可丟棄原型驗證 macOS 是否能穩定辨識內建與 USB 鍵盤的來源裝置，並確認按鍵配對、權限與事件抑制限制。藍牙列為後續解除限制前的相容性驗證。

### 執行項目

1. 在 `/tmp` 建立獨立 Command Line 原型，不加入 Xcode 專案。
2. 使用 `IOHIDManager` 只比對 Generic Desktop Keyboard 與 Keyboard or Keypad usage。
3. 列出下列非敏感資訊：
   - Vendor ID。
   - Product ID。
   - Transport。
   - Product 名稱。
   - 是否有 Serial Number，但不得輸出序號內容。
   - 是否為內建鍵盤。
4. 監聽 `IOHIDValueCallback`，驗證 `IOHIDValueGetElement` 與 `IOHIDElementGetDevice` 可回溯正確來源。
5. 建立最小 HID usage 對照，測試一般鍵與左右修飾鍵，並驗證 macOS 每部鍵盤修飾鍵設定可能使 HID usage 與最終 Carbon virtual key code 不同。
6. 同時操作兩把鍵盤，確認每把鍵盤的修飾鍵狀態相互獨立。
7. 將藍牙鍵盤休眠、喚醒、斷線、重新連線與 App 重啟測試列為後續解除「尚未驗證」限制的必要工作。
8. 使用已簽署 Development Build 驗證：
   - `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` 狀態。
   - `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` 行為。
   - 系統設定「輸入監控」授權後 callback 是否正常。
9. 比對 HID callback 與 `CGEventTap` 的事件順序，判斷裝置專用快速鍵能否可靠抑制原始按鍵。

### 產出

新增 `docs/DEVICE_BOUND_SHORTCUTS_FEASIBILITY.md`，記錄：

- 測試硬體與連線方式。
- 可取得的穩定識別欄位。
- 按鍵與修飾鍵支援結果。
- 藍牙驗證狀態與尚未驗證限制。
- 權限行為。
- 事件抑制是否可靠。
- Go、Go with limitation 或 No-go 結論。

不得記錄原始序號、藍牙位址、完整按鍵內容或一般輸入歷史。

### Go 條件

- 來源裝置辨識在內建與 USB 鍵盤上正確，USB 路徑至少取得完整事件證據。
- 左右修飾鍵與一般按鍵可在有界時間內與現有 `Shortcut` 語意配對，配對不明確時會安全停止。
- 權限狀態可診斷，拒絕時能安全降級。
- 藍牙未完成實測前不宣告支援，也不阻擋第一版內建與 USB 功能。

若只能觸發而不能可靠抑制原始按鍵，需把限制寫入可行性文件、設定介面說明與 CHANGELOG 後才可繼續。

### 驗證

- 原型只輸出裝置加入、移除與測試用事件，不保存檔案。
- 實機手動核對內建、USB 與雙鍵盤同時輸入。藍牙另列後續相容性驗證。
- 結束原型後確認 callback 與 run loop 已釋放。

### Commit

```text
docs: record device-bound shortcut feasibility
```

## Phase 1：資料模型與解析規則

### 目標

先建立不依賴 IOKit 或 UI 的純值型別與解析規則，固定裝置範圍、優先順序與衝突語意。

### 新增檔案

- `VoiceInk/Shortcuts/ShortcutBinding.swift`
- `VoiceInk/Shortcuts/KeyboardDeviceIdentity.swift`
- `VoiceInk/Shortcuts/ShortcutBindingResolver.swift`

### 實作項目

1. 建立 `ShortcutBinding`：
   - `id: UUID`。
   - `shortcut: Shortcut`。
   - `scope: KeyboardScope`。
2. 建立 `KeyboardScope`：
   - `allKeyboards`。
   - `device(KeyboardDeviceReference)`。
3. 建立 `KeyboardDeviceReference`：
   - 不可逆 `fingerprint`。
   - Vendor ID、Product ID、Transport、顯示名稱與 `matchStrength`。
   - 不包含原始序號。
4. 使用系統內建 CryptoKit 的 SHA-256 建立指紋，不新增套件。
5. 系統內建鍵盤使用固定類型識別，不依賴可變顯示名稱。
6. 建立純邏輯 `ShortcutBindingResolver`：
   - 裝置專用優先於同動作的全域綁定。
   - 單一事件同一動作最多回傳一次。
   - 權限不足或來源未知時不匹配裝置專用綁定。
7. 建立範圍重疊判斷，供 Resolver 與 Validator 共用。
8. 型別若跨佇列傳遞，明確遵守 `Sendable`，不得用未檢查的 `@unchecked Sendable` 掩蓋 IOKit 生命週期問題。

### 測試先行

在 `VoiceInkTests` 新增獨立測試檔，避免繼續擴大單一 `VoiceInkTests.swift`：

- `ShortcutBindingResolverTests.swift`
- `KeyboardDeviceIdentityTests.swift`

測試案例：

- 指定裝置優先於同動作全域綁定。
- 不同裝置可使用相同按鍵。
- 全域範圍與指定裝置範圍正確判定重疊。
- 同一事件不重複回傳相同動作。
- 來源未知時只允許全域綁定。
- 權限拒絕時不啟用裝置專用綁定。
- 指紋輸入包含序號時，產出不得包含序號明文。
- `modelFamily` 只能比對同型號範圍。

### 驗證

```bash
xcodebuild test \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

### Commit

```text
feat: add device-scoped shortcut binding model
```

## Phase 2：版本化儲存與既有設定遷移

### 目標

新增多筆綁定儲存格式，並將現有快速鍵安全轉成「所有鍵盤」。

### 影響檔案

- `VoiceInk/Shortcuts/ShortcutStore.swift`
- `VoiceInk/Shortcuts/ShortcutMigration.swift`
- `VoiceInk/Shortcuts/ShortcutAction.swift`
- `VoiceInkTests/ShortcutBindingStoreTests.swift`
- `VoiceInkTests/ShortcutBindingMigrationTests.swift`

### 實作項目

1. 新增 `ShortcutBindingStore` 或等價深層模組，將 UserDefaults 注入，讓測試不使用正式 domain。
2. 儲存鍵採 `ShortcutBindings_v1_<action>`。
3. 提供明確 API：
   - `bindings(for:)`。
   - `setBindings(_:for:)`。
   - `upsertBinding(_:for:)`。
   - `removeBinding(id:for:)`。
   - `hasBindings(for:)`。
   - `allKeyboardBinding(for:)`。
4. 保留現有 `ShortcutStore.shortcut(for:)` 作為 migration 過渡 adapter，只回傳 `allKeyboards` 綁定。
5. 所有正式執行路徑逐步改用 binding API，避免只有裝置專用綁定時被誤判為未設定。
6. migration 規則：
   - 舊 `Shortcut_<action>` 轉成一筆 `allKeyboards`。
   - 舊 `_cleared` 狀態維持清除。
   - 新格式已存在時不得覆寫。
   - 新格式成功寫入後才設 migration marker。
   - 重複執行不得新增重複 UUID 或綁定。
7. 至少保留一個公開版本的舊格式唯讀回退。
8. Notification 仍以 `ShortcutAction` 為 object，避免既有觀察者失效；如需綁定 ID，放在 `userInfo`。

### 測試先行

- 每種既有 action 都轉成全域綁定。
- Mode UUID action 正確使用版本化鍵名。
- 已清除設定不復原。
- migration 重跑不新增資料。
- 新格式存在時不受舊格式覆寫。
- 刪除單筆裝置綁定不影響全域綁定。
- 同一裝置同一 action 重複 upsert 不產生重複資料。
- 破損 JSON 採保守回退並保留舊設定，不寫入空集合覆蓋。

### 驗證

- 執行完整 `VoiceInkTests`。
- 使用隔離的 UserDefaults suite 檢查 migration 前後資料。
- `git diff --check`。

### Commit

```text
feat: migrate shortcuts to versioned bindings
```

## Phase 3：HID 鍵盤識別與事件監聽

### 目標

將 Phase 0 驗證結果轉成正式、單一實例且可安全取消的鍵盤裝置服務。

### 新增檔案

- `VoiceInk/Shortcuts/KeyboardDeviceMonitor.swift`
- `VoiceInk/Shortcuts/HIDKeyboardUsageMapper.swift`
- `VoiceInk/Shortcuts/KeyboardInputPermission.swift`
- `VoiceInkTests/HIDKeyboardUsageMapperTests.swift`
- `VoiceInkTests/KeyboardDeviceStateTests.swift`

### 實作項目

1. `KeyboardDeviceMonitor` 僅由 App 組合根建立一個實例，再注入快速鍵管理元件。
2. 使用專用序列 DispatchQueue 管理 `IOHIDManager`、裝置表與每裝置按鍵狀態。
3. 在啟用前註冊：
   - Device matching callback。
   - Device removal callback。
   - Input value callback。
   - Cancel handler。
4. callback context 的生命週期由 monitor 單一擁有，取消完成前不得釋放。
5. 只接受鍵盤 usage page，忽略滑鼠、Consumer Control 與其他 HID，除非 Phase 0 證明功能鍵需要明確納入且 Spec 已補充。
6. 每把鍵盤各自追蹤修飾鍵與按下狀態。
7. 產出不可變 `KeyboardInputEvent`，內容只包含比對所需欄位與來源指紋。
8. 不在 callback 讀寫 UserDefaults、記錄鍵碼或同步呼叫 Main Actor。
9. 裝置移除、監聽取消、權限撤銷與 callback 錯誤時清除該裝置狀態。
10. Device list 對 UI 發布時只提供安全的顯示資訊、連線狀態與 `matchStrength`。

### 測試策略

IOHID C API 以窄介面包裝，核心狀態機使用可注入的測試事件：

- 左右修飾鍵分開維護。
- 不同裝置的修飾鍵不混用。
- Key down、重複 key down、key up 轉換正確。
- 裝置移除會合成必要的 release 或重設事件。
- callback 取消後不再發布事件。
- 不支援的 usage 被忽略。

### 驗證

- 單元測試通過。
- 內建與 USB 鍵盤執行裝置加入與移除 smoke test。藍牙另列後續相容性驗證。
- Instruments 或 Xcode Memory Graph 確認反覆啟停沒有 monitor 或 callback 洩漏。

### Commit

```text
feat: monitor keyboard input by HID device
```

## Phase 4：裝置範圍衝突驗證

### 目標

讓所有儲存入口使用一致的按鍵與範圍衝突規則。

### 影響檔案

- `VoiceInk/Shortcuts/ShortcutValidator.swift`
- `VoiceInk/Shortcuts/ShortcutBindingResolver.swift`
- `VoiceInkTests/ShortcutBindingValidatorTests.swift`

### 實作項目

1. Validator 輸入改為 candidate binding 與 action，不只接受裸 `Shortcut`。
2. 保留既有一般鍵、Shift 單鍵、功能鍵與 macOS 保留快速鍵規則。
3. 將範圍重疊規則集中為共用純函式：
   - `allKeyboards` 與任何裝置重疊。
   - 相同唯一指紋重疊。
   - 相同 `modelFamily` 範圍重疊。
   - 可證明不同裝置時不重疊。
4. 同一 action 的裝置專用覆蓋全域綁定合法。
5. 不同 action 的相同按鍵只在範圍重疊時拒絕。
6. Recorder panel 保留按鍵仍視為所有鍵盤範圍。
7. 錯誤回傳衝突 action 與範圍，UI 不自行重算。

### 測試先行

- 建立完整衝突矩陣測試。
- 每條規則包含允許與拒絕案例。
- 驗證 mode action 與全域 utility action 交叉衝突。
- 驗證同型號無序號鍵盤的保守衝突判定。

### Commit

```text
feat: validate shortcuts across device scopes
```

## Phase 5：執行期整合與單次觸發保證

### 目標

將裝置專用事件接入既有錄音、模式與工具快速鍵，同時保留現有全域快速鍵行為。

### 影響檔案

- `VoiceInk/Shortcuts/ShortcutMonitor.swift`
- `VoiceInk/Shortcuts/RecordingShortcutManager.swift`
- `VoiceInk/Shortcuts/ModeShortcutManager.swift`
- `VoiceInk/Shortcuts/RecorderPanelShortcutManager.swift`
- App 組合根，例如 `VoiceInk/VoiceInk.swift`
- 對應 runtime 測試

### 實作項目

1. 由同一個 `KeyboardDeviceMonitor` 提供可取消 subscription，三個快速鍵管理元件不得各自建立 IOHIDManager。
2. 全域綁定維持既有 `CGEventTap` 路徑。
3. 裝置專用綁定只接受含來源指紋的 HID 事件。
4. 設定變更時原子重建 binding index，再切換 subscription，避免短暫重複觸發。
5. 為每次實體 transition 建立短生命週期 event token，只用於去重，不保存輸入歷史。
6. `pushToTalk` 與 `hybrid` 必須在相同裝置收到 key up 才結束。
7. 裝置移除時若該裝置有按下中的錄音快速鍵，執行安全 release 或 interruption，避免錄音卡住。
8. `RecordingShortcutManager.isShortcutConfigured` 改用 `hasBindings(for:)`。
9. 中鍵錄音維持原路徑，不依賴輸入監控權限。
10. 若 Phase 0 判定無法可靠抑制裝置專用按鍵，程式不得用時間猜測補救。

### 測試先行

- 同一實體按鍵只觸發一次。
- Device binding 命中時不再觸發同 action 的全域 binding。
- 來源鍵盤不同時不觸發。
- `pushToTalk` 的 down 與 up 不可跨裝置配對。
- 裝置中途移除不留下錄音 pressed state。
- CGEvent Tap timeout 與 HID reset 後狀態一致。
- 權限拒絕時既有全域快速鍵與中鍵錄音仍可用。

### 驗證

- 完整單元測試。
- 以備忘錄執行 toggle、push-to-talk、hybrid 與 utility actions 實機測試。
- 雙鍵盤同時按鍵，確認無重複觸發或交叉 release。

### Commit

```text
feat: route shortcuts by keyboard device
```

## Phase 6：快速鍵錄製器與設定介面

### 目標

讓使用者能查看、新增、編輯與刪除裝置專用快速鍵，並清楚辨識裝置與連線狀態。

### 新增檔案

- `VoiceInk/Shortcuts/KeyboardDevicePicker.swift`
- `VoiceInk/Shortcuts/ShortcutBindingEditor.swift`
- 視畫面複雜度拆分 `ShortcutBindingRow.swift`

### 影響檔案

- `VoiceInk/Shortcuts/ShortcutRecorder.swift`
- `VoiceInk/Views/Settings/SettingsView.swift`
- `VoiceInk/Modes/ModeTriggerSection.swift`
- `VoiceInk/Views/History/HistoryShortcutTipView.swift`
- `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift`
- Onboarding 的快速鍵錄製畫面

### 實作項目

1. 先將 `ShortcutRecorder` 改為編輯指定 binding，不在開始錄製時立即清除既有設定。
2. 只有成功錄製並通過驗證後才原子替換 binding；取消錄製時保留舊值。
3. 既有畫面預設只顯示全域 binding，保持目前資訊密度。
4. 提供「新增裝置專用快速鍵」，展開該 action 的多筆 binding。
5. 裝置選單顯示：
   - 所有鍵盤。
   - 已連線鍵盤。
   - 已儲存但未連線鍵盤。
6. 指定裝置錄製時，只接受該裝置事件，提示文字包含裝置名稱。
7. 無唯一識別資訊時，顯示同型號套用警告。
8. 刪除單筆 binding 前不需整體確認；移除整個裝置紀錄且影響多筆 binding 時才顯示影響數量。
9. 每個互動提供 VoiceOver label、value、help，並可用鍵盤完成。
10. 不使用 Emoji 或只用顏色表示狀態。

### UI 驗證

- 快速鍵只有一筆時不增加不必要的高度。
- 多筆 binding 展開後仍能辨認 action、裝置、按鍵與狀態。
- 長裝置名稱可截斷，但 VoiceOver 讀出完整名稱。
- Light、Dark 模式及不同視窗寬度均不截斷主要操作。
- 內建、USB 與未連線狀態均有文字標示；偵測到藍牙鍵盤時標示「尚未驗證」且不開放正式綁定。

### 測試

- 錄製取消保留舊 binding。
- 非指定裝置輸入不完成錄製。
- 成功錄製後只更新目標 binding。
- 刪除裝置 binding 不影響全域 binding。
- 設定變更後 runtime 無須重啟即更新。

### Commit

```text
feat: add keyboard scope controls to shortcuts
```

## Phase 7：輸入監控權限、在地化與診斷

### 目標

只在需要裝置專用功能時請求權限，提供清楚且保守的錯誤處理。

### 影響檔案

- `VoiceInk/Shortcuts/KeyboardInputPermission.swift`
- `VoiceInk/Views/Settings/SettingsView.swift`
- `VoiceInk/Views/Onboarding/OnboardingPermissionModels.swift`，僅共用狀態型別時修改
- `VoiceInk/Views/Onboarding/OnboardingPermissionController.swift`，原則上不加入首輪必要權限
- `VoiceInk/Views/Settings/DiagnosticsSettingsView.swift`
- String Catalog

### 實作項目

1. 建立三態以上權限模型：granted、denied、unknown，必要時補 restricted。
2. 新增裝置專用 binding 時才呼叫 `IOHIDRequestAccess`。
3. 既有使用者升級與只使用全域 binding 時不主動要求輸入監控。
4. denied 時保留設定、停用裝置專用 runtime，提供「開啟系統設定」。
5. 系統設定 URL 先在目標 macOS 版本驗證，失敗時開啟隱私與安全性首頁，不靜默失敗。
6. App 回到前景時重新檢查權限，避免要求重啟才能恢復。
7. 診斷資訊只顯示：
   - 輸入監控權限狀態。
   - HID monitor 是否運作。
   - 已連線鍵盤數量。
   - 裝置專用 binding 數量。
8. 不顯示或複製序號、指紋、鍵碼與按鍵歷史。
9. 新字串加入英文與台灣繁體中文，繁體中文用詞採「輸入監控」「鍵盤」「藍牙」「未連線」。

### 測試

- granted、denied、unknown 狀態映射。
- denied 不啟用裝置 binding，也不影響全域 binding。
- App activation 後權限狀態刷新。
- 診斷輸出不包含 fingerprint、serial、keyCode 或 modifierFlags。
- 所有新 UI 字串均有繁體中文值。

### Commit

```text
feat: add input monitoring permission flow
```

## Phase 8：完整驗證、自查與文件

### 目標

使用 Spec 內同一份 Preflight Checklist 完成回歸驗證，確認沒有越界或隱私退化。

### 自動化驗證

```bash
git diff --check

xcodebuild test \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  -skipMacroValidation

xcodebuild build \
  -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -configuration Release \
  -skipPackagePluginValidation \
  -skipMacroValidation
```

### 實機驗證矩陣

| 情境 | 內建鍵盤 | USB 鍵盤 | 藍牙鍵盤 |
|---|---:|---:|---:|
| 裝置列舉與名稱 | 必測 | 必測 | 後續驗證 |
| 裝置專用 toggle | 必測 | 必測 | 後續驗證 |
| push-to-talk down/up | 必測 | 必測 | 後續驗證 |
| hybrid 短按與長按 | 必測 | 必測 | 後續驗證 |
| 斷線與重新連線 | 不適用 | 必測 | 後續驗證 |
| 休眠與喚醒 | 必測 | 選測 | 後續驗證 |
| 權限撤銷後降級 | 必測 | 必測 | 後續驗證 |

另測：

- 兩把鍵盤同時按下不同修飾鍵。
- 相同快速鍵分配給不同裝置與不同 action。
- 只有裝置 binding、只有全域 binding、兩者並存。
- Mode、歷史記錄、詞典與取消錄音快速鍵。
- 中鍵錄音不受影響。
- Light、Dark、VoiceOver 與全鍵盤操作。

### Preflight 完工自查

逐項回到 Spec 的 `Preflight Checklist（feature-specific）` 勾選，並為每一項附上：

- 測試名稱或輸出摘要。
- 對應程式碼檔案。
- 實機驗證結果。
- 尚未解決的限制。

任何未勾選項目不得以「之後再處理」直接略過，需明確判定為阻擋發布或列入已知限制並取得確認。

### 文件更新

- 將 Spec 狀態改為「已實作」。
- 將本計畫狀態改為「已完成」，附測試摘要與日期。
- 更新 README 的快速鍵與隱私說明。
- 更新 CHANGELOG，包含輸入監控權限與裝置辨識限制。
- 若裝置專用按鍵無法抑制，必須在設定介面與 CHANGELOG 同時揭露。

### Commit

```text
docs: document device-bound shortcuts
```

## 完成定義

只有同時符合以下條件才可宣告完成：

- Phase 0 為 Go 或經確認的 Go with limitation。
- 所有自動化測試與 Release Build 通過。
- 既有快速鍵 migration、全域綁定與中鍵錄音沒有 regression。
- 內建與 USB 鍵盤完成實機驗證。
- 藍牙在介面與文件中維持尚未驗證，不對外宣告正式支援。
- 權限拒絕、撤銷與重新授權流程通過。
- 沒有保存或記錄原始序號、一般按鍵內容與按鍵歷史。
- Spec 的 Preflight Checklist 已逐項附證據完成。
- README、CHANGELOG、Spec 與實作計畫符合實際行為。

## 建議執行批次

為控制風險，建議分三個人工確認點：

1. Phase 0 完成後確認 Go 或 No-go。
2. Phase 5 完成後確認底層觸發、去重與錄音模式沒有 regression。
3. Phase 7 完成後確認 UI、權限文案與隱私揭露，再進入完整驗證。

若 Phase 0 為 No-go，停止後續階段，只保留可行性文件，不提交原型或半成品正式程式碼。
