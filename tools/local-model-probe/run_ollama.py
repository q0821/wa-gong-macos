"""Bounded local-only smoke test; inputs are only the checked synthetic ASR outputs."""
import hashlib,json,os,re,signal,subprocess,sys,time,urllib.request,threading,socket
from pathlib import Path

ROOT=Path(__file__).resolve().parent
RUNTIME=ROOT/'.runtime'
BASE='http://127.0.0.1:11435'
MODEL='qwen3.5:9b'
OPENER=urllib.request.build_opener(urllib.request.ProxyHandler({}))
INSTRUCTION='請將語音轉錄整理成台灣繁體中文。只修正標點與繁簡字，不改變詞序及用字，保留原意、否定、時間、金額與數字，不得新增事實。英文原句與英文單字保持原樣，不翻譯。只輸出整理後的文字。'

def api(path,body=None,timeout=120):
    payload=None if body is None else json.dumps(body).encode()
    request=urllib.request.Request(BASE+path,data=payload,headers={'Content-Type':'application/json'})
    with OPENER.open(request,timeout=timeout) as r:
        assert r.status==200
        return json.load(r)

def normalized(s):
    s=s.replace('12500','一萬兩千五百').replace('1250','一千兩百五十')
    return ''.join(c.lower() for c in s if c.isalnum())

def terminate(signum,frame):raise KeyboardInterrupt

