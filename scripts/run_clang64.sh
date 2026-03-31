#!/usr/bin/env sh
set -eu

GNUSTEP_SH=/clang64/share/GNUstep/Makefiles/GNUstep.sh

export MSYSTEM=CLANG64
export CHERE_INVOKING=1
export PATH=/clang64/bin:/usr/bin:$PATH
export CC=clang
export CXX=clang++
export GNUSTEP_CONFIG_FILE=/clang64/etc/GNUstep/GNUstep.conf
export GNUSTEP_MAKEFILES=/clang64/share/GNUstep/Makefiles
export GNUSTEP_SYSTEM_ROOT=/clang64

if [ ! -f "$GNUSTEP_SH" ]; then
  echo "run_clang64.sh: GNUstep.sh not found at $GNUSTEP_SH" >&2
  exit 1
fi

: "${ZSH_VERSION:=}"
. "$GNUSTEP_SH"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec "${SHELL:-/usr/bin/bash}" -l
