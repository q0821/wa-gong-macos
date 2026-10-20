# TEA／Qwen3-ASR 與 Ollama 全本機模型整合計畫

規劃與查證日期：2026-10-16。

狀態：核心接入與保護機制已實作，品質尚未全數放行。TEA 解碼與受控程序取消有真實證據；兩組共八次完整核心串接完成，但逐筆內容檢查發現 Qwen 中英混用新增用字，最終保護會拒絕該結果並保留原始轉錄。三次修復試驗後已停止模型重跑。新版測試 App 已依使用者授權安裝並啟動，實機與發布未放行。首輪證據見第 10 節，品質判定見第 11 節，最新安裝紀錄見第 12 節。

## 1. 目標與範圍

新增兩組可由使用者選用的全本機流程：

| 模式範本 | 辨識模型 | 文字整理模型 | 評估重點 |
| --- | --- | --- | --- |
| 台灣中文本機輸入 | TEA-ASR 1.1，Q6_K GGUF | Ollama 的 qwen3.5:9b | 台灣用詞、繁體輸出與中英夾雜品質。 |
| 快速本機輸入 | Qwen3-ASR 0.6B，Q8_0 GGUF | Ollama 的 qwen3.5:9b | ASR 等待時間及資源需求，整組仍包含 9B 整理模型。 |

目標資料流：錄音 → 所選本機 ASR → 保留原始轉錄 → 本機 Ollama 整理 → 既有交付流程。兩個 ASR 互為選項，不串接、不自動替換。

「全本機」僅在 ASR 於本機執行、Ollama 目的地為 loopback、模型已下載且測試未發生外部推論連線時成立。模型下載需要網路，不能將安裝與推論混稱完全離線。

本計畫補充既有功能實作計畫，該計畫的測試先行與功能分段原則仍適用。先前 [Breeze／TEA 與雲端整理計畫](BREEZE_TEA_INTEGRATION_PLAN.md) 保留原紀錄；雲端金鑰阻擋不應阻擋此全本機路線。

### 本次不處理的範圍與理由

- 不重寫快速鍵、錄音、貼上或鍵盤診斷。理由是本次需求只改變辨識與整理模型。
- 不移植 Hyday Talk 的 App、筆記整合、自動學習或完整 UI。理由是使用者要導入模型組合，現有聲筆流程可沿用。
- 不刪除 Breeze、Whisper、Cohere、雲端 Provider 或先前建立的 Python 服務與模型。理由是需要保留回歸基準與使用者既有設定。
- 不自動改變預設模型、既有模式或全域 Ollama 選項。理由是新組合尚未在目標機器完成品質與效能驗收。
- 不自動降級為其他模型，也不在失敗時送往雲端。理由是那會改變使用者選擇、隱私範圍及測試結果。
- 不隨 App 內附模型權重、不新增區網服務、不開放免認證 API、不改現有 API Key 規則。理由是原生本機 ASR 無須透過自訂 HTTP 服務接入。
- 規劃輪次不執行下載、安裝或推論；2026-10-16 使用者已核准第一階段，執行隔離模型下載與探針。此次仍不執行 App 功能修改、App 安裝、commit、push、公證或發布，避免跨入尚未開始的後續階段。

## 2. 目前程式碼與依賴基準

查證以目前工作目錄為準，HEAD 為 `06a876d`，另有本次對話先前的 ASR／雲端整合差異及既有鍵盤差異，不能只以 HEAD 代表完整原始碼。

| 已查證內容 | 證據與缺口 |
| --- | --- |
| 已有 transcribe.cpp 模型下載、大小與 SHA-256 檢查 | `VoiceInk/Transcription/TranscribeCpp/TranscribeCppModelManager.swift` 與 `TranscribeCppModelCatalog.swift`；目前清單只有 Cohere。 |
| 已有原生轉錄路由 | `TranscribeCppTranscriptionService.swift` 只分派至 Cohere，未知模型會拒絕。TEA 與 Qwen 尚未接入。 |
| Swift binding 已固定版本 | `Package.resolved` 的 Transcribe-cpp-swift 為 `0.2.0-dev.856d7c1`，revision `fb1c1ad99e8939a69fcfb613417d9635fb77ef42`。套件 UPSTREAM.md 記載底層來源為 `856d7c10a1a864b900e066b7c9801edf373f5148`。二進位實際能力仍需探針驗證。 |
| Hyday 使用不同底層來源 | 固定 commit `24f351686386e0c403578796f69ece4e6e437a9b` 的建置腳本使用 transcribe.cpp `f1dcd15858c4bbba87ca97862b4e448b2cf15b8f` 與 CLI。不能由同名引擎推論兩邊能力完全一致。 |
| 已有 Ollama 模型清單與整理 | `VoiceInk/Services/OllamaService.swift` 會讀取已安裝模型並送出 `think=false`；本機管理 UI 目前提供連線、重新整理與選擇，沒有安裝模型流程。 |
| Ollama 完成檢查有缺口 | 固定的 LLMkit revision `3b9086e3df729f39c2ca8951d09fb6ef4d4a193b` 中，OllamaClient 只解析 response，沒有驗證 done／done_reason；temperature 放於頂層，需依官方 options 格式驗證並修正本次使用路徑。 |
| 模式可分別指定 ASR 與整理模型 | `Modes/ModeRuntimeConfiguration.swift` 與 `Transcription/Engine/TranscriptionPipeline.swift` 可沿用。須確認模式的模型快照不會被全域切換覆蓋。 |
| 已有辭典快照與輸出保護 | `Services/VocabularySnapshot.swift` 已有能力判斷。新的 ASR 分支須另行接線，不能只因模型支援 hotwords 就標示辭典已生效。 |
| 端點已有 HTTPS 與 loopback 限制 | `Services/CustomEndpointPolicy.swift` 允許遠端 HTTPS，因此「Ollama Provider」本身不等於「全本機」。新範本須額外驗證實際目的地。 |

## 3. 模型產物與下載策略

