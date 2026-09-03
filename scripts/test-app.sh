#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJECT_PATH="$ROOT_DIR/VoiceInk.xcodeproj"
SCHEME="VoiceInk"
TEAM_ID="8N33V8XXTX"
BUNDLE_IDENTIFIER="com.jackie-yeh.wagong"
APP_DERIVED_DATA="$ROOT_DIR/.local-build"
BUILT_APP="$APP_DERIVED_DATA/Build/Products/Debug/Wa-Gong.app"
INSTALL_DIRECTORY="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIRECTORY/Wa-Gong Test.app"
RECEIPT_PATH="$APP_DERIVED_DATA/test-build-receipt.plist"
XCODEBUILD_VALIDATION_FLAGS=${XCODEBUILD_VALIDATION_FLAGS:--skipPackagePluginValidation -skipMacroValidation}
LOCAL_CODESIGN_IDENTITY=${LOCAL_CODESIGN_IDENTITY:-}
PRODUCTION_APP=${PRODUCTION_APP:-/Applications/Wa-Gong.app}
PRODUCTION_PROVISIONING_PROFILE=${PRODUCTION_PROVISIONING_PROFILE:-"$PRODUCTION_APP/Contents/embedded.provisionprofile"}

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

source_fingerprint() {
    (
        cd "$ROOT_DIR"
        {
            printf 'HEAD\0'
            git rev-parse HEAD
            printf 'TRACKED\0'
            git diff --binary HEAD -- \
                VoiceInk Shared VoiceInk.xcodeproj LocalBuild.xcconfig Makefile scripts/test-app.sh
            printf 'UNTRACKED\0'
            git ls-files --others --exclude-standard -z -- \
                VoiceInk Shared VoiceInk.xcodeproj LocalBuild.xcconfig Makefile scripts/test-app.sh |
                while IFS= read -r -d '' file; do
                    printf '%s\0' "$file"
                    if [ -L "$file" ]; then
                        readlink "$file"
                    elif [ -f "$file" ]; then
                        shasum -a 256 "$file"
                    fi
                done
        } | shasum -a 256 | awk '{ print $1 }'
    )
}

source_state() {
    if [ -n "$(cd "$ROOT_DIR" && git status --porcelain=v1 --untracked-files=all)" ]; then
        printf 'dirty\n'
    else
        printf 'clean\n'
    fi
}

xcodebuild_with_validation() {
    if [ -n "$XCODEBUILD_VALIDATION_FLAGS" ]; then
        # The override is intentionally a whitespace-separated list of xcodebuild flags.
        # shellcheck disable=SC2086
        /usr/bin/xcodebuild $XCODEBUILD_VALIDATION_FLAGS "$@"
    else
        /usr/bin/xcodebuild "$@"
    fi
}

resolve_signing_identity() {
    if [ -n "$LOCAL_CODESIGN_IDENTITY" ]; then
        security find-identity -v -p codesigning 2>/dev/null |
            awk -v requested="$LOCAL_CODESIGN_IDENTITY" -v team="($TEAM_ID)" '
                index($0, requested) > 0 && index($0, team) > 0 { print $2; exit }
            '
        return
    fi

    security find-identity -v -p codesigning 2>/dev/null |
        awk -v team="($TEAM_ID)" '
            index($0, team) > 0 && index($0, "Apple Development:") > 0 { print $2; found = 1; exit }
            END { if (!found) exit 1 }
        ' ||
        security find-identity -v -p codesigning 2>/dev/null |
            awk -v team="($TEAM_ID)" '
                index($0, team) > 0 && index($0, "Developer ID Application:") > 0 { print $2; exit }
            '
}

running_applications() {
    /usr/bin/osascript -l JavaScript - "$BUNDLE_IDENTIFIER" <<'JXA'
function run(argv) {
    ObjC.import("AppKit")
    const applications = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0])
    const rows = []
    for (let index = 0; index < applications.count; index += 1) {
        const application = applications.objectAtIndex(index)
        const executableURL = application.executableURL
        const executablePath = executableURL ? ObjC.unwrap(executableURL.path) : ""
        rows.push(`${application.processIdentifier}|${executablePath}`)
    }
    return rows.join("\n")
}
JXA
}

