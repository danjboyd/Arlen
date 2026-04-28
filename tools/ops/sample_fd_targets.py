#!/usr/bin/env python3
"""Sample Linux process file-descriptor targets for Arlen operator triage."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def parse_limits(pid: int) -> dict[str, int | None]:
    limits_path = Path(f"/proc/{pid}/limits")
    soft: int | None = None
    hard: int | None = None
    try:
        lines = limits_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return {"soft_open_files": None, "hard_open_files": None}
    for line in lines:
        if not line.startswith("Max open files"):
            continue
        parts = line.split()
        if len(parts) >= 5:
            soft = None if parts[3] == "unlimited" else int(parts[3])
            hard = None if parts[4] == "unlimited" else int(parts[4])
        break
    return {"soft_open_files": soft, "hard_open_files": hard}


def sample_pid(pid: int, top: int) -> dict[str, Any]:
    fd_dir = Path(f"/proc/{pid}/fd")
    targets: dict[str, int] = {}
    total = 0
    unreadable = 0
    for entry in fd_dir.iterdir():
        total += 1
        try:
            target = os.readlink(entry)
        except OSError:
            unreadable += 1
            target = "<unreadable>"
        targets[target] = targets.get(target, 0) + 1

    socket_count = sum(count for target, count in targets.items() if target.startswith("socket:"))
    pipe_count = sum(count for target, count in targets.items() if target.startswith("pipe:"))
    anon_count = sum(count for target, count in targets.items() if target.startswith("anon_inode:"))
    dev_null_count = targets.get("/dev/null", 0)
    regular_count = total - socket_count - pipe_count - anon_count - unreadable
    limits = parse_limits(pid)
    soft = limits["soft_open_files"]
    soft_usage_ratio = None
    remaining_soft = None
    if isinstance(soft, int) and soft > 0:
        soft_usage_ratio = total / soft
        remaining_soft = soft - total

    return {
        "pid": pid,
        "total_fds": total,
        "dev_null_fds": dev_null_count,
        "socket_fds": socket_count,
        "pipe_fds": pipe_count,
        "anon_inode_fds": anon_count,
        "regular_file_fds": regular_count,
        "unreadable_fds": unreadable,
        "soft_open_files": soft,
        "hard_open_files": limits["hard_open_files"],
        "remaining_soft_open_files": remaining_soft,
        "soft_usage_ratio": soft_usage_ratio,
        "top_targets": [
            {"target": target, "count": count}
            for target, count in sorted(targets.items(), key=lambda item: (-item[1], item[0]))[:top]
        ],
    }


def pgrep(pattern: str) -> list[int]:
    try:
        output = subprocess.check_output(["pgrep", "-f", pattern], text=True)
    except subprocess.CalledProcessError:
        return []
    pids: list[int] = []
    for line in output.splitlines():
        line = line.strip()
        if line.isdigit():
            pids.append(int(line))
    return pids


def status_for(samples: list[dict[str, Any]], warn_ratio: float, warn_remaining: int) -> str:
    status = "ok"
    for sample in samples:
        ratio = sample.get("soft_usage_ratio")
        remaining = sample.get("remaining_soft_open_files")
        dev_null = int(sample.get("dev_null_fds") or 0)
        if isinstance(ratio, float) and ratio >= warn_ratio:
            status = "warning"
        if isinstance(remaining, int) and remaining <= warn_remaining:
            status = "warning"
        if dev_null >= 100:
            status = "warning"
    return status


def print_text(payload: dict[str, Any]) -> None:
    print(f"status={payload['status']} pids={','.join(str(pid) for pid in payload['pids'])}")
    for sample in payload["samples"]:
        ratio = sample["soft_usage_ratio"]
        ratio_text = "n/a" if ratio is None else f"{ratio:.3f}"
        print(
            "pid={pid} total={total_fds} dev_null={dev_null_fds} sockets={socket_fds} "
            "regular={regular_file_fds} soft={soft_open_files} remaining={remaining_soft_open_files} "
            "usage={ratio}".format(**sample, ratio=ratio_text)
        )
        for target in sample["top_targets"]:
            print(f"  {target['count']:>5} {target['target']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", action="append", type=int, default=[], help="PID to sample")
    parser.add_argument("--pgrep", help="pgrep -f pattern used to discover PIDs")
    parser.add_argument("--top", type=int, default=12, help="top FD targets to include")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")
    parser.add_argument("--warn-ratio", type=float, default=0.85, help="soft-limit usage warning ratio")
    parser.add_argument(
        "--warn-remaining",
        type=int,
        default=128,
        help="remaining soft-limit descriptors warning threshold",
    )
    args = parser.parse_args()

    pids = list(args.pid)
    if args.pgrep:
        pids.extend(pgrep(args.pgrep))
    pids = sorted(set(pids))
    samples = []
    for pid in pids:
        try:
            samples.append(sample_pid(pid, args.top))
        except OSError as exc:
            samples.append({"pid": pid, "error": str(exc)})
    payload = {
        "schema": "arlen-fd-target-sample-v1",
        "status": status_for([item for item in samples if "error" not in item], args.warn_ratio, args.warn_remaining),
        "pids": pids,
        "samples": samples,
    }
    if args.json:
        json.dump(payload, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        print_text(payload)
    return 0 if payload["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
