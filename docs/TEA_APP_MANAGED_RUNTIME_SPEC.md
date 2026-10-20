# App 自動管理本機 TEA 語音辨識規格

日期：2026-10-20。

狀態：2026-10-20 使用者以「請修改」核准實作；程式已接入，原生與隔離測試通過，完整測試 App 安裝與實機驗收尚未執行。最新證據與限制見第 14 節。這次授權不包含切換使用者設定、執行計費雲端請求、安裝或發布。

## 1. 目標與範圍

使用者在 App 下載或匯入 TEA 模型後，選擇「TEA-ASR 1.1」即可錄音。App 負責啟動、載入、保溫、取消與回收辨識程序，不需終端機、Python、手動啟動服務、API 端點或本機密碼。

主要組合為「本機 TEA 辨識＋既有 Gemini 或 Anthropic 文字整理」。文字整理仍可關閉，兩個階段可獨立設定。雲端模型以帳號當下可用且經實測的模型 ID 為準，不在規格保證任何未驗證型號、費率或延遲。

### 本次不包含

- 不繼續最佳化本機 Ollama 整理，也不自動刪除或停用既有 Ollama 設定與模型。
- 不加入 Qwen3-ASR 下載卡、即時串流、ASR 詞彙提示或超過 30 秒的長音檔分段。原因是先將已測過的 TEA 短句路徑產品化，避免擴大驗收範圍。
- 不自動更改既有模式、自訂服務端點、雲端 Provider 或 API Key；不刪除使用者手動啟動的橋接服務。
- 不修改鍵盤辨識、權限政策、既有錄音保留政策、Bundle ID 或 Apple Developer Team。
- 第三方模型冠名錯誤仍由 [既有 Issue](issues/第三方模型來源標示錯誤.md) 處理。本功能的 TEA 卡必須正確標明來源，不將修復全部舊名稱併入此功能。

## 2. 現況與需求依據

2026-10-20 使用者回報：TEA 搭配 qwen3.5:9b 的一句中文約需 10～20 秒；關閉文字整理後明顯較快。這是使用者觀察，沒有該次分階段計時，不能推算確切 ASR 或整理延遲，也不能宣稱雲端一定更快。

目前程式碼已確認：

- `tools/local-model-probe/gguf_server.py` 是手動啟動的 Python HTTP 橋接，單次辨識啟動原生 worker，完成後釋放。
- `GGUFWorker.swift` 使用原生 transcribe.cpp／Metal，固定模型與音訊限制，並套用 `TEATranscriptDecoder`；現有程式只有單次輸入，不支援常駐多次辨識。
- `TranscribeCppModelCatalog.swift`、`TranscribeCppTranscriptionService.swift` 目前只註冊 Cohere；不能直接新增 TEA 卡卻讓它落到不支援的 dispatcher。
- `ModeConfig.swift` 與 `ModeRuntimeConfiguration.swift` 已將語音辨識、文字整理 Provider、整理模型與提示詞分開，沿用這個分工。
- `VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` 固定 `transcribe-cpp-swift` 為 `0.2.0-dev.856d7c1`，revision `fb1c1ad99e8939a69fcfb613417d9635fb77ef42`。本階段不預設升級 SDK。
- 前輪已查核固定原生實作的取消只在開始前檢查。新設計仍以可終止的獨立程序保證中途取消，不將 SDK callback 當作已具備持續取消能力。

既有來源與測試證據見 [整合計畫](LOCAL_ASR_OLLAMA_INTEGRATION_PLAN.md)；歷史安裝版本不代表本規格已到使用者電腦。

## 3. 架構決策

採用「App 管理的原生輔助程序＋私有 IPC」，不是將測試 Python server 自動放進背景。

```text
錄音與音訊格式檢查
  → TEA 辨識 adapter
  → App 的 runtime 管理器
  → App bundle 內簽署的原生輔助程序
  → 原始轉錄
  → 可選的 Gemini／Anthropic 整理
  → 既有輸出交付流程
```

