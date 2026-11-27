#!/usr/bin/env bash
#
# Add/fetch remote `base` (cheebun/immortalwrt branch `base`) as
# refs/remotes/base/base so scripts/getver.sh and scripts/set-build-version.sh
# can report the upstream commit (the merge-base of HEAD and base).
#
# In a shallow checkout (CI uses actions/checkout depth 1) both HEAD and base
# are deepened step by step until the merge-base is reachable, so the full
# ImmortalWrt history is never downloaded. Fails if no merge-base is found
# within BASE_MAX_DEEPEN commits.
#
# Environment:
#   BASE_REMOTE_URL   default https://github.com/cheebun/immortalwrt.git
#   BASE_MAX_DEEPEN   maximum total deepen per side (default 2048)
#
# Usage: bash scripts/fetch-upstream-base.sh   (run from the build tree root)

set -euo pipefail

url="${BASE_REMOTE_URL:-https://github.com/cheebun/immortalwrt.git}"
max_deepen="${BASE_MAX_DEEPEN:-2048}"
ref="refs/remotes/base/base"
refspec="+refs/heads/base:$ref"

[[ "$max_deepen" =~ ^[1-9][0-9]*$ ]] || {
	echo "error: BASE_MAX_DEEPEN must be a positive integer, got '$max_deepen'" >&2
	exit 1
}

[ -z "${TOPDIR:-}" ] || cd "$TOPDIR"
git rev-parse --git-dir >/dev/null

if git remote get-url base >/dev/null 2>&1; then
	git remote set-url base "$url"
else
	git remote add base "$url"
fi

head="$(git rev-parse HEAD)"

have_merge_base() {
	git merge-base HEAD "$ref" >/dev/null 2>&1
}

if [ "$(git rev-parse --is-shallow-repository)" != true ]; then
	git fetch --no-tags base "$refspec"
else
	git fetch --no-tags --depth=1 base "$refspec"
	step=8
	total=0
	until have_merge_base; do
		if ((total >= max_deepen)); then
			echo "error: no merge-base between HEAD and $ref within $max_deepen commits of shallow history" >&2
			exit 1
		fi
		total=$((total + step))
		echo "Deepening HEAD and base by $step (total $total)"
		git fetch --no-tags -q --deepen="$step" origin "$head"
		git fetch --no-tags -q --deepen="$step" base "$refspec"
		step=$((step * 2))
	done
fi

if ! have_merge_base; then
	echo "error: no merge-base between HEAD and $ref" >&2
	exit 1
fi

echo "base: $(git rev-parse "$ref")"
echo "upstream commit (merge-base): $(git merge-base HEAD "$ref")"
