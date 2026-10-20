"""Explicit GGUF loopback bridge, using the existing ASR contract and disposable native workers."""
import argparse,asyncio,base64,getpass,hashlib,json,os,signal,subprocess,sys,time,threading
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'taiwan-asr'))
from server import create_app,client_disconnected
from fastapi import HTTPException
sys.path.insert(0,str(HERE))
from download import verified

MODELS={'tea-gguf':{'repository':'mukiwu/TEA-ASR-1.1-transcribe-gguf'},
        'qwen3-asr-0.6b-gguf':{'repository':'handy-computer/Qwen3-ASR-0.6B-gguf'}}

class GGUFProcessWorker:
    def __init__(self):
        self.process=None;self.model=None;self.loaded=False;self.warmed=False
        self.close_lock=threading.Lock()
        self.buffer=b'';self.entered_native=asyncio.Event();self.events=[];self.validated={}
    def check_artifacts(self,key):
        build=json.loads((HERE/'.runtime/worker-build.json').read_text())
        for relative,digest in build['inputs'].items():
            if hashlib.sha256((HERE.parents[1]/relative).read_bytes()).hexdigest()!=digest:
                raise HTTPException(503,'worker_source_changed_rebuild_required')
        binary=HERE/'.runtime/GGUFWorker'
        if hashlib.sha256(binary.read_bytes()).hexdigest()!=build['binary_sha256']:
            raise HTTPException(503,'worker_binary_integrity_failed')
        a=json.loads((HERE/'artifacts.json').read_text())[key]
        path=HERE/'.runtime'/a['filename']
        st=path.stat();signature=(st.st_ino,st.st_mtime_ns,st.st_ctime_ns,st.st_size)
        if path.is_symlink():raise HTTPException(503,'model_integrity_failed')
        if self.validated.get(key)!=signature:
            if not verified(path,a):raise HTTPException(503,'model_integrity_failed')
            self.validated[key]=signature
        return binary,path
    def close(self):
        with self.close_lock:self._close()
    def _close(self):
        process=self.process
        if process is not None:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=2)
                except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
            self.events.append({'event':'reaped','pid':process.pid,'exit':process.returncode})
            if process.stdin and not process.stdin.closed:process.stdin.close()
            if process.stdout:process.stdout.close()
        self.process=None;self.model=None;self.loaded=False;self.warmed=False;self.buffer=b''
    async def next_event(self,request,deadline):
        while True:
            if await client_disconnected(request):raise HTTPException(499,'request_canceled')
            if time.monotonic()>deadline:raise HTTPException(504,'inference_timeout')
            if b'\n' in self.buffer:
                line,self.buffer=self.buffer.split(b'\n',1)
                try:return json.loads(line)
                except (ValueError,UnicodeError):raise HTTPException(503,'invalid_model_result')
            try:chunk=os.read(self.process.stdout.fileno(),65536)
            except BlockingIOError:chunk=None
            if chunk:
                self.buffer+=chunk
                if len(self.buffer)>65536:raise HTTPException(503,'invalid_model_result')
                continue
            if chunk==b'' or self.process.poll() is not None:raise HTTPException(503,'model_worker_stopped')
            await asyncio.sleep(0.01)
    async def transcribe(self,model,samples,language,request,timeout):
        if model not in MODELS:raise HTTPException(404,'model_not_found')
        key='tea' if model=='tea-gguf' else 'qwen'
        deadline=time.monotonic()+timeout
        self.entered_native.clear()
        try:
            binary,path=await asyncio.to_thread(self.check_artifacts,key)
            if await client_disconnected(request):raise HTTPException(499,'request_canceled')
            if time.monotonic()>deadline:raise HTTPException(504,'inference_timeout')
            self.model=model
            self.process=subprocess.Popen([str(binary),key,str(path)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                          stderr=subprocess.DEVNULL,bufsize=0)
            os.set_blocking(self.process.stdout.fileno(),False)
            message=await self.next_event(request,deadline)
            if message.get('event')!='loaded':raise HTTPException(503,'model_load_failed')
            self.loaded=True
            payload=json.dumps({'language':language,'pcm':base64.b64encode(samples.astype('<f4').tobytes()).decode()}).encode()
            # The child is waiting on stdin. Keep the event loop free during bounded writes.
            pipe=self.process.stdin
            def write_input():
                view=memoryview(payload)
                while view:
                    count=pipe.write(view)
                    if not count:raise BrokenPipeError()
                    view=view[count:]
                pipe.close()
            await asyncio.to_thread(write_input)
            message=await self.next_event(request,deadline)
            if message.get('event')!='running':raise HTTPException(503,'native_entry_not_observed')
            self.events.append({'event':'running','pid':self.process.pid,'model':model})
            self.entered_native.set()
            message=await self.next_event(request,deadline)
            if message.get('event')!='result' or not isinstance(message.get('text'),str) or not message['text'].strip():
                raise HTTPException(503,'invalid_model_result')
            try:await asyncio.to_thread(self.process.wait,2)
            except subprocess.TimeoutExpired:raise HTTPException(503,'model_worker_stopped')
            if self.process.returncode!=0:raise HTTPException(503,'model_worker_stopped')
            if await client_disconnected(request):raise HTTPException(499,'request_canceled')
            return message['text']
        finally:
            # Never release the handler/busy lock until the native process has ended.
            cleanup=asyncio.create_task(asyncio.to_thread(self.close))
            interrupted=False
            while not cleanup.done():
                try:await asyncio.shield(cleanup)
                except asyncio.CancelledError:interrupted=True
            await cleanup
            if interrupted:raise asyncio.CancelledError()

def app_for(token,worker=None):
    return create_app(token,worker=worker or GGUFProcessWorker(),timeout=90,models=MODELS)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8766);args=parser.parse_args()
    token=getpass.getpass('Local GGUF service token (32+ ASCII characters): ')
    import uvicorn
    uvicorn.run(app_for(token),host='127.0.0.1',port=args.port,log_level='warning',timeout_graceful_shutdown=5)
