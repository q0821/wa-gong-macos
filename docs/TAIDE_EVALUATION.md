# TAIDE 整合評估

更新日期：2026-08-26

## 1. 評估範圍與結論

本報告評估 TAIDE 模型是否適合加入 macOS 原生語音輸入 App「聲筆 Wa-Gong」，涵蓋繁體中文與台灣用語、模型大小、量化、本機部署、授權、Swift 整合方式，以及語音轉文字與文字生成的分工。

研究資料只採用第一方來源：

- [TAIDE 官方網站](https://taide.tw/)。
- [TAIDE 官方 Hugging Face 組織](https://huggingface.co/taide/models)。
- [TAIDE 官方 GitHub 組織](https://github.com/taide-taiwan)。
- TAIDE 官方網站或官方模型頁連結的授權文件。

結論如下：

1. TAIDE 適合放在 Wa-Gong 的「文字整理」階段，不適合取代目前的 Whisper 語音轉文字模型。TAIDE 官方公開模型的任務是文字生成或文字嵌入，並非音訊辨識。
2. 第一階段最適合評估 `TAIDE-LX-7B-Chat-4bit`。它是官方 Hugging Face 帳號提供的 `GGUF` 模型，檔案約 4.22 GB，官方同時提供 `llama.cpp` 與 Ollama 的本機執行方式。
3. 目前最適合繁體中文與台灣用語品質比較的模型是 `Gemma-3-TAIDE-12b-Chat-2602`。它加入中期訓練，官方說明特別提到台灣文化、地理、歷史、社會現象與台灣使用者的日常用語及專業術語，但官方權重檔案約 27.2 GB，尚未在官方模型頁提供 `GGUF` 或 `MLX` 版本，不適合直接作為目前磁碟空間有限的預設模型。
4. 不建議目前把 TAIDE 權重直接打包進 Wa-Gong。TAIDE 授權包含不可轉讓、不可再授權、來源網站、第三方基礎模型條款與散布時的告知義務，應先採「使用者從官方來源取得模型，Wa-Gong 連接本機執行服務」的模式，並在正式散布前進行授權審查。
5. Wa-Gong 已有 `OllamaService`、`AIProvider.ollama` 與本機文字整理流程，因此 Ollama 是最小整合範圍。直接把 `llama.cpp` 連進 Swift App 可行，但需要新增原生橋接層、模型生命週期管理與記憶體控制，不是只新增一個模型檔案即可完成。

## 2. 官方模型比較

以下容量是依官方 Hugging Face 檔案列表加總的約略值，實際下載後還會包含 tokenizer、設定檔與執行環境快取。

| 模型 | 官方定位與繁中能力 | 參數與上下文 | 官方權重／量化狀態 | 本機部署評估 |
| --- | --- | --- | --- | --- |
| [TAIDE-LX-7B-Chat](https://huggingface.co/taide/TAIDE-LX-7B-Chat) | 以 TAIDE-LX-7B 為基礎，經指令微調，強化辦公室任務與多輪問答；官方說明包含台灣文化、用語與國情。 | 7B，4K | `Safetensors`，3 個權重檔，約 13.9 GB。 | 可透過 `Transformers` 或 vLLM 使用，但對目前 Mac 磁碟空間不實際。 |
| [TAIDE-LX-7B-Chat-4bit](https://huggingface.co/taide/TAIDE-LX-7B-Chat-4bit) | 同一個聊天模型的官方 4 bit 版本。 | 7B，4K | 官方 `GGUF` 檔案 `taide-7b-a.2-q4_k_m.gguf`，約 4.22 GB。 | 最適合第一階段，以 `llama.cpp` 或 Ollama 執行。官方模型頁直接提供兩者的指令。 |
| [Llama-3.1-TAIDE-LX-8B-Chat](https://huggingface.co/taide/Llama-3.1-TAIDE-LX-8B-Chat) | 加強正體中文、台灣文化與長文處理，官方表示正體中文解碼速度提升 20%。 | 8.5B，131,584 | `Safetensors`，4 個權重檔，約 17.0 GB。官方模型頁未提供官方 `GGUF` 或 `MLX` 檔案。 | 可用 `Transformers` 或 vLLM，但不適合作為目前 Mac 的第一個內建模型。 |
| [Gemma-3-TAIDE-12b-Chat](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat) | 以 Gemma 3 12B 為基礎，強化台灣用語、在地知識、摘要、寫信與文章等任務。 | 12.4B，128K | `Safetensors`，4 個權重檔，約 24.8 GB。官方建議以文字輸入，輸出也是文字。 | 適合品質比較，不適合目前本機直接部署。 |
| [Gemma-3-TAIDE-12b-Chat-2602](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat-2602) | 目前較新的聊天模型，加入中期訓練，官方說明特別提到修正翻譯腔、台灣日常用語與專業術語。 | 12.4B，128K | `Safetensors`，6 個權重檔，約 27.2 GB。官方快速開始建議以 `bfloat16` 載入，未提供官方 `GGUF` 或 `MLX` 版本。 | 適合作為第二階段品質基準，不適合目前直接隨 App 下載。 |
| [embeddinggemma-GTAIDE-300m-2605](https://huggingface.co/taide/embeddinggemma-GTAIDE-300m-2605) | 以台灣法規資料微調，目標是法規檢索與文字相似度，不是聊天或文字整理。 | 0.3B，最大 2,048 tokens，輸出 768 維向量 | `Safetensors`，約 1.21 GB。 | 可作為未來字典、文件檢索或台灣法規檢索元件，不應當作文字生成模型。 |

模型清單與版本時間可由 [TAIDE 官方模型歷程](https://taide.tw/) 及 [TAIDE 官方 Hugging Face 模型清單](https://huggingface.co/taide/models) 交叉確認。官方網站列出的 `Gemma-3-TAIDE-12b-Chat-2602` 釋出日期為 2026-02-13，`Embeddinggemma-GTAIDE-300m-2605` 釋出日期為 2026-06-12。

### 2.1 不建議使用的模型形態

- `TAIDE-LX-7B` 是持續預訓練模型，官方說明指出它適合再做微調，沒有聊天模型的指令微調與偏好對齊，不適合作為 Wa-Gong 的一般文字整理預設值。[官方模型說明](https://huggingface.co/taide/TAIDE-LX-7B)
- 不應直接採用非 TAIDE 官方帳號提供的壓縮版或轉換版。TAIDE 官方網站明確說明，授權與相關說明適用於 TAIDE 官方網站及官方授權來源，對其他未經明確授權的網站不負擔保責任。[官方模型下載與來源說明](https://taide.tw/public/download-model)

## 3. 繁體中文與台灣用語適配性

`Gemma-3-TAIDE-12b-Chat-2602` 是本次評估中最值得優先做語言品質比較的模型，原因不是只有參數較大，而是官方明確記載它加入高品質台灣資料的中期訓練，並改善台灣文化、地理、歷史、社會現象、日常用語與專業術語。這是官方模型說明，不代表每一次輸出都一定正確或一定符合台灣慣用語。[TAIDE 官方模型歷程](https://taide.tw/)；[官方模型卡](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat-2602)

較小且較容易本機部署的 `TAIDE-LX-7B-Chat-4bit`，官方也標示它針對台灣文化、用語與國情加強，並提供自動摘要、寫信、寫文章、中翻英與英翻中等任務能力。[官方模型卡](https://huggingface.co/taide/TAIDE-LX-7B-Chat-4bit)

官方模型卡提供的 system prompt 範例為：

```text
你是一個來自台灣的 AI 助理，你的名字是 TAIDE，樂於以台灣人的立場幫助使用者，會用正體中文回答問題。
```

Wa-Gong 未來的文字整理 prompt 建議再加入產品用途限制，這是本專案的整合建議，不是 TAIDE 官方承諾：

```text
請使用台灣繁體中文與台灣慣用詞。
只整理輸入內容，不新增輸入中沒有的事實、人物、數字或網址。
保留專有名詞、英文、程式碼、網址、數字與原本的語氣。
只輸出整理後的文字，不要說明修改過程。
```

仍需注意，TAIDE 官方模型頁同時提醒語言模型可能產生不正確內容，使用時需要自行加入安全防護機制，不能把「台灣用語加強」解讀為事實查核或零幻覺保證。[TAIDE-LX-7B-Chat 官方免責說明](https://huggingface.co/taide/TAIDE-LX-7B-Chat)；[Gemma-3-TAIDE-12b-Chat-2602 官方模型卡](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat-2602)

## 4. 語音轉文字與文字生成的角色差異

Wa-Gong 的資料流應維持以下分工：

```text
麥克風音訊
→ Whisper／Apple Speech 等語音轉文字模型
→ 原始轉錄文字
→ TAIDE 等文字生成模型整理
→ 文字插入目前使用中的 App
```

| 工作 | 輸入 | 輸出 | Wa-Gong 目前對應 |
| --- | --- | --- | --- |
| 語音轉文字 | 音訊 | 文字 | `ggml-base` Whisper 多語言模型、Apple Speech、其他語音 Provider |
| 文字整理 | 文字、system prompt | 文字 | `Wa-Gong Refine`、Ollama、Local CLI、雲端文字 Provider |
| 向量嵌入 | 文字 | 向量 | 未納入目前主要流程；`embeddinggemma-GTAIDE-300m-2605` 可作未來檢索用途 |

因此，TAIDE 不會解決目前「Whisper 中文辨識品質」的問題。它能處理的是轉錄完成後的錯字修整、段落整理、語氣整理與台灣用語調整。若原始語音已經被辨識成錯誤文字，TAIDE 也可能把錯誤內容合理化，不能取代語音模型的準確度測試。

## 5. 授權與散布風險

TAIDE 官方網站目前將公開模型分為 L 類與 G 類，並列出適用模型：

- L 類包含 `TAIDE-LX-7B`、`TAIDE-LX-7B-Chat`、`TAIDE-LX-7B-Chat-4bit`、`Llama-3.1-TAIDE-LX-8B-Chat` 等。
- G 類包含 `Gemma-3-TAIDE-12b-Chat`、`Gemma-3-TAIDE-12b-Chat-2602` 與 `Embeddinggemma-GTAIDE-300m-2605`。

詳細條款以 [TAIDE 官方模型下載與授權頁](https://taide.tw/public/download-model) 的中文版為準。重要條款摘要如下：

| 項目 | L 類模型 | G 類模型 |
| --- | --- | --- |
| 授權性質 | 非專屬、全球、不可轉讓、不可再授權、無償 | 非專屬、全球、不可轉讓、不可再授權、無償 |
| 基礎模型條款 | 另須遵守 [Meta Llama 3 授權](https://llama.meta.com/llama3/license/) 與 [Meta Llama 3 使用政策](https://llama.meta.com/llama3/use-policy/) | 另須遵守 [Google Gemma Terms of Use](https://ai.google.dev/gemma/terms) 與其中的 Prohibited Use Policy |
| 使用限制 | 不得用於軍事或非法目的，並須遵守適用法律 | 除上述要求外，官方條款另限制非法或不當言論，且不得表示內容由人類生成 |
| 衍生或散布 | 修改內容須以顯著方式說明；散布時須提供授權條款副本並促使接收者遵守 | 除上述要求外，散布時須附帶 Gemma 條款通知、標示源自 TAIDE G 類模型與 `taide.tw` 官方網址 |
| 來源要求 | 只應從國研院或國研院授權的網站取用 | 只應從國研院或國研院授權的網站取用 |
| 終止效果 | 違反條款時授權可能終止，終止後須刪除並停止使用模型 | 同左 |

這些條款不是一般 MIT 或 Apache 這類寬鬆授權。Wa-Gong 是 GPL v3 開放原始碼專案，若將 TAIDE 權重直接放進 App 或 Release，可能同時涉及：

1. TAIDE 授權的不可轉讓與不可再授權條款。
2. Meta Llama 或 Google Gemma 的基礎模型條款。
3. 向 App 使用者散布模型時的授權副本、來源標示、限制告知與衍生作品標示。
4. Wa-Gong GPL v3 與模型個別授權條款能否共同散布的相容性。

因此，第一階段不把權重提交到 Git Repository、不放入 App Bundle，也不從非官方鏡像下載。較保守的做法是：使用者自行在官方 Hugging Face 頁面接受條款並取得模型，透過本機 Ollama 或 `llama.cpp` 服務執行，Wa-Gong 只連接 `localhost`。正式對外發布前，仍應針對「模型是否隨 App 散布」及「App 是否提供下載功能」取得授權意見。這是基於官方條款的風險控管建議，不是法律意見。

## 6. macOS Swift 整合方式

### 6.1 Ollama 中介層，第一優先

TAIDE 官方 `TAIDE-LX-7B-Chat-4bit` 模型頁直接提供 Ollama 用法：

```bash
ollama run hf.co/taide/TAIDE-LX-7B-Chat-4bit:Q4_K_M
```

官方同一頁也提供 `llama.cpp` 的 `llama serve` 與 `llama cli` 用法。[TAIDE-LX-7B-Chat-4bit 官方本機執行說明](https://huggingface.co/taide/TAIDE-LX-7B-Chat-4bit)

這條路徑最符合目前 Wa-Gong 的程式結構：

- [VoiceInk/Services/OllamaService.swift](../VoiceInk/Services/OllamaService.swift) 已負責本機 Ollama 連線、模型清單與文字生成。
- [VoiceInk/Services/AIEnhancement/AIService.swift](../VoiceInk/Services/AIEnhancement/AIService.swift) 已有 `AIProvider.ollama`，而且不需要 API Key。
- TAIDE 的角色可放在現有文字整理 Provider，不需要改動 Whisper 語音轉文字流程。
- 音訊與轉錄文字都留在本機，不需要新增雲端傳送路徑。

缺點是使用者仍需另外安裝 Ollama、下載模型並維持本機服務；Wa-Gong 必須清楚顯示服務未啟動、模型未下載與模型名稱不相容等狀態。

### 6.2 直接連結 `llama.cpp`

官方 4 bit 模型是 `GGUF`，理論上可由 `llama.cpp` 直接載入。若不使用 Ollama，Wa-Gong 需要：

1. 將 `llama.cpp` 的原生函式庫或 XCFramework 加入 Xcode 專案。
2. 建立 Swift 與 C API 之間的橋接層。
3. 管理模型下載、官方來源、版本、檔案完整性與刪除。
4. 管理 Metal、執行緒、上下文長度、取消、記憶體與模型卸載。
5. 使用正確的 chat template，並將 system prompt、轉錄文字與輸出限制分開處理。

目前專案內的 `whisper.cpp` XCFramework 是語音轉文字用途，不能直接拿來執行 TAIDE 文字生成模型。兩者都可能使用相近的底層技術名稱，但模型格式、推論 API 與工作流程不同。

### 6.3 `Transformers`、vLLM 與 `MLX`

- TAIDE 官方完整 `Safetensors` 模型頁提供 `Transformers` 與 vLLM 使用方式。這些範例不是 Swift API，若在 Mac App 中使用，仍需要本機 Python 服務、外部程序或其他原生執行層。[TAIDE-LX-7B-Chat 官方使用說明](https://huggingface.co/taide/TAIDE-LX-7B-Chat)；[Gemma-3-TAIDE-12b-Chat-2602 官方快速開始](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat-2602)
- 官方 TAIDE 模型頁目前列出的本機方式包含 `Transformers`、vLLM、`llama.cpp`、Ollama 等，但沒有提供 TAIDE 專用的 `MLX` 權重或 `mlx-swift` 使用範例。因此，不能因為 Wa-Gong 的 [Package.resolved](../VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) 已經有 MLX 相關 Swift Package，就視為 TAIDE 可以直接載入。要走 MLX，還需要轉換權重、驗證 tokenizer 與 chat template，並重新量測品質與記憶體。
- 在沒有官方 MLX 版本以前，Wa-Gong 不應把 `MLX` 當成 TAIDE 的第一整合路徑。這個判斷是根據官方模型頁未提供該格式與範例所作的工程推論。

## 7. 對 Wa-Gong 的具體建議

### 建議採用的第一階段

1. 保留目前 `ggml-base` 作為預設語音轉文字模型。它是 Whisper 多語言模型，TAIDE 不取代它。
2. 將 `TAIDE-LX-7B-Chat-4bit` 定義為「本機文字整理模型」，不是「語音模型」。
3. 優先接到既有 Ollama Provider，模型實際識別字使用官方模型頁建議的 `hf.co/taide/TAIDE-LX-7B-Chat-4bit:Q4_K_M`。
4. 使用者介面顯示模型名稱、參數量、約 4.22 GB 容量、`GGUF Q4_K_M`、支援台灣繁體中文，以及「需要另外安裝 Ollama」的狀態。
5. 不把 TAIDE 權重放進 App Bundle，不把模型檔提交到 Repository，也不使用第三方轉換版。
6. 對於語音輸入的即時低延遲路徑，先保留原始轉錄文字直接輸出；TAIDE 只作為使用者可選的文字整理步驟，避免 7B 模型載入時間拖慢每次出字。

### 第二階段品質比較

在使用者確認本機資源足夠後，再比較：

- `TAIDE-LX-7B-Chat-4bit`：容量較小、官方有 `GGUF`、適合產品整合驗證。
- `Gemma-3-TAIDE-12b-Chat-2602`：官方最新的台灣用語與在地知識版本，適合作為品質基準，但需要約 27.2 GB 權重空間，且目前官方頁沒有可直接給 Ollama 或 `llama.cpp` 使用的官方量化檔案。

比較資料應至少包含：中文口語整理、台灣專有名詞、數字與日期、英文與網址保留、中英混合、錯字修正、不可新增事實、長文字與取消操作。TAIDE 官方的 [taide-bench-eval](https://github.com/taide-taiwan/taide-bench-eval) 可作為文字任務參考，涵蓋中翻英、英翻中、摘要、寫文章與寫信；它不能取代 Wa-Gong 的錄音延遲、快速鍵、文字插入與跨 App 實測。

### 不建議現在做的事

- 不把 TAIDE 設成 Whisper 語音轉文字模型。
- 不把 `Gemma-3-TAIDE-12b-Chat-2602` 直接設成所有 Mac 的預設模型。
- 不直接下載非官方 Hugging Face 帳號的 TAIDE GGUF 轉換版。
- 不在未確認授權相容性前，將 TAIDE 權重與 GPL v3 App 一起打包發布。
- 不把 TAIDE 的官方模型卡評測分數當成 Wa-Gong 的實際中文錄音品質證明。

## 8. 後續實作驗收條件

未來若決定實作 TAIDE Provider，至少應符合以下條件：

- 模型來源固定為 TAIDE 官方網站或官方 Hugging Face 帳號，並記錄模型 Repository 與 revision。
- 本機模型頁清楚標示「文字生成」與「不支援語音轉文字」，避免使用者誤選。
- 只有明確啟用文字整理時才送出轉錄文字；不把音訊送給 TAIDE。
- 不把剪貼簿、選取文字或其他 Context 一起送出，除非未來另有明確的隱私設定與同意流程。
- Ollama 未啟動、模型不存在、模型回應逾時或使用者取消時，錄音與文字輸出流程都能正常失敗回復。
- Prompt 要求使用台灣繁體中文、保留網址與專有名詞、不得新增事實，並以程式碼層的輸出檢查作為最後防線。
- 在使用者的實際 Mac 上量測模型載入時間、記憶體、停止錄音至輸出延遲，以及連續使用時的穩定性。
- 若未來要提供模型下載或把模型放入 App，先完成 TAIDE L／G 類條款、Meta／Gemma 基礎條款與 GPL v3 散布方式的授權審查。

## 9. 官方來源

- [TAIDE 官方網站](https://taide.tw/)
- [TAIDE 官方模型歷程與模型下載、授權頁](https://taide.tw/public/download-model)
- [TAIDE 官方 Hugging Face 模型清單](https://huggingface.co/taide/models)
- [TAIDE-LX-7B-Chat](https://huggingface.co/taide/TAIDE-LX-7B-Chat)
- [TAIDE-LX-7B-Chat-4bit](https://huggingface.co/taide/TAIDE-LX-7B-Chat-4bit)
- [Llama-3.1-TAIDE-LX-8B-Chat](https://huggingface.co/taide/Llama-3.1-TAIDE-LX-8B-Chat)
- [Gemma-3-TAIDE-12b-Chat](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat)
- [Gemma-3-TAIDE-12b-Chat-2602](https://huggingface.co/taide/Gemma-3-TAIDE-12b-Chat-2602)
- [embeddinggemma-GTAIDE-300m-2605](https://huggingface.co/taide/embeddinggemma-GTAIDE-300m-2605)
- [TAIDE 官方 GitHub 組織](https://github.com/taide-taiwan)
- [TAIDE 官方 taide-bench-eval](https://github.com/taide-taiwan/taide-bench-eval)
