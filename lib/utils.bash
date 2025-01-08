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

# Make a query to the GitHub API
gh_query() {
	local url_rest="$1"
	curl "${curl_opts[@]}" \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"https://api.github.com/repos/$OWNER/$REPO/$url_rest" || fail "Could not curl $url_rest"
}

list_all_versions() {
	# The releases response also includes all the assets, so we can just use that
	# instead of querying the assets for each release separately
	gh_query "releases" |
		# Must not be an M0 version
		grep -oE '"name": "[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+"' |
		# Extract the asset names
		cut -d '"' -f 4 |
		uniq 
}

download_release() {
	local version filename tag url
	version="$1"
	filename="$2"

	# The Ammonite version is <Scala version>-<Ammonite tag>
	tag=$(cut -d "-" -f 2 <<<"$version")
	url="$GH_REPO/releases/download/$tag/$version"

	echo "* Downloading $TOOL_NAME release $version..."
	curl "${curl_opts[@]}" \
		-H "Accept: application/octet-stream" \
		-o "$filename" -C - "$url" ||
		fail "Could not curl $url"
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
		chmod +x "$install_path/$TOOL_NAME"

		local tool_cmd
		tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
		test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}
