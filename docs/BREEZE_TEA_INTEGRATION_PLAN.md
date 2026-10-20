# Breeze／TEA 語音辨識與 Gemini／Claude 潤飾接入規劃

盤點日期：2026-10-15。最後更新：2026-10-16。

狀態：本機模型、相容 API 與 App 接入已實作並經真實 loopback 請求驗證；新版 Gemini／Claude 已加入選單、單次傳輸及完整回應檢查。測試服務已停止，未留下常駐程序。尚未呼叫付費雲端 API、安裝新 App 或發布，整體四組與實機驗收尚未完成。

## 1. 目標與範圍

讓使用者在模式內選擇 Breeze-ASR-25 或 TEA-ASR-1.1 轉錄，再選擇 Gemini 3.8 Flash 或 Claude Haiku 5.5 潤飾，共四種組合。兩個 ASR 是替代選項，不串接兩次辨識，也不在失敗後自動改送另一個服務。

本次執行不包含模型隨 App 散布、App 自動安裝 Python、自動啟動常駐服務、串流逐字顯示、正式部署或發布，也不修改快速鍵、鍵盤診斷及其既有未提交內容。理由是這些工作不影響先驗證辨識與潤飾組合，且會增加獨立的部署與生命週期風險。

## 2. 實作前盤點基準（2026-10-15）

下表保留開工前的盤點，來源為當時 checkout 的 README、功能實作計畫、Swift 原始碼及官方模型頁。完成進度以第 6、11 節為準；開工前的缺口不再代表目前原始碼狀態。

| 能力 | 現況與證據 | 影響 |
| --- | --- | --- |
| 分開選 ASR 與潤飾 | `VoiceInk/Modes/ModeRuntimeConfiguration.swift`、`VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` | 沿用現有模式與處理流程，無須重寫錄音及貼上架構。 |
| 自訂 ASR | `VoiceInk/Transcription/Cloud/OpenAICompatibleTranscriptionService.swift` | 已以 multipart POST 上傳 WAV，帶 Bearer、model、response_format=json、temperature=0，指定語言時另帶 language，解析 JSON 的 text。服務需完整相容這份實際契約。 |
| 自訂模型設定 | `VoiceInk/Transcription/Cloud/CustomCloudModelManager.swift`、`VoiceInk/Models/TranscriptionModel.swift` | 可保存端點與模型 ID，金鑰走 Keychain；新增設定目前要求非空金鑰。 |
| 端點限制 | `VoiceInk/Services/CustomEndpointPolicy.swift` | 允許 HTTPS；HTTP 僅限 localhost、127.0.0.1、::1。區網 HTTP 端點不能直接填入。 |
| Gemini 與 Claude | `VoiceInk/Services/AIEnhancement/AIService.swift`、`AIChatCompletionService.swift` | 已有原生 API 呼叫分支，但固定選單缺少這兩個新版模型。 |
| 思考參數 | `VoiceInk/Services/AIEnhancement/ReasoningConfig.swift` | 舊模型部分使用 minimal；Gemini 3.8 官方僅列 low、medium、high，minimal 會報錯。 |
| 即時轉錄 | `VoiceInk/Models/TranscriptionRealtimeSupport.swift`、`TranscriptionModel.swift` | 自訂模型沿用非串流流程，第一階段停止錄音後才轉錄。 |
| 辨識詞彙提示 | `VoiceInk/Transcription/Cloud/CloudTranscriptionService.swift`、`VoiceInk/Services/VocabularySnapshot.swift` | 目前自訂 ASR 分支沒有傳送自訂詞彙，不能宣稱 TEA 熱詞已能使用。 |
| 連線測試 | `VoiceInk/Transcription/Cloud/CustomModelConnectionTester.swift` | 傳送非有效音檔，將 200、400、415、422 視為成功。這不足以證明新服務已載入正確模型、認證成功或能轉錄。 |

