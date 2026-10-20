"""Explicit, bounded download of pinned public probe artifacts. No automatic retry."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent

def verified(path, artifact):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != artifact['bytes']:
        return False
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest() == artifact['sha256']

def download(name):
    artifact = json.loads((ROOT / 'artifacts.json').read_text())[name]
    runtime = ROOT / '.runtime'
    runtime.mkdir(exist_ok=True)
    target = runtime / artifact['filename']
    partial = target.with_suffix(target.suffix + '.partial')
    if target.exists():
        if not verified(target, artifact):
            raise ValueError('existing artifact failed integrity check')
        print(name, 'existing artifact verified', flush=True)
        return
    if partial.exists() or partial.is_symlink():
        raise ValueError('partial artifact exists; inspect explicitly before resuming')
    if shutil.disk_usage(runtime).free < artifact['bytes'] + 3 * 1024**3:
        raise ValueError('insufficient disk space with 3 GiB reserve')
    total = 0
    last = time.monotonic()
    h = hashlib.sha256()
    with urllib.request.urlopen(artifact['url'], timeout=45) as response, partial.open('xb') as f:
        if response.status != 200:
            raise ValueError('unexpected HTTP status')
        while chunk := response.read(4 * 1024 * 1024):
            total += len(chunk)
            if total > artifact['bytes']:
                raise ValueError('download exceeded pinned size')
            f.write(chunk)
            h.update(chunk)
            if time.monotonic() - last >= 20:
                print(name, total, '/', artifact['bytes'], flush=True)
                last = time.monotonic()
            if shutil.disk_usage(runtime).free < 3 * 1024**3:
                raise ValueError('disk reserve reached')
    if total != artifact['bytes'] or h.hexdigest() != artifact['sha256']:
        raise ValueError('artifact failed integrity check')
    partial.rename(target)
    print(name, 'downloaded and SHA-256 verified', total, flush=True)

if __name__ == '__main__':
    try:
        for name in sys.argv[1:]:
            download(name)
    except Exception as error:
        print('Download stopped:', type(error).__name__, flush=True)
        sys.exit(1)
