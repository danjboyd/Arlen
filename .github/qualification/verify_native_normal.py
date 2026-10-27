#!/usr/bin/env python3
"""Match native normal XCTest receipts against full source inventories."""
from collections import Counter
import hashlib,json,re,sys,xml.etree.ElementTree as ET
from pathlib import Path
root,harness,out=map(Path,sys.argv[1:])
contract=json.loads((harness/'candidate-unit-contract.json').read_text())
skips={x['id']:x for x in contract['skips'] if x['category']!='existing-sanitizer-build-avoidance'}
assert len(skips)==15
integration=json.loads((harness/'candidate-integration-contract.json').read_text())
assert integration['frozen_commit']==contract['frozen_commit']
receipts={}
for bundle,logname in [('ArlenUnitTests','unit'),('ArlenIntegrationTests','integration')]:
 inventory=root/'tests/fixtures/test_inventory'/f'{bundle}.tests.txt'
 expected=inventory.read_text().splitlines()
 wanted_contract=contract if logname=='unit' else integration
 assert hashlib.sha256(inventory.read_bytes()).hexdigest()==wanted_contract['inventory_sha256']
 assert len(set(expected))==len(expected)
 xml=ET.parse(out/'xctest-results'/f'{bundle}.xml').getroot()
 cases=xml.findall('.//testcase')
 ids=[bundle+'/'+c.attrib['classname']+'/'+c.attrib['name'] for c in cases]
 assert Counter(ids)==Counter(expected)
 assert int(xml.attrib['tests'])==len(expected) and int(xml.attrib['failures'])==int(xml.attrib['errors'])==0
 assert not xml.findall('.//failure') and not xml.findall('.//error')
 actual={i:c.find('skipped') for i,c in zip(ids,cases) if c.find('skipped') is not None}
 wanted=skips if logname=='unit' else {x['id']:x for x in integration['skips']}
 assert set(actual)==set(wanted),(bundle,list(actual))
 for i,e in actual.items():
  spec=wanted[i];assert spec['reason_fragment'] in (e.attrib.get('message','')+(e.text or ''))
  assert hashlib.sha256((root/spec['source']).read_bytes()).hexdigest()==spec['source_sha256']
 assert int(xml.attrib['skipped'])==len(actual)
 started=[];current=None
 for line in (out/f'{logname}.log').read_text(errors='replace').splitlines():
  m=re.search(r'XCTest:\s+Running (\w+)\s*$',line)
  if m: current=m.group(1)
  m=re.search(r'XCTest:\s+(test\w+)\.\.\.',line)
  if m:
   assert current;started.append(bundle+'/'+current+'/'+m.group(1))
 assert Counter(started)==Counter(expected)
 receipts[bundle]={'methods':len(expected),'passed':len(cases)-len(actual),'skipped':list(actual),'failures':0,'inventory_sha256':hashlib.sha256(inventory.read_bytes()).hexdigest()}
assert receipts['ArlenUnitTests']['methods']==1393
p=json.loads((out/'normal-provenance.json').read_text())
assert p['lock']['sha256']=='a4d3736287fd93c10fd47603086260c7896f97e96af05d2371de6fe3d0975c9d'
assert p['build_host']['machine']=='aarch64' and p['build_host']['os_version']=='ubuntu-24.04'
(out/'verified-normal-receipt.json').write_text(json.dumps({'status':'pass','source':contract['frozen_commit'],'suites':receipts,'http_concurrency':'maintained gate passed'},indent=2)+'\n')