LLMkit 由 `VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 固定於 revision `3b9086e3df729f39c2ca8951d09fb6ef4d4a193b`。後續已讀取此 revision 的實作，發現重試及回應完整性缺口，並以 App 端共用傳輸與原生 client 處理，詳見第 11 節。未修改套件快取或升級該 revision。

## 3. 模型選擇前提

- Breeze-ASR-25：官方描述為 Whisper-large-v2 微調模型，適用台灣國語與中英混用。先以此作為 Breeze 候選。
- Breeze-ASR-26：官方定位為台語辨識，輸出國語漢字，不能因版號較新就替代國語候選。台語若要納入，需另訂語料、輸出期待與驗收。
- TEA-ASR-1.1：JacobLinCool 發布，基於 Qwen3-ASR，使用 qwen-asr 推論；官方建議台灣國語指定 Chinese。不能直接匯入現有 Whisper 的 .bin 載入器。
- Breeze-ASR-25 可評估轉成現有 whisper.cpp 可用格式，但轉換、tokenizer、精度與效能尚未實測，不能承諾只匯入檔案即可使用。
- 官方範例及模型頁不等於可購買的託管 API。尚未確認有適合本案的現成託管服務，規劃不假定已取得 API。

## 4. 路線比較與推薦決策

| 路線 | 必要工作 | 判斷 |
| --- | --- | --- |
| 同一台 Mac 上執行獨立 ASR 服務 | 建立兩種模型後端及相容 API，App 沿用自訂模型；核對 Apple Silicon 推論支援。 | 建議先做可行性驗證。統一兩種 ASR 接口，避免先新增兩套 App 原生推論。尚未證明 Mac 速度或記憶體可接受。 |
| 遠端 ASR 服務 | 模型主機、HTTPS、認證、容量、音檔清除及維運。 | 本機效能不符需求時的替代路線。錄音會離開 Mac，需明確選用與額外維運範圍。 |
| 模型全部整合進 App | Breeze 格式轉換；TEA 新增相容推論引擎或程序橋接；下載、校驗、載入、釋放、取消、簽署及散布。 | 後續產品化選項。首輪不採，因工作量與套件支援風險較高。 |

推薦流程：錄音 → 本機 ASR 服務（Breeze 或 TEA）→ 原始轉錄 → 雲端潤飾（Gemini 或 Claude）→ 現有文字輸出流程。

即使 ASR 在本機，啟用雲端潤飾仍會傳送轉錄文字。介面不能標示整條流程完全離線。

## 5. 必要修改與檔案範圍

### 5.1 ASR 執行服務（新增，主要工作）

建議新增 `tools/taiwan-asr/` 作為手動執行的驗證服務，待路線確認後才建立程式。

- 提供 OpenAI 相容的 `POST /v1/audio/transcriptions`，成功回傳 `{"text":"..."}`。
- 接受 App 實際傳送的全部欄位，明確定義 response_format 與 temperature 的處理，不將其未知欄位錯誤誤判為認證成功。
- 以明確模型 ID 路由 Breeze、TEA，固定模型 revision 及推論依賴版本，拒絕不存在的模型，不默默替換。
- 將 zh 映射為 TEA 所需的 Chinese；auto、en 與不支援語言需分別定義並測試，不能一律強制中文。
- 核對 WAV 聲道、取樣率及推論前轉換；限制檔案大小、音訊長度與並行數，過長音檔需有明確拒絕或分段策略。
- 分開回報服務可達、模型可用、模型已載入及忙碌狀態。採單模型常駐或切換載入由記憶體量測決定，不預設同時載入兩個模型。
- 只綁定 loopback，使用本機隨機 Bearer token；App 端存 Keychain，服務端透過安全的啟動注入取得，不寫入 repo。沿用非空金鑰要求，首輪不新增免認證模式。
- 暫存音檔在成功、失敗、取消後均清除；服務啟動時只清理自己可確認的殘留，不觸碰 App 原始錄音或匯入來源。
- 中斷連線後停止排隊工作；已開始的推論是否可真正中止，需依後端驗證。若只能丟棄結果，須回報限制並限制資源佔用，App 端仍必須阻擋後續潤飾與貼上。
- 不保存完整音訊、文字或金鑰到服務日誌。使用專案內獨立 .venv 與鎖定依賴，不變更全域 Python。

### 5.2 App 自訂 ASR 接入（沿用為主，針對驗證缺口修改）

預計涉及：

- `VoiceInk/Transcription/Cloud/OpenAICompatibleTranscriptionService.swift`：讓逾時政策可明確測試，涵蓋冷啟動、空白結果及服務錯誤；核對取消傳遞，必要時補上防護。
- `VoiceInk/Transcription/Cloud/CustomModelConnectionTester.swift`：不能用一般 4xx 當「模型可用」。以有效且已知內容的非私人測試音檔驗證轉錄，或另列服務健康檢查；必須區分兩者的證據等級。
- `VoiceInk/Views/AI Models/CustomProviderManagementView.swift`：連線測試顯示與錯誤說明同步，標明本機服務需要自行啟動；服務未啟動、模型不存在、忙碌及逾時各有明確訊息。
- 相關本地化資源與新增行為測試，實作時依專案實際資源位置補齊。

首輪透過既有自訂模型表單各新增一筆設定即可，不一定要新增 ModelProvider enum、內建模型目錄或修改模式資料結構。只有在需要內建入口時，才擴大到 `TranscriptionModelRegistry.swift`、`TranscriptionModel.swift` 與模型管理頁，避免把設定工作誤列為必要架構改動。

端點政策維持不變。若將來改用遠端或區網服務，優先提供 HTTPS，不為了方便直接開放任意區網 HTTP。

### 5.3 新版潤飾模型（必要，範圍較小）

- `VoiceInk/Services/AIEnhancement/AIService.swift`：新增 `gemini-3.8-flash` 與 `claude-haiku-5-5`，保留既有模型與使用者選擇，不自動更換預設值。
- `VoiceInk/Services/AIEnhancement/ReasoningConfig.swift`：Gemini 3.8 以 low 作為待驗證的低延遲設定，禁止傳 minimal；以請求行為測試守住模型能力差異。
- `VoiceInk/Services/AIEnhancement/AIChatCompletionService.swift`：核對既有 LLMkit 的實際 API 格式、思考設定、輸出上限、完成狀態、拒絕／截斷回應與取消處理；只在確認缺口時修改或升級套件。
- 新增對應回歸測試，驗證新版模型可選、舊設定仍可讀、請求參數正確，以及錯誤不觸發重複計費的自動重送。

優先使用現有 Gemini／Anthropic 原生分支，不要求使用者為此增加第三方轉接平台，理由是目前已有金鑰與目的地顯示流程。

### 5.4 模式與字典（設定及選配）

- 建立四種測試模式，逐一指定 ASR、潤飾模型、語言與提示詞；驗證切換期間不混用前一模式設定。
- 測試時明確關閉「短文字略過潤飾」，避免短句其實沒呼叫 LLM 而誤判組合成功；保留使用者一般模式原設定。
- 沿用台灣繁體中文、專有名詞保留及不新增事實的提示詞，分開評估原始 ASR 與潤飾輸出。
- 首輪保留現有辨識後詞彙替換，明確標示自訂 ASR 尚未使用辨識熱詞。
- TEA 熱詞列為選配：需擴充請求契約、`VocabularyPolicy`、快照傳遞與隱私提示，驗證其 context 長度及模型能力後才啟用。不為所有自訂模型無條件送出詞庫。

## 6. 分階段執行

| 階段 | 交付內容 | 成功標準 | 狀態 |
| --- | --- | --- | --- |
| 一、執行環境可行性 | 確認目標 Mac 規格、模型 revision、授權、套件及最小推論。 | Breeze 與 TEA 分別用非私人已知音檔產生可核對結果，記錄冷啟動、暖機延遲與峰值記憶體；不支援則明確改評估遠端路線。 | 最小可行性通過；完整記憶體壓力及真實語料品質待後續驗收 |
| 二、ASR API 接入 | 相容服務、認證、模型路由、App 連線測試與錯誤處理。 | 從 App 真實錄音經服務返回原始轉錄，錯誤與取消路徑符合要求。 | 原始碼及真實本機 HTTP／App 傳輸驗證通過；麥克風至貼上的實機路徑未驗 |
| 三、新版潤飾模型 | 模型清單、參數、套件相容性與回歸測試。 | 真實 API 驗證兩個模型，保留原始轉錄，無重複重送。 | 模型選項、單次傳輸與完整回應驗證已實作及測試；真實 API 待核准 |
| 四、四組端對端比較 | 同一套語料、快速鍵錄音、潤飾與跨 App 插入。 | 四組均有來源、版本及執行證據；延遲、辨識與內容保真可比較，限制逐項列出。 | 未開始 |

驗證紀錄需包含實際 source SHA、App Build ID、服務版本、模型 revision、硬體與參數。發布前另同步三段式版號及 CHANGELOG，簽署、公證、安裝與發布分開驗證。

## 7. Preflight Checklist

以下為待執行條件，未勾選不代表已通過。第一輪實作前及完成後使用同一份清單核對。

### 資料與模型能力

- [ ] 模型來源、revision、權重及執行環境依賴可重現；Breeze／TEA 及其基礎模型的授權告知完整。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [x] 本機服務只接收明確選用的錄音，不接收剪貼簿、OCR 或額外 Context。
- [ ] 雲端潤飾顯示正確目的地、模型與傳送文字的事實。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [x] 模型能力在實際請求路徑受約束，不能只在 UI 寫「非串流」或「不支援熱詞」。
- [x] 不把新增模型誤做成自動遷移或強制覆寫既有選擇。

### 端點與服務副作用

- [x] loopback 綁定與認證有正反測試，錯誤 token、未知模型與無效音檔不顯示成功。
- [ ] 不放寬 HTTP 限制；檢查重新導向不會把錄音或認證送到未預期目的地。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [x] 上傳大小、音訊長度、並行數、排隊、逾時與模型忙碌有明確限制。
- [ ] 取消、關閉面板與切換工作階段後，沒有新潤飾請求、晚到貼上或 HUD 復活。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 失敗不自動更換 Provider 或重複送出可能計費的請求。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] ASR 失敗顯示錯誤；潤飾失敗保留原始轉錄，重試沿用轉錄而非再辨識一次。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [x] 服務錯誤、例外與日誌不包含錄音、完整文字、token 或完整敏感請求網址。
- [ ] 暫存檔清理涵蓋成功、失敗、中斷及重啟，且不清理服務目錄以外的檔案。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】

### 品質與效能

- [ ] 四組使用相同非私人語料，包括中文、中英混用、人名、數字、日期、網址、停頓、背景聲與純靜音。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 分別比較原始 ASR 的 CER／中英混合錯誤率及 LLM 潤飾的保真度，不用潤飾結果掩蓋辨識錯誤。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 核對否定句、金額、人名與網址不得被潤飾改意或增補；原始與潤飾結果僅保留在既有授權的歷史位置或受控測試資料，不進日誌。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 冷啟動與暖機後分開量測，記錄 ASR、潤飾、貼上耗時與峰值記憶體；足夠樣本後才報 p50、p95。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 在選定硬體實測後訂出可接受延遲與記憶體門檻，再決定推薦模型，不預先宣稱最快或最佳。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 經正常快速鍵、麥克風、模式解析、服務、潤飾、文字輸出完整路徑測試，並涵蓋備忘錄與另一個實際使用的 App。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】
- [ ] 新版 App 已實際安裝，source、bundle、process 的 Build ID 一致；共用 Bundle ID 的測試宿主與正式 App 不同時執行。【阻擋完整驗收：在第 12 節對應的測試階段重新執行，不視為已通過。】

### 不適用範圍

- 資料庫 schema 與批次回填：第一輪沿用自訂模型與模式欄位，無 migration 需求。
- 網頁表單、Filament、CSRF、郵件與 webhook：本功能是 macOS App 與 ASR／LLM 請求，不涉及這些功能。
- 時區業務規則：不新增日期計費或排程；效能量測使用單調時鐘，不以牆上時間差計算。
- 第三方依賴：適用於新 ASR 服務；App 套件僅在相容性證據不足時評估最小變更。


## 8. 實作前仍需決定與未驗證事項

- 推薦先用同一台 Mac 的手動啟動服務。若要求「安裝 App 後即可直接下載使用」，需改採產品化範圍，加入模型管理及服務生命週期。
- 已量測目標 Mac 的硬體及最小推論速度，詳見第 10 節。單句兩次測試不能承諾穩態效能、完整支援機型或完成工時。
- 尚未取得真實錄音及 API 驗收證據；第一階段只證明可執行，後續仍需服務接入及四種組合實測。
- 外部部署、付費 API 驗證、模型散布及正式發布，執行前另列明確內容與影響範圍。

## 9. 官方資料來源

- [Breeze-ASR-25 模型與範例](https://huggingface.co/MediaTek-Research/Breeze-ASR-25)
- [Breeze-ASR-26 的台語定位與限制](https://huggingface.co/MediaTek-Research/Breeze-ASR-26)
- [TEA-ASR-1.1 模型、推論方式與評測限制](https://huggingface.co/JacobLinCool/TEA-ASR-1.1)
- [Gemini 3.8 Flash 模型 ID 與思考參數](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)
- [Claude Haiku 5.5 官方公告與 API 模型 ID](https://www.anthropic.com/claude-haiku-5-5)

本輪工具未提供 Context7 MCP；官方網頁已直接查核。實作前仍需依鎖定版本讀取實際套件原始碼與文件，不能用最新版文件替代既有依賴的相容性證據。

## 10. 2026-10-15 執行紀錄

### 已執行

- `sysctl -n hw.memsize hw.model` 回報 17179869184 bytes 與 MacBookPro18,3，為 16 GiB Apple Silicon Mac。
- 建立 `tools/taiwan-asr/.venv`，使用已安裝的 Python 3.12.9，不變更全域 Python。
- 模型下載於 `tools/taiwan-asr/.runtime/hf`，未使用使用者既有的模型快取。兩個模型的 revision 與大小記錄於 `tools/taiwan-asr/models.json`。
- 以 macOS Meijia 本機語音建立 5.419 秒、16 kHz、單聲道 PCM_16 WAV，內容為非私人固定測試句。沒有錄製或讀取使用者歷史音訊。
- PyTorch 2.9.1 在正常權限程序內回報 MPS available=true。沙盒內回報 false，已以正常權限實際核對，未把沙盒結果誤當成硬體不支援。
- 已知陽性的 64×64 MPS 矩陣乘法回報正確值 64.0，GPU 區段約 1.178 秒。
- Breeze 基準探針使用 PyTorch 2.9.1、float16、eager attention。在程序經過 5 分 54 秒後仍未產生第一筆結果，核對程序身分後停止。這是人工停止的觀察值，不是成功轉錄延遲。
- Breeze 載入期間的 `sample` 證據顯示 `mps_copy_`、`MPSStream::synchronize`、Metal `waitUntilCompleted` 等待，當時 physical footprint 約 4.4 GB、peak 約 4.6 GB。該單次取樣不代表整段運算的完整根因。
- TEA 基準探針使用 PyTorch 2.9.1、float16、SDPA，完成模型載入並進入推論，但超過整體 180 秒上限，程序已停止，沒有成功轉錄結果。
- 將本次隔離 venv 的 PyTorch 升為 2.14.1，移除本次額外安裝且推論不需要的 torchaudio。兩模型均以 Transformers 4.57.6、MPS、float16、SDPA 完成兩次轉錄，結果記錄如下。環境最終版本已重新輸出至 `requirements.lock`。
- 兩個模型的實際檔案大小與 SHA-256 均已驗證，摘要寫入 `models.json`。探針在下載完成及每次載入前都會驗證權重。
- 新增 `TaiwanASRRefinementTests.swift`，先對原 App 程式庫執行，確認兩項測試因缺少新版模型與 low 參數失敗，再修改 `AIService.swift` 與 `ReasoningConfig.swift`。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO ... build-for-testing` 實際回報 `TEST BUILD SUCCEEDED`。使用隔離 Swift harness 載入新建置的 App 程式庫，兩項 Swift Testing 測試通過。未啟動測試宿主或正式 App。
- `python -m unittest discover -s tools/taiwan-asr -p 'test_*.py' -v` 執行三項邊界測試通過，涵蓋相同大小的權重遭修改、既有結果拒絕覆寫及不相容音檔拒絕載入模型。這些不是模型品質或 App 端對端驗收。

