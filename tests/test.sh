#!/usr/bin/env sh
echo "running posix shell tests"

printf "parameter expansion\n"
var="hello world"
echo "${var}"
echo "${var%world}"

printf "if check\n"
if [ 1 -eq 1 ]; then echo "if: ok"; else echo "if: fail"; fi

printf "for loop\n"
for i in 1 2 3; do printf "%s " "$i"; done
echo ""

printf "functions\n"
fn() { echo "func: $1"; }
fn "ok"

echo "shell-posix-ok"
