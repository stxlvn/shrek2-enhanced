#!/bin/sh
# Builds the engine layer (d3d8.dll) into ../build. Needs llvm-mingw (i686-w64-mingw32-clang) on PATH.
# Run it from Git Bash or another POSIX shell, not PowerShell: the comma in -Wl,--kill-at is mangled there.
set -e
cd "$(dirname "$0")"
mkdir -p ../build
i686-w64-mingw32-clang -O2 -shared -o ../build/d3d8.dll enhnative.c d3d8.def -Wl,--kill-at \
	-lkernel32 -luser32 -lgdi32 -ladvapi32 -lshell32 -lws2_32
echo "built ../build/d3d8.dll"
