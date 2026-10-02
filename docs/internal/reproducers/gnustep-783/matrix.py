import subprocess, os, json, pathlib
root=pathlib.Path('/tmp/arlen-783-evidence')
peer=subprocess.Popen(['python3','tests/fixtures/http/metadata_server.py'],stdout=subprocess.PIPE,text=True)
port=peer.stdout.readline().strip()
if not port: raise RuntimeError('socket peer failed')
results=[]
try:
 for version in ['baseline','patched']:
  env=os.environ.copy()
  if version=='patched': env['LD_LIBRARY_PATH']='/tmp/arlen-783-base/Source/obj:'+env.get('LD_LIBRARY_PATH','')
  (root/(version+'-ldd.txt')).write_text(subprocess.check_output(['ldd',str(root/'probe')],env=env,text=True))
  for worker in [0,1]:
   for mode in ['custom','default']:
    cases=[('ok', int(version=='patched'), 'timeout' if version=='baseline' and mode=='custom' else 'ok',2)]
    if version=='patched': cases += [('ok',0,'timeout',0.3),('timeout',1,'timeout',0.3),('trickle',1,'timeout',0.3),('disconnect',1,'error',2)]
    for path,start,expect,deadline in cases:
     command=[str(root/'probe'),f'http://127.0.0.1:{port}/{path}',mode,str(start),str(worker),expect,str(deadline)]
     p=subprocess.run(command,env=env,text=True,capture_output=True,timeout=10)
     row=dict(version=version,mode=mode,worker=worker,path=path,start=start,expected=expect,exit=p.returncode,stdout=p.stdout,stderr=p.stderr)
     results.append(row); print(json.dumps(row),flush=True)
finally:
 peer.terminate(); peer.wait()
 (root/'matrix.json').write_text(json.dumps(results,indent=2))
raise SystemExit(any(r['exit'] for r in results))
