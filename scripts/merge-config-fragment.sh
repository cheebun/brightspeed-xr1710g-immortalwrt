#!/usr/bin/env bash
#
# Merge a .config fragment into a .config, the fragment winning.
#
# Usage: bash scripts/merge-config-fragment.sh <fragment> <config>
#
# Every symbol set in <fragment> ("CONFIG_X=<any value>" or
# "# CONFIG_X is not set") is removed from <config>, then the fragment is
# appended. When the fragment sets a symbol more than once, only the last
# setting is kept, so `make defconfig` never sees a conflicting reassignment.
# <config> is rewritten in place.

set -Eeuo pipefail

if (( $# != 2 )); then
	echo "usage: merge-config-fragment.sh <fragment> <config>" >&2
	exit 2
fi
fragment="$1"
config="$2"
for f in "$fragment" "$config"; do
	[[ -f "$f" ]] || { echo "merge-config-fragment: not found: $f" >&2; exit 2; }
done

# An empty fragment changes nothing (and would confuse NR==FNR below).
[[ -s "$fragment" ]] || exit 0

tmp="$(mktemp "${config}.merge.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

# key(): the symbol name of a setting line, or "" for anything else.
key_fn='
  function key(line,   k) {
    k = line
    if (k ~ /^# CONFIG_[^ =]+ is not set$/) { sub(/^# /, "", k); sub(/ is not set$/, "", k); return k }
    if (k ~ /^CONFIG_[^ =]+=/) { sub(/=.*$/, "", k); return k }
    return ""
  }
'

# Drop every symbol the fragment sets from the config.
awk "$key_fn"'
  NR == FNR { k = key($0); if (k != "") drop[k] = 1; next }
  { k = key($0); if (k != "" && (k in drop)) next; print }
' "$fragment" "$config" > "$tmp"

# Append the fragment, keeping only the last setting of each symbol.
awk "$key_fn"'
  { line[NR] = $0; k = key($0); if (k != "") last[k] = NR }
  END {
    for (i = 1; i <= NR; i++) {
      k = key(line[i])
      if (k != "" && last[k] != i) continue
      print line[i]
    }
  }
' "$fragment" >> "$tmp"

mv -f -- "$tmp" "$config"
trap - EXIT