| 選擇 | 理由 | 否決方案與原因 |
| --- | --- | --- |
| 原生 helper，透過匿名 pipe 通訊 | 無公開監聽端點，不需保存或輸入本機 API Key，App 可管理子程序 | 自動啟動 Python／固定 localhost 服務，仍需處理外部環境、連接埠衝突與認證交接 |
| 模型放 Application Support，helper 隨 App 打包 | 使用者可移動 App，不依賴 checkout、虛擬環境或開發用 framework 路徑 | 直接引用 `.runtime`／`.local-build`，無法作為可散布產物 |
| helper 載入模型後可連續處理，閒置後卸載 | 降低每次重新載入的成本，亦避免長期占用記憶體 | 每句重建 helper 不利延遲；永久保溫缺乏資源釋放界線 |
| 同一時間只處理一筆辨識 | 避免多份模型與 GPU 工作競爭，取消歸屬清楚 | 無界排隊或並行載入，容易在模式切換後交付過期結果 |
| 取消即回收該次 helper | 固定 SDK 無可靠的原生中途取消證據 | 只取消 Swift Task／HTTP，可能讓原生推論繼續 |

私有 IPC 是本 spec 的目標決策，尚需在固定 SDK 上驗證多次 session 與取消。若驗證失敗，須回報並修訂方案，不可靜默回退為每句載入仍宣稱已完成保溫。

## 4. 使用者流程與介面

1. 「AI 模型 → 本機」出現「TEA-ASR 1.1」卡片，註明約 1.69 GB，模型檔大小不代表執行記憶體需求。
2. 卡片提供「下載模型」與「匯入已下載模型」。顯示下載、驗證、未安裝、可用及失敗狀態，失敗附可理解的原因與使用者可採取的動作。
3. 在模式中選 TEA 為語音辨識模型。選用或準備錄音時非同步載入，不阻塞主執行緒；下載不因選取而默默開始。
4. 文字整理保持獨立選項：關閉、Gemini、Anthropic 或使用者其他既有服務。選用雲端整理時標示「音訊在本機辨識，轉錄文字會送至所選服務」。額外 Context 預設不因此開啟。
5. 第一次錄音時若模型仍載入，可正常錄音；停止後等待同一個載入工作，呈現「正在載入 TEA」。等待可取消，尚未就緒時不可送出雲端整理。
6. 接著依階段呈現「正在辨識」「正在整理」「正在交付」，避免全部顯示為轉錄。未開始的階段不提前計時。
7. 載入失敗或雲端未設定時，明確說明處理停在哪一步，提供使用原始轉錄的操作。禁止自行選另一個雲端服務。

VoiceOver 可讀取狀態與錯誤；下載、取消與模式選擇支援鍵盤。主介面不要求使用者理解 pipe、helper 或 token。

## 5. 模型來源、下載與相容性

| 項目 | 固定值 |
| --- | --- |
| 顯示名稱 | `TEA-ASR 1.1` |
| 建議內部識別 | `tea-asr-1.1-q6-k`，與現有手動 `tea-gguf` 自訂項目分開 |
| 原始模型 | `JacobLinCool/TEA-ASR-1.1` |
| GGUF 轉換來源 | `mukiwu/TEA-ASR-1.1-transcribe-gguf` |
| revision | `83f5b0668c4718db9f16e43940c83bef7e61df61` |
| 檔案 | `TEA-ASR-1.1-Q6_K.gguf` |
| 大小 | `1692286464` bytes |
| SHA-256 | `2417fa52d49f852bfc11704190e10ddb681c343a661a3a3d1bb213876c780b68` |

固定值取自目前已測產物清單，不跟隨 `main` 自動更換。模型卡顯示原作者及轉換者，保留 MIT 與底層 Qwen Apache-2.0 的來源、授權與必要聲明，不將第三方模型改冠產品品牌。