### 最小推論實測結果

測試音檔為同一段 5.418875 秒的非私人合成中文句子，內容含時間與否定句。比對時只移除標點及空白，將數字 3 與「三」視為等價；四次結果均符合預期文字。沒有用 LLM 修正辨識結果，也沒有外送音訊。

| 項目 | Breeze-ASR-25 | TEA-ASR-1.1 |
| --- | --- | --- |
| 模型載入 | 17.589 秒 | 33.072 秒 |
| 首次推論 | 4.995 秒 | 59.982 秒 |
| 第二次推論 | 1.872 秒 | 1.473 秒 |
| 程序 peak RSS | 1,960,542,208 bytes | 929,890,304 bytes |
| 最後一次同步後的 MPS driver allocation | 3,424,731,136 bytes | 4,634,476,544 bytes |

限制：最後一列不是 GPU 峰值；程序 RSS 也不是整機統一記憶體占用，兩者不能簡單相加為總峰值。只測單句兩次，不能把第二次的數字當 p50／p95，也不能因此判定 TEA 品質優於 Breeze。

決策：維持「獨立本機服務」路線，採常駐單模型並在服務 ready 前完成預熱，不能每次錄音重新啟動模型。理由是暖機後已出現可繼續驗證的延遲，但冷啟動成本明顯。暫不採同時常駐兩個模型，因尚未取得完整記憶體壓力證據；模型切換的卸載、重新預熱與狀態提示列入第二階段必要工作。

