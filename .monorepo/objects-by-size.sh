#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]
then
    echo "Usage: $0 <repo>"
    exit 1
fi

git -C "$1" rev-list --objects --all \
    | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
    | sed -n 's/^blob //p' \
    | sort --numeric-sort --key=2 \
    | grep -Pv '(.patch|/(abi_(used_)?symbols(32)?|pspec(_x86_64)?.xml))$' \
    | tail -n 100 \
    | cut -c 1-12,41- \
    | $(command -v gnumfmt || echo numfmt) --field=2 --to=iec-i --suffix=B --padding=7 --round=nearest
