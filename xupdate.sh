#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export XDIR=$SCRIPT_DIR
export XADDONSDIR=$XDIR/package/addons
FEEDSDIR=$XDIR/package/feeds
ADDONSCFG=$XDIR/_addons.config
ADDONSNSS=$XDIR/_addons_nss.config

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

#git reset --hard HEAD
git reset --hard HEAD~50
#git revert HEAD~50..HEAD
#git reset --hard HEAD

git fetch
[ "$?" != "0" ] && die "Can't fetch current repository"

git pull --force "origin" &> /dev/null 
#[ "$?" != "0" ] && die "Can't pull current repository"

CUR_BRANCH=$( git rev-parse --abbrev-ref HEAD )

git reset --hard origin/$CUR_BRANCH
[ "$?" != "0" ] && die "Can't reset current repository"

rm -f feeds.conf
cp -f feeds.conf.default feeds.conf
feed_lst=$( get_cfg_feed_lst "$ADDONSCFG" )
for feed in $feed_lst; do
	value=$( get_cfg_feed_url "$ADDONSCFG" $feed )
	#echo "$feed = '$value'"
	echo "src-git $feed $value" >> feeds.conf
done

if is_nss_repo "$XDIR"; then
	feed_lst=$( get_cfg_feed_lst "$ADDONSNSS" )
	for feed in $feed_lst; do
		value=$( get_cfg_feed_url "$ADDONSNSS" $feed )
		#echo "$feed = '$value'"
		echo "src-git $feed $value" >> feeds.conf
	done
fi

FULL_VERSION=$( grep '^VERSION_NUMBER:=$(if' $XDIR/include/version.mk 2>/dev/null )
[ -z "$FULL_VERSION" ] && { echo "ERROR: Cannot find VERSION_NUMBER"; exit 1; }
FULL_VERSION=$( echo $FULL_VERSION | cut -d"," -f3 | cut -d")" -f1 )
echo 'FULL_VERSION = "'$FULL_VERSION'"'
CUR_VER=
CUR_SNAPSHOT=
if [ "$FULL_VERSION" = "SNAPSHOT" ]; then
	CUR_SNAPSHOT=1
	echo "SNAPSHOT detected."
else 
	if ! echo "$FULL_VERSION" | grep -q "." ; then
		echo "ERROR: Incorrect branch version!"
		exit 13
	fi
	CUR_VER=${FULL_VERSION:0:5}
	VER_DELIM=${FULL_VERSION:5:1}
	if [ "$VER_DELIM" = "-" ]; then
		CUR_SNAPSHOT=$CUR_VER
		echo "snapshot detected."
	fi
fi
echo 'CUR_VER = "'$CUR_VER'"'

function update_feed_head()
{
	local FEEDNAME=$1
	local FEEDURL=$2
	local FEEDHEADLIST="$XDIR/feed_$FEEDNAME.list"
	
	git ls-remote -h $FEEDURL > $FEEDHEADLIST
	HEADHASH=$( grep "refs/heads/openwrt-$CUR_VER" $FEEDHEADLIST 2>/dev/null )
	if [ -z "$HEADHASH" ]; then
		echo "ERROR: Not found branch refs/heads/openwrt-$CUR_VER for feed $FEEDNAME"
		exit 17
	fi
	HEADHASH=$( echo $HEADHASH | cut -d" " -f1 )
	echo "For feed '$FEEDNAME' founded fresh hash = $HEADHASH"
	# src-git packages https://git.openwrt.org/feed/packages.git^b5ed85f6e94aa08de1433272dc007550f4a28201
	NEWLINE="src-git $FEEDNAME $FEEDURL^$HEADHASH"
	NEWLINE=$( sed_adapt "$NEWLINE" )
	sed -i "s/^src-git $FEEDNAME .*/$NEWLINE/g" feeds.conf
	if ! grep -q "$NEWLINE" "feeds.conf" ; then
		echo "ERROR: Cannot patch file feeds.conf"
		exit 18
	fi
	echo "Changed URL for feed '$FEEDNAME' = $FEEDURL^$HEADHASH"
}

if [ "$CUR_SNAPSHOT" != "1" ]; then
	update_feed_head  packages   https://github.com/openwrt/packages.git
	update_feed_head  luci       https://github.com/openwrt/luci.git
	update_feed_head  routing    https://github.com/openwrt/routing.git
	update_feed_head  telephony  https://github.com/openwrt/telephony.git
fi

if [ "$OPT_FULL_UPDATE" = "true" ]; then
	./scripts/feeds update -a
	./scripts/feeds install -a
fi

CLONE_ADDONS=true
if [ "$CLONE_ADDONS" = "true" ]; then
	mkdir -p $XADDONSDIR
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
		./vermagic_update.sh ipq807x generic
		./vermagic_update.sh qualcommax ipq807x
		./vermagic_update.sh ramips mt7621
		./vermagic_update.sh mediatek mt7622
		./vermagic_update.sh mediatek filogic
	fi
fi

if [ -f "$XDIR/luci_dispatcher.sh" ]; then
	chmod 755 ./luci_dispatcher.sh
	./luci_dispatcher.sh
fi

echo "All git sources updated!"
