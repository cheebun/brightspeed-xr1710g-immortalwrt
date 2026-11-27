#!/usr/bin/env bash
#
# Tests for scripts/getver.sh, scripts/set-build-version.sh and
# scripts/fetch-upstream-base.sh.
#
# Builds throwaway git repos: a "base" repo standing in for
# cheebun/immortalwrt `base` and a fork repo with extra commits on top, then
# checks that the upstream commit both scripts report is the fork point on
# refs/remotes/base/base, and that a missing base ref gives "unknown" with a
# warning instead of an empty or misleading value.
#
# Usage: bash scripts/test-getver.sh

set -Eeuo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# Keep the user's git config (signing, hooks, default branch) out of the fakes.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset TOPDIR GITHUB_REPOSITORY_OWNER UPSTREAM_COMMIT REPO_COMMIT BUILD_ID \
	VERSION_NUMBER VERSION_CODE VERSION_DIST 2>/dev/null || true

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

# commit <repo> <n>: add <n> commits to <repo>.
commit() {
	local i
	for ((i = 0; i < $2; i++)); do
		echo "$RANDOM $i" >> "$1/file"
		git -C "$1" add file
		git -C "$1" commit -q -m "commit $i"
	done
}

short() { git -C "$1" log -n 1 --no-show-signature --format=%h "$2"; }

date_re='[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}'

# getver_case <label> <repo> <expected upstream part> <expected local part>
getver_case() {
	local out err
	if ! out="$(TOPDIR="$2" bash "$scripts/getver.sh" 2>"$work/getver.err")"; then
		fail "getver $1: exited non-zero"
	fi
	err="$(cat "$work/getver.err")"
	[[ "$out" =~ ^${date_re}-$3-$4$ ]] ||
		fail "getver $1: got '$out', want DATE-$3-$4"
	if [[ "$3" == unknown ]]; then
		[[ "$err" == *warning* ]] || fail "getver $1: no warning on stderr for unknown upstream"
	fi
}

# setver_case <label> <repo> <expected upstream (8 chars)> <expected local (8 chars)>
setver_case() {
	local out
	printf 'CONFIG_TARGET_BOARD="airoha"\nCONFIG_TARGET_SUBTARGET="an7581"\n' > "$work/setver.config"
	if ! out="$(cd "$2" && BUILD_DATE=20260101 REPO_OWNER=owner \
		bash "$scripts/set-build-version.sh" "$work/setver.config" 2>"$work/setver.err")"; then
		fail "set-build-version $1: exited non-zero"
		return
	fi
	grep -qxF "CONFIG_VERSION_CODE=\"20260101-$4-$3\"" "$work/setver.config" ||
		fail "set-build-version $1: got $(grep '^CONFIG_VERSION_CODE=' "$work/setver.config"), want 20260101-$4-$3"
	grep -qxF "Configured firmware revision: 20260101-$4-$3" <<< "$out" ||
		fail "set-build-version $1: unexpected summary: $out"
	if [[ "$3" == unknown ]]; then
		grep -q warning "$work/setver.err" || fail "set-build-version $1: no warning on stderr for unknown upstream"
	fi
}

# --- fixtures -----------------------------------------------------------------

base="$work/base"
git init -q -b base "$base"
commit "$base" 2
base_tip="$(git -C "$base" rev-parse HEAD)"

fork="$work/fork"
git clone -q "file://$base" "$fork"
git -C "$fork" remote rename origin base
git -C "$fork" checkout -q -b base-main
commit "$fork" 1
fork_tip="$(git -C "$fork" rev-parse HEAD)"

# --- full clone with refs/remotes/base/base -----------------------------------

getver_case "full clone" "$fork" "$(short "$fork" "$base_tip")" "$(short "$fork" "$fork_tip")"
setver_case "full clone" "$fork" "${base_tip:0:8}" "${fork_tip:0:8}"

# base moved on after the fork point: upstream is the merge-base, not the tip.
commit "$base" 1
git -C "$fork" fetch -q base
getver_case "base ahead" "$fork" "$(short "$fork" "$base_tip")" "$(short "$fork" "$fork_tip")"
setver_case "base ahead" "$fork" "${base_tip:0:8}" "${fork_tip:0:8}"

# --- no base ref: "unknown" plus a warning, never the local hash --------------

nobase="$work/nobase"
git clone -q "file://$fork" "$nobase"
getver_case "no base ref" "$nobase" unknown "$(short "$nobase" "$fork_tip")"
setver_case "no base ref" "$nobase" unknown "${fork_tip:0:8}"

# --- shallow CI checkout + fetch-upstream-base.sh -----------------------------

# CI checks out with depth 1; put the fork point more than one deepen step away.
commit "$fork" 20
fork_tip="$(git -C "$fork" rev-parse HEAD)"

shallow="$work/shallow"
git clone -q --depth 1 --no-single-branch "file://$fork" "$shallow"
# Without the helper the base ref is missing or unreachable: never a wrong hash.
getver_case "shallow, no fetch" "$shallow" unknown "$(short "$shallow" "$fork_tip")"

if [[ ! -f "$scripts/fetch-upstream-base.sh" ]]; then
	fail "fetch-upstream-base.sh: missing"
elif ! (cd "$shallow" && BASE_REMOTE_URL="file://$base" \
	bash "$scripts/fetch-upstream-base.sh" >"$work/fetch.log" 2>&1); then
	fail "fetch-upstream-base.sh: failed on a shallow clone: $(tail -n 3 "$work/fetch.log")"
else
	[[ "$(git -C "$shallow" rev-parse --verify -q refs/remotes/base/base)" == "$(git -C "$base" rev-parse HEAD)" ]] ||
		fail "fetch-upstream-base.sh: refs/remotes/base/base is not the base tip"
	getver_case "shallow + fetch" "$shallow" "$(short "$shallow" "$base_tip")" "$(short "$shallow" "$fork_tip")"
	setver_case "shallow + fetch" "$shallow" "${base_tip:0:8}" "${fork_tip:0:8}"
	# Running it again (remote already added) must still work.
	(cd "$shallow" && BASE_REMOTE_URL="file://$base" \
		bash "$scripts/fetch-upstream-base.sh" >/dev/null 2>&1) ||
		fail "fetch-upstream-base.sh: second run failed"
fi

# Unrelated history: the helper must fail loudly, not report success.
stranger="$work/stranger"
git init -q -b base "$stranger"
commit "$stranger" 1
if [[ -f "$scripts/fetch-upstream-base.sh" ]] &&
	(cd "$shallow" && BASE_REMOTE_URL="file://$stranger" BASE_MAX_DEEPEN=64 \
		bash "$scripts/fetch-upstream-base.sh" >/dev/null 2>&1); then
	fail "fetch-upstream-base.sh: succeeded without a common ancestor"
fi

if ((failures)); then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "All getver tests passed"
