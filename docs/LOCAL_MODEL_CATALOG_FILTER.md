# 本機模型清單篩選

## 範圍與決策

本次只修改本機語音辨識清單，新增「支援中文」「已安裝」「全部模型」。預設為支援中文，記住篩選偏好。使用模型既有 supportedLanguages 判斷，不從名稱或多語標籤猜測。原因是 Parakeet V3 雖為多語模型，仍不支援中文。

不刪模型、不改下載／辨識流程、不更動目前模型或既有模式，也不修改雲端與自訂清單。文字整理模型獨立呈現，不套用語音語言篩選。否決移除模型支援或更改 registry，因為使用者需要精簡顯示，仍應能從全部模型找回選項。

「已安裝」沿用各引擎的本機安裝狀態；可用的系統 Apple Speech 也包含在內，不讀取雲端 API Key。未知篩選值回到支援中文，避免空白清單。

## 功能專用檢查清單

- [x] 中文模型包含 TEA、支援中文的多語模型；排除純英文與不支援中文的多語模型，實際 registry 契約測試通過。
- [x] 已安裝沿用各引擎狀態，View 觀察 manager 變更，全部模型保留存取入口，已檢查程式碼。
- [x] 篩選只改獨立 UI 偏好，setter 不觸發模型切換、刪除、載入、網路或雲端憑證讀取，已檢查程式碼。
- [x] 繁體中文文案、空清單說明與原生 Picker 標籤已接入，在地化 JSON 驗證通過。
- [x] 回歸測試與完整測試安裝通過，執行中的 Build ID 與來源相符。
- [ ] 實際畫面、偏好重啟保存、下載／刪除後即時更新及 VoiceOver 操作待人工驗收。現有 UI 工具先前回報 `Sky Computer Use native pipe startup failed`，未以編譯結果代替畫面驗證；下次由使用者切換三個篩選並重新開啟 App 驗收。
- 資料庫、時區、外部傳遞、SSRF、第三方套件：不適用，本次無相關變更。

## 驗證紀錄（2026-10-20）

- 修改 `ModelManagementView.swift`、新增 `LocalSpeechModelFilter.swift` 與三項 `LocalSpeechModelFilterTests`，補齊繁體中文文案。語音辨識與文字整理分區，篩選只作用於前者。
- 測試涵蓋 TEA、Whisper Base、Base English、Parakeet V3，已安裝英文模型可在「已安裝」找回；未知偏好值使用中文預設。
- `make test-app` 通過，243 項中 241 項通過、0 失敗、2 項既有 Vocabulary 測試略過。報告 `.local-build/Logs/Test/Test-VoiceInk-2026.10.20_23-32-06-+0800.xcresult`，日誌 `/tmp/wagong-catalog-filter-install-20261020.log`。
- 已安裝並啟動 `~/Applications/Wa-Gong Test.app`，Build ID `T-20261020-153150-124F8A70`。`scripts/test-app.sh status` 回報 `CURRENT`、`Running: MATCH`，strict codesign 通過。正式 App 未替換。

## 使用者回饋與下一步（2026-10-21）

使用者回報清單仍有很多模型，看起來雜亂。現有中文篩選仍會展開多個 Whisper 中文版本，不能算達成清單精簡的體驗驗收。已提出主畫面顯示常用 TEA、其他已安裝收合及另行瀏覽全部模型的方向，但尚未取得改版確認。

重啟時先確認回饋針對「AI 模型 → 本機」或「模式設定」模型下拉，避免再次修改錯誤入口；確認後再規劃具體畫面。本次收尾不追加 UI 實作。
