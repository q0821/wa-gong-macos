# Building Wa-Gong for macOS

## Requirements

- macOS 14.4 or later
- Xcode with Command Line Tools
- Git

## Local Build

```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
make local
open ~/Downloads/Wa-Gong.app
```

`make local` prepares `whisper.xcframework` in `~/VoiceInk-Dependencies`, builds in `.local-build`, and copies `Wa-Gong.app` to `~/Downloads`.

It uses `LocalBuild.xcconfig`, `VoiceInk.local.entitlements`, and the `LOCAL_BUILD` Swift flag. Without an override, it uses the only available Apple Development identity or falls back to ad-hoc signing when none or multiple are found.

The Makefile passes `-skipPackagePluginValidation -skipMacroValidation` to `xcodebuild`. This is required for the current Xcode 26.6 package graph, which otherwise stops at package plug-in or macro validation before compiling. Override the flags when using a different Xcode toolchain:

```bash
make local XCODEBUILD_VALIDATION_FLAGS=""
```

Choose an identity explicitly:

```bash
make local LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

Force ad-hoc signing:

```bash
make local LOCAL_CODESIGN_IDENTITY=-
```

Local builds do not include iCloud dictionary sync or automatic updates. Ad-hoc builds may require macOS permissions again after rebuilding. Normal project Debug and Release settings are unchanged.

## Other Commands

- `make check` — verify required tools
- `make whisper` — prepare `whisper.xcframework`
- `make build` — build the standard Debug configuration
- `make dev` — build and launch the app
- `make run` launches `~/Downloads/Wa-Gong.app`, or the first app found in DerivedData
- `make release` — create the signed release package
- `make release-setup` — configure release notarization credentials
- `make clean` — remove `~/VoiceInk-Dependencies`
- `make help` — list all commands

`XCODEBUILD_VALIDATION_FLAGS` can be supplied to either `make build` or `make local` to override the default Xcode package validation flags.

## Build with Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme and use the Debug configuration. Xcode uses the project’s normal signing settings; `LOCAL_BUILD` applies only through `make local`.

## Troubleshooting

- Run `make check` to verify the required tools.
- Run `make whisper` if the framework is missing.
- If several Apple Development identities exist, set `LOCAL_CODESIGN_IDENTITY` explicitly.
- If Xcode reports an XCFramework path from an old checkout, run `make local` to recreate the ignored `.local-build` directory.
- For additional help, open a [GitHub issue](https://github.com/Beingpax/VoiceInk/issues).
