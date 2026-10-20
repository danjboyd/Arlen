#!/usr/bin/env bash

aln_platform_realpath() {
  local target="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$target" <<'PY'
import os
import sys
sys.stdout.reconfigure(newline="\n")  # Windows CLANG64 python would print CRLF
print(os.path.realpath(sys.argv[1]))
PY
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MCwd=realpath -e 'print realpath($ARGV[0]), "\n"' "$target"
    return $?
  fi
  (
    cd "$(dirname "$target")" >/dev/null 2>&1 && pwd -P
  ) | awk -v base="$(basename "$target")" '{ print $0 "/" base }'
}

aln_platform_is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

aln_platform_is_msys() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

# aln_platform_rename_over <source> <dest>
# rename(2) <source> onto <dest> without following <dest> when it is a symlink
# to a directory: GNU `mv -T`, BSD/macOS `mv -h`, else python3 os.replace.
aln_platform_rename_over() {
  local source="$1"
  local dest="$2"
  if mv --version 2>/dev/null | grep -q 'GNU coreutils'; then
    mv -fT "$source" "$dest"
    return
  fi
  case "$(uname -s)" in
    Darwin|*BSD|DragonFly)
      mv -fh "$source" "$dest"
      return
      ;;
  esac
  python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' "$source" "$dest"
}

# aln_platform_link_directory <target> <link>
# Points <link> at the directory <target>, replacing an existing link. On POSIX
# the new link is made under a temporary name and renamed over <link>, so
# <link> is never missing (`ln -sfn` unlinks first, which left releases/current
# absent for a moment during activation). Under MSYS2, `ln -s` copies the
# directory (real symlinks need admin rights or Developer Mode), and a later
# `ln -sfn` then links inside the copy, so release activation and rollback
# silently kept the old release. Use an NTFS junction there instead; MSYS2
# reports junctions as symlinks, so `readlink -f` and `[[ -L ]]` keep working.
aln_platform_link_directory() {
  local target="$1"
  local link="$2"
  if ! aln_platform_is_msys; then
    if [[ -d "$link" && ! -L "$link" ]]; then
      # A real directory: keep `ln -sfn` semantics (link created inside it).
      ln -sfn "$target" "$link"
      return
    fi
    local tmp_link
    tmp_link="$(dirname "$link")/.$(basename "$link").tmp.$$"
    rm -f "$tmp_link"
    ln -s "$target" "$tmp_link"
    if ! aln_platform_rename_over "$tmp_link" "$link"; then
      rm -f "$tmp_link"
      return 1
    fi
    return
  fi
  if [[ -L "$link" ]]; then
    # rmdir on a junction removes the link, never the target.
    MSYS2_ARG_CONV_EXCL="*" cmd /c rmdir "$(cygpath -w "$link")" >/dev/null 2>&1 || rm -f "$link"
  elif [[ -d "$link" ]]; then
    echo "aln_platform_link_directory: $link is a real directory, not a link" >&2
    return 1
  fi
  MSYS2_ARG_CONV_EXCL="*" cmd /c mklink /J "$(cygpath -w "$link")" "$(cygpath -w "$target")" >/dev/null
}

aln_platform_sha256() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | awk '{print $1}'
    return $?
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha256sum | awk '{print $1}'
    return $?
  fi
  return 1
}

aln_platform_brew_prefix() {
  local formula="$1"
  # Homebrew can fetch API metadata for `brew --prefix <formula>` when HOME has
  # no cache, even if the formula is already installed. Prefer the stable opt
  # link on macOS so a newly created account can build an app offline.
  if aln_platform_is_macos; then
    local homebrew_root
    for homebrew_root in /opt/homebrew /usr/local; do
      if [[ -d "$homebrew_root/opt/$formula" ]]; then
        printf '%s\n' "$homebrew_root/opt/$formula"
        return 0
      fi
    done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    return 1
  fi
  brew --prefix "$formula" 2>/dev/null
}

aln_platform_first_brew_prefix() {
  local formula
  for formula in "$@"; do
    if [[ -z "$formula" ]]; then
      continue
    fi
    if prefix="$(aln_platform_brew_prefix "$formula")" && [[ -n "$prefix" ]]; then
      printf '%s\n' "$prefix"
      return 0
    fi
  done
  return 1
}
