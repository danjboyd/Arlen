#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

make -C "$repo_root" phase21-template-tests
make -C "$repo_root" phase21-protocol-tests
make -C "$repo_root" phase21-generated-app-tests
