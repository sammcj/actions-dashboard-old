#!/usr/bin/env bash
set -euo pipefail

inputs=()
output=
output_file=${output_file:-dashboard.md}
temp_workflow=${temp_workflow:-tmp/workflow.yaml}

mkdir -p tmp/
touch tmp/output.md
touch $output_file

usage() {
    cat <<EOF
usage: ${0##*/} [-h] -o OUTFILE [-i FILE]...

    -h  display this help
    -i  input file path
    -o  output markdown file path
EOF
    exit 1
}

urlencode() {
    for ((i = 0; i < "${#1}"; i++)); do
        local c="${1:i:1}"
        case $c in
        [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
        *) printf '%%%02X' "'$c" ;;
        esac
    done
}

isurl() { [[ "$1" =~ https?://* ]]; }

writeout() { output="$output""$1"; }

parse_repo() {
    repo="https://github.com/$1"
    repotmp="$tmpd/$1"
    reponame=${repo##*/}
    writeout "${reponame}\n"
    rm -rf "$repotmp"
    git clone --bare "$repo" "$repotmp" 2>/dev/null

    count=0
    while read -r workflow; do
        # trap any errors and continue
        trap 'continue' ERR

        [[ "$workflow" != *.yaml ]] && [[ "$workflow" != *.yml ]] && continue
        curl --header "Authorization: token ${GITHUB_TOKEN}" "https://raw.githubusercontent.com/$1/main/${workflow}" -o "$temp_workflow"
        name=$(yq '.name' "$temp_workflow")
        [ -z "$name" ] && name="$workflow"
        encoded_name="$(urlencode "$name")"
        writeout " [![${name}](${repo}/workflows/${encoded_name}/badge.svg)]"
        writeout "(${repo}/actions?query=workflow:\"$encoded_name\")"
        count=$((count + 1))
    done < <(git -C "$repotmp" ls-tree -r HEAD | awk '{print $4}' | grep '^.github/workflows/')

    # reset trap
    trap - ERR

    [ $count -eq 0 ] && writeout "(none)"
    writeout "\n\n"
    echo " Generated markdown for $1"
    echo -e "$output" >tmp/output.md
    rm -rf "$temp_workflow"
}

[ "$#" -lt 4 ] && usage
command -v yq >/dev/null || {
    echo "Need yq"
    exit 1
}

OPTIND=1
while getopts ":ho:i:" opt; do
    case $opt in
    i)
        inputs+=("$OPTARG")
        ;;
    o)
        output_file="$OPTARG"
        ;;
    *)
        usage
        ;;
    esac
done

[[ "$output_file" != *.md ]] && output_file="$output_file".md

tmpd="$(mktemp -d -t dashboardXXXX)"

for i in "${inputs[@]}"; do
    # trap any errors and continue
    trap 'continue' ERR

    echo Generating markdown for "${i##*/}"...
    title=${i##*/}
    title=${title%.*}
    writeout "### ${title}\n\n"
    count=0
    while read -r line; do
        [[ "$line" = \#* ]] && continue
        [ -z "$line" ] && continue
        parse_repo "$line"
        count=$((count + 1))
    done < <(if isurl "$i"; then curl -sL "$i"; else cat "$i"; fi)
    [ $count -eq 0 ] && {
        echo "Failed to read $i"
        exit 1
    }
    writeout "---\n\n"
done
# reset trap
trap - ERR

echo -e "$output" >"$output_file"
echo "Wrote to ${output_file}"
rm -rf "$tmpd" tmp/
