#!/bin/sh
# scripts/build_ext.sh
set -e
DIR="$(cd "$(dirname "$0")/../src/ext" && pwd)"
cc -c -o "$DIR/tty_syscall.o" "$DIR/tty_syscall.s"
