"""Register only SHA-256-verified public model layers in this probe's private model store."""
import hashlib,json,os,tarfile
from pathlib import Path
from download import ROOT,verified
runtime=ROOT/'.runtime'
artifacts=json.loads((ROOT/'artifacts.json').read_text())
manifest=json.loads((ROOT/'ollama-model.json').read_text())
archive=runtime/artifacts['ollama']['filename']
assert verified(archive,artifacts['ollama'])
binary_dir=runtime/'ollama-portable'
binary_dir.mkdir(exist_ok=True)
with tarfile.open(archive) as tar:
    for item in tar.getmembers():
        assert not item.name.startswith('/') and '..' not in Path(item.name).parts
        if item.issym() or item.islnk():
            assert not item.linkname.startswith('/') and '..' not in Path(item.linkname).parts
    tar.extractall(binary_dir,filter='data')
model_dir=runtime/'ollama-models'
blobs=model_dir/'blobs';blobs.mkdir(parents=True,exist_ok=True)
for key,artifact in artifacts.items():
    if not key.startswith('ollama-layer-'):continue
    source=runtime/artifact['filename'];target=blobs/artifact['filename']
    if source.exists():
        assert verified(source,artifact)
        assert not target.exists()
        source.rename(target)
    else:assert verified(target,artifact)
# Write exact original registry manifest bytes. Formatting would change its digest.
import urllib.request
u='https://registry.ollama.ai/v2/library/qwen3.5/manifests/9b'
data=urllib.request.urlopen(u,timeout=20).read()
assert hashlib.sha256(data).hexdigest()==manifest['manifest_sha256'],'registry tag changed; do not accept drift'
path=model_dir/'manifests/registry.ollama.ai/library/qwen3.5/9b'
path.parent.mkdir(parents=True,exist_ok=True)
with path.open('xb') as f:f.write(data)
print('Portable Ollama and private verified model store prepared')
