# 聲筆 Wa-Gong 功能實作計畫

更新日期：2026-08-26

本文件是本輪功能開發的執行依據。每個功能都必須先建立測試，再實作程式碼，驗證通過後獨立建立一個 Git commit。

## 1. 基礎決策

- 主要基底：`Beingpax/VoiceInk`。
- 功能參考：`opass/VoiceTwInk`。
- App 名稱：`聲筆 Wa-Gong`。
- Bundle ID：`com.jackie-yeh.wagong`。
- Swift module name：`VoiceInk`，暫時保留以維持 Xcode target 與既有測試的結構相容性；主要 Swift 型別識別字已改為 Wa-Gong 名稱。
- 品牌基準 commit：`7549938 chore: establish Wa-Gong app identity`。
- 不整批合併 `VoiceTwInk`，只依目前 VoiceInk 架構逐項移植需要的功能。

## 2. Non-scope

- 不上架 Mac App Store。
- 不建立 App Store Connect App。
- 不建立訂閱、付費授權、帳號或自有後端。
- 不建立遙測服務。
- 不移植 iOS 鍵盤程式碼至 macOS。
- 不刪除既有 Provider，除非確認有資安、授權或建置問題。
- 不新增與本輪需求無關的第三方套件。
- 不在沒有實測資料前，直接把新的本地模型設為預設模型。
- 不把剪貼簿內容傳送給任何 LLM Provider。

## 3. 執行規則

每個功能固定依序執行：

1. 讀取現有實作與資料流。
2. 先新增會失敗的行為測試。
3. 執行測試，確認測試能捕捉原始缺陷。
4. 實作最小修改。
5. 執行相關測試、Build 與必要的 UI 測試。
6. 更新本文件的狀態與驗證結果。
7. 建立只包含該功能的 commit。

預計 commit 邊界：

- `docs: define Wa-Gong feature implementation plan`
- `fix: default transcription to automatic language detection`
- `fix: prevent clipboard context from reaching llm providers`
- `feat: add default text refinement modes`
- `feat: add openai transcription provider`
- `feat: verify recording shortcuts and cursor delivery`
- `feat: improve custom vocabulary handling`
- `test: add local model comparison fixtures`

## 4. 階段一：語言預設與模型相容性

狀態：程式實作完成，`VoiceInkTests` 單元測試已實際通過，實機語言與模型品質比較待人工驗證

### 目標

修正英文預設問題，並避免使用 English-only 模型處理中文語音。

### 實作內容

- 預設語言由 `en` 改為 `auto`。
- 語言排序固定為 `Auto-detect`、`Chinese (Taiwan)`、`English`、`Japanese`、`Korean`、其他語言。
- 新增 `zh-TW` UI 語言識別字。
- 送至 Whisper 或 OpenAI 相容 API 前，將 `zh-TW` 轉換成 `zh`。
- `auto` 不加入中文種子提示詞，避免英文語音被翻譯成中文。
- 明確選擇 `zh-TW` 時，才使用台灣繁體中文提示詞。
- English-only 模型顯示相容性提示，不假裝支援中文。
- 對既有 `en` 設定採一次性遷移到 `auto`，但保留使用者明確選擇的語言。

### 測試

- 新安裝預設語言是 `auto`。
- 既有 `en` 設定可以安全遷移。
- 語言排序固定，不受 Dictionary 排序影響。
- English-only 模型不接受中文語言。
- 多語言模型可選擇中文、英文與 Auto-detect。
- Whisper 的 `zh-TW` API 邊界值為 `zh`。
- 純中文、純英文與中英混合輸入都保留原本語言。

### 本階段驗證結果

- [x] 測試先建立，先確認原始程式缺少預期語言 API，再補上實作。
- [x] `auto` 預設值、既有 `en` 遷移、語言排序、English-only fallback 與 `zh-TW` API 邊界測試已加入。
- [x] `xcodebuild build-for-testing` 通過。
- [x] 使用 `xcodebuild test-without-building` 實際執行 `VoiceInkTests`，共 22 項測試通過，0 失敗、0 跳過；結果由 `xcresulttool` 確認。

### 待人工決定或驗證

