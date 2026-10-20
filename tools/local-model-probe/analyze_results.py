"""Separate exact fixture equality from numeral spelling and English preservation."""
import json
from pathlib import Path
from run_ollama import normalized
ROOT=Path(__file__).resolve().parent/'.runtime'
def equivalent_fixture(output,reference):
    # Only for these fixed synthetic fixtures. Not a production numeral parser.
    return normalized(output).replace('兩','二')==normalized(reference).replace('兩','二')
def main():
    raw=json.loads((ROOT/'ollama-smoke.json').read_text())
    rows=[]
    for request in raw['requests']:
        rows.append({'asr':request['asr'],'fixture':request['fixture'],
                     'complete':request['complete'],
                     'literal_fixture_preserved':request['fixture_preserved'],
                     'fixture_equivalent_allowing_numeral_spelling':equivalent_fixture(request['response'],request['reference']),
                     'english_exactly_preserved':request['english_preserved']})
    result={'rows':rows,'complete_count':sum(r['complete'] for r in rows),
            'equivalent_count':sum(r['fixture_equivalent_allowing_numeral_spelling'] for r in rows),
            'english_preserved_count':sum(r['english_exactly_preserved'] for r in rows)}
    (ROOT/'ollama-analysis.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
