# USB 鍵盤快速鍵未觸發修正

## 問題與證據

2026-09-22，正式版 1.0.1 的 Majestouch Convertible 2 USB 右 Control 綁定可設定但未觸發。已核對偏好設定與目前裝置的 vendor、product、transport 相符；使用者提供的診斷畫面顯示輸入監控已允許、鍵盤監控執行中、已連線鍵盤與裝置綁定各 2 筆。

在未啟動 App 的隔離測試中，使用實際 `ShortcutMonitor` 與來源配對程式，重現兩條失敗路徑：

- USB 無序號裝置使用 modelFamily 辨識，設定端允許直接設定，觸發端卻要求只有藍牙設定流程才會建立的驗證紀錄。
- CG 按鍵事件先於 HID 來源事件到達時，原本只查一次來源，無法觸發已設定的快速鍵。

兩個測試修改前皆為 `downs == 0`，預期為 `1`。第二項是可重現的程式缺陷，尚未透過使用者實機事件時序證實本次也發生此情況。

## 決策與理由

- 觸發端採用設定端既有的連線政策：USB 與內建鍵盤直接比對，藍牙須驗證本次連線，不支援的連線不接受。否決把所有 modelFamily 裝置都要求驗證，因 USB 設定流程沒有此驗證步驟。
- 來源晚到時非同步等待，從 CG 事件收到起最多 75 毫秒，最多保留 32 筆記憶體事件，按收到順序處理。否決阻塞 event tap，避免拖慢系統按鍵處理。
- 當下來源未知時不攔截系統事件，不重播原始按鍵，不降級成全域綁定。因此延遲配對的組合鍵可能同時傳給前景 App，這是保守處理的已知限制。
- 停止、重新設定、event tap 中斷或裝置移除時取消待處理事件，已排程的 action callback 亦核對世代，避免停止後重新觸發。
- 匯出鍵盤狀態與計數，列出設定好的裝置專用快速鍵。不加入原始序號、裝置指紋或一般按鍵歷史。

## 驗證範圍

- [x] USB modelFamily 右 Control 觸發的失敗測試先紅後綠。
- [x] CG 事件入口先收到右 Control，HID 來源晚到時可觸發。
- [x] 按下與放開保持順序。
- [x] 停止、裝置移除、逾時、來源鍵盤不符時不觸發。
- [x] 已排程的 callback 在停止後失效。
- [x] 藍牙連線驗證仍受到保護。
- [x] 診斷快照含四項狀態，失敗與無資料狀態不混淆。
- [x] 完整 App 與測試套件以 `CODE_SIGNING_ALLOWED=NO build-for-testing` 編譯完成；未啟動測試宿主。
- [x] 換上新測試產物，核對執行路徑與 Build ID，退出共用資料位置的正式 App。
- [ ] 以同一把 USB 鍵盤實測。
- [ ] 實測右 Control 開始與停止錄音、轉錄、整理及回填原輸入欄位。
- [x] 在新版實際匯出日誌，核對四項狀態與畫面一致：granted、Running、4 把已連線鍵盤、2 筆裝置綁定。

未勾選項目為實機驗收阻擋，目前已可由使用者以實體 USB 鍵盤驗收。已完成本機測試版簽署與安裝，未進行公證、正式版替換、版本發布或 push。

隔離測試直接編譯正式來源，僅替代與測試無關的 action 顯示名稱與舊資料型別，沒有啟動 App、IOHID 監聽或 Provider。此結果不代表真實硬體、權限或跨 App 流程已通過。

## 本次自動化結果

- `swift test --package-path /private/tmp/wagong-shortcut-regression`：19 項測試通過，共 3 個 suite；參數化測試另外涵蓋 4 種取消情況與 2 種藍牙辨識方式。
- 相同隔離測試以 `--skip-build` 重跑 10 輪，全部通過。
- `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug -derivedDataPath .local-build -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO build-for-testing`：`TEST BUILD SUCCEEDED`。此指令略過套件 plugin 與 macro 驗證，且不簽署，不是正式發布驗證。
- `git diff --check`：通過。

本次隔離 runner 位於暫存目錄；回歸測試本體保留在 `VoiceInkTests/ShortcutMonitorDeviceRoutingTests.swift`、`VoiceInkTests/KeyboardDiagnosticsSnapshotTests.swift`，既有配對測試位於 `VoiceInkTests/KeyboardEventAttributionBrokerTests.swift`。

## 2026-09-22 測試版安裝歷史紀錄

- Build ID：`T-20260922-132425-918A29C6`。
- 安裝位置：`/Users/hd/Applications/Wa-Gong Test.app`。
- `scripts/test-app.sh status`：`CURRENT`、`Running: MATCH`，來源指紋與安裝包、啟動收據一致。
- Team ID：`8N33V8XXTX`；以既有 Developer ID 憑證簽署，未加時間戳或送公證。`codesign --verify --deep --strict` 通過。
- DER 權限已核對 application identifier 與正式版 Keychain 群組相符。
- 舊測試包保留於 `/Users/hd/Applications/.Wa-Gong-Test-backup-20260922-215043.app`，正式包未替換。
- 新版實際匯出檔：`/Users/hd/Downloads/Wa-Gong_Logs_2026-09-22_21-52-44.log`，包含同一 Build ID、四項鍵盤診斷及兩筆裝置專用右 Control 綁定。
- 當前操作模式為「按住說話」，實測需按住右 Control，放開後停止錄音。

安裝使用與既有腳本相同的建置設定、來源指紋及啟動收據流程；未執行腳本內會啟動 App 宿主的完整測試步驟。自動化執行證據仍為上述隔離測試，真實錄音與 Provider 路徑待驗。

## 納入版控驗證（2026-10-21）

- 使用者已授權將先前保留的鍵盤來源配對修正、診斷與測試分批納入 Git。
- 完整候選來源以 `CODE_SIGNING_ALLOWED=NO build-for-testing` 通過，包含鍵盤修改，未啟動 App 宿主。略過 package plugin 與 macro 驗證，沒有簽署或公證。日誌 `/tmp/wagong-repo-final-source-build.log`。
- 連結該候選 App 程式庫的隔離契約測試 57 項、11 suites 通過，包含來源配對、裝置專用路由、75 毫秒邊界與診斷快照，並回歸既有模型契約。日誌 `/tmp/wagong-repo-final-contract-tests.log`。
- 隔離 runner 首次使用 Swift 6，與專案實際 Swift 5 模式不符而無法編譯；已僅修改暫存 runner 為 `swiftLanguageModes: [.v5]` 後通過，保留 `/tmp/wagong-repo-final-contract-swift6-mismatch.log`，沒有修改正式來源或放寬時限。
- 保留正式來源的 75 毫秒等待及 50 毫秒匹配限制；測試時鐘只用於可重現邊界驗證。沒有放寬限制或把未知來源降級為全域快速鍵。
- 本次未重新安裝、錄音、合成系統按鍵或執行真實 Provider。上方同一把 USB 鍵盤、完整錄音與回填的未勾選項目仍是驗收阻擋；歷史安裝紀錄不代表目前提交已交付到執行環境。
