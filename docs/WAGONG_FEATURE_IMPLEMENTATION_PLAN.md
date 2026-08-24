# 聲筆 Wa-Gong 功能實作計畫

更新日期：2026-08-25

本文件是本輪功能開發的執行依據。每個功能都必須先建立測試，再實作程式碼，驗證通過後獨立建立一個 Git commit。

## 1. 基礎決策

- 主要基底：`Beingpax/VoiceInk`。
- 功能參考：`opass/VoiceTwInk`。
- App 名稱：`聲筆 Wa-Gong`。
- Bundle ID：`com.jackie-yeh.wagong`。
- Swift module name：`VoiceInk`，暫時保留以維持既有測試與內部程式碼相容性。
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

狀態：程式實作完成，已通過 `build-for-testing` 編譯驗證，單元測試執行受目前 macOS 測試執行器環境阻塞

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
- [ ] `xcodebuild test` 尚未取得測試 assertion 結果。測試 bundle 啟動時，macOS 測試執行器在 Launch Services worker 階段卡住，最後以退出碼 75 結束，不能視為測試通過。

### 待人工決定或驗證

- 預設本機模型目前仍是 Parakeet V3。它支援英文與部分歐洲語言，不包含中文。是否改成 Whisper 多語言模型作為中文優先的本機預設，需要依照「即時速度」與「中文準確度」取捨後決定。
- 需要實際下載模型，使用純中文、純英文與中英混合語音驗證辨識品質。
- 需要在具備麥克風與 Accessibility 權限的實機確認語言設定變更後的錄音與插入流程。

## 5. 階段二：剪貼簿隔離與隱私透明度

狀態：剪貼簿隔離已完成，Privacy HUD、取消流程與完整外部 Request 透明度仍在進行中

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
- [x] `xcodebuild build-for-testing` 通過。
- [ ] 單元測試 assertion 尚未取得，原因與階段一相同，macOS 測試執行器卡在 Launch Services worker。
- [ ] Privacy HUD、Request 目的地與資料類型顯示、取消後的工作階段檢查，待後續測試先行實作。
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

狀態：未開始

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

## 7. 階段四：Provider 整合

狀態：未開始

### 語音轉文字

- 保留既有 Groq Provider。
- 新增正式 OpenAI transcription Provider。
- 共用 API Key、逾時、取消、錯誤訊息與語言參數處理。
- API Key 一律存放在 Keychain。

### 文字整理

- 完成 OpenAI Provider 驗證。
- 完成 Gemini Provider 驗證。
- 將 Anthropic 在 UI 顯示為 Claude，程式內保留既有識別字相容性。
- 各 Provider 都支援三種整理模式與自訂提示詞。
- 網路失敗、逾時、額度不足與未設定 API Key 時提供清楚錯誤。

### 測試

- 不使用真實 API Key 的請求組裝測試。
- OpenAI 與 Groq 語言參數測試。
- Provider 未設定時不會嘗試傳送資料。
- API 逾時與取消不會卡住錄音流程。
- 本機模式不產生非必要外部 Request。

## 8. 階段五：快速鍵、游標插入與自訂詞彙

狀態：未開始

- 驗證全域快速鍵可以自訂開始、停止與錄音模式。
- 錄音開始時記錄目標 App 與輸出工作階段。
- 錄音完成後將結果插入目標 App 的游標位置。
- Accessibility 權限不足或目標 App 改變時 fail-closed。
- 保留一般貼上模式，另評估 VoiceTwInk 的模擬逐字輸入模式。
- 自訂詞彙分成本機確定性取代，以及使用者明確允許的 LLM Context。
- 自訂詞彙預設不包含在外部 Request。

### 測試

- 自訂快速鍵可觸發開始與停止錄音。
- 備忘錄、Mail、瀏覽器、Terminal 與聊天類 App 可正確插入文字。
- 貼上完成後不會覆蓋使用者等待期間的新剪貼簿內容。
- 自訂詞彙可以修正明確的專有名詞與產品名稱。
- 自訂詞彙不會強制取代語意不同的普通詞。

## 9. 階段六：本地模型比較

狀態：未開始

比較 Local Whisper、Parakeet、Apple Speech、VoiceInk Refine 與 Ollama：

- 中文、英文與中英混合準確度。
- 冷啟動與暖機後延遲。
- 記憶體使用量。
- 是否需要網路。
- 文字整理品質。

在有固定語料與實測數據前，不直接更換預設模型。

## 10. 共用 Preflight Checklist

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

## 11. Definition of Done

- 測試先於實作建立，且能捕捉原始問題。
- 功能測試、失敗測試、取消測試與降級測試通過。
- `make check` 通過。
- `xcodebuild build` 通過。
- 相關單元測試與 UI 測試通過。
- `git diff --check` 通過。
- 文件狀態與實際程式碼一致。
- 每個功能已建立獨立 commit。