沿用下載 manager 可用部分，但補足：固定 HTTPS 來源與重導向範圍、檔案大小與實際 SHA-256 校驗、取消及暫存、空間檢查、驗證成功後原子登錄。不可僅因 checksum 標記檔存在就當權重完整。模型替換、檔案身分改變或產物更新後須重新校驗。

匯入採「驗證後複製」，保留使用者來源；拒絕非一般檔案、符號連結、不符 hash 或不支援的架構。可讓使用者手動選目前已下載產物，避免重複下載；不自動搬走或清除探針目錄。

下載與匯入前計算剩餘所需大小，加上暫存及至少 3 GiB 空間保留；已有驗證模型不被半成品覆蓋。模型載入前還要檢查架構與記憶體壓力，最低記憶體需求須量測後決定，不把測試機容量寫成通用最低需求。

第一階段以 Apple Silicon／Metal 為驗收範圍；Intel 不顯示為已支援，不偷換到未驗證 CPU 路徑。語言維持 auto／zh／en，保留繁體 tokenizer 與 TEA 專用 PUA 解碼，不將此清理套用其他模型。

## 6. Runtime 狀態與生命週期

狀態由單一管理器序列化管理，模型下載狀態與 runtime 狀態分開。

| 狀態 | 事件 | 行為 |
| --- | --- | --- |
| 未啟動 | 選用 TEA／準備錄音 | 驗證產物後啟動一個 helper，進入載入中 |
| 載入中 | 同時收到另一個準備請求 | 共用載入 Task，不再 spawn；各自綁定工作階段 |
| 載入中 | 原生回報載入就緒 | 進入可用；僅程序存活不能算就緒 |
| 可用 | 提交有效音訊 | 進入辨識中，一次只處理一筆 |
| 辨識中 | 收到第二筆請求 | 回報忙碌，不無界排隊、不自動取消第一筆 |
| 辨識中 | 正常完成 | 驗證結果及 request ID，釋放本次 session，模型回到可用 |
| 載入／辨識中 | 取消、模式切換或工作階段失效 | 標記失效，停止並 wait helper；舊結果永不交付 |
| 可用 | 閒置 120 秒 | 卸載模型並停止 helper |
| 任意狀態 | App 正常退出、系統休眠 | 取消請求並停止自有 helper；喚醒後依需要重新啟動 |
| 任意狀態 | helper 異常退出 | 回報失敗並回收；僅下次使用者操作可重新啟動，不重跑本筆音訊 |

120 秒為初始保溫政策，不是已驗證的最佳值。收到記憶體壓力時，可用且無請求的模型立即卸載；辨識中不為釋放記憶體而無聲丟掉工作，若原生失敗，走明確錯誤路徑。雲端整理期間 TEA 可保溫，但不可宣稱此時模型已不占資源。

App 非預期消失時，helper 必須透過持續監聽的父程序生命週期 pipe 偵測 EOF 並退出，即使原生同步推論仍在進行也有效。不能依賴推論結束後才讀 stdin，或只以 PID 判斷父程序身分。此路徑須以真實父程序異常退出測試驗證。

初始界線：載入最長 30 秒、單次辨識最長 90 秒；停止先 TERM 等待最多 2 秒，再 KILL 並 wait 最多 5 秒。均為待實測的有界政策，不是速度承諾。回收失敗時禁止啟動替代 worker 或交付新結果，保留明確失敗狀態；不可只清空 handle 當回收成功。

所有期限、閒置與 elapsed 使用可注入的單調時鐘。診斷時間戳統一 UTC，介面依使用者時區顯示，不以牆鐘判定逾時。

## 7. 私有 IPC 與取消邊界

