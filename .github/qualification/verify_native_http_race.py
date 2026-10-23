#!/usr/bin/env python3
"""Verify native ARM64 instrumented HTTP and detecting-control receipts."""
import hashlib,json,re,sys
from pathlib import Path
out,thread,source=sys.argv[1:];out,thread=Path(out),Path(thread)
m=json.loads((thread/'manifest.json').read_text())
allowed={Path(p).resolve():h for p,h in m['artifacts'].items()}
records=[]
for n in (1,2):
 b=out/f'http-{n}';logs=list((b/'runtime_concurrency').glob('*.log'));raw=(b/'probe.log').read_text()
 assert len(logs)==4 and raw.count('runtime concurrency server exit=0; log retained:')==4 and 'runtime-concurrency-probe: ok' in raw
 pattern=r'(?:WARNING|ERROR|FATAL|SUMMARY):\s*(?:Thread|Address|Leak|Memory|UndefinedBehavior)Sanitizer|(?:^|\s)runtime error:'
 assert not any(re.search(pattern,p.read_text(errors='replace')) for p in logs)
 linkage=(b/'linkage.txt').read_text();dsos={}
 for name in ('libgnustep-base.so','libobjc.so','libdispatch.so','libBlocksRuntime.so'):
  paths=[Path(x.split('=>',1)[1].split()[0]).resolve() for x in linkage.splitlines() if x.strip().startswith(name) and '=>' in x]
  assert paths and all(p in allowed and hashlib.sha256(p.read_bytes()).hexdigest()==allowed[p] for p in paths)
  dsos[name]=[{'path':str(p),'sha256':allowed[p]} for p in paths]
 records.append({'run':n,'server_exit_codes':[0,0,0,0],'log_hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in logs},'actual_four_core_dsos':dsos})
d=json.loads((out/'diagnostics/summary.json').read_text());assert d['status']=='pass' and len(d['runs'])==30 and all(r['valid'] for r in d['runs'])
c=[r for r in d['runs'] if r['mode']=='canary'];assert len(c)==2 and all(r['exit_code']==66 and r['canary_detected'] for r in c)
(out/'verified-native-http-race.json').write_text(json.dumps({'status':'pass','source':source,'scope':'Native ARM64 instrumented HTTP restart/shutdown and dependency concurrency controls; full unit/integration acceptance is separately verified. This is not a full ARM64 TSan unit-suite pass.','http_runs':records,'diagnostics':{'valid':30,'detecting_canaries':2,'canary_exit_codes':[66,66]}},indent=2)+'\n')
