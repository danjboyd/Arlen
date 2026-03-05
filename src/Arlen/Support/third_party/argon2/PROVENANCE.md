# Argon2 Provenance

- Upstream repository: `https://github.com/P-H-C/phc-winner-argon2`
- Imported tag: `20190702`
- Imported commit: `62358ba2123abd17fccf2a108a301d4b52c01a7c`
- Import date: `2026-03-05`
- Imported files: reference `argon2id` library sources required for encoded hash/verify APIs
- Local build profile: reference path with `ARGON2_NO_THREADS=1` for deterministic GNUstep portability

Arlen vendors this source directly instead of using a submodule so framework builds and app-root `boomhauer` compiles stay self-contained.