第二階段先交付 loopback、Bearer 認證、單一推論併行、模型切換及明確取消的相容 API，再調整 App 連線驗證。先驗證冷啟動、預熱、服務停止與取消，不直接以正式使用者模式承接尚未驗收的服務。

### 潤飾套件查核新發現

已讀取本機鎖定 revision 的 LLMkit 原始碼：

- Gemini client 使用原生 Interactions API，支援 low 參數及 store=false，無需只為新增模型 ID 升級套件。
- `HTTPClient.swift` 的一般請求預設最多重試兩次，包含 HTTP 429、5xx 與部分網路例外，不能將新模型列入選單視為已滿足不重複計費要求。
- Gemini 回應目前只擷取文字步驟，Anthropic 回應目前只取第一段文字，均需補驗完成／截斷／拒絕狀態。這些是啟用真實 API 驗收前的待辦。

本次沒有直接修改套件快取或移動 Package.resolved revision，避免產生不可重現的本機套件修改。

### 證據與限制

- 建置記錄：`/tmp/wagong-asr-build.log`。
- 隔離測試：`/tmp/wagong-asr-refinement-tests/red.log` 與 `green.log`。
- Breeze 取樣：`/tmp/wagong-breeze-loading.sample.txt`。
- ASR 失敗／逾時記錄與模型完整性結果：`tools/taiwan-asr/.runtime/`。此資料夾被忽略，不進版控；暫存路徑不是備份承諾。
- 成功的原始量測：`tools/taiwan-asr/.runtime/breeze-torch214-zh.json`、`tea-torch214-zh.json`；包含固定合成音檔的轉錄文字，沒有私人內容，不放入一般日誌或版控。
- App 來源基準為 `06a876d45730ea3373292bf191b498c8d4602e17` 加目前未提交差異。最終測試產物 Build ID 為 `ASR-INTEGRATION-20261016`，沒有安裝至 `/Applications`。
- 後續 ASR API 與斷線取消已驗證，見第 11 節。真實雲端四種組合、真實口音、中英混用、App 面板取消與跨 App 插入仍未驗證，不能宣稱版本已完成。

