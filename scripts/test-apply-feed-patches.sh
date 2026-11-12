#!/usr/bin/env bash
#
# Tests for scripts/apply-feed-patches.sh.
#
# Each case builds a throwaway repository root containing a copy of the script,
# a git-tracked feed under feeds/demo and patches under patches/feeds/demo,
# then runs the script and checks the result.
#
# Usage: bash scripts/test-apply-feed-patches.sh

set -Eeuo pipefail

script_src="$(cd "$(dirname "$0")" && pwd)/apply-feed-patches.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

# new_root <name>: create a root with the script and an empty "demo" feed.
new_root() {
	local root="$work/$1"
	mkdir -p "$root/scripts" "$root/feeds/demo" "$root/patches/feeds/demo"
	cp "$script_src" "$root/scripts/"
	git -C "$root/feeds/demo" init -q
	echo "$root"
}

commit_feed() {
	git -C "$1/feeds/demo" add -A
	git -C "$1/feeds/demo" -c user.name=t -c user.email=t@t commit -qm base
}

run() {
	bash "$1/scripts/apply-feed-patches.sh"
}

expect_content() {
	local file="$1" want="$2" label="$3"
	if [[ "$(cat "$file")" != "$want" ]]; then
		fail "$label: unexpected content of $file:"
		sed 's/^/    /' "$file" >&2
	fi
}

# An append-at-end-of-file patch whose added block ends with the same lines as
# its leading context. After one application the context matches again at the
# new end of file, so a forward `git apply --check` passes forever.
append_patch() {
	cat <<'EOF'
--- a/conf
+++ b/conf
@@ -2,3 +2,8 @@ section a
 	opt x
 	opt y
 	opt z
+
+section b
+	opt x
+	opt y
+	opt z
EOF
}
conf_base=$'section a\n\topt x\n\topt y\n\topt z'
conf_patched=$'section a\n\topt x\n\topt y\n\topt z\n\nsection b\n\topt x\n\topt y\n\topt z'

test_append_with_repeated_tail_is_applied_once() {
	local root
	root="$(new_root repeated-tail)"
	printf '%s\n' "$conf_base" > "$root/feeds/demo/conf"
	commit_feed "$root"
	append_patch > "$root/patches/feeds/demo/100-append.patch"

	run "$root" > /dev/null
	run "$root" > /dev/null
	run "$root" > /dev/null
	expect_content "$root/feeds/demo/conf" "$conf_patched" "repeated-tail"
}

# A work tree left with the block appended several times (what the old
# forward-first script produced) is repaired.
test_corrupted_work_tree_is_repaired() {
	local root
	root="$(new_root repair)"
	printf '%s\n' "$conf_base" > "$root/feeds/demo/conf"
	commit_feed "$root"
	append_patch > "$root/patches/feeds/demo/100-append.patch"
	printf '%s\n%s\n' "$conf_patched" $'\nsection b\n\topt x\n\topt y\n\topt z' > "$root/feeds/demo/conf"

	run "$root" > /dev/null
	expect_content "$root/feeds/demo/conf" "$conf_patched" "repair"
}

# A pure deletion passes `git apply --reverse --check` on the unpatched file,
# because the reverse hunk's context is still there. It must still be applied.
test_pure_deletion_is_applied_on_fresh_feed() {
	local root
	root="$(new_root deletion)"
	# Like the LuCI menu JSON: the deleted entry ends with the same lines as
	# the entry before it, so the reverse hunk finds its context in place.
	printf 'a\n\tx\n},\n\n"plugins": {\n\tx\n},\n\n"startup": {\n' > "$root/feeds/demo/menu"
	commit_feed "$root"
	printf '%s\n' '--- a/menu' '+++ b/menu' '@@ -2,8 +2,4 @@' $' \tx' ' },' ' ' \
		'-"plugins": {' $'-\tx' '-},' '-' ' "startup": {' \
		> "$root/patches/feeds/demo/100-delete.patch"
	# Sanity: this fixture really is ambiguous for the --check heuristic.
	git -C "$root/feeds/demo" apply --reverse --check < "$root/patches/feeds/demo/100-delete.patch" 2>/dev/null ||
		fail "deletion: fixture is not ambiguous for --reverse --check"

	run "$root" > /dev/null
	expect_content "$root/feeds/demo/menu" $'a\n\tx\n},\n\n"startup": {' "deletion"
}