- 預設本機模型已改為 Whisper Base（`ggml-base`），支援中文與多語言；首次設定流程也會下載 Whisper Base。
- 需要實際下載模型，使用純中文、純英文與中英混合語音驗證辨識品質。
- 需要在具備麥克風與 Accessibility 權限的實機確認語言設定變更後的錄音與插入流程。

## 5. 階段二：剪貼簿隔離與隱私透明度

狀態：剪貼簿隔離、外部 Request HUD 與取消後的流程阻擋已完成，單元測試已通過，實機驗證待處理

### 資料政策

- 剪貼簿永遠不傳送給 LLM。
- `CursorPaster` 只可暫時寫入轉錄結果，並依設定還原原本剪貼簿。
- 貼上用的剪貼簿 Snapshot 與 LLM Context Snapshot 分離。
- 選取文字、畫面 OCR、自訂詞彙與系統 Context 各自有獨立開關。
- Privacy HUD 顯示資料類型、目的地與是否傳送，預設不顯示敏感資料全文。
- 錄音取消後不得繼續轉錄、整理、傳送或插入。

### 本階段目前驗證結果

- [x] 先加入測試，確認啟用選取文字與畫面 OCR 時仍可產生 Context，剪貼簿內容不會進入 Context。
- [x] 移除錄音 Context Snapshot 的剪貼簿欄位與擷取工作。
- [x] 保留 `CursorPaster` 的剪貼簿暫存、貼上與原內容還原流程。
- [x] 舊模式設定的剪貼簿欄位保留解碼相容性，但執行期固定為停用，設定畫面不再提供剪貼簿 Context 開關。
- [x] 共用 AI Prompt 不再描述或引用剪貼簿 Context。
- [x] 文字整理、助理對話、雲端語音轉文字與即時串流在送出前顯示實際目的地、模型與資料類型。
- [x] Privacy HUD 摘要不顯示完整文字、剪貼簿內容或 API Key，端點 Query、帳號與密碼會被移除。
- [x] 取消後不會進入新的整理 Request 或重試，也不會回寫整理結果或交付插入。
- [x] 交付層在面板關閉後再次檢查取消狀態，並將取消狀態傳入剪貼簿貼上流程，避免競態插入或 AutoSend。
- [x] 模擬鍵盤貼上在取消時會釋放已按下的 Command 修飾鍵，不留下卡住的輸入狀態。
- [x] 自訂指令日誌不再記錄 stdout、stderr 或錯誤訊息內容，只保留狀態、錯誤類型與位元組數。
- [x] 完成本輪程式碼的日誌靜態掃描，未發現新增的完整語音、完整文字、剪貼簿或 API Key 記錄；實際 Log Export 仍待人工確認。
- [x] `xcodebuild build-for-testing` 通過。
- [x] `xcodebuild build` 重新驗證通過；`/Users/hd/Downloads/Wa-Gong.app` 已確認顯示名稱為「聲筆 Wa-Gong」、版本為 `0.0.1`、Build 為 `1`，並使用 `com.jackie-yeh.wagong`。
- [x] `VoiceInkTests` 22 項單元測試已取得 assertion 結果，22 通過、0 失敗、0 跳過。
- [x] 本輪未執行端到端測試；新增的模型語言標示與舊 Provider 名稱遷移測試已隨 `build-for-testing` 編譯。
- [ ] Privacy HUD 目前是送出前提醒，不阻擋 Request；是否要改成需要人工允許後才送出，待醒來後決定。
- [ ] 需要實際取消錄音、取消整理、取消串流與跨 App 插入測試。
- 日誌不得記錄完整語音、完整文字、剪貼簿、選取文字、OCR 或 API Key。

### 實作內容

- 從 LLM Context 組裝路徑移除剪貼簿資料。
- 讓舊的 `useClipboardContext` 設定失效，避免舊模式重新啟用剪貼簿傳送。
- 建立 Context Allowlist，只允許明確啟用的資料進入外部 Request。
- 參考 VoiceTwInk 的 Privacy HUD，但不顯示或傳送剪貼簿內容。
- 加入工作階段識別字，阻擋取消後的非同步工作回寫舊資料。

### 測試