以下為 2026-10-16 以 Hugging Face API 唯讀核對的候選產物 metadata，尚未下載或驗證推論品質。GB 使用十進位，檔案大小不等於執行記憶體。

| 項目 | TEA-ASR 1.1 | Qwen3-ASR 0.6B |
| --- | --- | --- |
| 格式 | transcribe.cpp 單檔 Q6_K GGUF | transcribe.cpp 單檔 Q8_0 GGUF |
| 來源 | mukiwu/TEA-ASR-1.1-transcribe-gguf | handy-computer/Qwen3-ASR-0.6B-gguf |
| revision | `83f5b0668c4718db9f16e43940c83bef7e61df61` | `28c66fba077f1359a42b52c55b618a24cdb6e0e7` |
| 檔名 | `TEA-ASR-1.1-Q6_K.gguf` | `Qwen3-ASR-0.6B-Q8_0.gguf` |
| 位元組 | 1,692,286,464，約 1.69 GB | 850,423,456，約 850 MB |
| SHA-256 | `2417fa52d49f852bfc11704190e10ddb681c343a661a3a3d1bb213876c780b68` | `f081b2d5e23bd669d92cc331d722a8a0681943b8e6f34b48996fd5c319b5acd8` |

TEA 是第三方轉換版本，不是作者直接提供的原始 safetensors。必須確認包含 TEA 自己的 tokenizer、tensor 與輸出繁體能力，不能換成任意同名 GGUF。TEA 模型卡列 MIT，且明述底層 Qwen 權重仍受 Apache-2.0 與 attribution／NOTICE 要求約束，發布時一併列出。

qwen3.5:9b 使用 Ollama 官方 library。官方頁面本次顯示約 7.6 GB，tag 可變，不能把此大小或頁面短 digest 當成不可變鎖定值。驗收時記錄實際 Ollama 版本、模型完整 digest、量化、下載大小與設定，更新後重跑基準；本次尚未確認目標機器已安裝或可執行。

兩個 ASR 加整理模型約需 10 GB 的權重儲存量，另計既有 Python 權重、下載暫存與建置空間。下載前依實際剩餘 layer／檔案及驗證暫存估算空間；空間不足就明示停止，不自動清理其他模型或使用者資料。

## 4. 接入決策與替代方案

### 4.1 ASR 優先使用既有原生 binding

選擇：先以較小的 Qwen3-ASR 0.6B 驗證既有 Swift binding／binary，再加入共用架構的 TEA；產品推薦仍以 TEA 台灣中文候選為主。

理由：可沿用模型管理、取消與模式路由，避免新增 Python 環境、HTTP token 與常駐服務。先驗證底模可將引擎問題與 TEA 轉換問題分開定位。

否決直接把 GGUF 加到清單就完成：目前路由只有 Cohere，且 binary、語言參數、詞彙提示及取消介面尚未取得真實證據。

若現有 binding 不具必要能力，先比較底層差異，再提出最小的版本升級或受控 CLI 橋接方案。以相同語料跑通兩個模型及既有 Cohere 回歸後才決定。未證實需要前不升級套件、不編輯套件快取，也不默默改用 Python 路線。

### 4.2 整理沿用 Ollama，補齊 App 端請求契約

選擇：沿用現有 Ollama Provider 與模式欄位，在 App 端補齊可測試的原生請求與完整回應檢查。

理由：固定套件的公開 generate 介面只回傳字串，無法供 App 判斷結果是否截斷。App 端可沿用已建立的 SingleRequestHTTPTransport，集中處理取消、逾時與禁止重新導向。

否決為了單一模型直接全面升級 LLMkit 或覆寫所有 Provider：影響範圍超出本次模型組合，且已有局部接入能力。

候選設定：`POST /api/generate`、`stream=false`、`think=false`；sampling 放在 `options`。先比較既有 temperature=0.3 與低溫設定，不預設改掉所有模型的採樣行為。以 `/api/show` 核對模型能力，驗證不接受參數時明示錯誤，不偷偷移除限制。

成功需同時符合 HTTP 成功、有效 JSON、done=true、已驗證的正常完成原因及非空 response。截斷、只回傳 thinking、工具輸出或未知完成原因均不得交付。實測確定長度上限與超限提示後才開放長文字，不無限制提高 context。

### 4.3 安裝分兩步交付

第一步先用已明確安裝的 Ollama 與模型驗證組合，介面提供安裝指引與缺少模型狀態。理由是先取得模型品質與效能證據，再投入下載管理 UI。

第二步在本機組合驗收通過後，增加 App 內「下載 qwen3.5:9b」功能，呼叫本機 `/api/pull`、顯示進度與錯誤，完成後重新核對 `/api/tags` 的 digest。僅支援 loopback 下載操作，不修改遠端 Ollama 的模型庫。Ollama 軟體本身仍由使用者安裝，不執行未展示的安裝腳本。

取消 pull 後停止本次訂閱與 App 後續處理，但是否停止 Ollama 背景下載必須實測；不得宣稱 UI 取消等同伺服器已停止，也不刪除其他 App 共用的 layer。

## 5. 實作階段與放行條件

### 階段 1：相容性與資源探針

**狀態：進行中，第一輪探針已執行，阻擋與未驗事項見第 10 節。**

- 紀錄目標 Mac、記憶體、作業系統、剩餘磁碟與 Ollama 實際版本，確認目前 App／測試 App 的執行狀態。
- 固定來源並驗證候選 GGUF 的大小與 SHA-256，保留原始模型，拒絕損毀或混用 tokenizer 的產物。
- 使用不啟動 App 的隔離探針驗證現有 transcribe.cpp binary 能否載入 Qwen，再載入 TEA，驗證語言、繁體、英文與取消。
- Ollama 先用固定非私人文字驗證 qwen3.5:9b，記錄完整 digest、完成原因、冷啟動與暖機延遲。
- 比較 ASR 常駐與 ASR 釋放後再整理的兩種策略，量測記憶體壓力、swap 增量與總等待時間。不沿用 Python 推論的數字推論 GGUF 效能。

