# 裝置綁定快速鍵技術可行性紀錄

## 文件狀態

- 日期：2026-08-28。
- 階段：Phase 0 已完成，第一版範圍為內建與 USB 鍵盤。
- 結論：Go with limitation，可進入正式功能實作。
- 原型位置：`/tmp/wagong-hid-probe`，不納入 Xcode 專案與版本控制。

## 驗證目的

確認 Wa-Gong 能否透過 `IOHIDManager` 辨識實體鍵盤來源，將 HID 來源與現有 `Shortcut` 語意配對，並釐清輸入監控權限與原始按鍵抑制限制。第一版以內建與 USB 鍵盤為範圍，藍牙另列後續驗證。

## 測試環境與硬體

- MacBook 內建鍵盤：`Apple Internal Keyboard / Trackpad`，SPI 連線。
- 外接鍵盤：`Majestouch Convertible 2`，本次以 USB 連線。
- 藍牙鍵盤：本次測試時未連線，第一版不宣告支援。
- 系統可同時列出內建鍵盤與 USB 外接鍵盤。

本文件不記錄原始序號、藍牙位址、完整裝置指紋或一般輸入歷史。

## 原型範圍

原型只執行下列工作：

1. 以 Generic Desktop Keyboard 條件建立 `IOHIDManager`。
2. 列出產品名稱、Transport、Vendor ID、Product ID、是否為內建鍵盤與是否存在序號。
3. 透過 `IOHIDValueCallback` 取得 `IOHIDElement` 及其來源 `IOHIDDevice`。
4. 僅接受 Keyboard or Keypad usage page 且 usage 位於 `0x04...0xE7` 的事件。
5. 將常用一般鍵與左右修飾鍵轉為 Carbon virtual key code。
6. 事件只輸出至終端機，不保存檔案，達到指定事件數後結束。

## 已驗證結果

### 裝置列舉

- 成功列出 SPI 內建鍵盤與 USB 外接鍵盤。
- 可取得 Product、Transport、Vendor ID、Product ID、Built-in 與序號是否存在等欄位。
- 外接鍵盤本次沒有可用序號，因此永久識別策略不能只依賴序號。

### 來源裝置辨識

- USB 外接鍵盤的 Input Value callback 可回溯至正確的 `IOHIDDevice`。
- 多組一般鍵與修飾鍵事件都被辨識為 `Majestouch Convertible 2`，沒有誤標為內建鍵盤。
- 內建鍵盤雖可列舉，但尚未取得由內建鍵盤實際輸入的 callback 證據。

### 按鍵轉換

- 已驗證字母鍵、數字鍵、Delete 與部分修飾鍵的 HID usage 可映射至 Carbon virtual key code。
- 實測事件包含 `Z`、`H`、`Delete`，映射結果符合既有 macOS 鍵碼語意。
- 初版 callback 會收到 HID collection 等非按鍵資料。加入 Keyboard or Keypad usage page 與 `0x04...0xE7` 範圍過濾後，已排除該類雜訊。
- 外接鍵盤送出的 HID 左 Option usage，在 macOS 最終 `CGEvent` 中呈現為不同的修飾鍵碼。這表示使用者或鍵盤韌體的修飾鍵對映會作用於 HID 與 `CGEventTap` 之間，不能把 HID usage 固定轉成 Carbon virtual key code 後當作唯一匹配依據。
- 正式設計需分開保存「來源裝置」與「macOS 最終快速鍵語意」。錄製及執行時應以有界時間與事件順序配對 HID 來源和 `CGEventTap`，不可用固定修飾鍵對照覆蓋 macOS 的每部鍵盤設定。

### 輸入監控權限

- 未授權時，`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` 回報拒絕，`IOHIDManagerOpen` 無法開始監聽。
- 呼叫 `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` 後，系統允許授權，重新執行時可診斷為已授權並正常收到 callback。
- 權限拒絕時可安全停止裝置專用監聽，不影響既有全鍵盤快速鍵設計。

### HID callback 與 CGEventTap 順序