- 剪貼簿含有 API Key、密碼或個資時，LLM system message 不得出現剪貼簿內容。
- Email 模式保存舊設定時，也不得傳送剪貼簿。
- 停用選取文字後，Request 不得包含選取文字。
- 停用畫面 OCR 後，Request 不得包含 OCR 內容。
- 貼上後原本剪貼簿內容仍可還原。
- 錄音取消後不會觸發外部 Request。
- 舊工作階段的非同步工作完成後，不會讓 HUD 復活。

## 6. 階段三：文字整理模式與自訂提示詞

狀態：三個預設整理 Prompt 與既有切換流程已完成，模式 UI 與 Provider fallback 仍在進行中

預設提供三個可修改模式：

1. 去除贅詞：移除無意義贅詞，保留原意與語氣。
2. 商業整理：整理成正式、清楚、適合工作溝通的內容。
3. 智慧模式：依輸入內容選擇適當整理程度，保留中英混合與專有名詞。

### 實作內容

- 沿用 `CustomPrompt`、`ModeConfig` 與現有模式選擇流程。
- 建立穩定的預設 Prompt ID，避免升級後模式選擇失效。
- 每個模式可修改名稱、提示詞、語言、轉錄模型、整理 Provider 與快速鍵。
- 整理失敗時回退到原始轉錄文字。
- 將繁體中文規則放在共用提示詞層。
- OpenCC 或等效正規化只處理中文，不修改英文、URL、Email、檔案路徑與程式碼。

### 測試

- 三個預設模式在新安裝時都存在。
- 修改 Prompt 後，重啟 App 仍保留設定。
- 三種模式對贅詞、商業內容與中英混合內容產生不同結果。
- 整理 Provider 失敗時保留原始轉錄文字。
- 自訂模式可以新增、修改、刪除與重新選取。

### 預設整理 Prompt 目前驗證結果

- [x] 先加入固定 ID、標題與 Seeder 測試。
- [x] 新增「去除贅詞」、「商業整理」、「智慧模式」三個可修改預設 Prompt。
- [x] 任一 Starter Mode 初始化時都會補齊三個預設 Prompt，既有使用者的自訂 Prompt 不會被覆寫。
- [x] `EnhancementPromptPopover` 原有切換器可直接切換這三個 Prompt，不另造新的切換流程。
- [x] `xcodebuild build-for-testing` 通過。
- [ ] 尚未完成真實整理結果、Provider 失敗 fallback 與重啟後人工確認。

## 7. 階段四：Provider 整合

狀態：OpenAI 語音轉文字 Provider 已完成，OpenAI、Gemini、Claude 文字整理路徑已存在並完成名稱相容處理，真實 Provider 失敗與帳務驗證待處理

### 語音轉文字

- 保留既有 Groq Provider。
- 新增正式 OpenAI transcription Provider。
- 共用 API Key、逾時、取消、錯誤訊息與語言參數處理。
- API Key 一律存放在 Keychain。

### 文字整理

- 完成 OpenAI Provider 驗證。
- 完成 Gemini Provider 驗證。
- 模型與供應商選擇介面顯示 `Claude`，API 金鑰、API 服務與內部儲存識別顯示或保留 `Anthropic`。
- 各 Provider 都支援三種整理模式與自訂提示詞。
- 網路失敗、逾時、額度不足與未設定 API Key 時提供清楚錯誤。

### 測試

- 不使用真實 API Key 的請求組裝測試。
- OpenAI 與 Groq 語言參數測試。
- Provider 未設定時不會嘗試傳送資料。
- API 逾時與取消不會卡住錄音流程。
- 本機模式不產生非必要外部 Request。

### 文字整理 Provider 目前驗證結果

- [x] OpenAI、Gemini 與既有 Anthropic 實作共用三個整理 Prompt 與自訂提示詞流程。
- [x] 模型介面顯示 `Claude`，API Key 相關文字使用 `Anthropic API Key`，設定與 Keychain 仍使用 `Anthropic` 儲存識別字。
- [x] 加入回歸測試，固定 `Claude` 模型品牌與 `Anthropic` API 服務名稱不可混用。
- [x] Provider Request 送出前會顯示目的地、模型與實際資料類型。
- [x] 取消後會停止新的整理 Request 與重試，並避免回寫結果。
- [x] `xcodebuild build-for-testing` 通過。
- [ ] 未使用真實 API Key，未驗證各 Provider 的額度、逾時、網路失敗與實際整理品質。

