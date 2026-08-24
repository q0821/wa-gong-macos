# macOS 語音輸入 App 專案方向

更新日期：2026-08-24

## 1. 專案目標

建立一款原生 macOS 語音輸入 App，讓使用者透過全域快速鍵開始錄音，完成本機語音轉錄與文字整理後，將文字插入目前使用中的 App。

第一優先是降低停止錄音後的等待時間，其次是繁體中文品質、隱私透明度與日常使用穩定性。

預計採用開放原始碼方式開發，透過 GitHub 發布原始碼與執行檔，目前沒有營利、訂閱或 Mac App Store 上架計畫。

## 2. 已決定的基底策略

### 2.1 主要基底

以最新版 [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) 為主要基底，建立自己的 Fork。

理由：

- 上游仍持續維護，並已累積全域快速鍵、錄音、音訊路由、Accessibility、文字插入、模型管理、串流轉錄與模式管理等成熟能力。
- 上游已具有 macOS 26 的 `SpeechAnalyzer` 與 `SpeechTranscriber` 實作，可直接作為 Apple 本機語音轉錄的起點。
- 上游已具有 Apple Silicon 本機文字整理模型 `VoiceInk Refine V1`，可先驗證本機整理速度與品質。
- 從成熟架構延伸，比重新處理 `CGEvent`、Accessibility、浮動視窗與 macOS 權限生命週期的成本低。

### 2.2 VoiceTwInk 的定位

