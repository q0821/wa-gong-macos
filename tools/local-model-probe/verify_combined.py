"""Sequential audio -> actual App ASR client -> native worker -> actual App Ollama client."""
import json,secrets,socket,threading,time,sys
from pathlib import Path
import uvicorn
from gguf_server import app_for,GGUFProcessWorker
from verify_app_ollama import main as run_ollama
HERE=Path(__file__).resolve().parent

def verify(probe,label="first"):
    token=secrets.token_urlsafe(32);worker=GGUFProcessWorker()
    sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    server=uvicorn.Server(uvicorn.Config(app_for(token,worker),access_log=False,log_level='critical'))
    thread=threading.Thread(target=server.run,kwargs={'sockets':[sock]},daemon=True);thread.start()
    result={}
    try:
        for _ in range(100):
            if server.started:break
            time.sleep(.05)
        assert server.started
        run_ollama(probe,{'WAGONG_ASR_ENDPOINT':f'http://127.0.0.1:{port}/v1/audio/transcriptions',
            'WAGONG_LOCAL_TOKEN':token},['--combined'],label='combined-'+label)
        result['combined_passed']=True
    finally:
        server.should_exit=True;thread.join(timeout=10);worker.close()
        result['asr_server_stopped']=not thread.is_alive()
        result['worker_process_absent']=worker.process is None
        with (HERE/'.runtime'/('app-combined-'+label+'-summary.json')).open('x') as f:json.dump(result,f,indent=2)
    assert result['asr_server_stopped']
if __name__=='__main__':verify(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else 'first')
