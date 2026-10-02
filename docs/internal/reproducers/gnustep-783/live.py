import os,subprocess,pathlib,json
root=pathlib.Path('/tmp/arlen-783-evidence'); results=[]
env=os.environ.copy(); env['LD_LIBRARY_PATH']='/tmp/arlen-783-base/Source/obj:'+env.get('LD_LIBRARY_PATH',''); env['GS_TLS_VERIFY_S']='YES'; env['GS_TLS_CA_FILE']='/etc/ssl/certs/ca-certificates.crt'
for worker in [0,1]:
 for mode in ['custom','default']:
  url='https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration'
  for stage in ['discovery','jwks']:
   p=subprocess.run([str(root/'probe'),url,mode,'1',str(worker),'json','5'],env=env,text=True,capture_output=True,timeout=15)
   row=dict(stage=stage,worker=worker,mode=mode,exit=p.returncode,stdout=p.stdout,stderr=p.stderr); results.append(row);print(json.dumps(row),flush=True)
   if p.returncode: break
   if stage=='discovery': url=next(x[5:] for x in p.stdout.splitlines() if x.startswith('JWKS='))
(root/'live.json').write_text(json.dumps(results,indent=2))
raise SystemExit(any(r['exit'] for r in results))
