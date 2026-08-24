# macOS 語音輸入 App 實作計畫

更新日期：2026-08-24

本計畫依據 [PROJECT_DIRECTION.md](./PROJECT_DIRECTION.md) 執行。每個階段完成後更新狀態與驗證結果。

## Non-scope

第一輪明確不處理：

- 不上架 Mac App Store。
- 不建立訂閱、付費授權或帳號系統。
- 不建立自有後端或遙測服務。
- 不先實作 Private Cloud Compute。
- 不整批 Cherry-pick VoiceTwInk 的 Commit。
- 不先重做 VoiceInk 全部 UI 或品牌系統。
- 不移植 iOS 鍵盤程式碼至 macOS。
- 不刪除 VoiceInk 既有 Provider，除非有明確資安、授權或建置問題。
- 不新增與第一版核心流程無關的第三方套件。

## 階段 1：建立基底與可重現建置

**目標**：從最新版 VoiceInk 建立自己的 Fork，確認乾淨環境可編譯與執行。

**工作項目**：

- 建立自己的 GitHub Repository。
- 將 `origin` 指向自己的 Repository。
- 將 `upstream` 指向 Beingpax/VoiceInk。
- 將 `voicetwink` 指向 opass/VoiceTwInk。
- 記錄 Fork 起始 Commit SHA。
- 依上游文件完成本機簽署與建置。
- 盤點 macOS Deployment Target、Xcode、Swift 與套件版本。
- 建立第三方套件與模型授權清單。
- 確認 App 名稱、Bundle Identifier、圖示與資料目錄的重新命名範圍。

**成功標準**：

- 乾淨 Clone 後可依文件完成 Build。
- M1 Pro 可啟動 App 並取得麥克風與 Accessibility 權限。
- 上游原始流程可完成錄音、轉錄與文字插入。
- 沒有新增功能或無關重構。

**測試**：

- 執行上游現有單元測試與 UI 測試。
- 執行 Debug Build。
- 以備忘錄完成一次端對端實機測試。

**狀態**：未開始

## 階段 2：建立延遲基準與觀測能力

**目標**：先量出 VoiceInk 現有本機與雲端流程的實際延遲，再決定最佳化順序。

**工作項目**：

- 加入不含敏感內容的結構化時間事件。
- 記錄 `recording_started`。
- 記錄 `recording_stopped`。
- 記錄 `transcription_started`。
- 記錄 `first_partial_transcript`。
- 記錄 `final_transcript_received`。
- 記錄 `refinement_started`。
- 記錄 `refinement_finished`。
- 記錄 `text_inserted`。
- 記錄 Provider、模型 ID、音訊秒數與成功／失敗狀態。
- 建立固定短句、中句、中英混合與環境噪音測試語料。

**成功標準**：

- 可從單次工作階段 ID 還原完整延遲分布。
- 可分辨轉錄、文字整理與插入各自耗時。
- 日誌不包含完整語音、完整文字、剪貼簿、選取文字或 API Key。

**測試**：

- 每組測試語料至少執行 10 次。
- 計算 p50、p90 與失敗率。
- 分別測試冷啟動與模型已暖機狀態。

**狀態**：未開始

## 階段 3：Apple 本機語音轉錄

**目標**：在 macOS 26 以上啟用並驗證 `SpeechAnalyzer` 與 `SpeechTranscriber`。

**工作項目**：

- 確認 Xcode SDK 與 `ENABLE_NATIVE_SPEECH_ANALYZER` 設定。
- 驗證繁體中文、英文與中英混合語言支援狀態。
- 驗證 Apple Speech 語言資源下載、保留、替換與錯誤處理。
- 驗證錄音檔格式是否需額外轉換。
- 驗證現有檔案式流程延遲。
- 評估是否能以 `AVAudioEngine` Buffer 直接餵入分析器。
- 若 API 與 VoiceInk 架構允許，加入 Partial Transcript 顯示。
- 保留既有本機模型作為降級與比較方案。

**成功標準**：

- 完全離線可完成繁體中文短句轉錄。
- 語言資源未下載、額度已滿或語言不支援時有明確錯誤訊息。
- 不因 Apple Speech 不可用而破壞其他 Provider。
- 有實測延遲與準確率比較資料。

