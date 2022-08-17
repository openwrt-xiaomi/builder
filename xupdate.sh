#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export XDIR=$SCRIPT_DIR
export XADDONSDIR=$XDIR/package/addons
FEEDSDIR=$XDIR/package/feeds
ADDONSCFG=$XDIR/_addons.config

. ./xcommon.sh

OPT_FULL_UPDATE=false
while getopts "f" opt; do
	case $opt in
		f) OPT_FULL_UPDATE=true;;
	esac
done

[ ! -d "$FEEDSDIR" ] && OPT_FULL_UPDATE=true

rm -rf tmp
if [ "$OPT_FULL_UPDATE" = "true" ]; then
	rm -rf feeds/luci.tmp
	rm -rf feeds/packages.tmp
	#rm -rf feeds
	#rm -rf package/feeds
	rm -rf staging_dir/packages
	rm -rf $XADDONSDIR
fi

git reset --hard HEAD

git fetch
[ "$?" != "0" ] && die "Can't fetch current repository"

git pull --force "origin"
[ "$?" != "0" ] && die "Can't pull current repository"

rm -f feeds.conf
cp -f feeds.conf.default feeds.conf
feed_lst=$( get_cfg_feed_lst "$ADDONSCFG" )
for feed in $feed_lst; do
	value=$( get_cfg_feed_url "$ADDONSCFG" $feed )
	#echo "$feed = '$value'"
	echo "src-git $feed $value" >> feeds.conf
done

if [ "$OPT_FULL_UPDATE" = "true" ]; then
	./scripts/feeds update -a
	./scripts/feeds install -a
fi

CLONE_ADDONS=true
if [ "$CLONE_ADDONS" = "true" ]; then
	mkdir $XADDONSDIR
	pkg_lst=$( get_cfg_expkg_lst "$ADDONSCFG" )
	for pkg in $pkg_lst; do
		value=$( get_cfg_expkg_url "$ADDONSCFG" $pkg )
		#echo "$pkg = '$value'"
		url=$( echo "$value" | cut -d " " -f 1 )
		branch=$( echo "$value" | cut -d " " -f 2 )
		#echo "'$url' / '$branch'"
		if [ ! -d "$XADDONSDIR/$pkg" ]; then
			git clone $url -b $branch $XADDONSDIR/$pkg
			[ "$?" != "0" ] && die "Can't clone repository '$url'"
		fi
	done
	if [ "$OPT_FULL_UPDATE" = "true" ]; then
		./scripts/feeds install -a
	fi
fi

if [ "$OPT_FULL_UPDATE" = "true" ]; then
	if [ -f "$XDIR/vermagic_update.sh" ]; then
		./vermagic_update.sh ipq806x generic
		./vermagic_update.sh ramips mt7621
		./vermagic_update.sh mediatek mt7622
	fi
fi

if [ -f "$XDIR/luci_dispatcher.sh" ]; then
	./luci_dispatcher.sh
fi

echo "All git sources updated!"
