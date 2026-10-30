# Nemotron 3.5 Transcribe 整合評估與測試

- 建立日期：2026-10-30。
- 狀態：待測試，使用者要求先記錄待辦，晚點再測。
- 本機 Issue，尚未建立 GitHub Issue。本輪只建立文件，不下載模型、不安裝 runtime、不發出辨識請求、不修改 App。

## 問題與目標

評估 NVIDIA Nemotron 3.5 Transcribe 是否適合聲筆的台灣中文短句輸入、專有名詞提示及轉錄格式控制。以相同語料比較現有 TEA 與常用雲端辨識來源，取得品質、延遲及資源證據，再決定是否實作整合。

## 初步評估與限制

- 2026-10-30 已查閱官方模型卡與 NeMo-Speech.cpp 文件，尚未執行模型。以下是文件與原始碼評估，不能視為實機支援或效能證據。
- 目標為 `NVIDIA-Nemotron-3.5-Transcribe-30B-A4B`，總參數約 34B、啟用約 4.3B。與 App 現有 FluidAudio 的 Nemotron 0.6B 串流模型不同，不能只替換模型 ID 或權重檔。
- 官方標示為完整錄音的非即時串流模型；輸出 token 串流與內部音訊分塊不代表可邊收麥克風音訊邊辨識。
- 支援普通話、文字指示與詞彙情境提示；尚無本專案相同台灣語料下優於 TEA 的證據。繁體中文、中英夾雜、台灣口音及專有名詞須實測。
- NeMo-Speech.cpp 提供此模型的 `/v1/audio/transcriptions` 及聊天介面。App 既有自訂辨識傳輸可作為評估入口，但目前未送詞彙提示與轉錄指示，契約相容性仍待測試。
- runtime 整體提供 Metal 建置，但此模型專屬平台文件不足以確認 Apple Silicon 完整加速與效能。模型需 encoder 與 decoder，不能直接套用 TEA helper。
- 啟用參數數量不等於完整權重記憶體需求；NVIDIA GPU 的宣傳速度不能當成 Mac 延遲。

## 決策與理由

- 選擇先做獨立比較，否決直接替換 TEA 或設為預設，因為尚未取得中文品質、Mac 支援及停止後延遲證據。
- 優先評估停止錄音後辨識及專有名詞情境提示，否決將本模型標為即時串流，因為官方明確區分完整錄音與即時音訊輸入。
- 逐字轉錄與去贅詞／格式整理分開測量。否決把整理後輸出當成原始辨識，因為模型指示可能改變原話，會混淆錯誤來源與歷史資料語意。
- 本輪不納入 1.1.0 發版阻擋，因為這是尚未決定實作的模型探索；既有功能驗收限制維持。

## 後續測試計畫

1. 使用者明確要求開始時，重新查閱官方模型、runtime、平台及授權文件，記錄精確 revision、量化格式與執行硬體。先確認可用空間與記憶體，再決定本機或外部服務路線。
2. 準備 20～30 段非私人、具人工標準答案的台灣中文錄音，涵蓋短句、中英夾雜、人名公司名、技術術語、金額日期、否定句及噪音／靜音。不同長度分組比較。
3. 相同音檔比較 TEA、選定雲端辨識來源與 Nemotron。先關閉額外文字整理，比較原始辨識；Nemotron 分別測無提示與有詞彙提示。
4. 另測逐字模式與去贅詞／格式模式，記錄增刪改義、繁簡體、錯誤翻譯與額外說明，不用後處理掩蓋辨識問題。
5. 記錄中文 CER、專有名詞命中、數字與否定詞正確性、漏字及無語音時的額外生成。先確認評分方法可抓到已知錯誤，避免正規化掩蓋重要差異。
6. 分別量測冷啟動、暖機、停止後至完整結果時間及記憶體峰值；重複測量並記錄條件，不套用官方 GPU 數字。
7. 若品質與效能值得整合，再另寫功能 spec／plan，涵蓋詞彙能力、請求及回應格式、取消、逾時、失敗不重送、原始轉錄保留與診斷；本 Issue 不直接授權修改上述程式。

## 待辦與結案條件

- [ ] 確認測試硬體、runtime revision、權重來源、量化與完整性。
- [ ] 確認 Mac 實際後端、模型載入與記憶體需求，或外部辨識服務的實際契約。
- [ ] 完成相同語料、無提示／有提示與逐字／整理模式比較。
- [ ] 取得中文品質、專有名詞及數字／否定句的可複核結果。
- [ ] 取得冷暖延遲與記憶體證據，明列不支援或失敗情況。
- [ ] 給出採用、暫緩或不採用的結論及理由；若採用，先定義目標硬體、品質與延遲門檻，再展開整合規格。

重啟條件：使用者明確要求開始測試。付費雲端、對外傳送音訊或新增資源費用前，先確認服務、固定非私人語料、次數與費用範圍；本待辦不構成該類授權。

## 查證入口

- [NVIDIA 技術介紹](https://research.nvidia.com/labs/nemotron/NVIDIA-Nemotron-3.5-Transcribe/)
- [官方模型卡與評測](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B)
- [NeMo-Speech.cpp 模型使用指南](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/docs/salm/README.md)
- [模型與平台文件](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/docs/salm/models.md)
- [App 自訂語音辨識傳輸](../../VoiceInk/Transcription/Cloud/OpenAICompatibleTranscriptionService.swift)
- [App 既有模型清單](../../VoiceInk/Models/TranscriptionModelRegistry.swift)
- [App 既有 Nemotron 串流介面](../../VoiceInk/Transcription/Streaming/FluidAudioNemotronStreamingProvider.swift)

## 本次文件驗收

- [x] 記錄待測狀態、決策理由、測試步驟與重啟條件。
- [x] 初步評估與未驗證事項分開，未宣稱已支援或優於 TEA。
- [x] 本機連結及 diff 空白檢查通過；未修改 App 或執行模型測試。