- helper 由 bundle 內固定路徑啟動，不接受任意執行檔、shell 模板或使用者 URL。以建置時 manifest、IPC 版本與簽章驗證來源，不依賴 checkout fingerprint。
- 具獨立的父程序生命週期通道，請求與結果使用有長度上限的 framed 訊息；支援 ready、transcribe、result、error、shutdown，含協定版本、request ID、工作階段世代。舊版或不相容回應直接拒絕。
- 音訊只經記憶體 pipe，轉為 16 kHz 單聲道 PCM，限制最長 30 秒、樣本有限且有效，雙方皆驗證大小。不把音訊、文字、token 或使用者路徑放命令列。
- 控制程序持續讀 stdout／stderr，避免 pipe 塞滿。結果只存在專用結果通道；native logging 預設停用，stderr 不可直接寫進 App 日誌。
- helper 可以重用已載入模型，但每筆建立並釋放 session。多次 session 的狀態隔離必須先驗證，不沿用上一筆文字、音訊或 tokenizer 狀態。
- 取消仍以終止 helper 為準。取消、逾時、關閉面板或切換模式後，禁止後續整理請求、重試、HUD 復活或貼上。若雲端已接收請求，取消本機接收不代表可保證對方停止計費。

## 8. 雲端整理與結果保存

沿用既有 Gemini／Anthropic adapter，不修改其對外 API 或加入新的自動轉送服務。未設定有效雲端服務時不得假稱整理成功。

原始轉錄與整理結果分開，整理失敗不覆寫原始轉錄。雲端逾時、斷網或取消，不自動重送，也不自動改送另一家；使用者另行重試前明確知悉會發送新的請求。

不得因啟用此功能而開啟剪貼簿、選取文字、OCR 或螢幕 Context。雲端只收到模式明確允許的文字與必要提示；音訊不交給文字整理 Provider。沿用既有詞彙規則，但不宣稱 TEA 已支援 ASR 熱詞提示。

「本機辨識」與「雲端整理」各自顯示處理地點。內部狀態與設定名稱不得讓使用者以為全文留在本機。

## 9. 效能與隱私診斷

分開量測音訊前處理、模型校驗、載入、辨識、雲端整理、交付及整體等待；辨識時間不得包含載入，雲端整理不得被算成 ASR 慢。記錄冷啟動／保溫、模型固定 ID、音訊秒數、結果狀態與非敏感錯誤碼。

日誌與診斷不得含音訊、原文、整理文字、憑證、完整 URL、使用者路徑、裝置指紋或按鍵歷史。歷史內容沿用既有明確允許的資料政策，不為診斷另存全文。驗收使用固定非私人語料，另以自動測試斷言不洩漏敏感資料。

在同一目標 Mac、相同模型與背景工作負載下，先比較目前每句載入與新保溫流程：至少 30 次連續暖機測量及 5 次冷啟動，分別列 p50／p95、程序 RSS、可觀測 GPU 指標、系統記憶體壓力。RSS 不等於總統一記憶體用量。雲端延遲另外列出，不用單筆數字宣稱優勝。

功能門檻是第二次有效請求在保溫期限內實際重用模型且不再載入；數值速度與資源上限須在基準量測後、實機放行前另行定案。未定案時只能宣稱功能可執行，不能宣稱速度達標。

## 10. 影響範圍與階段

以下新增檔名為規劃，不表示已存在。

| 範圍 | 規劃工作 |
| --- | --- |
| `TranscribeCppModelCatalog.swift`、`TranscribeCppModelManager.swift`、`TranscriptionModelRegistry.swift` | 註冊 TEA 固定產物、下載／匯入、顯示來源與能力 |
| `TranscriptionModel.swift` 的 `TranscribeCppModel` | 效能與記憶體欄位可為 nil，因 TEA 尚無通用品質評分或最低記憶體證據，不以 0 假裝已量測；既有 Cohere 數值保持原值 |
| 新增 `TEARuntimeManager.swift`、`TEATranscriptionService.swift` | 生命週期、私有 IPC、取消、結果驗證與 adapter |
| 新增隨 App 打包的原生 helper target | 由測試 worker 整理成多次 session 協定，保持獨立程序取消能力 |
| `TranscribeCppTranscriptionService.swift` | 路由 TEA，既有 Cohere 路徑保持相容 |
| `AppDelegate.swift` 與實際 App 生命周期入口 | 綁定退出、休眠、記憶體壓力與清理，依目前真實入口接線，不預設事件已註冊 |
| 模型卡、模式 UI、`Localizable.xcstrings` | TEA 管理、階段狀態、來源與本機／雲端說明 |
| `TranscriptionPipeline.swift` 與既有 session metrics | 分階段計時，確認取消與雲端失敗保留原文，不重構無關流程 |
| Xcode target、打包與測試建置腳本 | 嵌入 helper／framework、相同團隊簽署、版本與產物可追溯性 |

