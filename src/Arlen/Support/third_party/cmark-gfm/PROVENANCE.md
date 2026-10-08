# cmark-gfm Provenance

- Upstream repository: `https://github.com/github/cmark-gfm`
- Imported tag: `0.29.0.gfm.13`
- Imported commit: `587a12bb54d95ac37241377e6ddc93ea0e45439b`
- Import date: `2026-10-08`
- Imported files: everything in upstream `src/` except `main.c` (the CLI), the
  `*.in` templates, `*.re` re2c sources (their generated `scanners.c` and
  `ext_scanners.c` are imported) and `CMakeLists.txt`; everything in
  `extensions/` except `ext_scanners.re` and `CMakeLists.txt`; `COPYING` as
  `LICENSE`.

Local changes:

- Upstream's `src/` and `extensions/` are flattened into this one directory, so
  `extensions/*.c` include their `src/` headers with quotes instead of angle
  brackets (`#include "parser.h"` for `#include <parser.h>`). No other source
  line is changed, and no build path needs an extra include directory.
- `config.h`, `cmark-gfm_export.h` and `cmark-gfm_version.h` are written by
  hand in place of the files CMake generates. The library is compiled into the
  Arlen framework, so the export macros are empty.

Arlen vendors this source directly instead of using a submodule so framework
builds and app-root `boomhauer` compiles stay self-contained. Only
`src/Arlen/Support/ALNMarkdown.m` includes these headers; nothing public in
Arlen exposes cmark-gfm types.

To update: re-import the same file set from a new upstream tag, re-apply the
include rewrite above, update the version numbers in `cmark-gfm_version.h` and
`VERSION`, and run `make test-unit`.
