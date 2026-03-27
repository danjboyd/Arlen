#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

make -C "$repo_root" phase20-sql-builder-tests
make -C "$repo_root" phase20-schema-tests
make -C "$repo_root" phase20-routing-tests
make -C "$repo_root" phase20-postgres-live-tests
make -C "$repo_root" phase20-mssql-live-tests
