# 錄音就緒與容量保留計畫

## 範圍

修正錄音就緒提示，新增音檔天數與容量雙重清理，以及明確的文字整理重試提示。保留轉錄文字，不修改資料庫結構、不清除專案外或手動匯入的原始音檔、不變更 API 金鑰、不自動發布。

## 階段 1：錄音就緒

- 等待成功寫入且非全零的音訊持續至少 200 毫秒，再切換為「錄音中」。等待期間的音訊也完整保留。
- 超過 10 秒未就緒時停止錄音並顯示中文提示。取消錄音不能晚到後重新顯示就緒。
- 只記錄裝置與啟動耗時，不記錄語音內容。硬體可能持續送入非零雜訊，軟體就緒檢查仍需 iPhone 實測驗收。
- 狀態：實作與自動測試完成，iPhone 硬體驗收待執行。

## 階段 2：自動清理

- 預設啟用，保留 3 天與 300 MB（十進位），任一限制超過即刪除最舊錄音。
- 保留使用者已明確選擇的設定；沒有舊設定者使用新預設。
- 設定可同時調整天數與容量，顯示實際錄音目錄用量；正在使用的檔案可暫時超限。
- 只刪除 App 錄音目錄內、已結束處理的歷史音檔；未關聯檔案只計入用量，不擅自刪除。
- 啟動、定期檢查及完成轉錄時檢查，手動清理與自動清理使用共同規則。刪除前再次檢查狀態與路徑。
- 狀態：實作與自動測試完成。

## 階段 3：文字整理與驗證

- 預設逾時改為 20 秒，預設停用逾時重送；保留已明確設定的值。
- 使用者啟用逾時重試時，明確顯示中文原因與次數。暫時性網路／伺服器錯誤由既有 LLMkit 單層處理，移除 App 外層對這類錯誤的重複重試。
- 測試就緒判斷、逾時、雙限制邊界、處理中保護、路徑限制、失敗處理與文字保留。只用暫存檔案測試清理。
- 狀態：實作完成，最後一輪完整測試通過。

## 實作前檢查清單

- [x] 清理共同入口確實執行天數與容量規則，邊界與先後順序有測試。
- [x] 使用中的檔案與待處理紀錄受保護，手動確認後仍重新檢查。
- [x] 檔案刪除限制在錄音根目錄，不追隨符號連結；刪除失敗保留關聯並回報。
- [x] 時間以固定時刻測試，保留天數定義為經過的 24 小時。
- [x] 錄音就緒只依實際寫入音訊判斷，等待可取消，逾時可恢復。
- [x] 設定與執行預設一致，明確舊設定不被覆寫。
- [x] 新介面與錯誤訊息具繁體中文翻譯，更新 CHANGELOG 與保留說明。
- [x] 實際編譯與相關測試通過；區分自動測試與尚待 iPhone 實測。

資料庫 migration、寄信、權限模型、SSRF 與新增第三方套件皆不適用。

## 驗證紀錄

- 測試範圍：`AudioCaptureReadinessTests`（3 項）、`AudioCleanupManagerTests`（5 項）、`EnhancementRequestRetryTests`（4 項）。
- 完整 `VoiceInkTests` 已於 2026-09-05 通過，共 136 項；補上匯入來源保護與清理通知後的最後一輪也全部通過。新增測試使用暫存目錄與記憶體資料庫，測試程序禁止自動清理正式資料。
- 最後一輪指令：`xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug -derivedDataPath .local-build -xcconfig LocalBuild.xcconfig -skipPackagePluginValidation -skipMacroValidation -destination 'platform=macOS,arch=arm64' -only-testing:VoiceInkTests CODE_SIGNING_ALLOWED=NO test`。
- 最後一輪結果：`TEST SUCCEEDED`，日誌位於 `/tmp/wagong-audio-final-tests.log`，本輪未產生編譯警告。語系 JSON 格式與 `git diff --check` 均通過。
- 錄音就緒測試先因尚未實作 `AudioCaptureReadiness` 編譯失敗，再加入實作通過。
- 已於 2026-09-05 編譯 Release 並覆蓋安裝 `/Applications/Wa-Gong.app`，驗證執行路徑與匯出產物 SHA-256 一致。內部 build 為 `2026090501`，架構為 arm64，Developer ID Team ID 為 `8N33V8XXTX`，Keychain 與 iCloud 權限與舊版一致。
- 首次啟動實際自動清除 71 個過期音檔，錯誤數為 0；錄音目錄剩約 2.79 MB。93 筆歷史紀錄與原始／整理文字皆保留。
- 舊 App、更新前錄音與歷史資料庫備份位於 `/tmp/wagong-install-20260905.XrpaJ1`。
- 本次未完成 Apple 公證：鑰匙圈中無法取得 `Wa-Gong-Notarization` 或 `Wa-Gong Notarization` 憑證設定。Developer ID 簽章驗證與實際啟動成功，未變更系統安全性設定。
- iPhone 漏收第一句仍待使用者實機驗收，未宣稱已確認解決。