**測試**：

- 繁體中文短句。
- 中英混合短句。
- 純英文短句。
- 無語音音檔。
- 尚未下載語言資源。
- 取消錄音與快速重複錄音。

**狀態**：未開始

## 階段 4：本機文字整理與繁體中文品質

**目標**：先驗證 VoiceInk Refine，再決定是否新增 Apple Foundation Models Provider。

**工作項目**：

- 下載並驗證 `VoiceInk Refine V1` 的模型版本、雜湊與授權。
- 測量模型冷啟動、暖機、推論時間與記憶體使用量。
- 測試補標點、去除贅詞、自動條列、商務整理與中英混合內容。
- 測試繁體中文與台灣用語品質。
- 移植或重新實作 OpenCC 簡體轉繁體保底處理。
- 確保正規化只處理中文，不破壞英文、日文、URL 與程式碼。
- 若 VoiceInk Refine 不符合需求，建立 Apple Foundation Models Provider Spike。
- 保持 Provider 可替換，不修改錄音與文字插入核心責任。

**成功標準**：

- 完全本機完成轉錄與文字整理。
- 中文預設輸出台灣繁體中文。
- 使用者可選擇不整理或切換整理 Provider。
- 整理失敗時可保留原始轉錄結果，不遺失內容。

**測試**：

- 贅詞與自我修正。
- 第一點、第二點、第三點等自然條列表達。
- 正式郵件與日常訊息。
- 中英混合、專有名詞與 URL。
- 簡體轉繁體容易誤轉的異體字。
- 模型未下載、模型損毀與推論逾時。

**狀態**：未開始

## 階段 5：隱私透明度與輸出相容性

**目標**：移植 VoiceTwInk 中與隱私及日常輸入直接相關的功能。

**工作項目**：

- 盤點 VoiceInk 實際會收集的選取文字、剪貼簿、畫面 OCR、系統 Context 與自訂詞彙。
- 提供各 Context 的全域開關。
- 外部請求前顯示傳送目的地與資料類型。
- 取消錄音時取消轉錄、整理與插入，不送出資料。
- 驗證 Context 只作為資料，不可覆蓋系統提示詞或執行指令。
- 加入模擬逐字輸入選項。
- 確保逐字輸入不受目前注音輸入法影響。
- 驗證換行、AutoSend、撤銷與剪貼簿還原行為。

**成功標準**：

- 使用者能在資料送出前知道目的地與資料類型。
- 停用 Context 後，實際 Request 不含該內容。
- 取消後不產生雲端 Request。
- 備忘錄、Mail、瀏覽器、LINE、Slack 與 Terminal 可正確插入文字。

**測試**：

- 剪貼簿包含 API Key 樣式文字。
- 選取文字包含密碼或個資。
- 錄音中途取消。
- 目標 App 切換與焦點消失。
- 多段落與大量文字。
- 注音輸入法啟用時的逐字輸入。

**狀態**：未開始

## 階段 6：開放原始碼發布

**目標**：建立可重現、可稽核且符合 GPL v3 的 GitHub Release 流程。

**工作項目**：

- 使用三段式版本號。
- 建立版本紀錄。
- 建立對應 Git Tag。
- 保存建置工具版本與 Release Commit SHA。
- 提供建置、簽署、權限與模型下載說明。
- 提供 GPL v3、第三方授權與模型授權清單。
- 確認 Release 執行檔與公開原始碼完全對應。
- 確認執行檔不含 API Key、憑證、Team ID 或本機路徑。
- 記錄已知限制與硬體需求。

**成功標準**：

- 新使用者可從乾淨環境依文件自行 Build。
- GitHub Release 可下載、啟動並完成權限設定。
- Release 頁面可直接找到對應原始碼與授權資訊。

**測試**：

- 從 Release Tag 重新 Clone 並 Build。
- 在未設定 API Key 的環境驗證完全本機流程。
- 檢查執行檔、設定檔與 Git History 是否含 Secret。

**狀態**：未開始

## Preflight Checklist

