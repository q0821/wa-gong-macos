# 台灣 ASR 本機驗證工具

已提供離線推論探針與手動啟動的 loopback HTTP 服務。兩模型、實際 App 傳輸、並行拒絕、模型切換、斷線清理與恢復已經過真實本機請求驗證。新 App 尚未安裝，真實雲端潤飾與錄音／貼上仍未驗收。詳細證據見 `docs/BREEZE_TEA_INTEGRATION_PLAN.md`。

## 環境

- Apple Silicon，Python 3.12。
- `models.json` 固定模型 repository、revision、推論權重大小與 SHA-256。
- `requirements.lock` 固定本次實際安裝的依賴版本，含 qwen-asr 所需的 Transformers 4.57.6。
- 本機成功測試的組合為 Python 3.12.9、PyTorch 2.14.1、Transformers 4.57.6、qwen-asr 0.0.6。舊 PyTorch 2.9.1 在本機測試過慢，未取得成功結果，不列為支援環境。
- `.venv` 與 `.runtime` 不進版控。模型、合成音檔及結果留在 `.runtime`，不使用使用者既有的 Hugging Face 快取。

在專案根目錄執行：

```sh
UV_CACHE_DIR="$PWD/tools/taiwan-asr/.runtime/uv-cache" uv venv --python 3.12 tools/taiwan-asr/.venv
UV_CACHE_DIR="$PWD/tools/taiwan-asr/.runtime/uv-cache" uv pip sync --python tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/requirements.lock
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/probe.py --help
```

## 模型下載

明確呼叫 download 才會下載模型。只取推論檔案，不下載 Breeze 的 optimizer、訓練狀態或另一份 PyTorch 權重。下載前檢查完整模型大小加 6 GiB 餘裕；同時下載其他模型時，需另外計入尚未下載的檔案大小。

```sh
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/probe.py download breeze
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/probe.py download tea
```

## 非私人合成測試音檔

以 macOS 已安裝的 Meijia 語音在本機產生，不播放、不使用付費服務。若語音未安裝，先確認可用語音，不能將下載失敗當作模型問題。

```sh
mkdir -p tools/taiwan-asr/.runtime
/usr/bin/say -v Meijia -o tools/taiwan-asr/.runtime/fixture-zh.wav --file-format=WAVE --data-format=LEI16@16000 '今天下午三點開會，請保留原始資料，不要刪除。'
```

## 離線推論

run 強制使用本機模型檔案，不允許推論時自動下載，並驗證權重大小與 SHA-256。固定單聲道、16 kHz、最長 30 秒，兩模型分開啟動程序。預設使用 MPS、SDPA 與 float16，理由是避免在 16 GB 統一記憶體上以 float32 加倍占用模型記憶體；未使用量化或 MPS 的 CPU fallback。整體執行預設限時 180 秒，逾時以 exit code 124 結束，沒有輸出成功結果；可透過 `--timeout` 在 30 至 600 秒間明確指定。

```sh
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/probe.py run breeze --audio tools/taiwan-asr/.runtime/fixture-zh.wav --output tools/taiwan-asr/.runtime/breeze-zh.json
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/probe.py run tea --audio tools/taiwan-asr/.runtime/fixture-zh.wav --output tools/taiwan-asr/.runtime/tea-zh.json
```

結果包含模型載入時間、首次與暖機推論時間、音檔摘要、程序 peak RSS，以及推論結束時的 MPS driver allocation。後者不是 GPU 峰值，RSS 也不能代替全系統統一記憶體峰值。

完整轉錄只寫入明確指定的結果檔，不寫入一般日誌，既有結果拒絕覆寫。僅可使用非私人合成或已授權的公開測試音檔。本工具不應用來批次處理使用者歷史錄音。

這些測試不證明真實使用者口音、中英混用、背景噪音、API 相容性、取消行為或跨 App 文字插入已通過。

邊界測試指令：

```sh
tools/taiwan-asr/.venv/bin/python -m unittest discover -s tools/taiwan-asr -p 'test_*.py' -v
```