**成功標準：** 三個模型各自真實推論成功，兩組串接皆有可重現證據，取消與錯誤可觀測。若 binary 不相容，先記錄差異與最小修正方案，後續階段不得以假成功繼續。

### 階段 2：原生 ASR 模型接入

**狀態：進行中，採受控 GGUF worker 經既有自訂 ASR 路徑接入；內建模型卡與下載尚未完成。**

- 擴充 TranscribeCppModelCatalog、模型清單、TranscribeCppTranscriptionService，新增 Qwen／TEA 共用服務；保留 Cohere 原路由。
- 沿用下載校驗與 App 模型卡，補足架構、量化、檔案大小與未下載狀態，不自動下載兩個模型。
- 接入 16 kHz 音訊、語言選項、安靜／空白錄音、分段與截斷檢查。分段長度依引擎實測決定，不直接複製 Cohere 的 35 秒。
- 模型切換、取消、關閉面板及新 session 必須取消舊作業並阻擋晚到結果，僅卸載本 App 持有且未使用中的模型。
- 辭典沿用 VocabularySnapshot；先驗證底層是否能傳 context／詞彙，未支援就顯示 unsupported，不把一般 prompt 當成詞彙介面。

**成功標準：** App 實際路由可選兩個模型，下載、缺檔、錯誤與取消均有測試；實際錄音端對端仍於階段 4 驗收。

### 階段 3：Ollama 整理與資源管理

**狀態：進行中，App client 與保留原文的拒絕路徑已實作，實機驗收尚未開始。**

- 以固定模型快照呼叫 qwen3.5:9b，補齊完成判斷、輸出限制、逾時與取消，測試舊 Ollama 模型相容性。
- 沿用既有台灣繁體中文提示詞，加入原始數字、金額、日期、否定、英文與專有名詞保護；先與 ASR 原文比較，避免把 ASR 錯誤與整理新增錯誤混為一談。
- 整理失敗顯示原因並保留原始轉錄；取消時不貼上原文或新結果；不自動重送或轉送雲端。
- 依階段 1 數據決定 ASR 駐留與 Ollama keep_alive 策略，明示冷啟動狀態，設定有限的載入與生成期限。
- 不自動卸載其他程序正在使用的 Ollama 模型。取消 HTTP 不等於伺服器已停止推論，須取得程序／服務端證據或列明限制。

**成功標準：** 正常、截斷、空白、逾時、取消、模型不存在及服務未啟動均走完整 App 處理路徑，原始轉錄保留且不發生晚到交付。

### 階段 4：模式與實機驗收

**狀態：未開始。**

- 提供兩個可由使用者建立的模式範本，保留既有模式與預設值；同名範本不得覆蓋既有設定。
- 全本機範本限制 Ollama 為 loopback，停用雲端 Context 與外部推論回退；自訂遠端 Ollama 仍可保留，但不標示為全本機。
- 依 BUILDING.md 的受支援測試 App 交付流程安排實機驗收。該流程會安裝與啟動 App，執行前處理共享 Bundle ID／資料位置與程序衝突，不能直接與正式 App 同時開啟。
- 完成下節語料與故障矩陣，再決定是否推薦為日常模式，不在結果未知前設成全域預設。
- 第二步下載 UI 視此階段結果另行交付；未完成時明列「需先在 Ollama 安裝模型」。

**成功標準：** 兩組由麥克風開始、整理至跨 App 交付皆有證據，來源／Bundle／執行程序 Build ID 一致，斷網推論與取消驗收通過。

## 6. 驗收語料與量測方式

先建立至少 40 句非私人、可重複播放且附人工參考稿的語料，台灣口語、中英混用、人物／產品／術語、數字／時間／金額／否定各至少 10 句。第一輪採短錄音，另做 30 秒及跨分段邊界案例；模型實際上限確認前不承諾長錄音支援。

- 同一音檔分別跑兩個 ASR，再以相同整理提示詞送入相同 digest 的 qwen3.5:9b。紀錄辨識前後與整理前後差異，區分兩層錯誤。
- 評估內容辨識的 CER／MER，以及獨立的繁體與台灣用詞符合度。不得透過繁簡正規化後的低錯誤率宣稱繁體品質已驗證。
- 使用公開基準加上使用者授權語料，不把模型作者自測成績當成本機量化版本的結果。
- 固定 ASR 參數、Ollama digest／options／context，先達穩態再取得至少 30 次暖機樣本；冷啟動另外統計。紀錄停止錄音至 ASR 完成、整理完成與交付的各段 p50／p95。
- 同步記錄程序與系統記憶體壓力、swap 變化及模型釋放結果。明確區分目前配置值、實際值與峰值。
- 輸出保護案例中的金額、日期、否定與英文遺失或改義均阻擋該模式放行，不由平均分數掩蓋。錯誤拒絕也需統計，不能只靠全面拒絕提高保真。
- 延遲門檻在階段 1 取得目標機器基準後、階段 4 前定案並寫回本文件；未定案前只能報數值，不能宣稱速度達標。
- 真實測試包含麥克風、備忘錄、另一個輸入 App、焦點切換、面板關閉、連續兩次錄音及整理中取消；每次取消都確認無 HUD 復活或晚到貼上。
- 模型已備妥後斷網測試兩組完整流程，搭配網路觀察核對無外部推論流量。下載與更新流量分開記錄。

## 7. 預計檔案影響範圍

以下為實作候選，不代表本輪已修改：

