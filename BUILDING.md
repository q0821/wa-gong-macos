# Building Wa-Gong for macOS

## Requirements

- macOS 14.4 or later
- Xcode with Command Line Tools
- Git

## Verified Local Test Build

```bash
git clone https://github.com/q0821/wa-gong-macos.git
cd wa-gong-macos
make test-app
```

`make test-app` is the only supported handoff command for manual testing. It:

- prepares `whisper.xcframework`;
- fingerprints the current commit, tracked changes, and untracked source files;
- runs the complete `VoiceInkTests` target;
- builds with `LocalBuild.xcconfig`, `VoiceInk.local.entitlements`, and the `LOCAL_BUILD` Swift flag;
- requires a stable signing identity from Team ID `8N33V8XXTX`;
- installs the app at `~/Applications/Wa-Gong Test.app`;
- launches that exact app path; and
- verifies that the source tree, installed bundle, and running process report the same Build ID.

The successful receipt looks like this:

```text
CURRENT
Build ID: T-YYYYMMDD-HHMMSS-XXXXXXXX
Data mode: production data
Installed: /Users/<name>/Applications/Wa-Gong Test.app
Running: MATCH
```

測試版刻意沿用正式版的 Bundle ID 與資料位置，以重現既有偏好設定、模型及應用程式資料相關問題。啟動固定的測試版路徑前，腳本會先關閉所有使用相同 Bundle ID 的執行中 App。請勿同時執行正式版與測試版。

測試版的 Keychain 寫入使用獨立本機命名空間。沒有本機覆寫時，會唯讀沿用正式版 Keychain 中的雲端服務 API Key。`make test-app` 會使用 `/Applications/Wa-Gong.app` 內嵌的 provisioning profile 重新簽署測試版，使兩者具備相同的 Keychain access group；找不到該檔案時會停止建置。測試版不包含 iCloud 詞典同步，也無法檢查自動更新。

Check whether the running app still matches the working tree without rebuilding:

```bash
make test-app-status
```

Launch and verify the already-installed test app:

```bash
make run
```

Choose a Team ID `8N33V8XXTX` signing identity explicitly:

```bash
make test-app LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

The Makefile passes `-skipPackagePluginValidation -skipMacroValidation` to `xcodebuild` for the current Xcode 26.6 package graph. Override the flags when using a different Xcode toolchain:

```bash
make test-app XCODEBUILD_VALIDATION_FLAGS=""
```

## Other Commands

- `make check` verifies required tools.
- `make whisper` prepares `whisper.xcframework`.
- `make build` builds the standard Debug configuration without installing it.
- `make test-app` tests, installs, launches, and verifies the fixed local test app.
- `make test-app-status` checks whether the running test app matches the current working tree.
- `make run` launches and verifies the installed test app without rebuilding.
- `make release` creates the signed release package.
- `make release-setup` configures release notarization credentials.
- `make clean` removes `~/VoiceInk-Dependencies`.
- `make help` lists all commands.

`XCODEBUILD_VALIDATION_FLAGS` can be supplied to either `make build` or `make test-app`.

## Build with Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme and use the Debug configuration. Xcode uses the project's normal signing settings. The verified `LOCAL_BUILD` workflow applies only through `make test-app`.

## Troubleshooting

- Run `make check` to verify the required tools.
- Run `make whisper` if the framework is missing.
- If no Team ID `8N33V8XXTX` signing identity is available, install one or pass it with `LOCAL_CODESIGN_IDENTITY`.
- If `make test-app-status` reports `STALE`, run `make test-app` again.
- For additional help, open a [GitHub issue](https://github.com/q0821/wa-gong-macos/issues).