### OpenAI 語音轉文字目前驗證結果

- [x] 先加入 Provider 設定測試，確認原始程式沒有 OpenAI 語音轉文字 Provider。
- [x] 新增 OpenAI Provider 與 `whisper-1` 模型，使用 OpenAI `/v1` 語音轉文字端點。
- [x] OpenAI Provider 加入共用 Provider Registry，API Key 仍由既有 Keychain 流程取得。
- [x] `xcodebuild build-for-testing` 通過。
- [ ] 未使用真實 API Key，也未執行網路請求。API Key 與實際帳務驗證待人工處理。

## 8. 階段五：快速鍵、游標插入與自訂詞彙

狀態：自訂詞彙核心資料流完成，快速鍵與游標插入的既有功能盤點完成，取消競態防護完成，實機驗證待人工處理

- 驗證全域快速鍵可以自訂開始、停止與錄音模式。
- 錄音開始時記錄目標 App 與輸出工作階段。
- 錄音完成後將結果插入目標 App 的游標位置。
- Accessibility 權限不足或目標 App 改變時 fail-closed。
- 保留一般貼上模式，另評估 VoiceTwInk 的模擬逐字輸入模式。
- 自訂詞彙分成本機辨識提示、本機確定性取代，以及使用者明確允許的 LLM Context。
- 本次新增的本機 Whisper 詞彙提示只留在本機；既有雲端語音 Provider 的字典功能仍會依 Provider 規格送出使用者已儲存的詞彙，後續需要納入 Privacy HUD 與獨立開關。

### 自訂詞彙目前實作與驗證結果

- [x] 先加入測試，確認本機 Whisper Context 會保留原有提示詞並加入自訂詞彙區塊。
- [x] 自訂詞彙會去除空白項目，並以不分大小寫方式去除重複項目。
- [x] 一般錄音、串流失敗後批次 fallback 與重新轉錄都會套用自訂詞彙至本機 Whisper。
- [x] 非 Whisper Provider 不會因共用 Context 變更而額外收到本機 Whisper 詞彙提示。
- [x] `xcodebuild build-for-testing` 通過，`make check` 通過。
- [x] 快速鍵限制與詞彙替換行為測試已加入，`xcodebuild build-for-testing` 編譯通過。
- [x] 取消後不會在面板關閉與游標貼上之間開始插入，也不會執行 AutoSend；交付取消測試已加入。
- [x] 使用序列化的 `xcodebuild test-without-building` 實際執行 `VoiceInkTests`，22 項測試全部通過。
- [ ] 需要實際模型與語音確認專有名詞辨識改善程度。

### 測試

- 自訂快速鍵可觸發開始與停止錄音。
- 備忘錄、Mail、瀏覽器、Terminal 與聊天類 App 可正確插入文字。
- 貼上完成後不會覆蓋使用者等待期間的新剪貼簿內容。
- 自訂詞彙可以修正明確的專有名詞與產品名稱。
- 自訂詞彙不會強制取代語意不同的普通詞。

### 快速鍵、游標插入與詞彙的人工驗證清單

- 需要 Accessibility 權限的全域快速鍵開始、停止與取消錄音。
- 備忘錄、Mail、瀏覽器、Terminal 與聊天類 App 的游標插入。
- 使用者在貼上延遲期間修改剪貼簿時，原剪貼簿不被錯誤覆蓋。
- 詞彙 UI 新增、刪除、匯入與快速加入。
- 使用實際本機 Whisper 模型確認中文、中英混合與專有名詞辨識。

## 9. 階段六：本地模型比較

狀態：未開始

比較 Local Whisper、Parakeet、Apple Speech、VoiceInk Refine 與 Ollama：

- 中文、英文與中英混合準確度。
- 冷啟動與暖機後延遲。
- 記憶體使用量。
- 是否需要網路。
- 文字整理品質。

在有固定語料與實測數據前，不直接更換預設模型。

## 10. 測試執行器診斷結果

