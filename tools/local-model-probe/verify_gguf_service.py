"""Real HTTP plus observed native-entry cancellation, using synthetic audio only."""
import http.client,json,secrets,socket,threading,time,wave,io,os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import httpx,uvicorn
from gguf_server import app_for,GGUFProcessWorker
HERE=Path(__file__).resolve().parent

def verify(output=None):
    output=output or HERE/'.runtime/gguf-service-fix.json'
    if output.exists():raise ValueError('preserve evidence; result already exists')
    worker=GGUFProcessWorker();token=secrets.token_urlsafe(32)
    app=app_for(token,worker)
    listener=socket.socket();listener.bind(('127.0.0.1',0));port=listener.getsockname()[1]
    url=f'http://127.0.0.1:{port}'
    server=uvicorn.Server(uvicorn.Config(app,access_log=False,log_level='critical',timeout_graceful_shutdown=5))
    thread=threading.Thread(target=server.run,kwargs={'sockets':[listener]},daemon=True);thread.start()
    headers={'Authorization':'Bearer '+token}
    result={'requests':[],'cancellation':None}
    audio=(HERE/'.runtime/zh.wav').read_bytes()
    try:
        with httpx.Client(trust_env=False,timeout=100) as client:
            for _ in range(100):
                if server.started:break
                time.sleep(0.05)
            assert server.started
            bad=client.get(url+'/health',headers={'Authorization':'Bearer wrong'});assert bad.status_code==401
            result['bad_auth_status']=bad.status_code
            def post(model):
                started=time.monotonic()
                r=client.post(url+'/v1/audio/transcriptions',headers=headers,
                    data={'model':model,'language':'zh','response_format':'json','temperature':'0'},
                    files={'file':('audio.wav',audio,'audio/wav')})
                assert r.status_code==200
                text=r.json()['text']
                assert not any(0xe000<=ord(c)<=0xf8ff for c in text)
                if model=='tea-gguf':assert ''.join(c for c in text if c.isalnum())=='今天下午三點開會請保留原始資料不要刪除'
                result['requests'].append({'model':model,'seconds':time.monotonic()-started,'pua_free':True})
            post('qwen3-asr-0.6b-gguf');post('tea-gguf')
            with wave.open(io.BytesIO(audio)) as wav:
                frames=wav.readframes(wav.getnframes());params=wav.getparams()
            buf=io.BytesIO()
            with wave.open(buf,'wb') as wav:wav.setparams(params);wav.writeframes(frames*4)
            boundary='gguf-cancel-positive'
            body=(f'--{boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\ntea-gguf\r\n'
                  f'--{boundary}\r\nContent-Disposition: form-data; name="language"\r\n\r\nzh\r\n'
                  f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n').encode()+buf.getvalue()+f'\r\n--{boundary}--\r\n'.encode()
            worker.entered_native.clear()
            conn=http.client.HTTPConnection('127.0.0.1',port,timeout=100)
            conn.request('POST','/v1/audio/transcriptions',body=body,
                         headers={**headers,'Content-Type':f'multipart/form-data; boundary={boundary}'})
            for _ in range(2000):
                if worker.entered_native.is_set():break
                time.sleep(0.01)
            assert worker.entered_native.is_set(),'no native-entry positive observed'
            busy=client.post(url+'/v1/audio/transcriptions',headers=headers,content=b'')
            assert busy.status_code==429
            result['busy_status']=busy.status_code
            pid=worker.process.pid
            stopped_at=time.monotonic();conn.close()
            for _ in range(700):
                if worker.process is None:break
                time.sleep(0.01)
            assert worker.process is None,'native worker survived cancellation'
            reaped=next(e for e in reversed(worker.events) if e['event']=='reaped' and e['pid']==pid)
            assert reaped['exit']<0,'process was not terminated after native-entry cancellation'
            try:os.kill(pid,0)
            except ProcessLookupError:pass
            else:raise AssertionError('old worker PID still alive')
            result['cancellation']={'native_entry_observed':True,'reaped':True,'exit':reaped['exit'],
                                    'stop_seconds':time.monotonic()-stopped_at}
            post('tea-gguf')
            result['recovery_passed']=True
    finally:
        server.should_exit=True;thread.join(timeout=10)
        if thread.is_alive():server.force_exit=True;thread.join(timeout=5)
        worker.close();result['server_stopped']=not thread.is_alive()
        output.write_text(json.dumps(result,indent=2))
    assert result['server_stopped']
    print(json.dumps(result,indent=2))
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);args=parser.parse_args()
    verify(args.output)
