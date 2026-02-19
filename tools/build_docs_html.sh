#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_root="${1:-$repo_root/build/docs}"

if ! command -v pandoc >/dev/null 2>&1; then
  echo "build_docs_html: pandoc not found in PATH" >&2
  exit 1
fi

rm -rf "$out_root"
mkdir -p "$out_root"

cat > "$out_root/style.css" <<'CSS'
body {
  margin: 0 auto;
  padding: 2rem 1rem 3rem;
  max-width: 980px;
  font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
  line-height: 1.55;
  color: #202225;
  background: #f8f9fb;
}

main {
  background: #ffffff;
  border: 1px solid #e6e8ef;
  border-radius: 10px;
  padding: 2rem 2.25rem;
  box-shadow: 0 2px 8px rgba(20, 24, 36, 0.04);
}

h1, h2, h3 {
  color: #1a2a44;
}

a {
  color: #0a58ca;
  text-decoration: none;
}

a:hover {
  text-decoration: underline;
}

code {
  background: #f1f3f8;
  padding: 0.1rem 0.3rem;
  border-radius: 4px;
}

pre code {
  display: block;
  padding: 0.9rem;
  overflow-x: auto;
}

table {
  border-collapse: collapse;
  width: 100%;
}

th, td {
  border: 1px solid #d9deea;
  padding: 0.45rem 0.6rem;
  text-align: left;
}
CSS

md_files=()
while IFS= read -r file; do
  md_files+=("${file#"$repo_root/"}")
done < <(find "$repo_root/docs" -maxdepth 1 -type f -name '*.md' | sort)

md_files+=(README.md V1_SPEC.md examples/tech_demo/README.md examples/basic_app/README.md)

for rel in "${md_files[@]}"; do
  src="$repo_root/$rel"
  [[ -f "$src" ]] || continue

  dst="$out_root/${rel%.md}.html"
  mkdir -p "$(dirname "$dst")"

  depth="$(awk -F'/' '{print NF-1}' <<<"${rel%.md}")"
  css_rel="style.css"
  if [[ "$depth" -gt 0 ]]; then
    css_rel="$(printf '../%.0s' $(seq 1 "$depth"))style.css"
  fi

  pandoc "$src" \
    --from=gfm \
    --to=html5 \
    --standalone \
    --css "$css_rel" \
    --metadata title="Arlen Docs - ${rel%.md}" \
    --output "$dst"

  sed -i 's/\.md"/.html"/g' "$dst"
  sed -i 's/\.md#/.html#/g' "$dst"
  sed -i 's|<body>|<body><main>|' "$dst"
  sed -i 's|</body>|</main></body>|' "$dst"
done

if [[ -f "$out_root/README.html" ]]; then
  cp "$out_root/README.html" "$out_root/index.html"
fi

echo "Docs HTML generated at: $out_root"
