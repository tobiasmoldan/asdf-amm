#!/usr/bin/env bash

set -euo pipefail

OWNER="com-lihaoyi"
REPO="Ammonite"
GH_REPO="https://github.com/$OWNER/$REPO"
TOOL_NAME="amm"
TOOL_TEST="amm --version"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

curl_opts=(-fsSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: Bearer $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

# Make a query to the GitHub API
gh_query() {
  local url_rest="$1"
  echo "$url_rest"
  curl "${curl_opts[@]}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$OWNER/$REPO/$url_rest" || fail "Could not curl $url_rest"
}

# Argument is the key whose value to get, JSON is gotten from stdin
get_str_value_from_json() {
  grep -oE "\"$1\": \"[^\"]*\"" | cut -d '"' -f 4
}

get_num_value_from_json() {
  grep -oE "\"$1\": [0-9][0-9]+" | cut -d ':' -f 2 | sed -E "s/(^ +)|\"//g" # Trim
}

# Get the tag names from a list of releases (or a single release) provided by
# the GitHub API. Reads from stdin.
tag_names() {
  get_str_value_from_json "tag_name"
}

list_github_tags() {
  gh_query "releases" | tag_names
}

get_release_id() {
  local tag="$1"
  gh_query "releases/tags/$tag" | get_num_value_from_json "id" | head -n 1
}

# Given a tag, list its scala-ammonite versions
list_assets() {
  local tag="$1"
  local id=$(get_release_id "$tag")
  gh_query "releases/$id/assets" | get_str_value_from_json "name" | cut -d '-' -f 1,2 | uniq
}

list_all_versions() {
  # While loop from https://superuser.com/a/284226
  while IFS= read -r tag || [[ -n $tag ]]; do
    list_assets "$tag"
  done < <(list_github_tags)
}

# The Ammonite version is <scala-version>-<ammonite tag>
tag_from_version() {
  cut -d "-" -f 2 <<< "$1"
}

download_release() {
  local version filename tag url
  version="$1"
  filename="$2"

  tag=$(tag_from_version "$version")
  url="$GH_REPO/releases/download/$tag/$version"

  echo "* Downloading $TOOL_NAME release $version..."
  curl "${curl_opts[@]}" \
      -H "Accept: application/octet-stream" \
      -o "$filename" -C - "$url" ||
    fail "Could not curl $url_rest"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="${3%/bin}/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

    [ -f /etc/resolv.conf ] || fail "$TOOL_NAME executable does not exist"
    chmod +x "$install_path/$TOOL_NAME-$version"

    local tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
    test -x "$install_path/$tool_cmd-$version" || fail "Expected $install_path/$tool_cmd-$version to be executable."

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}