| 檔案或模組 | 預計變更 |
| --- | --- |
| TranscribeCppModelCatalog.swift、Models/TranscriptionModel.swift、TranscriptionModelManager.swift | 固定兩個 GGUF 產物與模型登錄、能力及可用狀態。 |
| TranscribeCppTranscriptionService.swift、新增 QwenASRTranscriptionService.swift | Qwen／TEA 路由、語言、分段、模型生命週期與取消。 |
| TranscribeCppModelManager.swift | 優先沿用；僅為兩個新模型的必要行為調整，勿重構無關下載流程。 |
| OllamaService.swift、新增 OllamaRefinementClient.swift | 參數、完整回應判斷、受控單次傳輸、資源設定與相容行為。 |
| AIEnhancementService.swift、EnhancementRequestRetry.swift | 檢查 Ollama 是否仍被外層重試，取消及失敗保留原文；僅必要時修改。 |
| VocabularySnapshot.swift 與模式／pipeline 相關檔案 | 能力宣告、詞彙接入、模式快照及全本機目的地約束。 |
| ProviderLocalManagementView.swift、模型卡、模式範本所在介面、Localizable.xcstrings | 推薦組合、未安裝／載入／下載狀態、繁中提示及後續下載功能。 |
| VoiceInkTests／獨立推論探針 | 新增行為測試與真實模型測試，Cohere、既有 Ollama 與取消路徑回歸。 |
| README、BUILDING、授權清單與本計畫 | 實作時同步使用方式、版本／產物證據與限制；只寫已完成結果。 |

## 8. 實作前與完工自查清單

以下均為待實作／驗收項目，規劃時不打勾。每項完成須附指令、結果或實機紀錄；未完成就保留阻擋與重啟條件。

### 範圍與規則執行

- [ ] 未修改既有鍵盤差異、預設模式或無關 Provider，未刪除既有模型。
- [ ] 「全本機」在實際 request 目的地執行檢查，測試包含遠端 HTTPS、重新導向與設定中途變更反例。
- [ ] 模型／模式／session ID 固定於請求快照，舊結果無法回寫新 session。

### 隱私、下載與第三方依賴

- [ ] 音訊、文字、詞彙、金鑰及私人路徑不進一般日誌；錯誤不原樣輸出遠端 body 或含資料的 URL。
- [ ] ASR 來源、revision、大小與 SHA-256 固定；下載前查空間，拒絕損毀與非一般檔案，驗證完成才登錄可用。
- [ ] Ollama 完整 digest、實際版本與 options 可追溯，tag 改變後不沿用舊驗收結論。
- [ ] 安裝／下載只由明確操作觸發，僅管理本次模型，不刪除共用 layer 或執行隱藏安裝指令。
- [ ] TEA 原始模型、第三方轉換、Qwen 底模與推論引擎的 LICENSE／NOTICE 分別核對。模型授權不當成 Hyday App 程式碼授權。

### 非同步、資源與輸出正確性

- [ ] 取消、逾時、模型切換、視窗關閉及 App 結束無晚到結果、重試或貼上，實際模型作業是否停止另有證據。
- [ ] HTTP、JSON、done、done_reason、空白、截斷與 thinking-only 均有正反例。
- [ ] 長錄音分段與跨段詞句無遺失、重複或無聲截斷；語言不支援時明確拒絕。
- [ ] 辭典能力顯示與真實參數一致，包含詞彙造成幻覺與未提供詞彙的對照。
- [ ] 冷／暖啟動、p50／p95、系統記憶體壓力與 swap 有穩態量測；失敗保留原始轉錄且不轉雲端。

### 介面、回歸與實機

- [ ] 繁體中文、鍵盤操作、VoiceOver、下載錯誤與取消狀態可辨識，UI 不暴露不必要的推論內部細節。
- [ ] 舊 Cohere、Whisper、Ollama 自訂模型與既有模式回歸通過，不要求全部改用新 client 的專屬參數。
- [ ] 新 App 的實際 Build ID、錄音、跨 App 交付、焦點變更與斷網驗收逐項確認。
- [ ] 原始碼測試、模型探針、App 實機與發布證據分層回報，未完成項目明列阻擋。

### 不適用項目

- 資料庫 schema、資料回填、Filament、Web CSRF、帳號／付費權限：本次沒有新增相關介面或 migration。
- 寄信、SMS、webhook、排程與時區業務計算：本次不涉及；量測時間使用單調時鐘。
- 公開服務 SSRF 防護：本次不建立公開端點；本機 Ollama 是刻意允許的 loopback，不能套用一律阻擋 localhost 的通用規則。

## 9. 證據來源與目前待決事項

