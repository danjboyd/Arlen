#!/usr/bin/env python3
"""Summarize the xctest JUnit reports under test-results.

Writes a Markdown summary (to $GITHUB_STEP_SUMMARY when set), prints GitHub
error annotations for failed tests, and can fail when tests were skipped for a
reason a lane is expected to satisfy (for example a lane that provisions
PostgreSQL must not skip for a missing ARLEN_PG_TEST_DSN).
"""

from __future__ import annotations

import argparse
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Case:
    report: str
    suite: str
    name: str
    outcome: str  # passed | failed | skipped
    message: str = ""


@dataclass
class Totals:
    cases: list[Case] = field(default_factory=list)

    def count(self, outcome: str) -> int:
        return sum(1 for case in self.cases if case.outcome == outcome)


def parse_report(path: Path) -> list[Case]:
    root = ET.parse(path).getroot()
    suites = [root] if root.tag == "testsuite" else root.iter("testsuite")
    cases: list[Case] = []
    for suite in suites:
        for testcase in suite.iter("testcase"):
            outcome, message = "passed", ""
            for tag in ("failure", "error"):
                node = testcase.find(tag)
                if node is not None:
                    outcome = "failed"
                    message = node.get("message") or (node.text or "").strip()
                    break
            else:
                node = testcase.find("skipped")
                if node is not None:
                    outcome = "skipped"
                    message = node.get("message") or (node.text or "").strip()
            cases.append(
                Case(
                    report=path.stem,
                    suite=testcase.get("classname") or suite.get("name") or "",
                    name=testcase.get("name") or "",
                    outcome=outcome,
                    message=message,
                )
            )
    return cases


def one_line(text: str, limit: int = 300) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def markdown(totals: Totals, title: str, unreadable: list[str]) -> str:
    lines = [
        f"### {title}",
        "",
        f"{totals.count('passed')} passed, {totals.count('failed')} failed, "
        f"{totals.count('skipped')} skipped",
        "",
    ]
    for outcome, heading in (("failed", "Failed tests"), ("skipped", "Skipped tests")):
        cases = [case for case in totals.cases if case.outcome == outcome]
        if not cases:
            continue
        lines += [f"#### {heading}", "", "| Test | Report | Message |", "| --- | --- | --- |"]
        for case in cases:
            message = one_line(case.message).replace("|", "\\|")
            lines.append(f"| `{case.suite}/{case.name}` | {case.report} | {message} |")
        lines.append("")
    for path in unreadable:
        lines.append(f"- could not read `{path}`")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results_dir", nargs="?", default="test-results")
    parser.add_argument("--title", default="XCTest results")
    parser.add_argument(
        "--fail-on-skip-matching",
        action="append",
        default=[],
        metavar="TEXT",
        help="exit non-zero if any test was skipped with a message containing TEXT",
    )
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    reports = sorted(results_dir.rglob("*.xml")) if results_dir.is_dir() else []
    totals, unreadable = Totals(), []
    for report in reports:
        try:
            totals.cases.extend(parse_report(report))
        except (ET.ParseError, OSError):
            unreadable.append(str(report))

    summary = markdown(totals, args.title, unreadable)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(summary)
    else:
        sys.stdout.write(summary)

    if os.environ.get("GITHUB_ACTIONS") == "true":
        for case in totals.cases:
            if case.outcome == "failed":
                print(f"::error title={case.suite}/{case.name}::{one_line(case.message, 900)}")

    status = 0
    if not reports:
        print(f"junit-report: no JUnit reports under {results_dir}", file=sys.stderr)
    for needle in args.fail_on_skip_matching:
        offenders = [
            case for case in totals.cases if case.outcome == "skipped" and needle in case.message
        ]
        for case in offenders:
            print(
                f"junit-report: {case.suite}/{case.name} skipped ({one_line(case.message)}) "
                f"but this lane provides {needle}",
                file=sys.stderr,
            )
        if offenders:
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
