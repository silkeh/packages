#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 3 ]
then
    echo "Usage: $0 <package dir> <tag> <sign y/n>"
    exit 1
fi

src_dir="$1"
tag="$2"
sign="$3"

package="$(basename "${src_dir}")"
dir="$(mktemp -d)"
patch="$(mktemp)"
tag_args=(-m "Publish ${tag}" "${tag}")

if [ "${sign}" == "y" ]
then
    tag_args+=(-s)
fi

git format-patch --relative @~ --stdout > "${patch}"
git clone "git@github.com:solus-packages/${package}.git" "${dir}"

pushd "${dir}"

if git show-ref --quiet --tags "${tag}"
then
    echo "Tag already exists! Did you mean to call \`go-task republish\`?"
    exit 1
fi


git am "${patch}"
git push

git tag "${tag_args[@]}"
git push --follow-tags
