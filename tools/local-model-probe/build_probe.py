"""Build against the exact cached binding/binary used by the App; never resolves packages."""
from pathlib import Path
import subprocess
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
framework=ROOT/'.local-build/SourcePackages/artifacts/transcribe-cpp-swift/CTranscribe/TranscribeCpp.xcframework/macos-arm64_x86_64'
sources=sorted((ROOT/'.local-build/SourcePackages/checkouts/Transcribe-cpp-swift/Sources/TranscribeCpp').glob('*.swift'))
assert sources and (framework/'CTranscribe.framework').exists()
cmd=['swiftc','-parse-as-library','-O','-module-cache-path','/tmp/wagong-gguf-module-cache','-F',str(framework),'-Xlinker','-rpath','-Xlinker',str(framework),'-framework','CTranscribe','-framework','Accelerate','-framework','Metal','-framework','MetalKit','-lc++','-lz']
worker = '--worker' in sys.argv
name = 'GGUFWorker' if worker else 'GGUFProbe'
extra = [ROOT/'VoiceInk/Transcription/TranscribeCpp/TEATranscriptDecoder.swift'] if worker else []
cmd += [str(p) for p in sources+extra]+[str(HERE/(name+'.swift')),'-o',str(HERE/'.runtime'/name)]
status=subprocess.call(cmd)
if status==0:
    inputs=sources+extra+[HERE/(name+'.swift')]
    digests={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    binary=HERE/'.runtime'/name
    (HERE/'.runtime'/('worker-build.json' if worker else 'probe-build.json')).write_text(json.dumps({'inputs':digests,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()},indent=2))
raise SystemExit(status)
