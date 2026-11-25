#!/usr/bin/env bash
#
# Check that every enabled apk feed in a staged rootfs is actually hosted.
#
# Usage: bash scripts/check-distfeeds.sh <rootfs>...
#
# Reads <rootfs>/etc/apk/repositories.d/distfeeds.list and probes each URL with
# an HTTP HEAD request (following redirects):
#
#   enabled line,   200          ok
#   enabled line,   403/404/410  error: `apk update` on the device would fail
#   enabled line,   other        warning only (timeout or 5xx is not the
#                                firmware's fault)
#   commented line, 200          warning: hosted but disabled, consider adding
#                                the feed to DISTFEEDS_HOSTED
#   commented line, other        ok (expected for unhosted feeds)
#
# Commented lines never fail the check. include/version.mk expands %U, %A and
# the other placeholders at build time, so a remaining %X token is reported as
# an error instead of being probed.

set -Eeuo pipefail

if (( $# == 0 )); then
	echo "usage: check-distfeeds.sh <rootfs>..." >&2
	exit 2
fi

failures=0

error() {
	echo "::error::$*"
	failures=$((failures + 1))
}

warning() {
	echo "::warning::$*"
}

probe() {
	curl -sIL -o /dev/null -w '%{http_code}' \
		--retry 3 --retry-delay 2 --max-time 20 -- "$1" < /dev/null || true
}

check_line() {
	local list="$1" lineno="$2" url="$3" commented="$4" code

	# Malformed lines are errors, except on commented lines, which never fail.
	local bad=error
	[[ "$commented" == 1 ]] && bad=warning
	if [[ "$url" == *%[A-Za-z]* ]]; then
		"$bad" "$list:$lineno: unexpanded placeholder in '$url'"
		return
	fi
	if [[ ! "$url" =~ ^https?://[^[:space:]]+$ ]]; then
		"$bad" "$list:$lineno: not a URL: '$url'"
		return
	fi

	code="$(probe "$url")"
	[[ -n "$code" ]] || code=000

	if [[ "$commented" == 1 ]]; then
		if [[ "$code" == 200 ]]; then
			warning "$list:$lineno: $url is hosted but disabled, consider adding it to DISTFEEDS_HOSTED"
		else
			echo "ok (disabled, HTTP $code): $url"
		fi
		return
	fi

	case "$code" in
		200) echo "ok (HTTP 200): $url" ;;
		403 | 404 | 410) error "$list:$lineno: $url returned HTTP $code" ;;
		*) warning "$list:$lineno: $url returned HTTP $code, could not verify" ;;
	esac
}

for rootfs in "$@"; do
	list="$rootfs/etc/apk/repositories.d/distfeeds.list"
	if [[ ! -f "$list" ]]; then
		error "$list: not found"
		continue
	fi
	echo "=== $list ==="
	label="$list"

	lineno=0
	entries=0
	while IFS= read -r line <&3 || [[ -n "$line" ]]; do
		lineno=$((lineno + 1))
		line="${line%$'\r'}"
		# Trim surrounding whitespace.
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -n "$line" ]] || continue

		if [[ "$line" == \#* ]]; then
			url="${line#\#}"
			url="${url#"${url%%[![:space:]]*}"}"
			# Free-text comments (the generated header) are not feeds.
			[[ "$url" =~ ^(https?://|%U) ]] || continue
			check_line "$label" "$lineno" "$url" 1
		else
			entries=$((entries + 1))
			check_line "$label" "$lineno" "$line" 0
		fi
	done 3< "$list"

	if (( entries == 0 )); then
		error "$list: no enabled feeds"
	fi
done

if (( failures > 0 )); then
	echo "check-distfeeds: $failures error(s)" >&2
	exit 1
fi
