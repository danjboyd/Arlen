import subprocess,os,json,pathlib
root=pathlib.Path('/tmp/arlen-783-evidence'); results=[]
for tls in [False,True]:
 peer=subprocess.Popen(['python3','tests/fixtures/http/metadata_server.py']+(['--tls'] if tls else []),stdout=subprocess.PIPE,text=True)
 port=peer.stdout.readline().strip()
 try:
  for version in ['baseline','patched']:
   for worker in [0,1]:
    for mode in (['default'] if version=='baseline' else ['custom','default']):
     env=os.environ.copy()
     if version=='patched': env['LD_LIBRARY_PATH']='/tmp/arlen-783-base/Source/obj:'+env.get('LD_LIBRARY_PATH','')
     env['GS_TLS_VERIFY_S']='YES';env['GS_TLS_CA_FILE']='/etc/ssl/certs/ca-certificates.crt'
     for case in (['tls'] if tls else ['repeat','disconnect']):
      env['PROBE_REPEAT']='50' if case=='repeat' else '1'
      path='disconnect' if case=='disconnect' else 'ok'
      p=subprocess.run([str(root/'probe'),f'{"https" if tls else "http"}://127.0.0.1:{port}/{path}',mode,str(int(version=='patched')),str(worker),'ok' if case=='repeat' else 'error','2'],env=env,capture_output=True,text=True,timeout=25)
      row=dict(version=version,worker=worker,mode=mode,case=case,exit=p.returncode,stdout=p.stdout,stderr=p.stderr);results.append(row);print(json.dumps(row),flush=True)
 finally: peer.terminate();peer.wait()
(root/'extra.json').write_text(json.dumps(results,indent=2))