stop_running_applications() {
    running_applications |
        while IFS='|' read -r process_identifier executable_path; do
            if [ -n "$process_identifier" ]; then
                printf 'Stopping PID %s at %s\n' "$process_identifier" "$executable_path"
                /bin/kill -TERM "$process_identifier" 2>/dev/null || true
            fi
        done

    attempts=0
    while [ -n "$(running_applications)" ] && [ "$attempts" -lt 20 ]; do
        /bin/sleep 0.25
        attempts=$((attempts + 1))
    done

    if [ -n "$(running_applications)" ]; then
        running_applications |
            while IFS='|' read -r process_identifier executable_path; do
                if [ -n "$process_identifier" ]; then
                    printf 'Force stopping PID %s at %s\n' "$process_identifier" "$executable_path"
                    /bin/kill -KILL "$process_identifier" 2>/dev/null || true
                fi
            done
    fi
}

installed_executable_path() {
    executable_name=$(plist_value CFBundleExecutable "$INSTALLED_APP/Contents/Info.plist")
    printf '%s/Contents/MacOS/%s\n' "$INSTALLED_APP" "$executable_name"
}

running_installed_app() {
    expected_path=$(installed_executable_path)
    running_applications | awk -F'|' -v expected="$expected_path" '$2 == expected { found = 1 } END { exit found ? 0 : 1 }'
}

launch_installed_app() {
    [ -d "$INSTALLED_APP" ] || fail "Test app is not installed at $INSTALLED_APP"
    stop_running_applications
    rm -f "$RECEIPT_PATH"

    printf 'Launching %s\n' "$INSTALLED_APP"
    /usr/bin/open -n "$INSTALLED_APP" --args --test-build-receipt "$RECEIPT_PATH"

    attempts=0
    while [ ! -f "$RECEIPT_PATH" ] && [ "$attempts" -lt 120 ]; do
        /bin/sleep 0.25
        attempts=$((attempts + 1))
    done
    [ -f "$RECEIPT_PATH" ] || fail "The app did not write a launch receipt within 30 seconds"
    running_installed_app || fail "The running app is not the installed test app"
}

verify_status() {
    [ -d "$INSTALLED_APP" ] || {
        printf 'NOT INSTALLED: %s\n' "$INSTALLED_APP"
        exit 2
    }

    current_fingerprint=$(source_fingerprint)
    installed_build_id=$(plist_value WaGongBuildID "$INSTALLED_APP/Contents/Info.plist")
    installed_fingerprint=$(plist_value WaGongSourceFingerprint "$INSTALLED_APP/Contents/Info.plist")

    if [ "$current_fingerprint" != "$installed_fingerprint" ]; then
        printf 'STALE\n'
        printf 'Installed Build ID: %s\n' "$installed_build_id"
        printf 'Installed fingerprint: %s\n' "$installed_fingerprint"
        printf 'Current fingerprint:   %s\n' "$current_fingerprint"
        exit 3
    fi

    if [ ! -f "$RECEIPT_PATH" ]; then
        printf 'NOT RUNNING: no launch receipt\n'
        exit 4
    fi

    receipt_build_id=$(plist_value buildID "$RECEIPT_PATH")
    receipt_fingerprint=$(plist_value sourceFingerprint "$RECEIPT_PATH")
    receipt_bundle_identifier=$(plist_value bundleIdentifier "$RECEIPT_PATH")
    receipt_bundle_path=$(plist_value bundlePath "$RECEIPT_PATH")

    if [ "$installed_build_id" != "$receipt_build_id" ] ||
        [ "$installed_fingerprint" != "$receipt_fingerprint" ] ||
        [ "$receipt_bundle_identifier" != "$BUNDLE_IDENTIFIER" ] ||
        [ "$receipt_bundle_path" != "$INSTALLED_APP" ]; then
        printf 'IDENTITY MISMATCH\n'
        exit 5
    fi

    if ! running_installed_app; then
        if [ -n "$(running_applications)" ]; then
            printf 'WRONG APP\n'
            running_applications
            exit 6
        fi
        printf 'NOT RUNNING\n'
        exit 4
    fi

    printf 'CURRENT\n'
    printf 'Build ID: %s\n' "$installed_build_id"
    printf 'Data mode: production data\n'
    printf 'Installed: %s\n' "$INSTALLED_APP"
    printf 'Running: MATCH\n'
}

