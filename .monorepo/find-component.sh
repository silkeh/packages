#!/usr/bin/env bash
set -euo pipefail

package="$1"
dir="$2"
package_yml="${dir}/package.yml"
component_xml="${dir}/component.xml"
component=""

case "${package}" in
    calamares|budgie-network-applet|libypkg|linux-next|virtiofsd|xfce4-mixer|xfce4-taskmanager)
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

if [ -n "${component}" ]
then
    echo "${component}"
    exit
fi

if [ -e "${package_yml}" ]
then
    component="$(yq .component "${package_yml}")"
    if [[ "${component}" == "- "* ]]
    then
        component="$(yq .component[0] "${package_yml}")"
    fi
elif [ -e "${component_xml}" ]
then
        component="$(xq "${component_xml}" -e '//Name')"
fi

if [ -z "${component}" ]
then
    component="unknown"
fi


echo "${component}"
exit