- USB 外接鍵盤的多組按下與放開事件，均先收到 HID callback，之後才收到 `CGEventTap` callback。
- HID usage 映射後的 Carbon virtual key code 與 `CGEventTap` 的 key code 相同。
- HID 與 `CGEvent` 原始時間戳記的量級不同，不能直接假設兩者使用相同時間基準。
- 本機 `mach_timebase_info` 為 `125/3`。將實測 `CGEvent` 時間戳記依此反向換算後，會落在對應 HID 事件附近，可作為後續有界配對驗證依據，但仍需確認正確 API 時間單位與容許誤差。
- 以 callback 收到時間進行初步配對時，多組一般鍵在 50 毫秒窗口內成功找到相同來源，觀察到的 callback 間隔約為數百微秒至 20 毫秒。
- 目前只證明單一外接鍵盤、低速輸入時的 callback 順序，尚未證明在雙鍵盤同時輸入、快速連按或系統高負載時仍可無誤配地抑制事件。

## 尚待驗證

- 內建鍵盤的實際事件來源是否持續正確。
- 左右 `Command`、`Option`、`Control`、`Shift` 與 `Fn` 的完整映射。
- 修飾鍵經 macOS 每部鍵盤設定重新對映時，HID 與 `CGEventTap` 的可靠配對策略。
- 兩把鍵盤同時輸入時，各自的修飾鍵狀態是否隔離。
- USB 鍵盤拔除、重新插入與 App 重啟後的識別穩定性。
- 藍牙鍵盤首次連線、休眠、喚醒、斷線與重新連線後的識別穩定性。
- 相同型號且沒有序號的多把鍵盤，是否能採取可理解且保守的匹配策略。
- 已簽署 Development Build 的輸入監控授權、撤銷與重新授權流程。
- 雙鍵盤同時輸入與系統高負載時的 HID callback、`CGEventTap` 配對，以及裝置專用快速鍵能否可靠抑制原始按鍵。
- 原型結束、裝置移除與 App 結束時，callback、排程來源與 run loop 的生命週期清理。

## Go with limitation 判斷

目前證據已支持下列事項：

- `CGEvent` 以外的 `IOHIDManager` 路徑能提供 USB 鍵盤的實體來源裝置。
- HID usage 可轉為 Wa-Gong 現有的 Carbon 鍵碼語意。
- 輸入監控權限可被程式診斷，拒絕時可設計安全降級。
- USB 外接鍵盤的 HID callback 會先於對應的 `CGEventTap` callback 抵達，具備進一步驗證有限時間配對與事件抑制的條件。
- 裝置來源與 macOS 最終快速鍵語意必須分開處理，固定 HID usage 至 Carbon 鍵碼表不足以支援不同鍵盤配置。

第一版已調整為內建與 USB 鍵盤範圍。USB 鍵盤已完成來源辨識、一般鍵配對與權限降級驗證，因此可進入正式資料模型與純邏輯實作。

目前採 Go with limitation，限制如下：

- 內建鍵盤雖已成功列舉，實際輸入來源仍須在發布前完成實機驗證。
- USB 拔除、重新插入、雙鍵盤同時輸入與正式 App 權限流程仍是發布 Gate。
- 裝置專用按鍵的實際抑制尚未通過完整壓力測試。正式實作只能使用短時間、有上限且唯一的配對；不明確時不得觸發或誤攔截。
- 藍牙休眠、喚醒與重新連線尚未驗證，第一版不得在介面或發行文件宣告正式支援。

## 下一輪實機驗證

1. 在內建鍵盤輸入指定的一般鍵與左右修飾鍵，核對來源與映射。
2. 同時按住外接鍵盤修飾鍵並在內建鍵盤輸入，反向再測一次。
3. 建立已簽署 Development Build，測試權限首次要求、拒絕、授權與撤銷。
4. 以正式實作量測 HID callback 與 `CGEventTap` 配對及抑制，包含快速連按與高負載。
5. 日後取得藍牙操作條件後，記錄連線、休眠、喚醒、斷線、重連與 App 重啟結果，再決定是否解除藍牙限制。