test_plain_patch_applies_then_is_left_alone() {
	local root out before after
	root="$(new_root plain)"
	printf 'one\ntwo\nthree\n' > "$root/feeds/demo/file"
	commit_feed "$root"
	cat > "$root/patches/feeds/demo/100-plain.patch" <<'EOF'
--- a/file
+++ b/file
@@ -1,3 +1,3 @@
 one
-two
+TWO
 three
EOF
	out="$(run "$root")"
	[[ "$out" == *"1 files updated, 0 already up to date"* ]] || fail "plain: first run: $out"
	expect_content "$root/feeds/demo/file" $'one\nTWO\nthree' "plain"

	# Second run must not touch the file, or every make would rebuild it.
	touch -t 200001010000 "$root/feeds/demo/file"
	before="$(ls -l -T "$root/feeds/demo/file" 2>/dev/null || ls -l --time-style=full-iso "$root/feeds/demo/file")"
	out="$(run "$root")"
	after="$(ls -l -T "$root/feeds/demo/file" 2>/dev/null || ls -l --time-style=full-iso "$root/feeds/demo/file")"
	[[ "$out" == *"0 files updated, 1 already up to date"* ]] || fail "plain: second run: $out"
	[[ "$before" == "$after" ]] || fail "plain: second run changed the file's mtime"
}

test_new_file_and_stacked_patches() {
	local root
	root="$(new_root stacked)"
	printf 'a\nb\nc\n' > "$root/feeds/demo/file"
	commit_feed "$root"
	cat > "$root/patches/feeds/demo/100-first.patch" <<'EOF'
--- a/file
+++ b/file
@@ -1,3 +1,3 @@
-a
+A
 b
 c
EOF
	cat > "$root/patches/feeds/demo/200-second.patch" <<'EOF'
--- a/file
+++ b/file
@@ -1,3 +1,3 @@
 A
 b
-c
+C
diff --git a/new/dir/added.txt b/new/dir/added.txt
new file mode 100755
--- /dev/null
+++ b/new/dir/added.txt
@@ -0,0 +1 @@
+hello
EOF
	run "$root" > /dev/null
	run "$root" > /dev/null
	expect_content "$root/feeds/demo/file" $'A\nb\nC' "stacked"
	expect_content "$root/feeds/demo/new/dir/added.txt" "hello" "new-file"
	[[ -x "$root/feeds/demo/new/dir/added.txt" ]] || fail "new-file: mode 100755 not applied"
}

test_conflicting_patch_fails() {
	local root
	root="$(new_root conflict)"
	printf 'one\ntwo\nthree\n' > "$root/feeds/demo/file"
	commit_feed "$root"
	cat > "$root/patches/feeds/demo/100-conflict.patch" <<'EOF'
--- a/file
+++ b/file
@@ -1,3 +1,3 @@
 one
-deux
+TWO
 three
EOF
	if run "$root" > /dev/null 2>&1; then
		fail "conflict: script succeeded on a patch that does not apply"
	fi
	expect_content "$root/feeds/demo/file" $'one\ntwo\nthree' "conflict"
}

test_absent_feed() {
	local root
	root="$(new_root absent)"
	mkdir -p "$root/patches/feeds/missing"
	printf -- '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' > "$root/patches/feeds/missing/100.patch"
	printf 'x\n' > "$root/feeds/demo/keep"
	commit_feed "$root"
	run "$root" > /dev/null 2>&1 || fail "absent: non-strict run failed"
	if FEED_PATCHES_STRICT=1 run "$root" > /dev/null 2>&1; then
		fail "absent: strict run succeeded"
	fi
}

test_append_with_repeated_tail_is_applied_once
test_corrupted_work_tree_is_repaired
test_pure_deletion_is_applied_on_fresh_feed
test_plain_patch_applies_then_is_left_alone
test_new_file_and_stacked_patches
test_conflicting_patch_fails
test_absent_feed

if ((failures)); then
	echo "$failures test(s) failed." >&2
	exit 1
fi
echo "All apply-feed-patches tests passed."
