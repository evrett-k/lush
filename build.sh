#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
VERSION="0.1.0"
DIST="dist"

# ... (Previous code remains identical) ...

# 1. Update the ALL_TARGETS list to be empty or removed, 
# as your CI now manages the targets explicitly via the CI workflow.
# Alternatively, modify the script to NOT default to ALL_TARGETS.

TARGETS=("$@")

# If no arguments provided, we do nothing instead of running everything.
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "No targets specified. Usage: ./build.sh <target1> <target2> ..."
    exit 0
fi

SUCCESSES=()
FAILURES=()

for target in "${TARGETS[@]}"; do
    fn="${target//-/_}"
    if declare -f "$fn" >/dev/null; then
        if (set -e; "$fn"); then
            SUCCESSES+=("$target")
        else
            FAILURES+=("$target")
        fi
    else
        warn "unknown target: $target"
        FAILURES+=("$target")
    fi
done
# ... (rest of the script)