## 11. 2026-10-16 本機 API 與 App 接入結果

### 實作內容與決策

- `tools/taiwan-asr/server.py` 提供僅綁定 127.0.0.1 的 API，必要的 Bearer 認證在讀取音訊前執行。只接受既定模型及五種 multipart 欄位，拒絕額外 Context。
- 每次只保留一個獨立模型程序。切換模型先停止舊程序；斷線與逾時停止本次 worker，再次請求重新載入。選擇可停止的程序而非單純背景執行緒，因為取消 asyncio 工作不會停止仍在 GPU 上的推論。
- 服務拒絕併行請求，回覆 429，不排隊。選擇明確拒絕而非隱藏排隊，因為本機記憶體有限，排隊結果可能跨越使用者已切換的工作階段。
- 音訊限制為 30 秒、12 MiB、未壓縮 WAV，支援單／雙聲道及 8 至 96 kHz，推論前轉為單聲道 16 kHz。暫不處理長會議，理由是目前只有短句證據，尚未驗證長音檔的分段、延遲與記憶體。
- `probe.py` 的載入器由探針及服務共同使用，固定模型 revision、權重大小與 SHA-256。Whisper 與 Qwen 產生結果達到輸出上限時均拒絕回傳截斷文字。
- App 的 `OpenAICompatibleTranscriptionService.swift` 與 `CustomModelConnectionTester.swift` 共用相同請求及回應驗證。只有成功 HTTP 狀態與非空文字才通過；不再將 400、415、422 視為成功。
- App 加入 `asr-connection-test.wav`，為 macOS Meijia 產生的非私人「語音測試」音檔。已比對原始資源與新 App Bundle 內資源的 SHA-256 相同。測試頁提示音檔會送到所填服務，可能計費。
- localhost App 請求上限 180 秒，服務推論上限 150 秒，保留冷啟動與清理餘裕。冷啟動不是日常暖機延遲，使用前以有效測試音檔預熱。
- `NativeRefinementClient.swift` 保留原本 Gemini Interactions 與 Anthropic Messages 協定，增加完整完成狀態檢查。Gemini 必須 completed 且最後為文字 model_output；Claude 必須 end_turn 且有文字。拒絕截斷、拒絕或工具執行狀態，不將部分文字當成功。
- 原生 Gemini／Claude 與自訂 ASR 共同使用 `SingleRequestHTTPTransport.swift`，每次只送一次，拒絕重新導向，不持久快取請求。原生 Gemini／Claude 的外層逾時重試亦被禁用，即使既有設定明確啟用仍不自動重送，因為逾時無法證明伺服器尚未處理或計費。其他既有 Provider 的重試政策未在本任務改寫。
- 選擇 App 端可測試的 client 與共用傳輸，否決直接修改 LLMkit 套件快取，因為快取修改無法透過既有 lock file 重現，也會在重新解析依賴後消失。LLMkit 仍提供共用訊息型別及其他未改動功能。

