<div align="center">
  <h1>聲筆 Wa-Gong for macOS</h1>
  <p>本機優先、繁體中文優先的 macOS 語音輸入工具</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
  [![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
  [![Status](https://img.shields.io/badge/status-early%20development-orange.svg)](docs/IMPLEMENTATION_PLAN.md)
</div>

## 專案狀態

本專案目前處於早期開發階段，尚未發布可供一般使用者下載的穩定版本。

現階段程式碼以 [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) 最新版為基底，App 顯示名稱、Bundle Identifier 與本機產物名稱已完成第一階段的 Wa-Gong 品牌遷移。內部 target 名稱、部分上游元件名稱與既有本地化文案仍保留 VoiceInk，方便持續同步上游程式碼。

本專案是獨立社群 Fork，不是 VoiceInk 官方版本，也不由 VoiceInk 原作者提供支援。

## 專案目標

聲筆 Wa-Gong for macOS 希望提供一條快速、可稽核且能完全在本機執行的語音輸入流程：

```text
全域快速鍵
→ 錄音
→ 本機語音轉錄
→ 繁體中文正規化
→ 本機文字整理
→ 插入目前使用中的 App
```

開發優先順序：

1. 降低停止錄音後的等待時間。

2. 穩定輸出台灣繁體中文與中英混合內容。

3. 讓使用者清楚知道哪些資料留在本機，哪些資料會送往外部服務。

4. 保留可替換的本機與雲端 Provider，不綁定單一模型。

5. 透過 GitHub 提供可重現、可稽核的原始碼與 Release。

## 預計技術方向

### 語音轉錄

- 優先驗證 Apple `SpeechAnalyzer` 與 `SpeechTranscriber`。
- 保留 VoiceInk 既有 Whisper、FluidAudio 與雲端 Provider 作為比較及降級方案。
- 量測停止錄音、Partial Transcript、Final Transcript 與文字插入時間。

### 文字整理

- 先驗證 VoiceInk 既有的 `VoiceInk Refine V1` 本機模型。
- 評估 Apple Foundation Models 作為另一個本機文字整理 Provider。
- Private Cloud Compute 暫列後續研究，不作為第一版必要條件。

### 繁體中文

- 中文預設輸出台灣繁體中文。
- 參考 [opass/VoiceTwInk](https://github.com/opass/VoiceTwInk) 的台灣用語提示詞與 OpenCC 保底處理。
- 保留英文、日文、URL、程式碼與專有名詞，不進行破壞性轉換。

### 隱私

- 本機模式不傳送語音或轉錄文字至外部服務。
- 外部 Request 必須讓使用者理解傳送目的地與資料類型。
- 剪貼簿、選取文字、畫面 OCR 與自訂詞彙 Context 必須能獨立停用。
- 日誌不記錄完整錄音、完整文字、剪貼簿內容或 API Key。

## 文件

- [專案方向](docs/PROJECT_DIRECTION.md)
- [實作計畫與 Preflight Checklist](docs/IMPLEMENTATION_PLAN.md)
- [上游建置說明](BUILDING.md)
- [上游貢獻說明](CONTRIBUTING.md)

## 目前建置方式

目前仍沿用 VoiceInk 的建置流程。開始前請先閱讀 [BUILDING.md](BUILDING.md)。

基本需求：

- macOS 14.4 或更新版本。
- Xcode 與 Command Line Tools。
- Git。

```bash
git clone https://github.com/q0821/wa-gong-macos.git
cd wa-gong-macos
make check
make local
```

本機 Build 會輸出名為 `Wa-Gong.app` 的 App。正式 Wa-Gong Release 仍需另外完成 Apple Developer 能力、Sparkle 更新來源與簽署設定確認。

## Git Remote 建議

貢獻者若需要追蹤兩個參考專案，可設定：

```bash
git remote add upstream https://github.com/Beingpax/VoiceInk.git
git remote add voicetwink https://github.com/opass/VoiceTwInk.git
```

定位如下：

- `origin`：Wa-Gong for macOS。
- `upstream`：VoiceInk 的安全修正與主要架構更新來源。
- `voicetwink`：繁體中文、隱私與模擬輸入功能的參考來源。

VoiceTwInk 與 VoiceInk 已有明顯架構差異，本專案不會整批 Cherry-pick VoiceTwInk，而是依最新版 VoiceInk 架構逐項移植需要的能力。

## 發布方式

目前只規劃透過 GitHub 發布，不規劃 Mac App Store、付費授權或訂閱。

每個執行檔 Release 必須：

- 對應明確的 Git Tag 與 Commit SHA。
- 同步提供完全對應的原始碼與必要建置腳本。
- 提供第三方套件、模型與字典資產的授權資訊。
- 不包含 API Key、簽署憑證、Team ID 或開發者本機路徑。

## 授權

本專案是 VoiceInk 的衍生作品，依 [GNU General Public License v3.0](LICENSE) 發布。

發布修改版本時必須保留原作者著作權與授權聲明，並清楚標示修改內容。第三方套件、模型權重與資料檔案可能具有各自的授權條款，請另外查閱對應來源。

## 致謝

- [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)：本專案的主要程式碼與架構基底。
- [opass/VoiceTwInk](https://github.com/opass/VoiceTwInk)：繁體中文、隱私透明度與輸出方式的參考實作。
- VoiceInk 所列的所有核心技術、第三方套件與貢獻者。
