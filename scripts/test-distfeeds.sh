#!/usr/bin/env bash
#
# Tests for scripts/distfeeds-config.sh, scripts/merge-config-fragment.sh and
# scripts/check-distfeeds.sh.
#
# The check-distfeeds.sh cases that need a real HTTP 200/404 answer from
# downloads.immortalwrt.org are skipped when SKIP_NETWORK_TESTS=1.
#
# Usage: bash scripts/test-distfeeds.sh

set -Eeuo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

# fake_tree <name> <feeds...>: a tree whose scripts/feeds lists <feeds>.
fake_tree() {
	local tree="$work/$1"
	shift
	mkdir -p "$tree/scripts"
	printf '#!/bin/sh\n[ "$*" = "list -n" ] || exit 9\necho "%s"\n' "$*" > "$tree/scripts/feeds"
	chmod +x "$tree/scripts/feeds"
	echo "$tree"
}

# --- distfeeds-config.sh ----------------------------------------------------

tree="$(fake_tree good packages luci routing telephony video app_airoha \
	openwrt_bandix luci_app_bandix helloworld vantage)"
want='CONFIG_FEED_video=m
CONFIG_FEED_app_airoha=m
CONFIG_FEED_openwrt_bandix=m
CONFIG_FEED_luci_app_bandix=m
CONFIG_FEED_helloworld=m
CONFIG_FEED_vantage=m'
if got="$(bash "$scripts/distfeeds-config.sh" "$tree")"; then
	[[ "$got" == "$want" ]] || fail "distfeeds-config: unexpected output:"$'\n'"$got"
	n="$(grep -c '=m$' <<< "$got" || true)"
	[[ "$n" == 6 ]] || fail "distfeeds-config: expected 6 =m lines, got $n"
else
	fail "distfeeds-config: failed on a valid tree"
fi

got="$(DISTFEEDS_HOSTED="packages luci routing telephony video" \
	bash "$scripts/distfeeds-config.sh" "$tree")" || fail "distfeeds-config: DISTFEEDS_HOSTED override failed"
grep -q 'FEED_video=' <<< "$got" && fail "distfeeds-config: DISTFEEDS_HOSTED override ignored"

tree="$(fake_tree bad packages 'bad-name' vantage)"
if out="$(bash "$scripts/distfeeds-config.sh" "$tree" 2>/dev/null)"; then
	fail "distfeeds-config: accepted an invalid feed name"
fi
[[ -z "${out:-}" ]] || fail "distfeeds-config: printed a partial fragment for an invalid name"

if DISTFEEDS_HOSTED='packages lu$ci' bash "$scripts/distfeeds-config.sh" "$work/good" >/dev/null 2>&1; then
	fail "distfeeds-config: accepted an invalid DISTFEEDS_HOSTED name"
fi

mkdir -p "$work/broken/scripts"
printf '#!/bin/sh\nexit 3\n' > "$work/broken/scripts/feeds"
chmod +x "$work/broken/scripts/feeds"
if bash "$scripts/distfeeds-config.sh" "$work/broken" >/dev/null 2>&1; then
	fail "distfeeds-config: ignored a failing scripts/feeds"
fi

# --- merge-config-fragment.sh -----------------------------------------------

# merge_case <label> <config> <fragment> <expected>
merge_case() {
	local label="$1"
	printf '%s\n' "$2" > "$work/merge.config"
	printf '%s\n' "$3" > "$work/merge.frag"
	if ! bash "$scripts/merge-config-fragment.sh" "$work/merge.frag" "$work/merge.config"; then
		fail "merge ($label): script failed"
		return
	fi
	[[ "$(cat "$work/merge.config")" == "$4" ]] ||
		fail "merge ($label): unexpected result:"$'\n'"$(cat "$work/merge.config")"
}

merge_case "=m overrides =y" \
'CONFIG_PER_FEED_REPO=y
CONFIG_FEED_vantage=y
CONFIG_FEED_packages=y' \
'CONFIG_FEED_vantage=m' \
'CONFIG_PER_FEED_REPO=y
CONFIG_FEED_packages=y
CONFIG_FEED_vantage=m'

