# 自訂詞彙快速加入與修正實作計畫

日期：2026-10-21。依據：[規格](VOCABULARY_QUICK_LEARNING_SPEC.md)。

## 階段一：規格與共同邊界

**目標**：保存已確認的兩個流程、授權與驗收條件。
**步驟**：先完成 spec，依 preflight 拆出以下實作與驗證工作，建立功能分支。
**狀態**：已完成，已先後寫入 spec 與計畫，再於 `feat/vocabulary-quick-learning` 實作。

## 階段二：選取文字快捷加入

**影響檔案**：新增 `VoiceInk/Services/VocabularyLearningService.swift`（純輸入與修正邊界），新增 `VoiceInk/Services/VocabularySelectionCapture.swift`（有界 AX 讀取），修改 `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift` 與 `DictionarySettingsPanel.swift`。
**步驟**：先建立單詞驗證與測試，再於面板顯示前取得 AX 選取，帶入初始值或明確狀態；既有手動新增和文字替換保留。
**風險**：AX 呼叫會阻塞；使用元素級逾時與 App 身分核對，讀取失敗保留手動輸入。
**測試**：輸入邊界隔離測試與 build；跨 App、secure field、權限與焦點恢復需人工驗收。
**狀態**：原始碼已接入，單詞邊界隔離測試及第一輪編譯通過；跨 App 互動仍待實機驗收。

## 階段三：歷史修正並記住

**影響檔案**：共同 service、新增 `VoiceInk/Views/Dictionary/VocabularyCorrectionSheet.swift`、修改 `VoiceInk/Views/History/TranscriptionDetailView.swift`。
**步驟**：以來源快照建立表單與預覽，畫面 ModelContext 確認沒有待存變更後，重新檢查狀態、詞庫與規則，再於同步 MainActor 動作單次儲存。只有完成記錄有入口，取消及錯誤不回寫。
**風險**：歷史在表單開啟期間改變，以及規則衝突。用輸出快照、既有全規則驗證和 pending changes 防護保守拒絕。否決另一 context 回寫，以免畫面持有物件仍顯示舊資料。
**測試**：記住開關、固定替換、重複與停用詞、容量、循環／衝突、過期與已刪除記錄、原始辨識保留、持久化讀回。
**狀態**：原始碼已接入，第一輪隔離測試通過；實際表單、取消及歷史顯示更新仍待實機驗收。

## 階段四：在地化與驗證交接

**影響檔案**：`VoiceInk/Localizable.xcstrings`、`VoiceInkTests/VocabularyTests.swift`、本計畫與 spec 檢查表。
**步驟**：補繁中文案，執行 `scripts/test-vocabulary.sh`，使用實際 App library 的隔離測試，不啟動 App 宿主。檢查 diff 與範圍，回填已驗與未驗。
**驗收**：編譯與新舊詞彙回歸測試通過；實機、跨 App、無障礙不得以 build 或測試代替。
**狀態**：最後版本未簽署建置與 35 項隔離測試通過，文件已回填；跨 App、無障礙及實際互動仍為實機驗收阻擋。

## 驗證紀錄（2026-10-22）

- 首輪沙盒內建置無法寫入 Swift／Xcode 快取，未取得測試結果；日誌 `/tmp/wagong-quick-learning-validation.log` 及 `/tmp/wagong-vocabulary.SdMjO6/build.log`。
- 透過正式權限機制重跑 `./scripts/test-vocabulary.sh`，`/tmp/wagong-vocabulary.yYXJ2a/build.log` 為 `TEST BUILD SUCCEEDED`，`tests.log` 為 35 項、2 suites 通過。包含 10 項新流程測試與既有回歸。
- 使用 Debug `build-for-testing`、`CODE_SIGNING_ALLOWED=NO`、`-skipPackagePluginValidation -skipMacroValidation`，再連結實際 App debug library 執行隔離 Swift tests。未執行完整 App 宿主，不是簽章、公證或實機品質證據。
- 第一輪後補上持續可見的欄位標籤與動態標題在地化，清除切換模式後過期的選取提示；最後版本重新執行相同腳本，產物 `/tmp/wagong-vocabulary.GZkU9O/`。
- 最後腳本完成且 exit code 為 0，`build.log` 為 `TEST BUILD SUCCEEDED`，`tests.log` 為 `35 tests in 2 suites passed`，沒有失敗或略過測試。
- `git diff --check` 與新增字串的 `zh-Hant` 存在性檢查通過。
- 實機阻擋及重啟條件列於 spec 的「目前交付限制」，未安裝 App，不宣稱使用者目前執行的版本已具備本輪功能。

## 外部動作與交付

實作階段只產生可審閱的本機原始碼與文件。後續使用者明確要求「好 收尾」，依全域規則只提交本次 10 個檔案，推送 `feat/vocabulary-quick-learning`。本次不合併 `main`、不安裝、不發布、不更動 App 版本與簽署設定。

收尾重新檢視 diff 與未追蹤檔案，`git diff --check` 通過；核對最後一輪建置與 35 項隔離測試日誌，沒有新增程式碼修改，未重跑相同測試。跨 App 與 VoiceOver 仍為實機驗收阻擋。全域規則位於獨立 dotfiles repo，不納入 App 提交。
