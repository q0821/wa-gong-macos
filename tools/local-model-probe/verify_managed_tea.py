"""Fixed synthetic-only proof of production TEA helper; no microphone or provider calls."""
import argparse, base64, hashlib, json, os, selectors, struct, subprocess, sys, time, uuid, wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--worker', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--parent-exit-child', action='store_true')
parser.add_argument('--parent-exit-only', action='store_true')
args = parser.parse_args()
a = json.loads((HERE/'artifacts.json').read_text())['tea']
model = HERE/'.runtime'/a['filename']
assert not model.is_symlink() and model.stat().st_size == a['bytes']
with model.open('rb') as f:
    assert hashlib.file_digest(f, 'sha256').hexdigest() == a['sha256']

def pcm(name, repeat=1):
    with wave.open(str(HERE/'.runtime'/f'{name}.wav')) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 16000)
        samples = struct.unpack('<' + 'h'*w.getnframes(), w.readframes(w.getnframes()))
    data = struct.pack('<'+'f'*len(samples), *[v/32768 for v in samples]) * repeat
    assert len(data) <= 30*16000*4
    return base64.b64encode(data).decode()

class Worker:
    def __init__(self):
        self.generation = str(uuid.uuid4())
        r, self.life = os.pipe()
        self.p = subprocess.Popen([str(args.worker.resolve())], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=r, start_new_session=True)
        os.close(r)
        self.send('load', modelPath=str(model))
        ready = self.read(30)
        assert ready['kind']=='ready'
        self.load_seconds = ready['seconds']
    def send(self, kind, **values):
        self.id = str(uuid.uuid4())
        body = json.dumps(dict(version=1, kind=kind, id=self.id, generation=self.generation, **values)).encode()
        self.p.stdin.write(struct.pack('>I',len(body))+body); self.p.stdin.flush()
    def read_bytes(self, count, deadline):
        result=b''
        with selectors.DefaultSelector() as s:
            s.register(self.p.stdout, selectors.EVENT_READ)
            while len(result)<count:
                assert s.select(max(0,deadline-time.monotonic())), 'helper deadline'
                part=os.read(self.p.stdout.fileno(),count-len(result))
                assert part,'helper EOF'
                result+=part
        return result
    def read(self, seconds=90):
        deadline=time.monotonic()+seconds
        count=struct.unpack('>I',self.read_bytes(4,deadline))[0]
        assert 0<count<=3_000_000
        result=json.loads(self.read_bytes(count,deadline))
        assert result['version']==1 and uuid.UUID(result['generation'])==uuid.UUID(self.generation) and uuid.UUID(result['id'])==uuid.UUID(self.id)
        return result
    def run(self, name):
        self.send('transcribe', language='en' if name=='english' else 'zh', pcm=pcm(name))
        assert self.read()['kind']=='running' # emitted from actual native callback
        result=self.read()
        assert result['kind']=='result' and result['text'].strip()
        assert not any(0xE000<=ord(c)<=0xF8FF for c in result['text'])
        return result
    def close(self):
        if self.life is not None: os.close(self.life); self.life=None
        try: self.p.wait(timeout=2)
        except subprocess.TimeoutExpired: self.p.kill(); self.p.wait(timeout=5)
        self.p.stdin.close(); self.p.stdout.close()

if args.parent_exit_child:
    w=Worker()
    w.send('transcribe', language='zh', pcm=pcm('zh',repeat=3))
    assert w.read()['kind']=='running'
    print(json.dumps({'helper_pid':w.p.pid,'native_entry_observed':True}),flush=True)
    os._exit(7) # Real parent death; no Python finally/cleanup closes the pipe explicitly.

if args.parent_exit_only:
    child=subprocess.Popen([sys.executable,__file__,'--worker',str(args.worker),'--output',str(args.output),
                            '--parent-exit-child'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    out,_=child.communicate(timeout=40)
    assert child.returncode==7
    evidence=json.loads(out)
    deadline=time.monotonic()+5
    while True:
        try:os.kill(evidence['helper_pid'],0)
        except ProcessLookupError:break
        assert time.monotonic()<deadline,'orphan helper survived parent death'
        time.sleep(0.02)
    evidence.update(real_parent_exit_code=7,helper_absent=True)
    with args.output.open('x') as f:json.dump(evidence,f,indent=2)
    print(json.dumps(evidence,indent=2))
    raise SystemExit(0)

evidence={}
w=Worker()
try:
    first=w.run('zh'); second=w.run('english')
    assert '今天' in first['text'] and '不要刪除' in first['text']
    assert 'API' in second['text'] and '今天' not in second['text']
    evidence['reuse']={'pid':w.p.pid, 'load_events':1, 'fresh_sessions':2,
                       'load_seconds':w.load_seconds, 'recognition_seconds':[first['seconds'],second['seconds']],
                       'fixed_fixture_checks_passed':True}
    w.send('transcribe', language='zh', pcm=pcm('zh',repeat=3))
    assert w.read()['kind']=='running'
    start=time.monotonic();w.p.terminate();w.p.wait(timeout=2)
    evidence['native_cancel']={'entry_observed':True,'reaped':True,'exit':w.p.returncode,
                               'seconds':time.monotonic()-start}
finally:w.close()
w=Worker()
try:
    assert w.run('zh')['kind']=='result'
    evidence['recovery']=True
    w.send('transcribe', language='zh', pcm=pcm('zh',repeat=3))
    assert w.read()['kind']=='running'
    start=time.monotonic(); os.close(w.life); w.life=None
    w.p.wait(timeout=2)
    evidence['lifetime_pipe_eof']={'native_entry_observed':True,'reaped':True,
                                  'seconds':time.monotonic()-start}
finally:w.close()
with args.output.open('x') as f: json.dump(evidence,f,indent=2)
print(json.dumps(evidence,indent=2))
