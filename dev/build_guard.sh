#!/bin/sh
# Builds the crash guard. Copy the result to BOB2-Win11-Fix/dinput8.dll and
# to the dev install; Setup's crash-fix step deploys it from the package.
set -e
cd "$(dirname "$0")"
i686-w64-mingw32-gcc -shared -o dinput8.dll dinput8_guard.c -lkernel32 -luser32 -lole32 -Wl,--kill-at -O2 -Wall
ls -la dinput8.dll