install_test_app() {
    initial_fingerprint=$(source_fingerprint)
    initial_revision=$(cd "$ROOT_DIR" && git rev-parse HEAD)
    initial_state=$(source_state)
    build_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    build_stamp=$(date -u '+%Y%m%d-%H%M%S')
    fingerprint_prefix=$(printf '%s' "$initial_fingerprint" | cut -c 1-8 | tr '[:lower:]' '[:upper:]')
    build_id="T-$build_stamp-$fingerprint_prefix"
    signing_identity=$(resolve_signing_identity)

    [ -n "$signing_identity" ] || fail "No signing identity for Team ID $TEAM_ID was found"
    [ -f "$PRODUCTION_PROVISIONING_PROFILE" ] ||
        fail "Production provisioning profile was not found at $PRODUCTION_PROVISIONING_PROFILE"

    printf 'Running VoiceInkTests for %s\n' "$build_id"
    xcodebuild_with_validation \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$APP_DERIVED_DATA" \
        -xcconfig "$ROOT_DIR/LocalBuild.xcconfig" \
        -only-testing:VoiceInkTests \
        CODE_SIGN_IDENTITY="$signing_identity" \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGNING_ALLOWED=YES \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/VoiceInk/VoiceInk.local.entitlements" \
        SWIFT_ACTIVE_COMPILATION_CONDITIONS="\$(inherited) LOCAL_BUILD" \
        WAGONG_BUILD_ID="$build_id" \
        WAGONG_SOURCE_FINGERPRINT="$initial_fingerprint" \
        WAGONG_SOURCE_REVISION="$initial_revision" \
        WAGONG_SOURCE_STATE="$initial_state" \
        WAGONG_BUILD_TIMESTAMP="$build_timestamp" \
        test


    [ -d "$BUILT_APP" ] || fail "Built app was not found at $BUILT_APP"

    final_fingerprint=$(source_fingerprint)
    [ "$initial_fingerprint" = "$final_fingerprint" ] ||
        fail "Source files changed during the test build; run make test-app again"

    built_build_id=$(plist_value WaGongBuildID "$BUILT_APP/Contents/Info.plist")
    built_fingerprint=$(plist_value WaGongSourceFingerprint "$BUILT_APP/Contents/Info.plist")
    [ "$built_build_id" = "$build_id" ] || fail "Built app contains the wrong Build ID"
    [ "$built_fingerprint" = "$initial_fingerprint" ] || fail "Built app contains the wrong source fingerprint"
    /usr/bin/ditto "$PRODUCTION_PROVISIONING_PROFILE" "$BUILT_APP/Contents/embedded.provisionprofile"
    /usr/bin/codesign \
        --force \
        --sign "$signing_identity" \
        --options runtime \
        --timestamp=none \
        --entitlements "$ROOT_DIR/VoiceInk/VoiceInk.test.entitlements" \
        "$BUILT_APP"


    signed_team=$(/usr/bin/codesign -d --verbose=4 "$BUILT_APP" 2>&1 | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')
    [ "$signed_team" = "$TEAM_ID" ] || fail "Built app is signed by Team ID $signed_team instead of $TEAM_ID"
    effective_entitlements=$(/usr/bin/codesign -d --entitlements :- "$BUILT_APP" 2>/dev/null)
    expected_keychain_group="$TEAM_ID.$BUNDLE_IDENTIFIER"
    case "$effective_entitlements" in
        *"<key>keychain-access-groups</key>"*"<string>$expected_keychain_group</string>"*) ;;
        *) fail "Built app cannot access production Keychain group $expected_keychain_group" ;;
    esac

    stop_running_applications
    mkdir -p "$INSTALL_DIRECTORY"
    [ ! -L "$INSTALLED_APP" ] || fail "Refusing to replace symbolic link at $INSTALLED_APP"

    temporary_app="$INSTALL_DIRECTORY/.Wa-Gong Test.app.installing.$$"
    previous_app="$INSTALL_DIRECTORY/.Wa-Gong Test.app.previous.$$"
    rm -rf "$temporary_app" "$previous_app"
    /usr/bin/ditto "$BUILT_APP" "$temporary_app"
    /usr/bin/xattr -cr "$temporary_app"

    if [ -e "$INSTALLED_APP" ]; then
        mv "$INSTALLED_APP" "$previous_app"
    fi
    if ! mv "$temporary_app" "$INSTALLED_APP"; then
        if [ -e "$previous_app" ]; then
            mv "$previous_app" "$INSTALLED_APP"
        fi
        fail "Could not install the test app"
    fi
    rm -rf "$previous_app"

    launch_installed_app
    verify_status
}

case "${1:-install}" in
    install)
        install_test_app
        ;;
    run)
        launch_installed_app
        verify_status
        ;;
    status)
        verify_status
        ;;
    *)
        fail "Usage: $0 [install|run|status]"
        ;;
esac
