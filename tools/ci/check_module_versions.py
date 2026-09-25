#!/usr/bin/env python3
"""Require a module.plist version bump when a first-party module's files change.

Apps vendor modules and `arlen module upgrade` keys off the declared version,
so shipping changed module sources under an unchanged version leaves upgraded
apps on stale code (issue #54). This compares each `modules/<name>/` tree in
the working tree against the merge base with `--base` and fails when files
changed but the top-level `version` did not increase.
"""

import argparse
import os
import re
import subprocess
import sys


def git(repo_root, *args, check=True):
    result = subprocess.run(
        ["git", "-C", repo_root, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if check and result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result


def top_level_version(plist_text):
    """Return the top-level `version` of an OpenStep-style module.plist.

    Nested dictionaries and arrays (e.g. dependency constraints, which also use
    `version = ...`) are skipped by only keeping text at brace depth 1.
    """
    depth = 0
    in_string = False
    escaped = False
    kept = []
    for char in plist_text:
        if in_string:
            if depth == 1:
                kept.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            if depth == 1:
                kept.append(char)
        elif char in "{(":
            depth += 1
        elif char in "})":
            depth -= 1
        elif depth == 1:
            kept.append(char)
    match = re.search(r'(?:^|[;\s])version\s*=\s*"([^"]*)"', "".join(kept))
    return match.group(1) if match else None


def version_key(version):
    parts = re.findall(r"\d+", version or "")
    return tuple(int(part) for part in parts[:3]) + (0,) * (3 - min(len(parts), 3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--base",
        default=os.environ.get("ARLEN_MODULE_VERSION_BASE", ""),
        help="git ref to compare against (its merge base with HEAD is used)",
    )
    args = parser.parse_args()
    repo_root = os.path.abspath(args.repo_root)

    if not args.base or set(args.base) == {"0"}:
        print("module-versions: no --base ref given; skipping")
        return 0
    if git(repo_root, "rev-parse", "--verify", "--quiet", f"{args.base}^{{commit}}", check=False).returncode != 0:
        print(f"module-versions: base ref {args.base} is not available (fetch full history)", file=sys.stderr)
        return 2
    merge_base = git(repo_root, "merge-base", args.base, "HEAD").stdout.strip()

    changed = git(repo_root, "diff", "--name-only", merge_base, "--", "modules/").stdout.split()
    untracked = git(repo_root, "ls-files", "--others", "--exclude-standard", "--", "modules/").stdout.split()
    changed_by_module = {}
    for path in changed + untracked:
        parts = path.split("/")
        if len(parts) >= 3:
            changed_by_module.setdefault(parts[1], set()).add("/".join(parts[2:]))

    failures = []
    for module in sorted(changed_by_module):
        manifest = f"modules/{module}/module.plist"
        current_path = os.path.join(repo_root, manifest)
        if not os.path.exists(current_path):
            continue  # module removed
        base_manifest = git(repo_root, "show", f"{merge_base}:{manifest}", check=False)
        if base_manifest.returncode != 0:
            continue  # module added
        with open(current_path, encoding="utf-8") as handle:
            current_version = top_level_version(handle.read())
        base_version = top_level_version(base_manifest.stdout)
        if version_key(current_version) <= version_key(base_version):
            files = ", ".join(sorted(changed_by_module[module]))
            failures.append(
                f"modules/{module}: files changed ({files}) but version stayed "
                f"{current_version or '<missing>'} (was {base_version or '<missing>'})"
            )

    if failures:
        print("module-versions: bump `version` in module.plist for changed modules:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"module-versions: ok ({len(changed_by_module)} changed module(s) since {merge_base[:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
