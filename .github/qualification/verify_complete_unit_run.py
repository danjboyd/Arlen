#!/usr/bin/env python3
"""Verify complete frozen-source unit receipts. Does not load or execute tests."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(contract, inventory, junit, log, lane):
    require(hashlib.sha256(inventory.read_bytes()).hexdigest() == contract['inventory_sha256'],
            'frozen unit inventory hash mismatch')
    expected = inventory.read_text().splitlines()
    require(len(expected) == len(set(expected)) == contract['unit_methods'] == 1373,
            'unit inventory is not exactly 1373 unique methods')
    source_root = inventory.parents[3]
    for skip in contract['skips']:
        require(hashlib.sha256((source_root / skip['source']).read_bytes()).hexdigest() == skip['source_sha256'],
                'skip source does not match frozen contract: ' + skip['id'])
    require(lane['unit_methods_started'] == len(expected), 'maintained log counter is not the complete inventory')
    current_class = None
    started = []
    logged_skips = {}
    for line in log.read_text(errors='replace').splitlines():
        match = re.search(r'XCTest:\s+Running (\w+)\s*$', line)
        if match:
            current_class = match.group(1)
        match = re.search(r'XCTest:\s+(test\w+)\.\.\.', line)
        if match:
            require(current_class is not None, 'method start has no XCTest class')
            started.append('ArlenUnitTests/' + current_class + '/' + match.group(1))
        match = re.search(r'XCTest:\s+(test\w+) SKIPPED at .*', line)
        if match:
            require(current_class is not None, 'skipped method has no XCTest class')
            identifier = 'ArlenUnitTests/' + current_class + '/' + match.group(1)
            require(identifier not in logged_skips, 'duplicate logged skip: ' + identifier)
            logged_skips[identifier] = line
    require(Counter(started) == Counter(expected),
            'log method identities are incomplete, duplicated, or unexpected')
    xml = ET.parse(junit).getroot()
    require(xml.tag == 'testsuites', 'unexpected JUnit root')
    require(int(xml.attrib['tests']) == len(expected), 'JUnit total differs from frozen inventory')
    require(int(xml.attrib['failures']) == int(xml.attrib['errors']) == 0, 'JUnit contains failures/errors')
    cases = xml.findall('.//testcase')
    ids = ['ArlenUnitTests/' + c.attrib['classname'] + '/' + c.attrib['name'] for c in cases]
    require(Counter(ids) == Counter(expected), 'JUnit identities are incomplete, duplicated, or unexpected')
    require(not xml.findall('.//failure') and not xml.findall('.//error'), 'JUnit case failure/error recorded')
    for suite in xml.findall('testsuite'):
        suite_cases = suite.findall('testcase')
        require(int(suite.attrib['tests']) == len(suite_cases), 'JUnit suite count is incomplete')
        require(int(suite.attrib['failures']) == int(suite.attrib['errors']) == 0,
                'JUnit suite failure/error recorded')
        require(int(suite.attrib['skipped']) == sum(c.find('skipped') is not None for c in suite_cases),
                'JUnit suite skip count mismatch')
    expected_skips = {s['id']: s for s in contract['skips']}
    require(set(logged_skips) == set(expected_skips), 'logged skip identities differ from frozen mapping')
    for identifier, line in logged_skips.items():
        require(expected_skips[identifier]['reason_fragment'] in line,
                'logged skip reason differs from frozen mapping: ' + identifier)
    skips = {}
    for identifier, case in zip(ids, cases):
        skip = case.find('skipped')
        if skip is not None:
            require(identifier in expected_skips, 'unexpected skipped method: ' + identifier)
            reason = skip.attrib.get('message', '') + (skip.text or '')
            require(expected_skips[identifier]['reason_fragment'] in reason,
                    'skip reason differs from frozen mapping: ' + identifier)
            skips[identifier] = {'category': expected_skips[identifier]['category'], 'actual_reason': reason}
    require(set(skips) == set(expected_skips), 'expected skip mapping differs from actual profile')
    require(len(skips) == int(xml.attrib['skipped']) == contract['unit_skipped'] == 17,
            'JUnit skipped total is not exactly the mapped 17')
    require(len(cases) - len(skips) == contract['unit_passed'] == 1356, 'completed pass count mismatch')
    return {'status': 'pass', 'frozen_source': contract['frozen_commit'],
            'inventory_sha256': contract['inventory_sha256'], 'expected_methods': len(expected),
            'logged_method_starts': len(started), 'unique_logged_methods': len(set(started)),
            'JUnit_cases': len(cases), 'logged_skips': len(logged_skips), 'passed': len(cases) - len(skips), 'skipped': len(skips),
            'failures': 0, 'errors': 0, 'skips_by_id': skips,
            'scope': 'full TSan unit inventory; existing HTTP concurrency and diagnostic gates are separate',
            'input_hashes': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [inventory, junit, log]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['contract', 'inventory', 'junit', 'log', 'lane-summary', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    result = verify(json.loads(args.contract.read_text()), args.inventory, args.junit, args.log,
                    json.loads(args.lane_summary.read_text()))
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('Frozen full unit receipt: 1373 starts / 1373 unique JUnit methods / 1356 pass / 17 mapped skips')


if __name__ == '__main__':
    main()