## 啟動本機服務

以下指令在這台 Mac 的專案根目錄執行，不是在 Mac mini 執行。

```sh
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/server.py --port 8765
```

服務只綁定 `127.0.0.1`，不開放區網。提示時輸入至少 32 字元的 ASCII 隨機 token，建議由密碼管理器產生。不把 token 放進指令參數、程式碼、版控或一般日誌。服務只將它保存在記憶體；App 自訂模型的金鑰仍由既有 Keychain 流程保存。

App 自訂轉錄設定：

| 欄位 | 設定 |
| --- | --- |
| API Endpoint | `http://127.0.0.1:8765/v1/audio/transcriptions` |
| API Key | 與服務啟動時輸入的 token 相同 |
| Model Name | `MediaTek-Research/Breeze-ASR-25` 或 `JacobLinCool/TEA-ASR-1.1`，也接受 `breeze`、`tea` |
| 語言 | 台灣國語建議選中文；也接受英文與自動偵測，後兩者的模型品質尚未實測。 |
| 即時轉錄 | 不支援，停止錄音後才轉錄。 |

先用 App 的「測試連線」傳送內建測試音檔，確認模型已可轉錄，再開始日常錄音。首次使用與切換模型會載入權重並建立 GPU 執行狀態，可能等待數十秒；本機 App 請求上限為 180 秒，服務推論上限為 150 秒。

服務一次只保留一個模型程序，不會同時常駐兩個模型。切換模型會停止舊程序，重新載入所選模型。另一個請求正在處理時回覆 429，不自動排隊或重送。斷線或逾時會停止該 worker，下一次請求需重新載入模型。

限制：

- 只接受未壓縮 WAV，最長 30 秒，上傳總大小最多 12 MiB。
- 支援單聲道或雙聲道、8 kHz 至 96 kHz，推論前轉為單聲道 16 kHz。
- 達到模型輸出上限會回報錯誤，不回傳截斷結果。
- `temperature` 只接受 0，`response_format` 只接受 json。
- 不支援串流、說話者分離、熱詞或額外 Context；未知參數會明確拒絕。
- 請求音訊僅供本次轉錄。Multipart 暫存檔由表單解析器的關閉流程清除，服務不另行保存錄音或轉錄紀錄。
- 關閉服務用目前執行它的終端機送出 Ctrl+C，會停止模型 worker。這是手動工具，尚未設定常駐自動啟動。

## 真實本機驗收

以下工具會建立隨機埠的臨時 loopback 服務，token 僅在記憶體內；使用前先產生上述固定合成音檔。需要兩個模型都已下載及可用的 Metal GPU。執行結束會停止服務及 worker，成功結果才寫入指定的新檔案。

```sh
tools/taiwan-asr/.venv/bin/python tools/taiwan-asr/verify_service.py --audio tools/taiwan-asr/.runtime/fixture-zh.wav --output tools/taiwan-asr/.runtime/my-service-check.json
```

`verify_transport.swift` 是連結實際 Debug App 程式庫的傳輸探針，不啟動 App，也不讀 Keychain。它需依專案建置的 module／framework 搜尋路徑編譯，再透過 `verify_service.py --app-probe <執行檔>` 加入實際 App 傳輸驗證。

`verify_refinement.swift` 是四組雲端驗收工具。預設不讀金鑰、不送請求；只有明確核准後才可設定 `WAGONG_ALLOW_BILLABLE_VALIDATION=yes` 執行。不得把本機測試通過寫成四組雲端驗收已通過。

工具以唯讀方式查詢既有 App Keychain，不執行遷移或改寫，不彈出認證提示；只記錄狀態碼，不記錄金鑰或完整遠端回應。2026-10-16 的四次合成文字測試已核准，但命令列程序在金鑰讀取階段停止，實際送出 0 次。這不代表已證明 App 內未設定金鑰，詳細結果及重啟條件見 `docs/BREEZE_TEA_INTEGRATION_PLAN.md` 第 12 節。