實作分四階段，每階段先取得證據再進下一階段：

1. 驗證固定 SDK 的常駐模型、多次 session、私有 IPC 及程序取消。失敗即回報架構限制，不先做可下載卻不能使用的模型卡。
2. 接入模型 catalog／manager、TEA adapter、runtime 狀態機與下載／匯入，建立自動化回歸。
3. 接 UI 與雲端混合模式、階段計時，確認既有模式與手動自訂模型保持相容。
4. 以支援的 `make test-app` 流程測試安裝，核對 source／bundle／process Build ID，完成真實錄音、取消、貼上、資源與品質驗收。簽署、公證與發布另依授權執行。

第一階段品質集至少 40 句，涵蓋台灣口語、英文、中英混用、金額、日期與否定詞。保留原文與參考答案於明確的非私人測試資料，分開評估 TEA 與雲端整理；不得以整理補對字就掩蓋 ASR 漏字。

## 11. 功能驗收與完成定義

- [ ] 無 Python、無專案 checkout 依賴的測試 App 能下載／匯入正確模型並使用，不需 API 端點或本機密碼。
- [ ] TEA 可單獨辨識，也能搭配已授權且可用的 Gemini／Anthropic，兩階段設定獨立。
- [ ] 同一模型連續兩次辨識可重用，結果不互相污染；閒置、休眠、App 退出後實際釋放。
- [ ] helper 啟動失敗、模型損毀、不相容協定、IPC 半包、超大輸入及異常退出皆有明確錯誤，不假裝就緒。
- [ ] 確認進入 native 推論後執行取消，子程序實際結束且被回收；取消後不啟動雲端請求、不回寫、不貼上。
- [ ] 父程序異常退出與休眠測試確認 helper 無殘留；不終止使用者的 Python、Ollama 或手動 ASR 服務。
- [ ] 30 秒界線與格式驗證測試通過，超限在兩端拒絕並提示，不靜默截斷。錄音 UI 須在使用 TEA 時明示限制。
- [ ] 雲端失敗保留原始轉錄，不新增自動重送、Provider 切換或未允許 Context。
- [ ] 分階段時間、冷暖機與資源證據完整，速度門檻完成定案且達標。
- [ ] 模型名稱、來源、授權、VoiceOver、鍵盤操作、繁中錯誤與取消操作完成實機驗收。
- [ ] 完整測試、測試版安裝與簽章檢查通過，source／bundle／process Build ID 一致；真實錄音、裝置快速鍵與跨 App 貼上逐項取得證據。

任何未勾選的實機、無障礙、品質或發布項目都維持阻擋或已知限制，不以一次 build 或單元測試代替完成。實作如需 bump 版本，遵守三段式版本並同步 changelog，本規格不先指定發布版本。

## 12. 功能專用開工與完工檢查清單

依 `preflight-feature` 建立；開工前審閱，完工後以同一份清單逐項附證據。

### 範圍與規則落實

- [x] 修改限第 10 節；未擅自刪模型、改雲端設定、修第三方冠名或重構無關鍵盤程式。新增測試及授權資源屬相同功能；本次變更清單見第 14 節。
- [x] lifecycle、single-flight、期限與取消集中於單一管理器，UI 不能繞過驗證直接 spawn。原生 App runtime 隔離驗收通過，見 `managed-tea-app-runtime-proof.json`。
- [ ] 多重 prepare、連點、模式切換、取消競態、晚到 callback 與回收失敗均有正反例測試。

