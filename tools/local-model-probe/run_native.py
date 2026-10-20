"""Bounded execution of pinned models against synthetic fixtures only."""
import argparse
import json
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import time
from download import ROOT, verified

RUNTIME=ROOT/'.runtime'

def execute(name, label):
    build=json.loads((RUNTIME/'probe-build.json').read_text())
    for relative,digest in build['inputs'].items():
        assert hashlib.sha256((ROOT.parents[1]/relative).read_bytes()).hexdigest()==digest,'stale probe source'
    assert hashlib.sha256((RUNTIME/'GGUFProbe').read_bytes()).hexdigest()==build['binary_sha256'],'stale probe binary'
    artifact=json.loads((ROOT/'artifacts.json').read_text())[name]
    model=RUNTIME/artifact['filename']
    if not verified(model,artifact):
        raise ValueError('model integrity check failed')
    fixtures=json.loads((RUNTIME/'fixtures.json').read_text())
    for fixture in fixtures:
        pcm=Path(fixture['pcm']).resolve()
        assert pcm.parent == RUNTIME.resolve() and fixture['synthetic'] is True
        assert pcm.stat().st_size > 16000*4
    output=RUNTIME/(name+'-'+label+'-native.jsonl')
    errors=RUNTIME/(name+'-'+label+'-native.stderr.log')
    if output.exists() or errors.exists():
        raise ValueError('result already exists; preserve evidence and choose a new run explicitly')
    started=time.monotonic()
    with output.open('x') as out,errors.open('x') as err:
        process=subprocess.Popen([str(RUNTIME/'GGUFProbe'),str(model),str(RUNTIME/'fixtures.json')],stdout=out,stderr=err,start_new_session=True)
        peak=0
        timeout=False
        try:
            while process.poll() is None:
                if time.monotonic()-started>180:
                    timeout=True
                    break
                usage=subprocess.run(['ps','-o','rss=','-p',str(process.pid)],capture_output=True,text=True)
                if usage.returncode==0 and usage.stdout.strip():
                    peak=max(peak,int(usage.stdout.strip())*1024)
                time.sleep(0.5)
        finally:
            if process.poll() is None:
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
        status=process.wait()
    records=[]
    for line in output.read_text().splitlines():
        if line.startswith('{'):
            records.append(json.loads(line))
    result=dict(model=name,exit_code=status,timeout=timeout,sampled_rss_peak_bytes=peak,elapsed=time.monotonic()-started,events=records)
    (RUNTIME/(name+'-'+label+'-native-summary.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(name,'exit',status,'sampled RSS peak',peak,'events',len(records),flush=True)
    for event in records:
        print({k:v for k,v in event.items() if k!='text'},flush=True)
    if status!=0:raise RuntimeError('native probe failed; inspect retained evidence')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('models',nargs='+',choices=['qwen','tea'])
    parser.add_argument('--label', default='first', choices=['first','bounded','resident','final'])
    args=parser.parse_args()
    for name in args.models:execute(name,args.label)
