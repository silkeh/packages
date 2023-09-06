#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$(realpath "$0")")"
repos_dir="/tmp/repos"
repos_list="${repos_dir}/list.txt"
mono_dir="${repos_dir}/packages"

mkdir -p "${repos_dir}"

# Get a list of repos
if [ ! -e "${repos_list}" ]
then
    echo "Creating repo list. This may take a long time..."
    gh repo list solus-packages -L10000 --json name,isArchived,visibility | \
        jq -r '.[] | select(.isArchived == false) | select(.visibility == "PUBLIC") | .name' | \
        grep -Pv '^(.github|budgie-network-applet|libypkg|linux-next)$' | \
        sort > "${repos_list}"
fi

mapfile -t repos < "${repos_list}"

# if [ ! -e "${mono_dir}" ]
# then
    rm -rf "${mono_dir}"
    git clone https://github.com/getsolus/packages.git "${mono_dir}"
# fi

cd "${mono_dir}"

# Import common
bash "${script_dir}/import-single-repo.sh" \
     common "${repos_dir}/common" "${mono_dir}" \
     https://github.com/getsolus/common.git

# Import all
for package in "${repos[@]}"
do
    if [ ! -d "${package}" ]
    then
        while [ "$(jobs | wc -l)" -gt "$(nproc)" ]
        do
            sleep 0.25
        done

        bash "${script_dir}/import-single-repo.sh" \
             "${package}" "${repos_dir}/${package}" "${mono_dir}" \
             "https://github.com/solus-packages/${package}.git" &
    fi
done < "${repos_list}"

wait

echo Failed packages:
comm -13 <(sort "${repos_list}") <(sort "${mono_dir}/import-success")