def main():
    signal.signal(signal.SIGTERM,terminate)
    signal.signal(signal.SIGINT,terminate)
    output=RUNTIME/'ollama-smoke.json'
    assert not output.exists(),'preserve existing result'
    expected=json.loads((ROOT/'ollama-model.json').read_text())
    fixtures={f['id']:f for f in json.loads((RUNTIME/'fixtures.json').read_text())}
    records=[]
    for model in ['qwen','tea']:
        native=json.loads((RUNTIME/(model+'-final-native-summary.json')).read_text())
        for event in native['events']:
            if event.get('event')=='transcript' and event['iteration']==1:
                source=event['text']
                # TEA's official tokenizer.json explicitly removes this PUA range.
                clean=re.sub('[\ue000-\uf8ff]+','',source) if model=='tea' else source
                records.append({'asr':model,'fixture':event['fixture'],'input':clean,
                                'official_tea_decoder_applied':model=='tea',
                                'reference':fixtures[event['fixture']]['reference']})
    assert len(records)==8
    env=os.environ.copy()
    env.update(OLLAMA_HOST='127.0.0.1:11435',OLLAMA_MODELS=str((RUNTIME/'ollama-models').resolve()),
               OLLAMA_NO_CLOUD='1',OLLAMA_NOHISTORY='1',OLLAMA_NOPRUNE='1',OLLAMA_DEBUG='0',
               OLLAMA_NUM_PARALLEL='1',OLLAMA_MAX_LOADED_MODELS='1',OLLAMA_CONTEXT_LENGTH='2048',OLLAMA_KEEP_ALIVE='0')
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1',11435))
    result={'model':MODEL,'manifest_sha256':expected['manifest_sha256'],'requests':[],
            'network_policy':'loopback-only.sb','app_started':False,'server_stopped':False}
    server=None
    stop_monitor=threading.Event()
    sampled={'peak_process_tree_rss_bytes':0}
    def monitor():
        while not stop_monitor.is_set():
            if server is not None:
                rows=subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()
                rows=[tuple(map(int,row.split())) for row in rows if len(row.split())==3]
                owned={server.pid}
                for _ in range(4):
                    owned.update(pid for pid,parent,rss in rows if parent in owned)
                rss=sum(rss*1024 for pid,parent,rss in rows if pid in owned)
                sampled['peak_process_tree_rss_bytes']=max(sampled['peak_process_tree_rss_bytes'],rss)
            stop_monitor.wait(0.5)
    monitor_thread=None
    result['swap_before']=subprocess.check_output(['sysctl','vm.swapusage'],text=True).strip()
    try:
        # No shell and no system service installation; only this process group is managed.
        with (RUNTIME/'ollama-server.log').open('x') as log:
            server=subprocess.Popen(['sandbox-exec','-f',str(ROOT/'loopback-only.sb'),
                str(RUNTIME/'ollama-portable/ollama'),'serve'],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            monitor_thread=threading.Thread(target=monitor);monitor_thread.start()
            print('Started isolated local-only Ollama PID',server.pid,flush=True)
            for _ in range(60):
                if server.poll() is not None:raise RuntimeError('local server exited before ready')
                try:version=api('/api/version',timeout=1);break
                except OSError:time.sleep(0.5)
            else:raise TimeoutError('server readiness timeout')
            result['version']=version
            tags=api('/api/tags')
            match=next(x for x in tags['models'] if x['name']==MODEL)
            assert match['digest'].removeprefix('sha256:')==expected['manifest_sha256'],'model digest drift'
            result['installed_model']=match
            show=api('/api/show',{'model':MODEL})
            result['capabilities']=show.get('capabilities')
            for record in records:
                body={'model':MODEL,'prompt':record['input'],'system':INSTRUCTION,'stream':False,
                      'think':False,'keep_alive':'1m','options':{'temperature':0.1,'num_ctx':2048,'num_predict':512}}
                started=time.monotonic();answer=api('/api/generate',body);duration=time.monotonic()-started
                complete=answer.get('done') is True and answer.get('done_reason')=='stop'
                text=answer.get('response','')
                complete=complete and bool(text.strip())
                words=re.findall('[A-Za-z][A-Za-z0-9]*',record['input'])
                output_words=re.findall('[A-Za-z][A-Za-z0-9]*',text)
                row={**record,'response':text,'seconds':duration,'complete':complete,
                     'fixture_preserved':normalized(text)==normalized(record['reference']),
                     'english_preserved':words==output_words,
                     'load_duration_ns':answer.get('load_duration'),'eval_count':answer.get('eval_count'),
                     'eval_duration_ns':answer.get('eval_duration'),'done_reason':answer.get('done_reason')}
                result['requests'].append(row)
                output.write_text(json.dumps(result,ensure_ascii=False,indent=2))
                print('Validated local request',record['asr'],record['fixture'],round(duration,3),
                      'complete',complete,'fixture',row['fixture_preserved'],'English',row['english_preserved'],flush=True)
                if not complete:raise ValueError('incomplete generation; stop without retry')
            cancel_body={'model':MODEL,'prompt':'請依序列出一到一千的數字，用逗號分隔。',
                         'stream':True,'think':False,'keep_alive':'1m',
                         'options':{'num_ctx':2048,'num_predict':512,'temperature':0}}
            request=urllib.request.Request(BASE+'/api/generate',data=json.dumps(cancel_body).encode(),
                                           headers={'Content-Type':'application/json'})
            first_content=False
            cancel_started=time.monotonic()
            with OPENER.open(request,timeout=30) as response:
                for _ in range(200):
                    line=response.readline()
                    if not line:break
                    event=json.loads(line)
                    if event.get('response'):
                        first_content=True;break
            result['http_cancel_probe']={'first_content_received':first_content,
                                        'connection_closed_seconds':time.monotonic()-cancel_started}
            assert first_content,'stream never reached known-positive content'
            recovery_started=time.monotonic()
            recovery=api('/api/generate',{'model':MODEL,'prompt':'今天下午三點開會。','system':INSTRUCTION,
                'stream':False,'think':False,'keep_alive':'1m',
                'options':{'num_ctx':2048,'num_predict':128,'temperature':0.1}})
            result['http_cancel_probe']['recovery_seconds']=time.monotonic()-recovery_started
            result['http_cancel_probe']['recovery_complete']=recovery.get('done') is True and recovery.get('done_reason')=='stop'
            print('Stream closed after content; recovery complete:',result['http_cancel_probe']['recovery_complete'],flush=True)
            result['resident_after_requests']=api('/api/ps')
            api('/api/generate',{'model':MODEL,'keep_alive':0})
            for _ in range(40):
                unloaded=api('/api/ps')
                if not unloaded['models']:break
                time.sleep(0.25)
            result['unloaded']=not unloaded['models']
            print('Private model unloaded:',result['unloaded'],flush=True)
    except BaseException as error:
        result['failure_type']=type(error).__name__
        print('Local validation stopped:',type(error).__name__,flush=True)
        raise
    finally:
        if server is not None:
            if server.poll() is None:
                os.killpg(server.pid,signal.SIGTERM)
                try:server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(server.pid,signal.SIGKILL);server.wait(timeout=5)
            result['server_stopped']=server.poll() is not None
        stop_monitor.set()
        if monitor_thread:monitor_thread.join(timeout=5)
        result['resources']=sampled
        result['swap_after']=subprocess.check_output(['sysctl','vm.swapusage'],text=True).strip()
        output.write_text(json.dumps(result,ensure_ascii=False,indent=2))
        print('Isolated server stopped:',result['server_stopped'],flush=True)

if __name__=='__main__':main()
