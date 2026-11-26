#!/usr/bin/env bash
#
# Check that the firmware ships the Vantage LuCI theme and no Argon.
#
# Usage:
#   bash scripts/check-luci-theme.sh --config <.config>
#        [--manifest <file>]... [--rootfs <dir>]...
#
#   --config    The top-level .config after `make defconfig` (required).
#   --manifest  An image package list, one package name per line (optionally
#               followed by whitespace and more fields).
#   --rootfs    A staged root filesystem (build_dir/.../target-dir-<id>).
#
# `make defconfig` silently drops symbols whose package is missing (for
# example when the vantage feed was not installed), so this checks the
# resolved .config and the built images, not the seed. Every failure is
# reported before exiting non-zero.

set -Eeuo pipefail

usage() {
	cat >&2 <<'EOF'
usage: check-luci-theme.sh --config <file> [--manifest <file> ...] [--rootfs <dir> ...]
EOF
	exit 2
}

config_file=""
manifests=()
rootfses=()

while (( $# > 0 )); do
	case "$1" in
		--config)
			(( $# >= 2 )) || usage
			config_file="$2"
			shift 2
			;;
		--manifest)
			(( $# >= 2 )) || usage
			manifests+=("$2")
			shift 2
			;;
		--rootfs)
			(( $# >= 2 )) || usage
			rootfses+=("$2")
			shift 2
			;;
		*)
			usage
			;;
	esac
done

[[ -n "$config_file" && -f "$config_file" ]] || usage
for manifest in ${manifests[@]+"${manifests[@]}"}; do
	[[ -f "$manifest" ]] || { echo "manifest not found: $manifest" >&2; exit 2; }
done
for rootfs in ${rootfses[@]+"${rootfses[@]}"}; do
	[[ -d "$rootfs" ]] || { echo "rootfs not found: $rootfs" >&2; exit 2; }
done

# Must be built into the image. The i18n packages are hidden and follow
# CONFIG_LUCI_LANG_zh_Hans.
required_packages=(
	luci-theme-vantage
	luci-i18n-vantage-theme-zh-cn
	luci-app-vantage
	luci-i18n-vantage-zh-cn
	luci-app-vantage-traffic
	luci-i18n-vantage-traffic-zh-cn
	luci-theme-bootstrap
)

# Neither in the image (=y) nor built (=m). Extended regex, whole name.
# luci-app-argon-config is the name luci-theme-argon provides; its
# translations are luci-i18n-argon-config-*.
forbidden_packages='(luci-theme-argon|luci-app-argon-config|luci-i18n-argon-config-.*|luci-theme-glass|luci-app-vantage-aps|luci-i18n-vantage-aps-.*)'

failed=0
fail() {
	echo "check-luci-theme: $*" >&2
	failed=1
}

for package in "${required_packages[@]}"; do
	grep -Fqx "CONFIG_PACKAGE_${package}=y" "$config_file" ||
		fail "$config_file: CONFIG_PACKAGE_${package}=y is missing"
done
while IFS= read -r line; do
	fail "$config_file: forbidden package is selected: $line"
done < <(grep -E "^CONFIG_PACKAGE_${forbidden_packages}=[ym]$" "$config_file" || true)

for manifest in ${manifests[@]+"${manifests[@]}"}; do
	for package in "${required_packages[@]}"; do
		grep -Eq "^${package}([[:space:]]|$)" "$manifest" ||
			fail "$manifest: required package $package is not in the image"
	done
	while IFS= read -r line; do
		fail "$manifest: forbidden package is in the image: $line"
	done < <(grep -E "^${forbidden_packages}([[:space:]]|$)" "$manifest" || true)
done

for rootfs in ${rootfses[@]+"${rootfses[@]}"}; do
	for path in www/luci-static/vantage/vantage.css \
		usr/share/ucode/luci/template/themes/vantage/header.ut \
		etc/uci-defaults/30_luci-theme-vantage \
		www/luci-static/bootstrap/cascade.css; do
		[[ -f "$rootfs/$path" ]] || fail "$rootfs: /$path is missing (luci-theme-vantage / luci-theme-bootstrap)"
	done

	vantage_defaults="$rootfs/etc/uci-defaults/99-vantage"
	if [[ -x "$vantage_defaults" ]]; then
		grep -qF '/luci-static/vantage' "$vantage_defaults" ||
			fail "$rootfs: /etc/uci-defaults/99-vantage does not select /luci-static/vantage"
	else
		fail "$rootfs: /etc/uci-defaults/99-vantage is missing or not executable (files/ overlay)"
	fi

	landing="$rootfs/usr/share/luci/menu.d/zz-landing-override.json"
	if [[ -f "$landing" ]]; then
		python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$landing" 2>/dev/null ||
			fail "$rootfs: /usr/share/luci/menu.d/zz-landing-override.json is not valid JSON"
	else
		fail "$rootfs: /usr/share/luci/menu.d/zz-landing-override.json is missing (files/ overlay)"
	fi

	for path in etc/uci-defaults/30_luci-theme-argon www/luci-static/argon etc/config/argon \
		www/luci-static/glass; do
		if [[ -e "$rootfs/$path" ]]; then fail "$rootfs: /$path is present (Argon/Glass must not be in the image)"; fi
	done
done

(( failed == 0 )) || exit 1
echo "LuCI theme check passed: Vantage (${#manifests[@]} manifest(s), ${#rootfses[@]} rootfs)"