> 開工前檢查一輪，完工後以同一份清單再次自查。

### A. 範圍控制

- [ ] 沒有越界實作 Non-scope 項目。
- [ ] 沒有整批搬入 VoiceTwInk 或無關上游變更。
- [ ] 每個階段均維持可編譯、可執行與可回退。

### B. 隱私與敏感資料

- [ ] 麥克風只在使用者明確觸發後啟用。
- [ ] 錄音狀態持續可見，停止與取消行為清楚。
- [ ] Audio、Transcript、Clipboard、Selected Text 與 Screen OCR 的保存期限明確。
- [ ] 暫存音檔使用 App 私有目錄，並依設定或工作階段結束清除。
- [ ] API Key 儲存在 Keychain，不寫入 UserDefaults、日誌或 Git。
- [ ] 日誌只記錄時間、Provider、模型、狀態與錯誤類型，不記錄完整內容。
- [ ] 外部 Request 只包含使用者已啟用的 Context。
- [ ] 錄音取消後，不得繼續執行轉錄、整理或網路傳送。

### C. 外部服務與網路

- [ ] 所有外部 Request 均有 Timeout。
- [ ] 重試僅用於可安全重試的請求，避免重複計費。
- [ ] 自訂 Endpoint 若保留，限制為 HTTPS，並防止 localhost、私有 IP 與 Metadata Endpoint SSRF。
- [ ] 錯誤訊息不洩漏 API Key、完整 URL Query 或使用者內容。
- [ ] 完全本機模式不產生非必要網路 Request。

### D. 第三方套件與模型供應鏈

- [ ] 建立套件、模型、字典與圖示資產授權清單。
- [ ] 確認每項授權與 GPL v3 相容。
- [ ] 模型下載固定版本或 Revision，不追蹤未固定的 Latest。
- [ ] 模型檔案驗證大小與雜湊。
- [ ] 新增套件前記錄無法使用現有 Framework 的原因。
- [ ] 上游安全修正有固定檢查與同步方式。

### E. macOS 權限與輸出

- [ ] Accessibility、麥克風與畫面錄製權限分開說明用途。
- [ ] 權限不足時功能 Fail-closed，不嘗試繞過系統限制。
- [ ] 文字只插入錄音開始時或使用者確認的目標 App。
- [ ] 焦點 App 改變時，不把敏感文字送到錯誤視窗。
- [ ] 剪貼簿備份與還原處理競態條件。
- [ ] 模擬逐字輸入有速率限制、取消與大量文字保護。

### F. 繁體中文與多語言

- [ ] 中文預設輸出台灣繁體中文。
- [ ] OpenCC 不改寫英文、日文、URL、Email、檔案路徑與程式碼。
- [ ] 中英混合內容保留原語言與專有名詞。
- [ ] UI、錯誤訊息與權限說明至少提供繁體中文。
- [ ] 不支援語言有明確降級流程。

### G. 效能與穩定性

- [ ] 分開量測錄音、轉錄、整理與插入延遲。
- [ ] 冷啟動與暖機狀態分開記錄。
- [ ] 長錄音有長度、記憶體與逾時保護。
- [ ] 模型暖機不造成 App 啟動或 UI 阻塞。
- [ ] MainActor 不執行音訊轉換、模型推論或檔案雜湊等重工作。
- [ ] Audio Route 變更與裝置拔除有恢復流程。

### H. 測試與發布

- [ ] 新功能有成功、失敗、取消與降級測試。
- [ ] 測試不依賴真實 API Key。
- [ ] M1 Pro 實機完成端對端測試。
- [ ] 每個 Release Tag 可重現對應執行檔。
- [ ] 版本號使用三段式格式。
- [ ] 發布前更新 Changelog、授權清單與已知限制。

### I. 不適用項目

- 資料庫 Schema：第一版沒有伺服器或共用資料庫。
- 帳號與付款：第一版沒有登入、訂閱或付費流程。
- 後台管理：第一版沒有後台。
- Email、SMS 與 Webhook：第一版不主動傳送。
- 時區業務規則：只允許將時區作為使用者可見 Context，不作付款或權限判斷。