### 個資、程序與網路

- [ ] helper 路徑、IPC 大小、輸入格式與模型路徑驗證，來源不唯一或身分不符時保守拒絕。
- [ ] helper 無遠端下載能力與無必要網路權限；App 不為此新增監聽端點。依實際發布環境驗證可用的權限隔離，不將未測隔離宣稱為完成。
- [ ] 下載固定來源，重導向不可轉向任意內網或第三方；雲端文字只送選定服務，無額外 Context 外送。
- [ ] secret、音訊與全文不進 log／UserDefaults／Git；測試包含錯誤字串、stderr、crash 診斷與晚到結果。

### 第三方產物與發布

- [x] 不默默更新 SDK，既有 lock 未修改；固定權重、來源與 MIT／Apache-2.0 資源均已保留。授權資源存在於建置產物，尚不代表發布審查已完成。
- [ ] helper／framework 可從安裝包相對位置載入，簽章與 IPC 協定版本相符。
- [ ] 僅使用既有 Bundle ID／團隊政策；若新 target 必須新增受管理識別或權限，先依 Apple 規則確認，不擅自建立。
- [ ] 未驗證的既有下載 manager 行為逐項補證據，不將「沿用」當成完整驗收。

### 時間、效能與介面

- [ ] 單調時鐘可控制，75 毫秒鍵盤既有政策不受此改動；模型期限與閒置無牆鐘漂移問題。
- [ ] 下載不阻塞 UI，stderr／pipe 消費不死鎖；取消與回收有界。
- [ ] 正確區分載入、辨識與整理，保溫重用與卸載皆有可觀測陽性證據。
- [ ] i18n 與無障礙、空間不足、未下載、離線、權限拒絕、模型不可用均有可理解狀態。

### 不適用項目與理由

- DB migration／欄位變更：不適用，本功能沿用模型設定與 metrics；若實作發現需改資料模型，先修訂 spec。
- Filament／網頁表單、CSRF：不適用，這是原生 macOS App 的私有 IPC，不新增網頁端點。
- 郵件、SMS、webhook：不適用，不對外通知。
- 金流、收費方案調整：不適用，僅沿用使用者選定雲端服務；真實雲端驗收的計費請求仍需事前授權。
- 公開伺服器與多人共用：不適用，helper 只服務其父 App，未提供通用本機 API 或 LAN 存取。

## 13. 進入實作前的決策點

本文件建議採用內建原生 helper，使用者審閱後才進入實作。SDK 常駐可行性、硬體最低需求、效能門檻與 helper 最終打包方式必須依階段 1 證據完成定案；其中打包簽署若需要新的 Apple 識別，另外提出完整字串與影響範圍。

確認實作範圍不等於核准真實雲端請求、刪除既有模型、切換使用者模式、安裝測試版或正式發布，各項仍依當次授權執行。

## 14. 本次實作紀錄與尚未放行項目（2026-10-20）

### 原始碼接入

