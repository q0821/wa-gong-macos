<div align="center">
  <h1>聲筆 Wa-Gong for macOS</h1>
  <p>雲端優先、繁體中文優先的 macOS 語音輸入工具</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
  [![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
  [![Status](https://img.shields.io/badge/status-1.0.0%20released-brightgreen.svg)](https://github.com/q0821/wa-gong-macos/releases/tag/v1.0.0)
</div>

## 專案狀態

首個公開版本 `1.0.0` 已發布。OpenAI 語音轉錄、Gemini 文字整理、全域快速鍵與文字貼上已形成可用的核心流程。正式 DMG 已完成 Developer ID 簽署、Sparkle 更新簽章與 Apple 公證，可由 [GitHub Releases](https://github.com/q0821/wa-gong-macos/releases/latest) 下載。

現階段程式碼以 [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) 最新版為基底，App 顯示名稱、Bundle Identifier、本機產物名稱、主要執行期識別字與繁體中文資源已完成 Wa-Gong 品牌遷移。Xcode target、Swift module、部分上游元件名稱與必要的相容性識別字仍予以保留，方便持續同步上游程式碼與搬遷既有設定。

本專案是獨立社群 Fork，不是 VoiceInk 官方版本，也不由 VoiceInk 原作者提供支援。

## 專案目標

聲筆 Wa-Gong for macOS 提供一條快速、可稽核，並可自由選擇雲端或本機 Provider 的語音輸入流程：

```text
全域快速鍵
→ 錄音
→ 雲端或本機語音轉錄
→ 選用的文字整理
→ 台灣繁體中文輸出
→ 插入目前使用中的 App
```

開發優先順序：

1. 降低停止錄音後的等待時間。

2. 穩定輸出台灣繁體中文與中英混合內容。

3. 讓使用者清楚知道哪些資料留在本機，哪些資料會送往外部服務。

4. 保留可替換的本機與雲端 Provider，不綁定單一模型。

5. 透過 GitHub 提供可重現、可稽核的原始碼與 Release。

## 目前技術方向

### 語音轉錄

- 預設優先使用雲端語音轉錄 API，不要求下載本機模型。
- 支援 OpenAI `gpt-4o-mini-transcribe`、`gpt-4o-transcribe`、`gpt-transcribe`、說話者分離模型與 `whisper-1`。
- 保留 Apple `SpeechAnalyzer` 與 `SpeechTranscriber` 作為系統原生選項。
- 保留上游既有的 Whisper、FluidAudio 與其他雲端 Provider 作為選用方案。
- 量測停止錄音、Partial Transcript、Final Transcript 與文字插入時間。

### 文字整理

- 已驗證 Gemini 可用於轉錄後的文字整理與台灣繁體中文調整。
- 支援 OpenAI、Claude、Gemini 與其他可設定的雲端 AI Provider。
- 保留 `Wa-Gong Refine`、Ollama 與 Local CLI 作為本機文字整理選項。

### 繁體中文

- 中文預設輸出台灣繁體中文。
- 參考 [opass/VoiceTwInk](https://github.com/opass/VoiceTwInk) 的台灣用語提示詞與 OpenCC 保底處理。
- 保留英文、日文、URL、程式碼與專有名詞，不進行破壞性轉換。

### 快速鍵與鍵盤裝置

- 既有快速鍵預設適用於所有鍵盤，升級後不需要重新設定。
- 同一個動作可另外加入內建鍵盤、USB 鍵盤或藍牙鍵盤專用快速鍵，適合不同鍵盤配置。
- 裝置專用快速鍵需要 macOS「輸入監控」權限；只使用所有鍵盤快速鍵時不會主動要求此權限。
- 鍵盤事件只在本機記憶體中即時比對，不保存一般按鍵內容、按鍵歷史或原始裝置序號，也不傳送至外部服務。
- 建立或修改藍牙鍵盤專用快速鍵前，必須在選定鍵盤按下一個字母鍵，確認本次連線的事件來源；重新連線後若要修改設定，需重新驗證。
- 藍牙鍵盤的休眠、喚醒與重新連線仍需依實際硬體完成相容性測試。

### 隱私

- 使用雲端轉錄模型時，錄音會送至使用者選定的語音轉錄服務。
- 使用本機轉錄模型時，錄音不會送至雲端轉錄服務；若模式另行啟用雲端 AI 潤飾，轉錄文字仍會送至所選 AI Provider。
- 外部 Request 必須讓使用者理解傳送目的地與資料類型。
- 剪貼簿內容不會傳送給 AI Provider；選取文字與畫面 OCR 只會在對應模式明確啟用時使用。
- 日誌不記錄完整錄音、完整文字、剪貼簿內容或 API Key。

## 文件

- [專案方向](docs/PROJECT_DIRECTION.md)
- [實作計畫與 Preflight Checklist](docs/IMPLEMENTATION_PLAN.md)
- [變更紀錄](CHANGELOG.md)
- [建置說明](BUILDING.md)
- [貢獻說明](CONTRIBUTING.md)

## 目前建置方式

目前沿用上游的建置流程。開始前請先閱讀 [BUILDING.md](BUILDING.md)。

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

本機 Build 會輸出名為 `Wa-Gong.app` 的 App。正式 Wa-Gong Release 需另外設定 Apple Developer 簽署、Apple 公證與 Sparkle 更新金鑰，詳情請參考 [建置說明](BUILDING.md)。

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
- 不包含 API Key、私密簽署金鑰、憑證匯出檔或開發者本機路徑。

## 授權

本專案是 VoiceInk 的衍生作品，依 [GNU General Public License v3.0](LICENSE) 發布。

發布修改版本時必須保留原作者著作權與授權聲明，並清楚標示修改內容。第三方套件、模型權重與資料檔案可能具有各自的授權條款，請另外查閱對應來源。

## 致謝

- [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)：本專案的主要程式碼與架構基底。
- [opass/VoiceTwInk](https://github.com/opass/VoiceTwInk)：繁體中文、隱私透明度與輸出方式的參考實作。
- VoiceInk 所列的所有核心技術、第三方套件與貢獻者。
