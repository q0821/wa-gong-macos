# 聲筆 Wa-Gong 建置與本機安裝

## 環境需求

- macOS 14.4 或更新版本。
- 完整 Xcode 與 Command Line Tools。
- Git。
- 本機測試版安裝需有 Team ID `8N33V8XXTX` 的簽署身分，以及既有正式 App 內的 provisioning profile。

## 測試版建置與驗證

執行宿主測試前，先結束正式版及其他共用 Bundle ID 的 App。測試版沿用 `com.jackie-yeh.wagong` 與正式資料位置，不可同時執行。腳本會在安裝與啟動測試版前關閉同 Bundle ID 的 App，但執行測試前仍須先自行確認。

```bash
git clone https://github.com/q0821/wa-gong-macos.git
cd wa-gong-macos
make check
make test-app
```

`make test-app` 是現有的標準測試交付流程：

- 準備及驗證 `whisper.xcframework`。
- 計算目前 commit、已追蹤差異與未追蹤來源的指紋。
- 使用 `LocalBuild.xcconfig`、`VoiceInk.local.entitlements` 與 `LOCAL_BUILD` 執行完整 `VoiceInkTests`。
- 使用既有簽署身分及 `/Applications/Wa-Gong.app` 內嵌的 provisioning profile，檢查正式 Keychain access group。
- 安裝至 `~/Applications/Wa-Gong Test.app`，啟動該路徑並核對來源、bundle 與程序的 Build ID。

成功狀態範例：

```text
CURRENT
Build ID: T-YYYYMMDD-HHMMSS-XXXXXXXX
Data mode: production data
Installed: /Users/<name>/Applications/Wa-Gong Test.app
Running: MATCH
```

測試版沒有個別覆寫金鑰時，唯讀沿用正式 Keychain；測試版新增或修改金鑰仍只寫入本機測試命名空間。找不到簽署身分或正式 provisioning profile 時會停止安裝。測試版不包含 iCloud 詞典同步，也不執行正式自動更新。

```bash
make test-app-status
make run
```

`make run` 只啟動並驗證已安裝的測試版，不重新建置。若 `status` 顯示 `STALE`，須重新建置後再用新版結果驗收。

需要明確選擇既有簽署身分時：

```bash
make test-app LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

現有 Makefile 預設使用 `-skipPackagePluginValidation -skipMacroValidation`。這是建置的驗證前提，通過不代表套件 plugin 或 macro 已另做安全審查；可透過 `XCODEBUILD_VALIDATION_FLAGS` 覆寫。

## 隔離詞彙回歸測試

```bash
./scripts/test-vocabulary.sh
```

此流程先以 `CODE_SIGNING_ALLOWED=NO` 執行 `build-for-testing`，再連結實際 App library 執行詞彙測試及合成舊資料遷移測試，不啟動 App 宿主。結果不能取代簽署、真人錄音、跨 App、VoiceOver 或真實 Provider 驗收。

## 一般 Release 本機安裝

本機正式位置是 `/Applications/Wa-Gong.app`。一般 Release 不使用 `LocalBuild.xcconfig` 或 `LOCAL_BUILD`；不得把 Debug 測試版改名後當作一般 Release。

此流程目前以逐次安裝紀錄管理，尚無通用的正式版安裝 Make target。每次都須先記錄來源、版本、Build ID 與指紋，備份原 App，保留原正式 entitlements／profile，以既有 Developer ID 建置、驗證 helper manifest 與簽章，再於沒有共用 Bundle ID App 執行時替換。備份還原及交換流程必須先在副本實測。

本機 Release 安裝成功，不等於 Apple 公證、Sparkle 產物簽章或公開發布完成。`1.1.0` 的準備與驗證入口見 [發版計畫](docs/RELEASE_1.1.0_PLAN.md)。

## 公開發布

公開版需要對應的版本、build number、來源提交、Tag、DMG、Developer ID、Apple 公證與 Sparkle 簽章。`release-notes/<version>.html` 應與 CHANGELOG 一致。

`make release` 會呼叫 `scripts/release.sh` 進行封裝、公證與 appcast 產生，屬於需另行授權的發布準備動作，本輪不執行。腳本不會自動 commit、push、Tag 或建立 GitHub Release。正式更新 feed 只在資產及公開網址驗證完成後更新，不能先指向尚不存在的下載檔案。

公證認證設定、發布金鑰與簽署材料不可加入 Git。功能仍有實機阻擋時，須在發版計畫逐項列明並取得處置決定。

## 現有 Make 指令

| 指令 | 用途 |
| --- | --- |
| `make check` | 檢查必要工具 |
| `make whisper` | 準備並驗證 Whisper framework |
| `make setup` | 準備建置依賴 |
| `make build` | 一般 Debug 編譯，不安裝 |
| `make test-app` | 完整測試、簽署、安裝及啟動測試版 |
| `make test-app-status` | 核對已安裝測試版與來源 |
| `make run` | 啟動並核對既有測試版 |
| `make release` | 建立公開發布候選產物，需另行授權 |
| `make release-setup` | 設定公證認證，需另行授權 |
| `make help` | 顯示指令 |

`make clean` 會刪除 `~/VoiceInk-Dependencies`，不可當作例行檢查或在未確認影響時執行。

## Xcode 操作

```bash
make setup
open VoiceInk.xcodeproj
```

選擇 `VoiceInk` scheme。Xcode 直接建置使用專案的一般簽署設定；`LOCAL_BUILD` 測試設定由 `make test-app` 提供。遇到失敗先保留日誌並確認來源、快取與簽署前提，不透過清空 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 修復套件錯誤，因為會破壞套件需要的條件編譯。