### 取消測試與量測修正

第一次真實服務測試發現短清理等待可能掩蓋原始錯誤。第二次發現斷線未可靠到達處理器。縮小為不載入模型的真實 TCP 測試後，又發現若在處理器進入前就用極短逾時取消，不能以「處理器未收到取消」判斷失敗。

最終測試先確認處理器／模型 worker 已進入，再關閉連線。實作改用獨立 ASGI 斷線監聽及明確事件，不依賴被取消作用域包住的 receive 輪詢。該短回歸測試及第三次完整模型驗證均通過。保留失敗紀錄，沒有以模擬測試的成功掩蓋先前的真實路徑失敗。

### 實際通過的層級

| 層級 | 執行內容與結果 | 證據 |
| --- | --- | --- |
| App 建置 | CODE_SIGNING_ALLOWED=NO 的 build-for-testing 通過，不代表簽署或安裝通過。 | `/tmp/wagong-asr-build.log` |
| App 邏輯 | 隔離 harness 連結實際 App 程式庫，14 項測試涵蓋模型選項、參數、ASR 契約、回應完整性、單次傳輸、外層逾時重送阻擋與取消。 | `/tmp/wagong-asr-refinement-tests/complete.log` |
| 既有重試回歸 | 另執行 6 項既有 EnhancementRequestRetryTests，全部通過，確認未指定原生 Provider 的既有行為仍相容。 | `/tmp/wagong-asr-refinement-tests/retry-regression.log` |
| Python 邊界與 HTTP | 13 項測試通過，含損毀權重、截斷結果、音檔限制、請求契約、認證與實際 TCP 斷線。 | `/tmp/wagong-asr-server-tests.log` |
| 真實服務 | 真實 Uvicorn、HTTP、兩個模型 worker、認證反例、忙碌拒絕、切換、斷線及恢復均通過。 | `tools/taiwan-asr/.runtime/live-service-check-3.json`、`/tmp/wagong-asr-live-service-3.log` |
| 實際 App 傳輸 | `verify_transport.swift` 連結實際 App 程式庫，以真實 localhost 服務驗證 App 請求建立、URLSession 傳送與回應解析。 | 上述服務結果的 actual_app_transport_passed=true |