- 新增 `TEAWorker` 原生 executable target，與 App 一起建置並嵌入 `Contents/MacOS/WaGongTEAWorker`，使用既有套件，不建立 Apple App ID 或變更 Team。
- `Shared/TEAWorkerProtocol.swift` 定義有長度上限的 framed IPC、版本、request ID、generation 與音訊驗證。fd 2 保留為獨立的父程序生命週期讀取通道，不接收原生日誌。
- `TEARuntimeManager.swift` 管理單一載入、並行拒絕、120 秒閒置卸載、取消／逾時回收、異常退出與失敗後下次操作恢復。回收期間拒絕新工作；回收失敗不啟動替代 helper。
- helper 每句建立新 session，重用已載入模型。App 的正式路徑要求 helper manifest SHA-256、協定版本及既有 Team 簽章均正確，並以系統 sandbox-exec 套用禁止網路 profile；缺少 sandbox-exec 時保守拒絕。此工具的長期 macOS 相容性仍需隨發版驗證。
- `TEAModelInstaller.swift` 提供固定來源、重導向白名單、空間檢查、全檔 hash、驗證後原子登錄與匯入複製；使用者來源保留。TEA 安裝 UI 可取消且顯示錯誤，不修改既有 Cohere 下載流程。
- 模型卡與模式 UI 顯示原始模型、轉換者、本機／雲端界線及 30 秒限制。未量測的效能欄位使用 nil，不杜撰評分。
- 錄音準備可非同步載入 TEA；file session 取消、模式切換、刪模型、休眠與 App 結束接到 runtime 清理。記憶體壓力僅卸載無辨識工作的模型。
- UI 補上載入、辨識與交付階段，沿用既有整理階段。診斷分開記錄前處理、檔案驗證、模型載入、原生辨識及交付，僅記錄 metadata。既有歷史 `transcriptionDuration` 仍為整段轉錄等待，尚未拆成新的永久欄位，不能將其當成純 native 時間。
- `scripts/test-app.sh` 的 source fingerprint 納入 `TEAWorker`，避免 helper 變更而安裝狀態仍誤判 CURRENT。
- 未修改既有手動 TEA 設定、Ollama、雲端 API Key、鍵盤修正或模型冠名 Issue；未終止使用者手動服務。

### 已驗證的層次

1. `CODE_SIGNING_ALLOWED=NO build-for-testing` 通過。最終日誌 `/tmp/wagong-tea-final-source-build.log`；套件解析鎖定，略過 plugin 與 macro 驗證，未簽署或啟動 App 宿主。
2. 連結實際 App 程式庫的隔離 SwiftPM 契約測試：34 項、7 suites 通過。含 IPC framing、半包／超大包、版本拒絕、30 秒音訊邊界、非法樣本、固定來源、下載白名單、來源署名及既有整理／傳輸回歸。日誌 `/tmp/wagong-tea-final-contract-results.log`；未執行完整 Xcode 測試宿主。
3. 原生 helper 兩句固定合成語料在同一 PID 連續成功，僅載入一次；native-entry 後 TERM 取消、回收、恢復辨識與生命週期 pipe EOF 通過。證據 `tools/local-model-probe/.runtime/managed-tea-proof-20261020.json`。
4. 搬移 helper 與 framework 到獨立 `/tmp` bundle 後，以實際 App runtime 呼叫，驗證共同 prepare、模型重用、忙碌拒絕、推論中取消、程序異常退出不重送、恢復與測試用短閒置期卸載。證據 `.runtime/managed-tea-app-runtime-proof.json`。沒有初始化 App、讀寫模型偏好或 Keychain；簽章正向路徑刻意未測，結果欄位 `signed_identity_path_tested=false`。
5. 同輪 30 次固定合成短句、保溫狀態下 App runtime p50 約 0.401 秒、p95 約 0.481 秒。這不包含麥克風、冷載入、雲端整理或貼上，也不是穩態完整資源／品質比較。原生首輪載入約 1.731 秒，兩句約 0.387／0.322 秒，不能用一次載入當冷啟動分位數。
6. 真正父程序在觀測到 native-entry 後異常退出，helper 透過 OS 關閉的生命週期 pipe 自行退出，非僅模擬 EOF。證據 `.runtime/managed-tea-parent-death-proof.json`。
7. 最新 App runtime 的 1 毫秒載入逾時測試確認回傳 timedOut 並回收 helper，日誌 `/tmp/wagong-tea-timeout.log`。
8. 相同 sandbox profile 對自建 loopback 服務：未隔離可回應，隔離後被阻擋；證據 `.runtime/managed-tea-network-proof.json`。未以查無回應直接推論網路已隔離。
9. 建置內 helper SHA-256 與 manifest 相符，MIT、Apache-2.0 及來源說明資源存在；專案 plist、在地化 JSON 及 `git diff --check` 通過。
10. 2026-10-20 22:54（Asia/Taipei）以自身 PID 作陽性對照，確認當輪 `WaGongTEAWorker` 與 `RuntimeAcceptance` 無殘留；證據 `.runtime/managed-tea-cleanup-proof.json`。不包含停止使用者原有服務。當時尚未替換舊測試版，後續安裝結果見下一項。
11. 使用者授權後，執行完整 `make test-app` 通過，Xcode summary 為 240 項測試、238 通過、0 失敗、2 略過。略過為既有 `VocabularyTests/migratesSyntheticLegacyStoreWithoutForgingHistory()` 與 `VocabularyTests/providerRequestsContainSelectedTerms()`，未修改略過條件。測試報告 `.local-build/Logs/Test/Test-VoiceInk-2026.10.20_23-02-07-+0800.xcresult`，安裝日誌 `/tmp/wagong-tea-install-20261020.log`。
12. 已安裝並啟動 `~/Applications/Wa-Gong Test.app`，Build ID `T-20261020-150153-D7CEF714`。`scripts/test-app.sh status` 回報 `CURRENT`、`Running: MATCH`。安裝前停止相同 Bundle ID 的舊 App；保留正式 App、使用者偏好與手動服務。
13. 安裝產物 App 的 `codesign --verify --deep --strict` 與 helper 的 strict 驗證通過，helper Team 為 `8N33V8XXTX`，簽署後實際雜湊與 manifest 相符。隔離工具連結實際 App runtime，啟用 `validateSignature: true`，使用安裝版 helper 與既有固定合成短句，確認載入、辨識與回收通過。另驗證雜湊錯誤，以及竄改 binary 並同步更新 manifest 雜湊後，均回傳 invalidHelper。證據 `.runtime/managed-tea-signed-proof.json`，工具原始碼 `tools/local-model-probe/ManagedTEASignedAcceptance.swift`；未初始化 App、讀寫使用者偏好或呼叫雲端。

