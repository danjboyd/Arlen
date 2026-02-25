#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "docs-quality: missing required tool: $tool" >&2
    exit 1
  fi
}

require_tool python3
require_tool pandoc
require_tool git

python3 ./tools/docs/generate_api_reference.py --repo-root "$repo_root"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git diff --quiet -- docs/API_REFERENCE.md docs/api; then
    echo "docs-quality: generated API reference docs are out of date" >&2
    echo "docs-quality: run 'make docs-api' and commit generated docs/API_REFERENCE.md + docs/api/* changes" >&2
    git --no-pager diff -- docs/API_REFERENCE.md docs/api >&2 || true
    exit 1
  fi
fi

bash ./tools/build_docs_html.sh

required_files=(
  "build/docs/index.html"
  "build/docs/docs/README.html"
  "build/docs/docs/API_REFERENCE.html"
)

for rel_path in "${required_files[@]}"; do
  if [[ ! -f "$repo_root/$rel_path" ]]; then
    echo "docs-quality: missing expected docs artifact: $rel_path" >&2
    exit 1
  fi
done

api_pages_count="$(find "$repo_root/build/docs/docs/api" -type f -name '*.html' | wc -l | tr -d ' ')"
if [[ -z "$api_pages_count" || "$api_pages_count" -lt 1 ]]; then
  echo "docs-quality: expected generated API HTML pages under build/docs/docs/api" >&2
  exit 1
fi

if ! grep -q 'docs/README.html' "$repo_root/build/docs/index.html"; then
  echo "docs-quality: build/docs/index.html does not link to docs/README.html" >&2
  exit 1
fi

if ! grep -q 'API_REFERENCE.html' "$repo_root/build/docs/docs/README.html"; then
  echo "docs-quality: docs/README rendered HTML missing API reference link" >&2
  exit 1
fi

echo "ci: docs quality gate complete"
