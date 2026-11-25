#!/usr/bin/env bash
#
# Print a .config fragment that comments out unhosted feeds in distfeeds.list.
#
# Usage: bash scripts/distfeeds-config.sh <tree>
#
# With CONFIG_PER_FEED_REPO, include/feeds.mk (FeedSourcesAppendAPK) writes one
# line per feed into /etc/apk/repositories.d/distfeeds.list and prefixes it with
# "# " when CONFIG_FEED_<name>=m. Third-party feeds from feeds.conf.default
# (app_airoha, vantage, ...) are compiled into the image but not published on
# the ImmortalWrt download server, so an uncommented line makes `apk update`
# fetch a 404. This prints CONFIG_FEED_<name>=m for every feed of <tree> that is
# not in DISTFEEDS_HOSTED, keeping the line visible but disabled. "base" is
# always written by include/feeds.mk and is not a feed here.
#
#   DISTFEEDS_HOSTED  Space-separated feeds hosted upstream
#                     (default: "packages luci routing telephony").

set -Eeuo pipefail

hosted="${DISTFEEDS_HOSTED-packages luci routing telephony}"
name_re='^[A-Za-z0-9_]+$'

if (( $# != 1 )); then
	echo "usage: distfeeds-config.sh <tree>" >&2
	exit 2
fi
tree="$1"
if [[ ! -x "$tree/scripts/feeds" ]]; then
	echo "distfeeds-config: $tree/scripts/feeds not found or not executable" >&2
	exit 2
fi

# Space-padded so membership is a whole-word match.
hosted_set=" "
read -ra hosted_list <<< "$hosted"
for feed in ${hosted_list[@]+"${hosted_list[@]}"}; do
	if [[ ! "$feed" =~ $name_re ]]; then
		echo "distfeeds-config: invalid name in DISTFEEDS_HOSTED: '$feed'" >&2
		exit 1
	fi
	hosted_set+="$feed "
done

feeds_out="$(cd "$tree" && ./scripts/feeds list -n)"
read -ra feeds <<< "$(printf '%s' "$feeds_out" | tr '\n' ' ')"
if (( ${#feeds[@]} == 0 )); then
	echo "distfeeds-config: scripts/feeds list -n returned no feeds" >&2
	exit 1
fi

# Validate everything before printing, so a bad name never yields a partial
# fragment.
for feed in "${feeds[@]}"; do
	if [[ ! "$feed" =~ $name_re ]]; then
		echo "distfeeds-config: invalid feed name: '$feed'" >&2
		exit 1
	fi
done

for feed in "${feeds[@]}"; do
	[[ "$hosted_set" == *" $feed "* ]] && continue
	printf 'CONFIG_FEED_%s=m\n' "$feed"
done