最後一次完整服務測試使用固定 5.419 秒合成句，TEA 第一次 HTTP 請求約 50.84 秒，第二次約 1.10 秒；切換至 Breeze 約 25.63 秒，取消後重新載入 Breeze 約 34.87 秒。這包含當次服務與程序成本，不是穩態統計。Breeze 及 TEA 的文字均符合固定語料，App 傳輸亦通過。

取消測試先確認新的 TEA worker 已啟動，再關閉 TCP 連線。服務記錄 status=499，該次 worker 路徑約 0.12 秒就進入停止處理；此數字不是 App 面板取消至 GPU 記憶體完全回收的量測。服務可隨後重新載入 Breeze 並成功轉錄。驗證結束已停止伺服器與模型程序，隨機測試 token 未保存。

### 產物與未變更範圍

- 模型與環境分別位於 `tools/taiwan-asr/.runtime`（約 6.7 GiB）與 `.venv`（約 1.3 GiB），均被 gitignore 排除。僅清理本次建立的安裝快取，未刪除使用者既有模型或 Xcode 資料。
- 測試產生的 coverage 資料改放 `.runtime`；已保留本次意外寫入 default.profraw 的產物並還原其原有空白佔位內容。
- 未修改既有快速鍵與鍵盤診斷差異，未修改使用者實際模式、UserDefaults 或 Keychain。
- 沒有安裝／啟動新 App，沒有與正式 App 同時執行測試宿主，沒有 commit、push 或發布。
- 四種使用者模式仍待新 App 實機驗收時建立；目前只新增可選模型及接入能力，沒有覆寫既有模式。

## 12. 已核准雲端測試與完整驗收阻擋

### 已核准的四組請求與實際執行結果

`tools/taiwan-asr/verify_refinement.swift` 預設停用外部呼叫，不讀 Keychain。2026-10-16 使用者已明確核准下列最多四次請求，驗收工具已設定 WAGONG_ALLOW_BILLABLE_VALIDATION=yes 執行一次。實際在金鑰讀取階段停止，未發送任何雲端請求。

| 次數 | 來源 | 目的地與模型 | 輸出上限 |
| --- | --- | --- | --- |
| 1 | Breeze 的固定合成轉錄 | Google 原生 Gemini API，gemini-3.8-flash | 2048 tokens，low，store=false |
| 2 | Breeze 的固定合成轉錄 | Anthropic Messages API，claude-haiku-5-5 | 512 tokens |
| 3 | TEA 的固定合成轉錄 | Google 原生 Gemini API，gemini-3.8-flash | 2048 tokens，low，store=false |
| 4 | TEA 的固定合成轉錄 | Anthropic Messages API，claude-haiku-5-5 | 512 tokens |

目的地固定為 `https://generativelanguage.googleapis.com/v1/interactions` 與 `https://api.anthropic.com/v1/messages` ，不經第三方轉接服務。

待送文字只來自本次已核對的非私人合成句「今天下午三點開會，請保留原始資料，不要刪除。」兩模型的原始輸出。工具會先核對來源符合此固定內容；不傳送錄音、歷史文字、剪貼簿、OCR 或其他 Context。使用既有已設定的兩個 API Key，任一缺少時不送請求。最多四次，任一失敗立即停止，不重送，也不變更 App 的設定。

固定 system instruction：

```text
請將語音轉錄整理成台灣繁體中文。只修正標點與繁簡字，不改變詞序及用字，保留原意、否定、時間與數字，不得新增事實。只輸出整理後的文字。
```