- [Hyday 固定版本模型清單](https://github.com/mukiwu/hyday-talk/blob/24f351686386e0c403578796f69ece4e6e437a9b/Sources/TalkCore/LocalSpeechModels.swift)：候選模型與格式參考，沒有移植其 App 程式碼。
- [TEA 轉換來源 metadata](https://huggingface.co/api/models/mukiwu/TEA-ASR-1.1-transcribe-gguf?blobs=true) 與 [Qwen GGUF metadata](https://huggingface.co/api/models/handy-computer/Qwen3-ASR-0.6B-gguf?blobs=true)：本次唯讀核對 revision、大小、雜湊與授權標籤。
- [TEA 官方模型卡](https://huggingface.co/JacobLinCool/TEA-ASR-1.1)：台灣中文定位、tokenizer、context 與底模授權說明，作者成績不作為本 App 驗收。
- [Qwen3-ASR 官方模型卡](https://huggingface.co/Qwen/Qwen3-ASR-0.6B)：底模能力與使用來源。
- [Ollama qwen3.5:9b](https://ollama.com/library/qwen3.5:9b) 與 [Generate API](https://docs.ollama.com/api/generate)：模型取得與完成狀態、think、options、keep_alive 契約。
- 當前工具清單沒有 Context7，因此本次以固定套件原始碼及官方文件查證，不宣稱已使用 Context7。

目前待決事項：既有 binary 的 Qwen 真實能力、TEA 量化品質、目標機器的 Ollama 最低相容版本與實際 digest、資源策略及可接受延遲門檻。均安排於階段 1 取得證據後定案，不先填成已完成。


## 10. 第一階段執行紀錄（2026-10-16）

本節保留首輪結果與當時未通過的證據，不能覆蓋第 11 節的後續修正，也不會將舊反例改成通過。

### 環境與產物

- 已驗證：MacBookPro18,3，arm64，16 GiB 記憶體，macOS 27.0.1（26A434）。初查可用磁碟約 14 GiB，後續可用量隨系統狀態變動，下載器保留至少 3 GiB，不自動清理其他資料。
- 初查 PATH 無 Ollama 指令、Applications 未見 Ollama，127.0.0.1:11434 無服務回應；這是該查核範圍的結果，不用來推論所有可能安裝位置均不存在。
- 新增 `tools/local-model-probe/`，下載、模型及輸出置於 gitignore 的 `.runtime`；官方 Ollama 可攜版固定為 0.40.5，沒有安裝到 Applications 或註冊系統服務。
- Qwen 與 TEA GGUF 已下載，大小與 SHA-256 符合第 3 節。Ollama 官方 tgz 亦已通過 SHA-256。慢速 GitHub 下載採用同一官方產物的分段續傳，完整校驗後才解壓；沒有換成其他來源版本。
- Ollama registry 本次回傳的完整 manifest SHA-256 為 `56671c2ab9385f9cfcb404638e32cd62d88e3501d44822208363c010179a3c90`，模型 layers 合計 6,550,825,373 bytes，與網頁顯示約 7.6 GB 有差異。以 `tools/local-model-probe/ollama-model.json` 保存此次內容，不把 tag 或網頁大小當成固定產物。

### 已跑出的原生 ASR 結果

獨立探針編譯自 App 已快取的 Swift binding，連結同一 CTranscribe framework，不啟動 App；執行回報原生版本 0.2.0、commit 856d7c1，Metal 可用，模型 backend 為 MTL0。

| 指標 | Qwen3-ASR 0.6B Q8_0 | TEA-ASR 1.1 Q6_K |
| --- | --- | --- |
| 四句合成語料各跑兩次 | 8 次均有非空且未截斷文字 | 8 次均有非空且未截斷文字 |
| 載入時間，當次樣本 | 約 1.56 秒 | 約 3.34 秒 |
| 每句第二次辨識，音訊約 4 至 5 秒 | 約 0.24 至 0.30 秒 | 約 0.35 至 0.56 秒 |
| 探針程序 sampled RSS peak | 約 1.55 GB | 約 2.79 GB |
| 文字觀察 | 中文為簡體；固定英文與中英混用句有保留 | 繁體中文，但 6／8 筆含私用區字元，不能直接交付 |

數字來源為 `.runtime/qwen-final-native-summary.json` 與 `.runtime/tea-final-native-summary.json`。它們保留本次實際執行結果，但不作為修正後探針或整體驗收通過證據。兩次樣本、下載期間量測與 sampled RSS 均不是穩態 p50／p95、統一記憶體峰值或機型支援承諾。

TEA 差異有具體來源：既有官方 TEA tokenizer.json 的 decoder 為 ByteLevel 後接 Replace，明確移除 `[\ue000-\uf8ff]+`。GGUF 原生路徑輸出保留該範圍。已保存 `.runtime/tea-decoder-difference.json`，但尚未在 App 接入這項解碼語意。後續 Ollama 對照會明確記錄是否套用該官方規則，不讓 LLM 整理掩蓋原始 ASR 問題。

### 原生取消測試的失敗與量測限制

- 第一次探針以重複約 32 秒音訊、nCtx=512 測取消，先回 inputTooLong，未觸及取消路徑。不能將其當成取消失效。
- 改為約 21.68 秒、nCtx=2048 後，未取消對照可正常完成；取消探針仍回傳成功且 wasAborted=false，沒有取得可接受的原生取消證據。成功返回分支未記錄 timer callback 的陽性確認，因此目前不斷言底層忽略取消的完整根因。
- 舊探針在持有 Metal 物件時直接 exit，結束階段發生資源 assertion。此為探針生命週期問題，不能直接宣稱 App 或引擎正常結束必定崩潰。
- 修正探針時有一次 Int／Int32 編譯失敗，但檢查命令最後一步遮蔽了失敗 exit code，後續誤用舊執行檔。已如實保留原結果，達三次失敗後停止該取消路徑，不再重試。
- 工具已修正先釋放物件再 exit，並加入原始碼、binary 的 SHA-256 build fingerprint；修正版已編譯與核對 fingerprint，未再重跑原生取消，因此不能將此工具修正算成取消功能已通過。

### 網路限制與工具檢查

`loopback-only.sb` 只限制本次 Ollama 程序及其子程序的對外連線，不影響整台 Mac 網路。先前 profile 使用數字 IP 的語法不受此 macOS 版本支援，後續 curl 又隱藏了底層 errno，兩者均未算作通過。最後以 socket 做正反例：

- 隔離程序外連同一公開 registry IP 的 TCP 443 成功。
- 隔離程序內連 localhost 成功。
- 隔離程序內連該公開 IP 回 errno=1，權限拒絕。

證據為 `.runtime/network-policy-check.json`。Ollama 另設 OLLAMA_NO_CLOUD=1、專用 11435 連接埠與專案內模型庫。首次啟動依原廠程式建立 ~/.ollama 本機識別檔，並非聲筆 API Key；不讀取或改寫聲筆金鑰、UserDefaults 或模式。

工具檢查：`python3 -m py_compile tools/local-model-probe/*.py` 通過，另有三項離線契約測試通過，驗證檔案損毀／符號連結拒絕，以及測試比較不會忽略金額對調或否定遺失。這三項只驗工具邊界，不代替模型或 App 測試。證據為 `/tmp/wagong-local-probe-tests.log`。

### Ollama 與階段結論

官方模型層已全部通過 SHA-256，已在專案內獨立模型庫登錄，並由 Ollama `/api/tags` 確認完整 digest 相符。實際版本 0.40.5，qwen3.5:9b 為 Q4_K_M、9.0B，API 回報總大小 6,550,825,550 bytes（包含 config）。

以八組固定 ASR 文字各生成一次，參數固定為 think=false、stream=false、temperature=0.1、num_ctx=2048、num_predict=512、keep_alive=1m。沒有調 prompt 重送。TEA 輸入先套用上文已核對的官方 PUA decoder 規則，結果欄位 official_tea_decoder_applied=true；這是探針中的參考轉換，不代表 App 已修好。

| 驗收項目 | 實際結果 |
| --- | --- |
| HTTP 與生成完成 | 8／8 為完整且非空結果，done=true、done_reason=stop。 |
| 中文句 | 兩組均轉／保留為繁體，保留「不要刪除」。 |
| 中英混用句 | 兩組內容符合固定語料；TEA 的 api 被整理成 API，英文大小寫並非完全原樣保留。 |
| 純英文句 | 兩組均被翻譯成中文，即使 prompt 已要求英文不翻譯，屬阻擋。 |
| 金額與否定句 | 兩組金額數值與否定均保留；「一千兩百」改為「一千二百」。最初字面比較將此判為 false，另加明確的固定語料數字變體比較後確認不是金額改變。不得把字面差異誤報為金額遺失。 |
| 僅允許數字寫法差異的內容比較 | 6／8 符合，另外兩筆為英文翻譯；大小寫原樣保留另行檢查，不能只看此數字。 |
| 第一次整理 | 約 17.52 秒，含模型載入。 |
| 後續七次整理 | 約 1.22 至 2.08 秒，不是穩態 p95。 |
| Ollama 程序樹 sampled RSS peak | 約 6.42 GB，不是全部 Metal／統一記憶體峰值。 |

證據：`.runtime/ollama-smoke.json`、`ollama-analysis.json` 與 `/tmp/wagong-ollama-smoke.log`。原始字面結果保留，另存語意比較，沒有覆寫原測試為通過。

記憶體方面，推論前系統 swap used 約 8,955 MB，結束約 12,809 MB，增加約 3,853 MB。這是整台 Mac 的觀測，當時有其他工作負載，不能全歸因於模型；也不能因本次推論成功就宣稱 16 GiB 使用體驗已達標。ASR 保持載入與釋放後再整理的正式對照尚未完成，目前只有分開執行的證據。

Ollama HTTP 斷線測試先收到實際生成內容，再關閉連線，約 1.48 秒；隨後固定整理請求約 1.02 秒完成。伺服器該次記錄為 200，沒有取得原生工作停止的專屬確認，因此只宣稱 HTTP 斷線後可恢復，不宣稱 GPU 推論已在某毫秒內停止，也不替代 App 面板取消驗收。

已明確卸載本次 Ollama 模型，`/api/ps` 回空清單，再停止本次服務。額外以程序群組無殘留及 11435 connect_errno=61 確認，證據為 `.runtime/cleanup-check.json`。原廠建立的 ~/.ollama/id_ed25519 與 .pub 僅檢查存在，未讀取內容；檔案留在原廠位置，沒有自動刪除。隔離模型與工具約占 9.2 GiB，保留供後續驗證，不在背景常駐。

### 放行判斷與下一步

第一階段的正常推論可行性已取得證據，完整階段仍未結清，階段 2 至 4 仍未開始。以下項目各自保留，不以正常路徑或工具測試通過取代：

1. TEA tokenizer 解碼：後續 App adapter 需依官方 decoder 契約實作並比較原始／解碼結果，不將 PUA 刪除規則任意套用其他模型。重啟時機為開始原生 ASR 整合前。
2. 原生取消：目前探針未取得合格證據，該路徑三次失敗已停；需先校正 timer callback、abort status 與物件釋放的量測，再於新的明確修復工作檢查 binding／底層或受控 worker 替代路線，不立即第四次重跑同一探針。
3. 英文保留：需設計純英文整理策略與輸出保護，固定失敗語料作回歸。不能只依賴單句「不要翻譯」指令，也不在本階段靜默改成略過整理。重啟時機為 Ollama adapter 實作前。
4. 資源策略：在固定機器基準、背景工作負載與足夠暖機樣本下比較 ASR 駐留／釋放策略，定案延遲門檻並測系統記憶體壓力。此次未為此關閉使用者 App 或重啟 Mac。
5. 辭典、長錄音、模型切換壓力、真實口述與跨 App 交付：本次未驗。尤其 initial_prompt 能力回報 false，不代表已窮盡所有 Qwen context 介面，仍須核對正確家族 API 才能下不支援的結論。
6. 此次只有四句合成語料，每個 ASR 兩次辨識及八組整理，未完成 40 句品質集或 30 次暖機統計，不能宣稱較準、較快或日常預設已可用。

此次沒有呼叫 Gemini／Claude 付費 API，先前核准的四次雲端額度沒有使用；未啟動聲筆 App、未修改既有鍵盤差異或 App 設定，沒有 commit、push、安裝或發布。


## 11. 後續修正與核心整合驗證（2026-10-16）

### 採用方案與原因

查閱固定原生來源 [qwen3_asr/model.cpp](https://github.com/handy-computer/transcribe.cpp/blob/856d7c10a1a864b900e066b7c9801edf373f5148/src/arch/qwen3_asr/model.cpp) 後，確認其只在 run 開始前呼叫 poll_abort，並未在辨識過程持續輪詢。這解釋了首輪用延遲 token 無法取得中途取消證據，不再重跑相同探針。

本輪選擇「受控原生 GGUF 子程序＋既有 localhost ASR API」作為可驗收接入路徑。原因是可以沿用 App 已驗證的自訂 ASR 請求與認證，取消時由父程序終止並 wait 子程序，無須新增 App ID、修改 SDK 或假稱協作取消已支援。否決在 App 主程序直接執行無法中途取消的 Qwen；亦未切回較重的 Python 模型推論。Python 僅提供 HTTP 控制與音訊轉換，辨識仍是原生 GGUF／Metal。

每次 ASR 請求只啟動一個 worker，完成、逾時、斷線或 Task 取消均須先回收程序才釋放 busy lock。單次 ASR 在回傳文字前已退出，但 Ollama 模型可依其 keep_alive 保持載入，並不等於兩個引擎在所有時間都不占記憶體；完整資源策略仍須量測。

### 修改範圍

- `TEATranscriptDecoder.swift`：依官方 tokenizer 規則移除 BMP 私用區標記，僅用於 TEA；保留非 BMP 漢字及其他模型原文。
- `tools/local-model-probe/GGUFWorker.swift`：單次原生辨識，PCM 由 stdin、文字由 stdout 的專用 pipe 傳遞，不透過指令參數或一般日誌。native-entry callback 提供取消探針的陽性事件。
- `gguf_server.py`：固定模型產物與 build fingerprint 校驗、一次一個 worker、有限等待、SIGTERM／必要時 SIGKILL 並等待退出；取消後不接收晚到結果。
- 既有 `tools/taiwan-asr/server.py`：只增加可注入模型清單，沿用認證、音檔限制、multipart、斷線觀察與 busy lock；既有 Python 模型預設不變。
- `OllamaRefinementClient.swift` 與 `OllamaService.swift`：共用單次 HTTP 傳輸，sampling 改放正確的 options，拒絕未完成、截斷與空結果，取消不轉成一般錯誤，逾時不自動重送。
- `LocalCleanupOutputPolicy.swift`、`PromptTemplates.swift` 與 `AIEnhancementService.swift`：只對 qwen3.5:9b 與未修改的內建智慧整理套用語言保留及輸出檢查，自訂翻譯／助理不套用。原系統訊息組裝抽為純函式，讓實際 App client 探針共用相同內容，不初始化 App、OCR 或資料庫。
- `Localizable.xcstrings`：超長輸入及受保護內容被改變時的繁中提示，原始轉錄保留，不以空白或假資料補位。

qwen3.5:9b 在 App 中指定 num_ctx=16384、num_predict=2048，prompt 與 system 的 UTF-8 合計上限為 12000 bytes。理由是 App 完整系統訊息比首輪短提示詞更長，使用保守 byte 上界並預留 envelope／輸出空間，避免讓伺服器靜默截斷輸入。否決無上限 context 與只調大 timeout。超限會明確拒絕，不截字；此設定不同於首輪 2048 context，延遲與記憶體需另看本輪，不能沿用首輪數字。

### 英文保留的反例與修正

分開驗證的四句整理曾全部通過，但第一輪實際音檔串接只有 7／8 通過：TEA 中英混用的 deploy 被改成「部署」，保留檢查將此結果拒絕。失敗的 `.runtime/app-combined-summary.json`、`app-ollama-combined-summary.json` 與 UUID 命名的原始結果保留，不覆寫為成功。

因此新增 `CleanupProtectedText`，在混合中文輸入中把 Latin 詞語替換成單次請求專用隨機標記，整理後要求每個標記恰好存在一次，再還原原字。標記對照僅在記憶體；缺少、重複、損壞或殘留時明確拒絕、不重送，原始轉錄保留。純英文仍用英文整理，另檢查語言、英文詞及否定是否遺失，並非靜默跳過模型。

此為保守保護，不是完整語意驗證。較大幅度的英文改寫或詞語拼字修正可能被拒絕，辭典搭配尚待驗收；不能宣稱所有金額、否定與專有名詞錯誤都已能偵測。

### 已取得證據

- 最終 unsigned build-for-testing 通過，Build ID 標記 LOCAL-ASR-FIX-20261016。證據 `/tmp/wagong-local-final-content-build.log`，不代表已簽署、安裝或發布。
- 連結實際 App 程式庫的 26 項測試、6 個 suites 通過，含片段還原／遺失／重複、語言保留、已觀察到的中文新增與否定遺失、自訂指令排除、Ollama 參數與完成狀態、過長輸入、單次傳輸與重試回歸。證據 `/tmp/wagong-local-final-content-tests.log`。
- 共用 ASR server 原有 13 項回歸測試通過，證據 `/tmp/wagong-asr-regression-local-fix.log`。
- 真實 GGUF HTTP 測試通過，包含錯誤 token=401、busy=429、兩個模型辨識、TEA 無 PUA。確定已進入原生辨識後斷線，worker 以 SIGTERM 結束並被回收，最後一次約 0.176 秒；隨後重新辨識成功。證據 `.runtime/gguf-service-final.json`，不是 App 面板至 GPU 完全回收的時間承諾。
- 實際 App ASR 請求建立、URLSession 與解析，對修正後 TEA GGUF 服務通過。證據 `.runtime/app-asr-fix.json` 與 `/tmp/wagong-app-asr-fix.log`，沒有讀 Keychain 或啟動 App。
- 修正前完整串接的 7／8 反例已取得，修正後受保護版本亦完成八組呼叫，但呼叫完成不等於品質通過，最後逐筆判定如下。

### 尚未放行的項目

App 內建 TEA／Qwen 下載卡尚未接入，本輪需透過手動啟動的本機橋接；設定值與命令見 `tools/local-model-probe/README.md`。尚未自動建立使用者模式、改預設或啟動常駐服務。40 句品質集、穩態 p50／p95、記憶體策略、辭典、長錄音及真實錄音／面板／跨 App 貼上仍待逐項驗收，不以核心 client 通過取代。


### 最後逐筆判定與停止條件

本次完整核心串接是實際合成 WAV → App 的 ASR factory／URLSession／解析 → 原生 GGUF worker → App 的 Ollama factory／完整回應解析／輸出保護。沒有初始化 App 的服務、Keychain、資料庫或錄音面板，亦不代表 GUI 全流程已驗證。

第三輪純識別碼版本八次呼叫均完整完成，當時的英文／標記保護也回 true。然而人工逐筆比對發現一筆額外錯誤，不能將護欄 true 寫成品質通過：

- TEA 四句：固定英文、中英混用、中文與金額句內容符合參考；中英混用保留 review、api 與 deploy。
- Qwen 三句：固定英文、中文及金額句內容符合參考。
- Qwen 中英混用：原文為「请帮我review这个API。今天先不要deploy。」，整理成「请帮我处理 review 和 API。今天先不要处理 deploy。」。英文雖保留，卻新增「处理」與「和」，並保留簡體，列為品質阻擋。

第三輪原始結果保留於 `.runtime/app-combined-C68D4E76-5C09-47FD-8311-7B73127A8BCF.json`，以及 `.runtime/app-combined-ids-summary.json`、`app-ollama-combined-ids-summary.json` 和 `/tmp/wagong-local-combined-ids.log`。這些原始結果的 accepted=true 是當時較弱護欄的判定，不是最終品質結論。

前兩輪亦保留：未遮罩時 deploy 被翻譯；括號標記版本被模型移除括號，因此嚴格還原拒絕。最終採用純 ASCII 完整識別碼 WG_<隨機值>_<索引>_END，仍要求一個標記恰好一次，不猜補或接受損壞標記。原生辨識使用相同固定產物，沒有重新下載或偷偷切換模型。

本路徑三次試驗已停止，不再繼續改 prompt 呼叫模型。最後僅以已捕捉的失敗結果補上確定性的拒絕規則與回歸測試：中英混用的保護路徑只允許標點、空白、大小寫與正常繁簡轉換；以 Foundation Hans-Hant 作比較用正規化，正規化不可用時明確拒絕。中文用字或順序改變一律保留原始轉錄，包含上述新增「處理」及否定遺失的反例。

此規則是保守拒絕，不是將模型品質修好。會限制中英混用的贅詞刪除、大幅潤飾與詞彙修正，亦未證明所有標點造成的語意變化均能辨識。原始壞輸出不覆寫；最終 App 規則另以離線重審紀錄保存。沒有第四次模型請求，也不把離線重審算成重新推論通過。

已執行連結最終 App 程式庫的 `LocalFixAcceptance --audit`，不發送網路請求。`.runtime/final-content-audit.json` 保留各輪重審結果；第三輪八筆接受七筆，拒絕上述 Qwen 中英混用。這驗證拒絕條件確實生效，不代表已改善該筆模型輸出。

2026-10-16 09:50（Asia/Taipei）再次核對清理狀態，先以自身 PID 確認程序清單查詢有效，再確認本次 Ollama 程序群組與 GGUF worker 無殘留，專用 11435 連接回傳 errno=61。證據 `.runtime/final-content-cleanup.json`；模型檔保留，不清除其他服務或資料。

第三輪核心等待時間約 4.51 至 25.78 秒（含 ASR 與整理），當時仍有其他工作負載，不能視為穩態統計；其中部分整理超過原預設 20 秒。實機測試前需檢查使用者目前的全域整理 timeout，現有 UI 上限 60 秒；工具未自動修改該設定。探針本輪使用 90 秒上限，不能把此設定差異隱去而宣稱預設 GUI 體驗已通過。

### 目前交付與下一階段

- 已提供可檢查的原始碼、橋接工具、原始結果與失敗拒絕測試；未推送、安裝或發布。
- 目前可支持「核心傳輸與模型串接能執行」，不能支持「兩組品質均通過」。本輪 TEA 四句符合，Qwen 中英混用仍為明確阻擋；四句合成資料也不能替代真實語料品質評比。
- App 安裝、錄音、面板取消、模式切換與跨 App 貼上仍未驗。內建模型下載卡、自動模式範本及辭典亦未完成。
- 模型品質路徑重啟需先檢討中英混用的整理範圍或模型選擇，以已保存反例為基準，再另定新的驗證工作；不在本工作無限試 prompt。

## 12. 測試版安裝（2026-10-16）

使用者要求安裝，並授權處理完整測試中兩項右 Control 失敗。首次 `make test-app` 有 227 項通過、2 項失敗、2 項略過，未替換 App。相同產物僅執行鍵盤 suite 時兩項均通過，因此不能將首次失敗直接判定為實體鍵盤故障。

問題類型是非同步事件測試將執行器排程時間混入短暫的實體事件配對視窗。選擇在 monitor 與 broker 注入預設為系統單調時間的時鐘，正向測試改用受控時間，並等待實際 pending Task 與 callback；否決放寬正式的 75 毫秒等待或 50 毫秒來源視窗，以及略過失敗測試。新增相同 CG 入口的 74／76 毫秒測試，分別確認期限內可觸發、逾時拒絕。首次失敗的具體排程時間未記錄，因此排程干擾為依據窄範圍通過與受控時間結果的診斷，並非硬體根因證據。

- `make test-app` 最終回傳成功，`TEST SUCCEEDED`。日誌：`/tmp/wagong-install-clockfix-20261016.log`。
- xcresult：`.local-build/Logs/Test/Test-VoiceInk-2026.10.16_10-24-43-+0800.xcresult`，230 項通過、0 項失敗、2 項略過，總計 232 項。
- 略過項目為 `VocabularyTests/migratesSyntheticLegacyStoreWithoutForgingHistory()` 及 `VocabularyTests/providerRequestsContainSelectedTerms()`，未列為通過。
- 安裝位置：`/Users/hd/Applications/Wa-Gong Test.app`。版本 1.0.1，Build ID `T-20261016-022421-93EF2F48`。
- `scripts/test-app.sh status`：`CURRENT`、`Running: MATCH`，來源指紋、安裝包與啟動收據相符。此建置包含目前工作目錄既有修改，並非乾淨 commit 的發布產物。
- `codesign --verify --deep --strict` 通過；Bundle ID `com.jackie-yeh.wagong`，Team ID `8N33V8XXTX`。採既有專案測試簽署，不新增識別或憑證，不公證或發布。
- 正式 App 路徑未替換；測試 App 共用既有資料，安裝流程避免兩版同時執行。未修改 ASR／Ollama 模型偏好，亦未啟動模型常駐服務。

本節更新第 11 節當時「尚未安裝」的狀態，並不取消品質限制。實體右 Control、麥克風錄音、面板取消、模式切換、真實 Provider 與跨 App 貼上仍未驗收；Qwen 中英混用品質仍未放行。
