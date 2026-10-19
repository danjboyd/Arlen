#!/usr/bin/env python3
"""Compare scan-build HTML reports against a baseline of accepted warnings.

Each report is keyed by (repo-relative file, bug type, function, issue hash).
The issue hash is clang's ISSUEHASHCONTENTOFLINEINCONTEXT, which does not
change when unrelated edits shift line numbers, so the baseline stays stable.

  static_scan_build_gate.py --reports DIR --root REPO --baseline baseline.json
  static_scan_build_gate.py --reports DIR --root REPO --baseline baseline.json --write-baseline

Exit 0: every report is in the baseline. Exit 1: new reports (printed).
Stale baseline entries (warnings that no longer occur) are listed but do not
fail the gate; remove them when convenient.

--write-baseline rewrites the baseline from the current reports, keeping the
`reason` of entries that are still present and marking new ones "TODO". Every
entry needs a real reason before it is committed.
"""

import argparse
import glob
import json
import os
import re
import sys
from typing import Dict, List

FIELDS = (
    "BUGFILE",
    "BUGTYPE",
    "FUNCTIONNAME",
    "ISSUEHASHCONTENTOFLINEINCONTEXT",
    "BUGLINE",
    "BUGDESC",
    "BUGCATEGORY",
)


def read_reports(report_dir: str, root: str) -> Dict[str, Dict[str, object]]:
    root_prefix = os.path.realpath(root) + os.sep
    found: Dict[str, Dict[str, object]] = {}
    pattern = os.path.join(report_dir, "**", "report-*.html")
    for path in sorted(glob.glob(pattern, recursive=True)):
        with open(path, encoding="utf-8", errors="replace") as handle:
            head = handle.read(8192)
        meta = {}
        for field in FIELDS:
            match = re.search(r"<!-- %s (.*?) -->" % field, head)
            meta[field] = match.group(1) if match else ""
        rel = meta["BUGFILE"]
        if rel.startswith(root_prefix):
            rel = rel[len(root_prefix):]
        key = "|".join([rel, meta["BUGTYPE"], meta["FUNCTIONNAME"],
                        meta["ISSUEHASHCONTENTOFLINEINCONTEXT"]])
        found[key] = {
            "file": rel,
            "line": int(meta["BUGLINE"] or 0),
            "type": meta["BUGTYPE"],
            "category": meta["BUGCATEGORY"],
            "function": meta["FUNCTIONNAME"],
            "message": meta["BUGDESC"],
            "hash": meta["ISSUEHASHCONTENTOFLINEINCONTEXT"],
        }
    return found


def load_baseline(path: str) -> List[Dict[str, object]]:
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return list(json.load(handle).get("accepted", []))


def write_baseline(path: str, current: Dict[str, Dict[str, object]],
                   previous: List[Dict[str, object]]) -> int:
    reasons = {str(entry.get("key")): entry.get("reason", "TODO") for entry in previous}
    entries = [dict(value, key=key, reason=reasons.get(key, "TODO"))
               for key, value in sorted(current.items())]
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({"version": 1, "accepted": entries}, handle, indent=2)
        handle.write("\n")
    return len(entries)


def compare(current: Dict[str, Dict[str, object]],
            accepted_entries: List[Dict[str, object]]) -> int:
    accepted = {str(entry["key"]) for entry in accepted_entries}
    new = sorted(key for key in current if key not in accepted)
    stale = sorted(key for key in accepted if key not in current)
    for key in new:
        item = current[key]
        print("NEW %s:%d [%s] %s (%s)" % (item["file"], item["line"], item["type"],
                                          item["message"], item["function"]))
    for key in stale:
        print("STALE (no longer reported; remove from baseline) %s" % key)
    print("scan-build gate: %d reports, %d accepted, %d new, %d stale"
          % (len(current), len(current) - len(new), len(new), len(stale)))
    return 1 if new else 0


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reports", required=True, help="scan-build -o directory")
    parser.add_argument("--root", required=True, help="repository root")
    parser.add_argument("--baseline", required=True, help="accepted-warnings JSON")
    parser.add_argument("--write-baseline", action="store_true",
                        help="rewrite the baseline from the current reports")
    args = parser.parse_args(argv)

    current = read_reports(args.reports, args.root)
    previous = load_baseline(args.baseline)
    if args.write_baseline:
        count = write_baseline(args.baseline, current, previous)
        print("wrote %d baseline entries to %s" % (count, args.baseline))
        return 0
    if not os.path.exists(args.baseline):
        print("scan-build gate: baseline not found: %s" % args.baseline, file=sys.stderr)
        return 2
    return compare(current, previous)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
