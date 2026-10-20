"""Generate only explicit, non-private acceptance fixtures using installed macOS voices."""
from pathlib import Path
import subprocess,json,wave,array
ROOT=Path(__file__).resolve().parent / '.runtime'
FIXTURES=[('zh','Meijia','今天下午三點開會，請保留原始資料，不要刪除。','zh'),('mixed','Meijia','請幫我 review 這個 API，今天先不要 deploy。','zh'),('english','Samantha','Please review the API tomorrow. Do not delete the original data.','en'),('numbers','Meijia','訂單金額是一萬兩千五百元，不是一千兩百五十元。','zh')]
def main():
 records=[]
 for name,voice,text,language in FIXTURES:
  aiff=ROOT/(name+'.aiff'); wav=ROOT/(name+'.wav'); pcm=ROOT/(name+'.f32')
  subprocess.run(['say','-v',voice,'-r','175','-o',str(aiff),text],check=True)
  subprocess.run(['afconvert','-f','WAVE','-d','LEI16@16000','-c','1',str(aiff),str(wav)],check=True)
  with wave.open(str(wav)) as f:
   assert f.getsampwidth()==2 and f.getnchannels()==1 and f.getframerate()==16000
   assert f.getnframes() > 16000, 'empty or too short fixture'
   ints=array.array('h',f.readframes(f.getnframes()))
  floats=array.array('f',(x/32768 for x in ints)); pcm.write_bytes(floats.tobytes())
  records.append(dict(id=name,pcm=str(pcm),language=language,reference=text,synthetic=True,seconds=len(floats)/16000))
  print(name, 'validated audio seconds:',len(floats)/16000,flush=True)
 (ROOT/'fixtures.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