[opass/VoiceTwInk](https://github.com/opass/VoiceTwInk) 作為功能規格與參考實作，不作為主要 Git 基底。

截至 2026-08-24，VoiceTwInk 與上游已大幅分歧，自有約 67 個 Commit，同時落後 VoiceInk 上游約 344 個 Commit。直接承接 VoiceTwInk 會增加同步、安全修正與架構衝突成本。

優先參考與移植的功能：

- 繁體中文與台灣用語調校。
- OpenCC 簡體轉繁體保底處理。
- Privacy HUD 與雲端傳送內容預覽。
- 選取文字、剪貼簿與自訂詞彙 Context 的獨立開關。
- 取消錄音時不傳送任何資料。
- 模擬逐字輸入，避免大量文字被目標 App 視為貼上內容。
- 本機自行編譯與穩定簽署流程。

不直接整批 Cherry-pick VoiceTwInk 的 Commit。每項功能應依最新版 VoiceInk 的架構重新評估與移植。

### 2.3 不從零開始

目前不採從零開發，原因如下：

- GPL v3 與本專案的開放原始碼發布方向相容，沒有為了避開授權而重寫的必要。
- macOS 全域輸入工具的主要成本不只在語音模型，還包括 Accessibility、`CGEvent`、音訊路由、權限、焦點 App、游標位置與浮動視窗生命週期。
- VoiceInk 已建立可擴充的轉錄與文字整理 Provider 架構，可用較小變更加入 Apple 技術。

若未來改為閉源、商業授權，或必須透過 Mac App Store 發布，需重新評估是否改用自行開發或寬鬆授權基底。

## 3. 目標技術流程

```text
全域快速鍵
→ AVAudioEngine 錄音與音量偵測
→ Transcription Provider
→ 原始轉錄文字
→ 繁體中文正規化
→ Text Refinement Provider
→ 文字輸出防護
→ Accessibility／CGEvent 插入目前 App
```

### 3.1 語音轉錄優先順序

1. Apple `SpeechAnalyzer`／`SpeechTranscriber`，作為 macOS 26 以上的本機優先方案。

2. VoiceInk 既有本機模型，作為相容性、語言品質與效能比較基準。

3. 既有雲端 Provider 保留為選用方案，不作為預設依賴。

Apple Speech 現有程式碼受 `ENABLE_NATIVE_SPEECH_ANALYZER` 編譯旗標控制。實作前必須確認使用中的 Xcode、macOS SDK、Build Settings 與語言資源下載流程，不可只因程式碼存在就視為可用。

### 3.2 文字整理優先順序

1. 先測試上游現有的 `VoiceInk Refine V1`。

2. 若速度、繁體中文品質或可自訂性不足，再新增 Apple Foundation Models Provider。

3. Private Cloud Compute 暫列後續研究，不納入第一版必要條件。

文字整理 Provider 應保持可替換，不讓錄音、轉錄、整理與輸出耦合成單一路徑。

### 3.3 文字輸出策略

預設沿用 VoiceInk 現有輸出機制，並驗證不同 App 的相容性：

- 一般文字欄位。
- LINE、Slack 與 Discord。
- Mail、備忘錄與瀏覽器。
- Terminal、Claude Code CLI 與其他會區分貼上及鍵入的工具。

必要時加入 VoiceTwInk 的模擬逐字輸入模式，但不取代所有使用情境的預設貼上流程。

## 4. 產品原則

- 本機優先：可以在裝置完成的工作，不預設送往雲端。
- 明確同意：任何語音、文字、剪貼簿、選取文字或畫面內容送往外部服務前，使用者必須可理解並控制。
- 繁體中文優先：中文輸出預設採台灣繁體中文，保留中英混合內容與專有名詞。
- 低延遲優先：先讓停止錄音後快速出字，再追求極致文字整理品質。
- 漸進移植：以可編譯、可測試的小步驟導入功能，不整批搬移舊 Fork。
- 不新增不必要套件：優先使用 VoiceInk 既有架構與 Apple 原生 Framework。
- 可稽核：網路傳送內容、目的地與觸發條件應能從 UI 或日誌確認。

## 5. 授權與發布決策

VoiceInk 與 VoiceTwInk 均採 GNU GPL v3。本專案作為衍生作品，發布時維持 GPL v3。

GitHub 發布要求：

- 保留原作者著作權、授權與免責聲明。
- 在文件與版本紀錄中清楚標示修改內容與日期。
- 每個執行檔 Release 建立對應 Git Tag。
- 每個執行檔必須能取得完全對應版本的原始碼與必要建置腳本。
- 不將 App 名稱、圖示與 Bundle Identifier 設計成 VoiceInk 官方版本。
- 第三方套件、模型權重與語言轉換字典須另外盤點授權，不能只依賴主專案的 GPL v3。

非營利不會免除 GPL v3 義務，但 GPL v3 允許免費或收費發布，與目前 GitHub 開放原始碼方向相容。

## 6. Repository 規劃

正式建立 Git Repository 後，預計使用：

```text
origin
→ 自己的 GitHub Repository

upstream
→ https://github.com/Beingpax/VoiceInk.git

voicetwink
→ https://github.com/opass/VoiceTwInk.git
```

同步原則：

- 以 `upstream/main` 為主要安全修正與架構更新來源。
- VoiceTwInk 僅用於閱讀差異、參考測試與移植特定功能。
- 自有功能以獨立、小型 Commit 實作，降低未來同步衝突。
- 不改寫上游歷史，不使用 Force Push 覆蓋已發布版本。

## 7. 第一版成功定義

- M1 Pro 實機可使用全域快速鍵開始與停止錄音。
- Apple 本機轉錄或替代本機模型可在不連網時完成短句轉錄。
- 中文結果穩定輸出台灣繁體中文。
- 可選擇完全本機文字整理流程。
- 可將結果插入常用 App，不破壞原本剪貼簿內容。
- 日誌可量測錄音停止、轉錄完成、整理完成與文字插入時間。
- 日誌不包含完整錄音、完整轉錄內容、API Key 或剪貼簿內容。
- GitHub Release 的執行檔、Git Tag 與原始碼完全對應。

初始效能目標需在基準測試後確認，暫定以短句為主：

- 停止錄音至原始轉錄完成的 p50 不超過 1 秒。
- 停止錄音至整理後文字插入的 p50 不超過 2 秒。
- 不以隱藏等待、固定 Sleep 或犧牲輸出正確性達成表面數字。

## 8. 參考資料

- [VoiceInk Repository](https://github.com/Beingpax/VoiceInk)
- [VoiceInk NativeAppleTranscriptionService](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift)
- [VoiceInk NativeAppleSpeechAssetManager](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Transcription/Native/NativeAppleSpeechAssetManager.swift)
- [VoiceInk VoiceInkRefineService](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Services/AIEnhancement/VoiceInkRefineService.swift)
- [VoiceTwInk Repository](https://github.com/opass/VoiceTwInk)
- [VoiceTwInk Fork Changes](https://github.com/opass/VoiceTwInk/blob/main/FORK-CHANGES.md)
- [VoiceTwInk 作者的 Fork 評估](https://www.opasschang.com/blog/i-paid-2800-for-voice-input-class-then-forked-instead)
- [GNU GPL v3](https://www.gnu.org/licenses/gpl.en.html)
