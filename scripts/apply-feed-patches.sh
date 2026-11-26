#!/usr/bin/env bash
#
# Apply the feed patches kept under patches/feeds/.
#
# Layout: patches/feeds/<feed>/<path inside the feed>/NNN-name.patch
# e.g.    patches/feeds/luci/modules/luci-mod-network/htdocs/luci-static/
#             resources/view/network/102-align-switch-vlan-design-tokens.patch
#
# The directory mirroring the patched file is only a filing convention; the
# actual target paths live inside the patch and are relative to the feed's
# repository root.
#
# How it works, per feed:
#
#   1. Start a scratch index from the feed's HEAD and apply every patch of
#      that feed to it, in sorted order (`git apply --cached`). This yields the
#      exact content every touched file must have. A patch that does not apply
#      to HEAD is an error: the feed moved on and the patch needs a rebase.
#   2. Compare each touched file in the work tree with that expected content.
#      Files that already match are left alone, so their mtimes do not change
#      and no package is rebuilt for nothing. Files that differ are rewritten
#      (or removed, if the patch set deletes them).
#
# This is idempotent by construction and does not try to guess whether a patch
# "is applied" from `git apply --check` / `--reverse --check`. That guess is
# wrong both ways: an appended block whose tail repeats its leading context
# still passes the forward check after it was applied (it would be appended on
# every run), and a pure deletion passes the reverse check on an unpatched
# tree (it would never be applied). A work tree left in a bad state by an
# earlier tool is repaired on the next run.
#
# Files touched by the patch set are owned by this script: local edits to them
# in feeds/<feed> are overwritten. Keep such changes as patches instead.
#
# Run it after `./scripts/feeds update -a` / `install -a`; include/feed-patches.mk
# hooks it into every make invocation, so a normal build does this
# automatically.
#
# A feed that has not been fetched yet is skipped with a warning rather than
# treated as an error, because the patched package is not in the tree either.
# Set FEED_PATCHES_STRICT=1 to turn that into a failure.
#
# Patches are fed to git on stdin rather than by path: `git -C <feed> apply`
# resolves a path argument relative to the feed directory, and building an
# absolute one from $PWD is not portable ($PWD is an MSYS path under Git Bash
# on Windows, which the native git.exe cannot open).

set -Eeuo pipefail

# Resolve the repository root from this script's own location: the build hook
# calls us by absolute path, and everything below (patches/feeds, feeds/<feed>)
# is relative to the repository root.
cd "$(cd "$(dirname "$0")" && pwd)/.." || exit 1

if [[ ! -d patches/feeds ]]; then
	echo "No patches/feeds directory, nothing to apply."
	exit 0
fi

scratch_index="$(mktemp "${TMPDIR:-/tmp}/feed-patches-index.XXXXXX")"
trap 'rm -f -- "$scratch_index"' EXIT

total_updated=0
total_current=0
absent=0

# sync_feed <feed name>
sync_feed() {
	local feed_name="$1"
	local feed_dir="feeds/$feed_name"
	local patch_file path expected current mode sha
	local updated=0 current_ok=0 patches=0

	# A feed that has not been fetched yet is not a build error: the patched
	# package is not in the tree either, so there is nothing to patch. This
	# happens on a fresh checkout, where this script (a prerequisite of
	# prepare-tmpinfo) runs before prepare-tmpinfo's own recipe creates feeds/.
	# Fail loudly only when CI asks for strictness.
	if [[ ! -d "$feed_dir" ]]; then
		echo "Feed patches skipped, feed '$feed_name' is not present." >&2
		echo "  -> run './scripts/feeds update -a && ./scripts/feeds install -a' first" >&2
		if [[ "${FEED_PATCHES_STRICT:-0}" == "1" ]]; then
			exit 1
		fi
		absent=$((absent + 1))
		return 0
	fi

	if ! git -C "$feed_dir" rev-parse --verify -q HEAD > /dev/null; then
		echo "Feed '$feed_name' is not a git checkout with a HEAD commit; cannot patch it." >&2
		exit 1
	fi

	# Step 1: expected content = feed HEAD + all of this feed's patches.
	rm -f -- "$scratch_index"
	GIT_INDEX_FILE="$scratch_index" git -C "$feed_dir" read-tree HEAD
	while IFS= read -r -d '' patch_file; do
		if ! GIT_INDEX_FILE="$scratch_index" git -C "$feed_dir" apply --cached --whitespace=nowarn < "$patch_file"; then
			echo "Feed patch does not apply to $feed_dir HEAD: $patch_file" >&2
			echo "The feed moved on; rebase the patch before building." >&2
			exit 1
		fi
		patches=$((patches + 1))
	done < <(find "patches/feeds/$feed_name" -type f -name '*.patch' -print0 | LC_ALL=C sort -z)

	# Step 2: bring every touched file in the work tree to its expected content.
	while IFS= read -r -d '' path; do
		expected="$(GIT_INDEX_FILE="$scratch_index" git -C "$feed_dir" ls-files -s -- "$path")"

		if [[ -z "$expected" ]]; then
			# Deleted by the patch set.
			if [[ -e "$feed_dir/$path" || -L "$feed_dir/$path" ]]; then
				echo "Feed patch: removing $feed_dir/$path"
				rm -f -- "$feed_dir/$path"
				updated=$((updated + 1))
			else
				current_ok=$((current_ok + 1))
			fi
			continue
		fi

		mode="${expected%% *}"
		sha="${expected#* }"
		sha="${sha%% *}"
		if [[ "$mode" != "100644" && "$mode" != "100755" ]]; then
			echo "Feed patch result has unsupported mode $mode: $feed_dir/$path" >&2
			exit 1
		fi

		current=""
		if [[ -f "$feed_dir/$path" && ! -L "$feed_dir/$path" ]]; then
			current="$(git -C "$feed_dir" hash-object --no-filters -- "$path")"
		fi

		if [[ "$current" == "$sha" ]]; then
			current_ok=$((current_ok + 1))
			continue
		fi

		echo "Feed patch: updating $feed_dir/$path"
		mkdir -p -- "$(dirname -- "$feed_dir/$path")"
		rm -f -- "$feed_dir/$path"
		git -C "$feed_dir" cat-file blob "$sha" > "$feed_dir/$path"
		if [[ "$mode" == "100755" ]]; then
			# No "--": BSD chmod rejects it; the path starts with feeds/.
			chmod 755 "$feed_dir/$path"
		fi
		updated=$((updated + 1))
	done < <(GIT_INDEX_FILE="$scratch_index" git -C "$feed_dir" diff-index --cached --name-only -z HEAD)

	echo "Feed '$feed_name': $patches patches, $updated files updated, $current_ok already up to date."
	total_updated=$((total_updated + updated))
	total_current=$((total_current + current_ok))
}

while IFS= read -r -d '' feed_path; do
	sync_feed "${feed_path#patches/feeds/}"
done < <(find patches/feeds -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)

echo "Feed patches: $total_updated files updated, $total_current already up to date, $absent feeds absent."