原生探針第一次在 Swift 大寫 UUID 與 Python 小寫字串比較時失敗，已改為 UUID 語意比較；沒有將此量測問題誤判成 native 載入失敗。後續固定探針通過，不覆寫原始失敗日誌的結論。

### 阻擋與下一步

- 完整測試、既有 Team 簽署、測試版安裝與啟動已通過；未執行正式版替換、公證或發布。
- helper 簽署正向與竄改反例已在安裝產物驗證，但尚未完成 App UI 錄音入口到最終交付的完整路徑。
- 下載、匯入與取消已有程式與邊界測試，但尚未從 App UI 真實下載／匯入 1.69 GB，也未驗收磁碟不足、下載中斷、重導向變動與原子替換的整條路徑。
- 真實麥克風、同一把實體鍵盤、模式切換、關閉面板、VoiceOver、跨 App 貼上，以及真實 App 休眠／喚醒仍待驗收。父程序死亡探針不替代系統休眠測試。
- 尚未執行真實 Gemini／Anthropic 付費請求，無法宣稱混合組合已端到端通過；原始轉錄保存與既有雲端回歸仍需在實際模式確認。
- 40 句品質集、5 次冷啟動、舊路徑對照、GPU／RSS／記憶體壓力量測、最低硬體需求與速度門檻尚未完成。120 秒正式閒置政策的系統情境未實測，隔離測試使用短期限驗證同一機制。
- 下一步是由使用者從「AI 模型 → 本機」匯入現有固定 TEA 檔，建立內建 TEA 與 Gemini／Anthropic 整理的測試模式，保持既有手動設定不覆蓋。步驟見 `handoff.md`。無須重抓模型，亦不需刪除舊服務。

本輪交付為功能原始碼、已安裝的簽署測試版與隔離證據，並非完整 spec 或發布驗收完成。
