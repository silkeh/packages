#!/usr/bin/env bash
set -euo pipefail

package="$1"
dir="$(mktemp -d)"
exp="$(mktemp)"

if find ./* -type d -name "${package}" | grep -q .
then
    exit 0
fi

git clone -q "https://github.com/solus-packages/${package}.git" "${dir}"

pushd "${dir}"

case "${package}" in
    budgie-network-applet|libypkg|linux-next)
        component=skip
        ;;
    burn-my-windows)
        component=desktop
        ;;
    font-firago|font-ibm-plex|font-weather-icons)
        component=desktop.font
        ;;
    yaru-theme)
        component=desktop.theme
        ;;
    kid3)
        component=multimedia.audio
        ;;
esac

if [ -z "${component+x}" ]
then
    if [ -e package.yml ]
    then
        component="$(yq .component package.yml)"
        if [[ "${component}" == "- "* ]]
        then
            component="$(yq .component[0] package.yml)"
        fi

        if [[ "${component}" == *:* ]]
        then
            read -rp "Component for ${package} or 'skip': " component
        fi
    elif [ -e component.xml ]
    then
        component="$(xq component.xml -e '//Name')"
    else
        read -rp "Component for ${package} or 'skip': " component
    fi
fi

if [ "${component}" = "skip" ]
then
    exit 0
fi

ref="$(git -C "${dir}" rev-parse HEAD)"
tree="${component/./\/}/${package}"

cat > "${exp}" <<EOF
regex:^(?!${package}: )==>${package}:\040
EOF

git filter-repo \
    --to-subdirectory-filter "${tree}" \
    --replace-message "${exp}"

popd

if [ -d "${tree}" ]
then
    exit 0
fi

git remote add "${package}" "${dir}"
git fetch -q "${package}"
git merge -q \
    --no-edit \
    --allow-unrelated-histories "${package}/master" \
    -m "Add '${package}' from commit '${ref}'"
git remote remove "${package}"

if git tag | grep -q "^${package}"
then
    git tag -d $(git tag | grep "^${package}")
fi

rm -rf "${dir}" "${exp}"
