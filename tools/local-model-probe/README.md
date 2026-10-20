# 全本機模型第一階段探針

這是與聲筆 App 分離的相容性驗證工具，不能把此結果當成 App 實機或發布驗收。

- `artifacts.json` 固定官方 Ollama 可攜版、Qwen3-ASR 0.6B 與 TEA-ASR 1.1 GGUF 的大小與 SHA-256。
- `download.py` 只有明確指定產物才下載，保留至少 3 GiB 空間，不自動重送；損毀或部分產物必須人工核對，不能直接覆寫。
- `fixtures.py` 只使用四句寫死的非私人合成語料，不存取麥克風、剪貼簿、歷史文字或 API Key。macOS 語音合成可能在受限沙盒回傳空檔，必須檢查有效音框。
- `build_probe.py` 使用 App 目前已快取的 Swift binding 與原生 framework，不解析或更新套件，不修改快取。
- `GGUFProbe.swift` 驗證原生版本、Metal、模型載入、固定語料兩次辨識與原生取消。`run_native.py` 校驗權重與 fixture，180 秒 watchdog 只終止自己啟動的程序。
- 一般日誌只印 metadata，固定合成語料的辨識文字留在被忽略的 `.runtime`，不得拿工具記錄私人音訊或文字。
- RSS 為程序指標，不代表全部 Metal／統一記憶體峰值；下載期間的兩次辨識不是穩態 p50／p95。

規劃、放行條件與證據整理於 `docs/LOCAL_ASR_OLLAMA_INTEGRATION_PLAN.md`。執行後保留 `.runtime` 中的下載、雜湊與原始探針結果，不自動刪除既有模型。


第一輪執行結果已記入整合計畫第 10 節，正常推論不等於整體放行。

- `run_ollama.py` 僅讀取固定合成 ASR 結果；TEA 明確套用官方 tokenizer 的 PUA decoder 規則後再比較，未修改 App。
- `prepare_ollama.py` 以已核對的原始 manifest 與每層 SHA-256 在私有模型庫登錄，不改使用者模型庫。
- 官方 Ollama 首次 serve 仍會建立 ~/.ollama 本機識別檔，即使模型庫在隔離目錄。此行為已記錄，不把模型庫隔離宣稱為所有檔案均隔離。
- `loopback-only.sb` 的網路限制已用同一公開 IP 在外可連、在內 errno=1，並以本機可連的陽性對照驗證。
- 原生取消探針達三次失敗後已停止。修正過的程式已加 build fingerprint，但未再次執行取消，不得將編譯成功寫成取消通過。
- `analyze_results.py` 將原始字面比較與固定測試語料的「兩／二」數字變體比較分開，保留原始失敗證據。這不是通用中文數字解析器。
- 執行完畢已確認模型卸載、專用程序群組及連接埠關閉；模型檔保留，沒有常駐服務。

## 修正後的接入路徑

目前採用「受控原生 GGUF 子程序＋既有 localhost ASR API」，原因是固定版 Qwen 後端只在開始前檢查取消。沒有升級套件，也沒有把它標示為 App 內建 Qwen／TEA 引擎已完成。每個請求在回應前都會等待 native worker 結束，避免下一段 Ollama 整理與該次 ASR 同時運算。

`GGUFWorker.swift` 使用 App 共用的 `TEATranscriptDecoder`。英文片段保護位於 App 的 `LocalCleanupOutputPolicy.swift`，僅套用於 qwen3.5:9b 與未修改的內建智慧整理。自訂翻譯、助理及其他模型不自動套用此策略。英文片段對照只保存在單次請求記憶體中，標記遺失或重複即拒絕結果，保留原始轉錄，不自動重送。

最終中英混用保護只允許標點、空白、大小寫及正常繁簡轉換，中文用字或順序改變即拒絕。這會限制贅詞刪除與大幅潤飾，原因是實際結果曾新增中文用字。三輪試驗後停止模型重跑，保存結果以最終 App 規則離線重審為七筆接受、一筆拒絕；Qwen 中英混用品質仍未放行。詳見整合計畫第 11 節，不以呼叫完成或舊版 accepted=true 當成品質通過。

### 之後實機驗收時的設定

本節是驗收準備指引，未代表新版 App 已安裝或實機驗收通過。先依專案 BUILDING.md 的受支援測試 App 流程交付可追溯版本；不要將舊版 App 的結果當成本次修正。

在主 Mac 的專案目錄，各開一個終端機前景執行：

```sh
tools/taiwan-asr/.venv/bin/python tools/local-model-probe/gguf_server.py
```

啟動時以互動方式輸入至少 32 字元的 ASCII token，來源可用密碼管理器。不要將 token 放進指令、shell history、設定檔或對話。ASR 服務只把它存在記憶體，App 自訂模型金鑰走既有 Keychain。

另一個終端機執行：

```sh
python3 tools/local-model-probe/serve_ollama.py
```

新版測試 App 中的預計設定：

| 項目 | 值 |
| --- | --- |
| 自訂 ASR 端點 | `http://127.0.0.1:8766/v1/audio/transcriptions` |
| TEA 模型 ID | `tea-gguf` |
| Qwen3-ASR 0.6B 模型 ID | `qwen3-asr-0.6b-gguf` |
| ASR 金鑰 | 上述互動輸入的同一 token，勿貼到對話中。 |
| 整理 Provider | Ollama |
| Ollama 端點 | `http://127.0.0.1:11435` |
| 整理模型 | `qwen3.5:9b` |
| 文字整理逾時 | 實機測試前先檢查目前值，本輪曾超過預設 20 秒，可評估手動選 60 秒。這是全域整理設定，會影響其他 Provider；工具不自動修改。 |
| 整理提示詞 | 未修改的內建「智慧模式」。修改過的自訂提示詞不會自動套用本次語言保護。 |

兩個 ASR 設定互為選項，請不要覆蓋既有模式。本橋接只接受 WAV 最長 30 秒、auto／zh／en，不提供即時串流或 ASR 詞彙提示。GGUF worker 需保留目前 checkout 的原生 framework；清除 `.local-build` 或移動專案後，要先重新建置並驗證 worker，不能直接把這份工具當成可散布的 App 產物。

兩個終端機均以 Control-C 停止服務。本次自動驗證啟動的服務會自行停止，不需要手動終止其他 App 或使用 killall。
