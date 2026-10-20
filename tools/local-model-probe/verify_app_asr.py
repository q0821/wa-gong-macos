"""Actual built App transport against the disposable GGUF loopback bridge."""
import json,os,secrets,socket,subprocess,threading,time
from pathlib import Path
import uvicorn
from gguf_server import app_for,GGUFProcessWorker
HERE=Path(__file__).resolve().parent

def main(probe):
    result={};token=secrets.token_urlsafe(32);worker=GGUFProcessWorker()
    sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    server=uvicorn.Server(uvicorn.Config(app_for(token,worker),access_log=False,log_level='critical'))
    thread=threading.Thread(target=server.run,kwargs={'sockets':[sock]},daemon=True);thread.start()
    try:
        for _ in range(100):
            if server.started:break
            time.sleep(.05)
        assert server.started
        env=os.environ.copy();env.update(WAGONG_LOCAL_ENDPOINT=f'http://127.0.0.1:{port}/v1/audio/transcriptions',
            WAGONG_LOCAL_AUDIO=str(HERE/'.runtime/zh.wav'),WAGONG_LOCAL_TOKEN=token,
            LLVM_PROFILE_FILE=str(HERE/'.runtime/app-asr-fix-%p.profraw'))
        result['app_probe_exit']=subprocess.run([probe,'--asr'],env=env,timeout=90).returncode
        assert result['app_probe_exit']==0
    finally:
        server.should_exit=True;thread.join(timeout=10);worker.close()
        result['server_stopped']=not thread.is_alive()
        path=HERE/'.runtime/app-asr-fix.json'
        with path.open('x') as f:json.dump(result,f,indent=2)
    assert result['server_stopped']
    print(result)
if __name__=='__main__':
    import sys
    main(sys.argv[1])
