# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
WHISPER_CPP_REVISION := 233fe1fc9b48a09e361d3594520838ca266537fe
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
FRAMEWORK_PROVENANCE := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework.provenance
WHISPER_FORCE_REBUILD ?= 0
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_CODESIGN_IDENTITY ?=
XCODEBUILD_VALIDATION_FLAGS ?= -skipPackagePluginValidation -skipMacroValidation

.PHONY: all clean whisper setup build check healthcheck help test-app test-app-status run release release-setup

# Default target
all: check build

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(WHISPER_CPP_DIR)/.git" ]; then \
		git clone --no-checkout https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
	fi
	@if [ -n "$$(git -C $(WHISPER_CPP_DIR) status --porcelain)" ]; then \
		echo "whisper.cpp checkout has local changes; refusing to replace them"; exit 1; \
	fi
	@if [ "$$(git -C $(WHISPER_CPP_DIR) rev-parse HEAD 2>/dev/null || true)" != "$(WHISPER_CPP_REVISION)" ]; then \
		git -C $(WHISPER_CPP_DIR) fetch origin $(WHISPER_CPP_REVISION); \
		git -C $(WHISPER_CPP_DIR) checkout --detach $(WHISPER_CPP_REVISION); \
	fi
	@test "$$(git -C $(WHISPER_CPP_DIR) rev-parse HEAD)" = "$(WHISPER_CPP_REVISION)"
	@if [ "$(WHISPER_FORCE_REBUILD)" = "1" ] && [ -d "$(FRAMEWORK_PATH)" ]; then \
		rm -rf "$(FRAMEWORK_PATH)" "$(FRAMEWORK_PROVENANCE)"; \
	fi
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
		framework_sha="$$(find "$(FRAMEWORK_PATH)" -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$$file"; done | shasum -a 256 | awk '{print $$1}')"; \
		{ printf 'revision=%s\n' "$(WHISPER_CPP_REVISION)"; printf 'sha256=%s\n' "$$framework_sha"; } > "$(FRAMEWORK_PROVENANCE)"; \
	else \
		test -f "$(FRAMEWORK_PROVENANCE)" || { echo "whisper.xcframework has no trusted provenance; rerun with WHISPER_FORCE_REBUILD=1"; exit 1; }; \
		test "$$(sed -n 's/^revision=//p' "$(FRAMEWORK_PROVENANCE)")" = "$(WHISPER_CPP_REVISION)" || { echo "whisper.xcframework revision does not match the pinned source"; exit 1; }; \
		expected_sha="$$(sed -n 's/^sha256=//p' "$(FRAMEWORK_PROVENANCE)")"; \
		actual_sha="$$(find "$(FRAMEWORK_PATH)" -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$$file"; done | shasum -a 256 | awk '{print $$1}')"; \
		test -n "$$expected_sha" && test "$$actual_sha" = "$$expected_sha" || { echo "whisper.xcframework content does not match its provenance record"; exit 1; }; \
		echo "whisper.xcframework provenance verified"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		$(XCODEBUILD_VALIDATION_FLAGS) \
		CODE_SIGN_IDENTITY="" build

# Build, test, install, launch, and verify the fixed local test app.
test-app: check setup
	@XCODEBUILD_VALIDATION_FLAGS="$(XCODEBUILD_VALIDATION_FLAGS)" \
		LOCAL_CODESIGN_IDENTITY="$(LOCAL_CODESIGN_IDENTITY)" \
		./scripts/test-app.sh install

# Report whether the running test app matches the current working tree.
test-app-status: check
	@./scripts/test-app.sh status

# Launch and verify the already-installed test app.
run: check
	@./scripts/test-app.sh run

# Build a signed, notarized DMG and matching local Sparkle Appcast.
release: whisper
	@if [ -n "$(NOTES)" ]; then \
		./scripts/release.sh --notes "$(NOTES)" $(RELEASE_ARGS); \
	else \
		./scripts/release.sh $(RELEASE_ARGS); \
	fi

# Store Apple's notarization credentials securely in Keychain.
release-setup:
	@./scripts/setup-release-notarization.sh

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to the Wa-Gong project"
	@echo "  build              Build the Wa-Gong Xcode project"
	@echo "  test-app           Test, install, launch, and verify ~/Applications/Wa-Gong Test.app"
	@echo "    LOCAL_CODESIGN_IDENTITY=<SHA or name> overrides Team ID 8N33V8XXTX identity detection"
	@echo "    XCODEBUILD_VALIDATION_FLAGS=... overrides package and macro validation flags"
	@echo "  test-app-status    Verify the running test app matches the current working tree"
	@echo "  run                Launch and verify the installed test app"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
