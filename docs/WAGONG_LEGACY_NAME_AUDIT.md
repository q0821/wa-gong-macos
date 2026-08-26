# Wa-Gong 舊名稱盤查

盤查日期：2026-08-26

## 結論

App 的使用者介面、執行期日誌識別字、目前使用的 Keychain 服務、剪貼簿工作階段識別字、外部連結與本機環境變數，已改用 Wa-Gong 名稱。

目前仍看得到的 `VoiceInk`，主要分成兩類：

1. 為了讓既有使用者資料與自訂指令繼續可用而保留的相容性識別字。
2. Xcode 專案、Swift module、XPC target、檔案路徑，以及第三方模型與依賴的結構性或來源名稱。這些名稱若要改動，必須同時處理編譯 target、檔案路徑、XPC 連線與資料遷移，不適合和本輪可見問題混在一起改。

## 已完成的清理

### 執行期識別字

- `Logger` subsystem 已統一為 `com.jackie-yeh.wagong`。
- 核心 Swift 型別、Refine XPC 型別、CSV 匯出服務、按鈕元件與 App 型別的執行期識別字，已改為 Wa-Gong 名稱。
- Engine 與 Refine 相關的 Logger category 已改為 Wa-Gong 名稱。
- 新的 Keychain 服務使用 `com.jackie-yeh.wagong`，本機建置使用 `com.jackie-yeh.wagong.Local`。
- 新的剪貼簿工作階段型別使用 `com.jackie-yeh.wagong.PasteSession`。
- 主視窗與歷史記錄視窗使用 Wa-Gong 的 frame autosave 名稱。
- 裝置識別字使用 `WaGongDeviceIdentifier`。
- 文字整理與自訂指令的主要環境變數改為 `WAGONG_TRANSCRIPT`、`WAGONG_SYSTEM_PROMPT`、`WAGONG_USER_PROMPT` 與 `WAGONG_FULL_PROMPT`。

### 外部連結與遠端內容

- GitHub Star 功能改為 `q0821/wa-gong-macos`。
- 公告來源改為 Wa-Gong Repository 的 raw JSON，公告檔目前為空陣列，不會顯示上游 VoiceInk 舊公告。
- 自訂模型、模式與推薦模型的說明連結改為 Wa-Gong Repository。
- 支援信箱改為 `jackie@tellustek.com`，常見問題連結改為 Wa-Gong GitHub Issues。
- Sparkle 舊的上游 feed URL 與公開金鑰已移除，更新功能在 Wa-Gong 建立自己的 feed 前保持停用。
- `appcast.xml` 已移除舊版上游項目，避免誤下載 VoiceInk DMG。

## 保留的相容性識別字

以下項目不是遺漏，而是為了避免升級後遺失資料或破壞使用者設定：

- `com.prakashjoshipax.VoiceInk`：只作為舊 Application Support 與 UserDefaults 的搬遷來源。
- 舊 Keychain service：已停止讀取、刪除與存在性檢查，避免 macOS 反覆要求存取舊項目；目前只使用 Wa-Gong service。
- `VoiceInkChecksForUpdatesOnLaunch` 與 `VoiceInkInteractedUpdateVersions`：只作為更新設定的讀取來源，新的資料寫入 Wa-Gong key。
- `VoiceInkDeviceIdentifier`：只作為裝置識別字的一次性讀取來源。
- `VOICEINK_TRANSCRIPT`、`VOICEINK_SYSTEM_PROMPT`、`VOICEINK_USER_PROMPT` 與 `VOICEINK_FULL_PROMPT`：仍會隨自訂指令提供，讓使用者既有的 shell 指令不會失效；介面與範本已改用 `WAGONG_*`。
- `VoiceInkRefine` 模型資料夾：啟動時會搬遷至 `WaGongRefine`，不會重新下載已存在的模型。

## 保留的結構性或來源名稱

這些名稱不是使用者介面或執行期品牌遺留，而是專案結構、第三方來源或相容層：

- `VoiceInk.xcodeproj`、`VoiceInk` scheme、`VoiceInk` target 與 `VoiceInk` Swift module。
- `VoiceInk*.swift` 的實體檔名與 Xcode project reference。程式內的主要型別已改名，但檔案搬遷會擴大 project diff。
- `VoiceInkRefineXPC` XPC target、實體檔名與 module 名稱。XPC client 與 service 的 Swift 型別已改名，但 target/module 改名仍需另行驗證安裝產物與連線。
- `beingpax/VoiceInk-Refine-V1`：這是實際模型的上游 Repository ID，不能改成不存在的 Wa-Gong Repository ID。
- `Beingpax` 的 Swift Package URL 與文件中的上游引用：這些是第三方依賴與來源著作權資訊，不是 App 的執行期品牌。
- Makefile 使用的 `~/VoiceInk-Dependencies`：這是既有 whisper.cpp 依賴路徑。直接改成新路徑會造成重新下載與重建大型 XCFramework，因此先保留。

若下一階段要讓 Repository 內部也完全不出現 `VoiceInk`，應另開一次結構性改名工作，包含檔案搬遷、Xcode project reference、Swift module、XPC、既有資料遷移與完整建置驗證。
