"""Run actual App client with local-only Ollama and no App/service initialization."""
import json,os,signal,socket,subprocess,time,urllib.request
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main(probe, extra_env=None, arguments=(), label="fix"):
    result={'server_stopped':False}
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def api(path,body=None):
        request=urllib.request.Request('http://127.0.0.1:11435'+path,
            data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        with opener.open(request,timeout=45) as response:return json.load(response)
    with socket.socket() as s:s.bind(('127.0.0.1',11435))
    env=os.environ.copy();env.update(OLLAMA_HOST='127.0.0.1:11435',OLLAMA_MODELS=str(HERE/'.runtime/ollama-models'),
        OLLAMA_NO_CLOUD='1',OLLAMA_NOPRUNE='1',OLLAMA_DEBUG='0',OLLAMA_NOHISTORY='1',
        OLLAMA_NUM_PARALLEL='1',OLLAMA_MAX_LOADED_MODELS='1',OLLAMA_KEEP_ALIVE='1m',
        WAGONG_LOCAL_ENDPOINT='http://127.0.0.1:11435',LLVM_PROFILE_FILE=str(HERE/'.runtime/app-ollama-fix-%p.profraw'))
    if extra_env:env.update(extra_env)
    process=None
    try:
        with (HERE/'.runtime'/('app-ollama-'+label+'-server.log')).open('x') as log:
            process=subprocess.Popen(['sandbox-exec','-f',str(HERE/'loopback-only.sb'),
                str(HERE/'.runtime/ollama-portable/ollama'),'serve'],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            result['server_pid']=process.pid
            for _ in range(100):
                if process.poll() is not None:raise RuntimeError('server exited')
                try:result['version']=api('/api/version');break
                except OSError:time.sleep(.2)
            else:raise TimeoutError('server not ready')
            tags=api('/api/tags');tag=next(x for x in tags['models'] if x['name']=='qwen3.5:9b')
            assert tag['digest']==json.loads((HERE/'ollama-model.json').read_text())['manifest_sha256']
            result['app_probe_exit']=subprocess.run([probe,*arguments],env=env,timeout=300).returncode
            api('/api/generate',{'model':'qwen3.5:9b','keep_alive':0})
            for _ in range(40):
                if not api('/api/ps')['models']:break
                time.sleep(.25)
            result['unloaded']=not api('/api/ps')['models']
            assert result['app_probe_exit']==0
    finally:
        if process and process.poll() is None:
            os.killpg(process.pid,signal.SIGTERM)
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
        result['server_stopped']=process is None or process.poll() is not None
        with (HERE/'.runtime'/('app-ollama-'+label+'-summary.json')).open('x') as f:json.dump(result,f,indent=2)
        print(result)
if __name__=='__main__':
    import sys
    main(sys.argv[1])