- [x] 先以單一測試建立可重現的測試迴圈，確認先前確實是在 App-hosted test 啟動階段中止，沒有把退出碼誤判成 assertion 通過。
- [x] 確認測試 bundle 已完成連結並通過 `codesign --verify --deep --strict`。
- [x] 找到兩個位於 `/private/tmp/wa-gong-precise-naming-red` 的殘留測試宿主程序。兩者使用相同測試 App 路徑與 Bundle ID，會讓 Launch Services 可能指向過期的測試宿主。
- [x] 清除上述明確確認的殘留測試宿主程序後，使用 `-only-testing:VoiceInkTests` 與 `-parallel-testing-enabled NO` 實際執行測試。
- [x] `xcresulttool` 確認本次測試結果為 22 通過、0 失敗、0 跳過。
- App 首次啟動會進行本地模型預熱，這次記錄約 97 秒。若在測試完成前強制終止，可能留下測試宿主程序，下一輪測試需要先清除相同測試產物對應的殘留程序。
- [ ] 完整 UI 測試與實機跨 App 插入仍待人工驗證。

## 11. Build 診斷與驗證結果

- [x] 確認 `mlx-swift-lm` 鎖定 revision 與 checkout 一致，並確認其 manifest 正確宣告 `MLXHuggingFaceMacros`。
- [x] 以獨立 SwiftPM scratch build 編譯 `MLXHuggingFace`，包含巨集 target，確認第三方套件本身可正常編譯。
- [x] Xcode 26.6 使用 `-skipPackagePluginValidation` 與 `-skipMacroValidation` 後，已越過 Package Plugin 與 Swift Macro 驗證階段。
- [x] 使用 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 完整編譯 `Wa-Gong.app`，並確認產物內的 `CFBundleDisplayName`、Bundle ID、版本與 `AppIcon` 都正確。
- 本機標準簽署 Build 仍需要 Apple Development 憑證、私密金鑰與 `com.jackie-yeh.wagong` provisioning profile；這是本機帳號環境待處理項目，不修改專案設定。

## 12. 共用 Preflight Checklist

### 隱私與資料流

- [ ] 剪貼簿永遠不在 LLM Request。
- [ ] 剪貼簿貼上暫存與 LLM Context 分離。
- [ ] 所有外部 Request 都有明確目的地與資料類型。
- [ ] API Key 只存在 Keychain。
- [ ] 日誌不包含完整內容或秘密資料。
- [ ] 錄音取消後所有非同步工作都有取消或工作階段檢查。

### 語言與輸出

- [ ] 預設語言是 Auto-detect。
- [ ] English-only 模型不會被當成多語言模型。
- [ ] 中文預設輸出台灣繁體中文。
- [ ] 中英混合、URL、Email 與程式碼不被破壞。

### Provider 與網路

- [ ] OpenAI、Groq、Gemini、Claude 都有未設定、失敗、逾時與取消測試。
- [ ] 完全本機模式不產生非必要外部 Request。
- [ ] 自訂 Endpoint 若保留，必須檢查 HTTPS、localhost、私有 IP 與 Metadata Endpoint。
- [ ] 不使用未固定版本的新增第三方套件或模型權重。

### macOS 輸入與權限

- [ ] 麥克風與 Accessibility 權限用途清楚。
- [ ] Accessibility 不可用時不嘗試繞過系統限制。
- [ ] 文字只插入使用者確認的目標 App。
- [ ] 貼上、逐字輸入、換行、取消與 AutoSend 都有測試。

### 發布與提交

- [ ] 每個功能先測試、後實作。
- [ ] 每個功能獨立 commit。
- [ ] 每個 commit 可編譯、可測試、可回退。
- [ ] 不提交 API Key、Team ID、個人資料或本機錄音。
- [ ] 完成前更新本文件的狀態與驗證結果。

## 13. Definition of Done

- 測試先於實作建立，且能捕捉原始問題。
- 功能測試、失敗測試、取消測試與降級測試通過。
- `make check` 通過。
- 未簽署本機 `xcodebuild build` 通過；標準簽署 Build 仍待補齊 Apple Development 憑證與 provisioning profile。
- `VoiceInkTests` 單元測試 22 項通過；UI 測試與實機驗證另行完成後才可勾選完整驗收。
- `git diff --check` 通過。
- 文件狀態與實際程式碼一致。
- 每個功能已建立獨立 commit。