依每次輸入 500 tokens 的保守估算與上述輸出上限，四次合計約 US$0.017，可抓 US$0.03 測試預算。此為該四次固定請求的估算，不是帳戶層級的總費用上限。價格查核日為 2026-10-16，依 [Google 官方 Gemini 價格](https://ai.google.dev/gemini-api/docs/pricing) 的導入價格與 [Anthropic 官方 Haiku 5.5 價格](https://www.anthropic.com/claude-haiku-5-5) 計算，實際以供應商帳務為準。

### 2026-10-16 本次驗收的已驗證範圍

- 工具改用 Security framework 的唯讀查詢，避開 App KeychainService 可能觸發的舊資料遷移，且禁止互動式認證提示。原因是本次只核准使用既有金鑰，不包含遷移或改寫 App 設定。
- `swift build --package-path /tmp/wagong-asr-refinement-tests --product RefinementAcceptance` 通過，來源與 repo 的 `verify_refinement.swift` 逐位元相符。證據：`/tmp/wagong-asr-refinement-tests/approved-runner-build.log`。一般沙盒下首次編譯因全域 module cache 寫入限制失敗，取得編譯權限後成功，並非原始碼編譯錯誤。
- 以核准環境旗標執行工具一次，exit=1。`geminiAPIKey` 在 App Local 與 production Data Protection Keychain 查詢均回傳 -25300（errSecItemNotFound），工具在第一個請求建立前停止。證據：`/tmp/wagong-asr-refinement-tests/approved-cloud-acceptance.log`。
- 另以唯讀 metadata 查詢核對 App 兩個 service 在兩種 Keychain 模式下的可見性，均回傳 -25300。已安裝 App 的 CFBundleIdentifier 確認為 com.jackie-yeh.wagong；App preferences domain 存在，兩個舊 LocalKeychain 欄位均不存在。核對腳本：`/tmp/wagong-asr-credential-inventory.swift`，未輸出任何金鑰值。
- 上述證據只證明命令列程序無法取得既有 App 金鑰。未以已知可讀的 App 金鑰取得陽性對照，也未從已安裝 App 本身執行讀取，因此不據此斷言使用者未設定金鑰；App 身分與 Keychain 可見性仍需釐清。
- 本次發送請求數為 0，沒有重送，沒有私人資料外送。四組真實雲端結果全部未驗證，不能推論模型可用性、帳號權限、實際價格或輸出品質。沒有改寫 App 的 UserDefaults 或 Keychain。
- 重啟條件：確認 App 中兩個 Provider 的既有金鑰設定，以及驗收程序可讀取的授權儲存位置。金鑰不得貼到對話、指令參數或檔案。原核准的四次額度尚未使用；不得改用其他服務或增加測試範圍。

### 未勾選項目的重啟條件

第 7 節未勾選項目均阻擋宣稱完整功能／版本完成，按以下條件重啟，不因原始碼或單層測試通過而略過：

- 雲端呼叫、失敗回復、原始轉錄保留及完成狀態：上述四次付費驗證已取得同意，目前等待釐清 Keychain 存取。完成這四次只可證明固定合成文字的成功路徑，失敗回復與原始轉錄保留仍須各自取得完整 App 路徑證據；不把本機 200 回應或 mock 當成真實 Provider 成功。
- HUD 目的地、面板取消、模式切換、晚到貼上與跨 App 交付：安裝可追溯 Build ID 的測試 App，先停止共用 Bundle ID 的正式 App／宿主，再由使用者以非私人語料實測。
- 真實中文、中英混用、純英文、人物與金額保真：取得可用的非私人／明確授權語料後，比較原始 ASR 與潤飾結果。單句 smoke test 不代替品質評比。
- 重複使用時的 p50／p95、統一記憶體峰值及模型切換壓力：在固定環境達穩態、具有足夠樣本後量測，不從目前兩次結果推論容量或支援機型。
- 重新導向、非正常終止及 multipart 實際落盤暫存檔的完整清理矩陣：補做對應故障測試；目前已有拒絕重新導向與表單關閉程式路徑，但未把未跑過的故障路徑標為已驗證。
- 授權與散布告知：只在準備對外散布 App／服務或模型時完成完整授權清單及發布檢查，本次未散布權重，不以模型卡標籤替代散布審查。
- 新版本可見性：最後對照 source SHA、Bundle 與執行程序 Build ID，確認使用者實際開啟的是新碼。發布版號及 changelog、簽署、公證另行處理。

依本次載入的共用規則 `~/dotfiles/agent-rules/CLAUDE.md` 第 29 行「在執行任何具外部影響或破壞性的動作前，必須先把完整內容與影響範圍貼出來給我確認，收到明確同意後才執行」。使用者已核准上述範圍，本次未因額外確認而停止；目前阻擋是命令列驗收程序無法取得 App 的既有金鑰。
