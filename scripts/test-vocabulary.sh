#!/bin/bash
# Isolated tests against the actual compiled app library; never launches the app.
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TASK_OUTPUT=$(mktemp -d /tmp/wagong-vocabulary.XXXXXX)
TASK_BUILD="$TASK_ROOT/.local-build"
printf 'Vocabulary validation artifacts: %s\n' "$TASK_OUTPUT"
cd "$TASK_ROOT"
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
    -derivedDataPath "$TASK_BUILD" -disableAutomaticPackageResolution -skipPackageUpdates \
    -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
    WAGONG_BUILD_ID="VOCAB-$(date -u '+%Y%m%dT%H%M%SZ')" \
    build-for-testing > "$TASK_OUTPUT/build.log" 2>&1
python3 - "$TASK_ROOT" "$TASK_OUTPUT" <<'PY'
import json, pathlib, shlex, sys, shutil
root, out = map(pathlib.Path, sys.argv[1:])
build = root / '.local-build/Build/Products/Debug'
cache = root / '.local-build/vocabulary-test-import-flags.json'
lines = (out / 'build.log').read_text().splitlines()
command = next((line for line in lines if 'swiftc -module-name VoiceInkTests ' in line), None)
if command:
    args = shlex.split(command)
    flags = []
    index = 0
    while index < len(args):
        if args[index] in ('-I', '-F', '-Xcc'):
            flags.extend(args[index:index + 2]); index += 2
        else:
            index += 1
    cache.write_text(json.dumps(flags))
elif cache.exists():
    flags = json.loads(cache.read_text())
else:
    raise SystemExit('No compiler import flags available. Build the VoiceInkTests target before running the isolated harness.')
package = out / 'harness'
tests = package / 'Tests/VocabularyHarnessTests'
tests.mkdir(parents=True)
shutil.copyfile(root / 'VoiceInkTests/VocabularyTests.swift', tests / 'VocabularyTests.swift')
# Reuse the existing self-contained vocabulary regressions, without unrelated App tests.
source = (root / 'VoiceInkTests/VoiceInkTests.swift').read_text()
methods = []
for name in ['localWhisperContextIncludesCustomVocabularyWithoutReplacingPrompt',
             'wordReplacementPrefersLongerTermsAndRespectsWordBoundaries',
             'geminiTranscriptionRequestPreservesSpokenLanguageAndMinimizesThinking']:
    position = source.index('func ' + name + '(')
    start = source.rfind('    @Test', 0, position)
    end = source.find('    @Test', position)
    if start < 0 or end < 0:
        raise SystemExit('Existing regression method could not be isolated: ' + name)
    methods.append(source[start:end])
(tests / 'ExistingVocabularyRegressionTests.swift').write_text(
    'import Foundation\nimport SwiftData\nimport Testing\n@testable import VoiceInk\n'
    '@Suite(.serialized) struct ExistingVocabularyRegressionTests {\n' + ''.join(methods) + '}\n')

link = [str(build / 'Wa-Gong.app/Contents/MacOS/Wa-Gong.debug.dylib')]
for path in ['MacOS', 'Frameworks']:
    link += ['-Xlinker', '-rpath', '-Xlinker', str(build / 'Wa-Gong.app/Contents' / path)]
(package / 'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\n'
    'let package = Package(name: "VocabularyHarness", platforms: [.macOS("14.4")], targets: ['
    '.testTarget(name: "VocabularyHarnessTests", swiftSettings: [.unsafeFlags(' + json.dumps(flags) + ')], '
    'linkerSettings: [.unsafeFlags(' + json.dumps(link) + ')])])\n')
PY
xcrun swiftc -parse-as-library -module-name VoiceInk -target arm64-apple-macos14.4 \
    -module-cache-path "$TASK_OUTPUT/module-cache" \
    scripts/fixtures/vocabulary-legacy.swift -o "$TASK_OUTPUT/seed" > "$TASK_OUTPUT/migration-build.log" 2>&1
"$TASK_OUTPUT/seed" "$TASK_OUTPUT/legacy.store" > "$TASK_OUTPUT/migration-seed.log" 2>&1
WAGONG_ISOLATED_VOCABULARY_TESTS=1 WAGONG_VOCABULARY_LEGACY_STORE="$TASK_OUTPUT/legacy.store" \
    swift test --package-path "$TASK_OUTPUT/harness" > "$TASK_OUTPUT/tests.log" 2>&1
printf 'Build, synthetic migration, and isolated vocabulary tests passed.\n'
tail -3 "$TASK_OUTPUT/tests.log"
