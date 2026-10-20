"""Manually run this probe's private Ollama store; never installs a system service."""
import argparse,hashlib,json,os,socket
from pathlib import Path
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=11435);args=parser.parse_args()
if not 1024<=args.port<=65535:raise ValueError('Use a non-privileged local port')
with socket.socket() as s:s.bind(('127.0.0.1',args.port))
manifest=HERE/'.runtime/ollama-models/manifests/registry.ollama.ai/library/qwen3.5/9b'
expected=json.loads((HERE/'ollama-model.json').read_text())['manifest_sha256']
if hashlib.sha256(manifest.read_bytes()).hexdigest()!=expected:raise ValueError('model manifest changed')
env=os.environ.copy();env.update(OLLAMA_HOST=f'127.0.0.1:{args.port}',
    OLLAMA_MODELS=str(HERE/'.runtime/ollama-models'),OLLAMA_NO_CLOUD='1',OLLAMA_NOHISTORY='1',
    OLLAMA_NOPRUNE='1',OLLAMA_NUM_PARALLEL='1',OLLAMA_MAX_LOADED_MODELS='1',OLLAMA_KEEP_ALIVE='1m')
print(f'Private local Ollama: http://127.0.0.1:{args.port}; stop with Control-C',flush=True)
os.execvpe('sandbox-exec',['sandbox-exec','-f',str(HERE/'loopback-only.sb'),str(HERE/'.runtime/ollama-portable/ollama'),'serve'],env)
