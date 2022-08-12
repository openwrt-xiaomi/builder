#!/bin/bash

XSUPPORTEDVER=21
XREPOADDR=https://github.com/openwrt-xiaomi
XDEFBRANCH=xq-21.02.3

logmsg() {
	echo "$@"
}

logerr() {
	echo "ERROR: $@" >&2
}

die() {
	logerr $@
	exit 1
}

#[ ! -d "$XDIR" ] && die "Base directory not defined"

get_cfg_inc_lst() {
	local cfg=$1
	local k=$( grep -o -P '(?<=^#include ).*' "$cfg" 2> /dev/null )
	echo "$k"
}

get_cfg_feed_lst() {
	local cfg=$1
	local k=$( grep -o -P '(?<=^CONFIG_FEED_).*(?==[y|m])' "$cfg" 2> /dev/null )
	echo "$k"
}

get_cfg_feed_url() {
	local cfg=$1
	local name=$2
	local k=$( grep -o -P "(?<=^#GIT_FEED $name=).*" "$cfg" 2> /dev/null )
	echo "$k"
}

get_cfg_expkg_lst() {
	local cfg=$1
	local k=$( grep -o -P '(?<=^#GIT_PACKAGE ).*(?==)' "$cfg" 2> /dev/null )
	echo "$k"
}

get_cfg_expkg_url() {
	local cfg=$1
	local name=$2
	local k=$( grep -o -P "(?<=^#GIT_PACKAGE $name=).*" "$cfg" 2> /dev/null )
	echo "$k"
}

get_cfg_board() {
	local cfg=$1
	local k=$( grep -o -P "(?<=^CONFIG_TARGET_)[a-z0-9]+(?==y)" "$cfg" 2> /dev/null )
	[ $( echo "$k" | wc -l ) != 1 ] && { echo ""; return 0; }
	echo "$k"
}

get_cfg_subtarget() {
	local cfg=$1
	local board=$2
	local k=$( grep -o -P "(?<=^CONFIG_TARGET_"$board"_)[a-z0-9]+(?==y)" "$cfg" 2> /dev/null )
	[ $( echo "$k" | wc -l ) != 1 ] && { echo ""; return 0; }
	echo "$k"
}

get_cfg_dev_lst() {
	local cfg=$1
	local board=$2
	local subtarget=$3
	local k=$( grep -o -P "(?<=^CONFIG_TARGET_"$board"_"$subtarget"_DEVICE_).*(?==y)" "$cfg" 2> /dev/null )
	[ $( echo "$k" | wc -l ) != 1 ] && { echo ""; return 0; }
	echo "$k"
}

get_cfg_pkg_flag() {
	local cfg=$1
	local name=$2
	local k=$( grep -o -P "(?<=^CONFIG_PACKAGE_$name=).*" "$cfg" 2> /dev/null )
	echo "$k"
}


