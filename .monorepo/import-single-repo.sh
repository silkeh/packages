#!/usr/bin/env bash
set -euo pipefail

exp="$(mktemp)"
package="$1"
dir="$2"
mono="$3"
orig="${dir}.orig"
repo="$4"

if [ ! -d "${orig}" ]
then
    git clone -q "${repo}" "${orig}"
fi

rm -rf "${dir}"
cp -a "${orig}" "${dir}"

cat > "${exp}" <<EOF
regex:^(?!${package}: )==>${package}:\040
EOF

v="$(git -C "${dir}" describe --tags --always)"
git -C "${dir}" filter-repo \
    --path-glob "*.eopkg" \
    --path-glob "*/log.txt" \
    --path-glob "*.tar.*" \
    --path-glob "*/download.1" \
    --invert-paths \
    --to-subdirectory-filter "${package}" \
    --replace-message "${exp}"

(
    flock 9 || exit 1
    git -C "${mono}" remote add "${package}" "${dir}"
    git -C "${mono}" fetch "${package}" master --no-tags --no-auto-gc
    git -C "${mono}" merge "${package}/master" --no-edit --allow-unrelated-histories \
        -m "Merge '${package}' from tag '${v}'"
    git -C "${mono}" remote remove "${package}"
) 9>"${mono}/.lock"

rm -f "${exp}"

echo "${package}" >> "${mono}/import-success"