merge_case "=m overrides is not set" \
'CONFIG_PER_FEED_REPO=y
# CONFIG_FEED_vantage is not set' \
'CONFIG_FEED_vantage=m' \
'CONFIG_PER_FEED_REPO=y
CONFIG_FEED_vantage=m'

merge_case "existing =y and is not set options" \
'# Automatically generated file; DO NOT EDIT.
CONFIG_KERNEL_DEBUG_INFO_REDUCED=y
# CONFIG_KERNEL_NETKIT is not set
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
CONFIG_VERSION_REPO="https://example.invalid/snapshots"
CONFIG_PACKAGE_keep=m' \
'# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_NETKIT=y
# CONFIG_PACKAGE_vlmcsd is not set
# CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn is not set
CONFIG_VERSION_REPO="https://downloads.immortalwrt.org/snapshots"' \
'# Automatically generated file; DO NOT EDIT.
CONFIG_PACKAGE_keep=m
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_NETKIT=y
# CONFIG_PACKAGE_vlmcsd is not set
# CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn is not set
CONFIG_VERSION_REPO="https://downloads.immortalwrt.org/snapshots"'

merge_case "last fragment setting wins" \
'CONFIG_FEED_easytier=y' \
'# CONFIG_FEED_easytier is not set
CONFIG_PACKAGE_jq=y
CONFIG_FEED_easytier=m' \
'CONFIG_PACKAGE_jq=y
CONFIG_FEED_easytier=m'

# --- check-distfeeds.sh -----------------------------------------------------

base_url="https://downloads.immortalwrt.org/snapshots/packages/aarch64_cortex-a53"

# rootfs <name> <distfeeds.list content>
rootfs() {
	local dir="$work/$1"
	mkdir -p "$dir/etc/apk/repositories.d"
	printf '%s\n' "$2" > "$dir/etc/apk/repositories.d/distfeeds.list"
	echo "$dir"
}

check() {
	bash "$scripts/check-distfeeds.sh" "$@" > "$work/check.log" 2>&1
}

mkdir -p "$work/nolist"
check "$work/nolist" && fail "check-distfeeds: passed without distfeeds.list"

dir="$(rootfs placeholder "%U/packages/%A/base/packages.adb")"
check "$dir" && fail "check-distfeeds: passed with an unexpanded placeholder"
grep -q 'unexpanded placeholder' "$work/check.log" ||
	fail "check-distfeeds: no placeholder message"

if [[ "${SKIP_NETWORK_TESTS:-0}" != 1 ]]; then
	dir="$(rootfs ok "# This file is auto-generated and build-specific.
$base_url/packages/packages.adb")"
	check "$dir" || { fail "check-distfeeds: hosted feed failed"; cat "$work/check.log" >&2; }

	dir="$(rootfs bad "$base_url/packages/packages.adb
$base_url/vantage/packages.adb")"
	check "$dir" && fail "check-distfeeds: unhosted enabled feed passed"
	grep -q '::error::.*vantage.*404' "$work/check.log" ||
		fail "check-distfeeds: no 404 error for vantage"

	dir="$(rootfs commented "$base_url/packages/packages.adb
# $base_url/vantage/packages.adb")"
	check "$dir" || { fail "check-distfeeds: commented unhosted feed failed"; cat "$work/check.log" >&2; }

	dir="$(rootfs disabled-hosted "$base_url/packages/packages.adb
# $base_url/luci/packages.adb")"
	check "$dir" || fail "check-distfeeds: commented hosted feed failed"
	grep -q '::warning::.*DISTFEEDS_HOSTED' "$work/check.log" ||
		fail "check-distfeeds: no warning for a hosted but disabled feed"

	# One good rootfs does not hide a missing list in another.
	check "$work/ok" "$work/nolist" && fail "check-distfeeds: second rootfs ignored"
else
	echo "skipping network cases (SKIP_NETWORK_TESTS=1)"
fi

if (( failures > 0 )); then
	echo "$failures test(s) failed" >&2
	exit 1
fi
echo "all distfeeds tests passed"
