#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export XDIR="$SCRIPT_DIR"

. ./xcommon.sh

if echo "$XDIR" | grep -E '[ "]' >/dev/null ;then
	die "The path to the base directory cannot contain spaces!"
fi

MAKE_JOBS=
XTARGET=
OPT_FULL_REBUILD=false
while getopts "j:t:f" opt; do
	case $opt in
		j) MAKE_JOBS=$OPTARG;;
		t) XTARGET=$OPTARG;;
		f) OPT_FULL_REBUILD=true;;
	esac
done

[ -z "$XTARGET" ] && die "Target config not specified!"
if echo "$XTARGET" | grep -E '[ "]' >/dev/null ;then
	die "Target config filename cannot contain spaces!"
fi
TARGETCFG=$XDIR/$XTARGET.config
[ ! -f $TARGETCFG ] && die "File '$XTARGET.config' not found!"

CFG=$XDIR/.config

if [ $OPT_FULL_REBUILD = true ]; then
	[ -f $CFG ] && make clean
	rm -rf $XDIR/tmp
	rm -rf $XDIR/feeds/luci.tmp
	rm -rf $XDIR/feeds/packages.tmp
	rm -rf $XDIR/feeds/nss.tmp
	rm -rf $XDIR/staging_dir/packages
	rm -rf $XDIR/staging_dir
	rm -rf $XDIR/build_dir
fi

rm -f $CFG
cp -f $TARGETCFG $CFG
if is_nss_repo $XDIR; then
	sed -i "/#include _base/a #include _addons_nss.config" $CFG
fi
inclst=$( get_cfg_inc_lst $CFG )
for inc in $inclst; do
	incfn=$XDIR/$inc
	[ ! -f $incfn ] && die "File '$inc' not found!"
	sed -i "/#include $inc/a <<LF>><<LF>>" $CFG
	sed -i "s/<<LF>>/\n/g" $CFG
	sed -i "/#include $inc/ r $incfn" $CFG
done

cp -f $CFG $XDIR/__current.config

DIS_SVC_FN=$XDIR/disabled_services.lst
rm -f $DIS_SVC_FN
DIS_SVC_LST="$( get_cfg_dis_svc_lst $CFG )"
if [ -n "$DIS_SVC_LST" ]; then
	echo $DIS_SVC_LST > $DIS_SVC_FN
fi

make defconfig

NSS_DRV_PPPOE_ENABLE=$( get_cfg_opt_flag $CFG NSS_DRV_PPPOE_ENABLE )
if [ "$NSS_DRV_PPPOE_ENABLE" = y ]; then
	sed -i 's/CONFIG_PACKAGE_kmod-qca-nss-drv-pppoe=m/CONFIG_PACKAGE_kmod-qca-nss-drv-pppoe=y/g' $CFG
fi

pkg_dnsmasq_full=$( get_cfg_pkg_flag $CFG dnsmasq-full )
if [ "$pkg_dnsmasq_full" = y ]; then
	echo "Forced using dnsmasq-full !!!"
	sed -i '/CONFIG_DEFAULT_dnsmasq=y/d' $CFG
	sed -i '/CONFIG_PACKAGE_dnsmasq=y/d' $CFG
fi

TARGET_INITRAMFS_FORCE=$( get_cfg_opt_flag $CFG TARGET_INITRAMFS_FORCE )
if [ "$TARGET_INITRAMFS_FORCE" = y ]; then
	echo "Forced uses integrated INITRAMFS !!!"
	sed -i '/CONFIG_USES_SEPARATE_INITRAMFS=y/d' $CFG
	sed -i '/CONFIG_TARGET_ROOTFS_INITRAMFS_SEPARATE=y/d' $CFG
fi

NETPORTSDIR=$XDIR/package/addons/luci-app-tn-netports/root/etc/config
if [ -d $NETPORTSDIR ]; then
	rm -f $NETPORTSDIR/luci_netports
	TARGET_NETPORTS=$XDIR/$XTARGET.netports
	if [ -f $TARGET_NETPORTS ]; then
		cp -f $TARGET_NETPORTS $NETPORTSDIR/luci_netports
	fi
fi

DASHBRDPO=$XDIR/feeds/luci/modules/luci-mod-dashboard/po/ru/dashboard.po
if [ -f $DASHBRDPO ]; then
	sed -i 's/msgid "Dashboard"/msgid "__dash_board__"/g' $DASHBRDPO
fi

OPKG_DIR=$XDIR/files/etc/opkg
if [ -d $OPKG_DIR ]; then
	rm -rf $OPKG_DIR
fi
FANT_PKG_KEY=$XDIR/53FF2B6672243D28.pub
if [ -f $FANT_PKG_KEY ]; then
	OPKG_SRC_DIR=$XDIR/package/system/opkg/files
	OPKG_KEYS_DIR=$OPKG_DIR/keys
	mkdir -p $OPKG_KEYS_DIR
	cp $FANT_PKG_KEY $OPKG_KEYS_DIR/53ff2b6672243d28
	OPKG_CFEED_FN=$OPKG_DIR/customfeeds.conf
	cp $OPKG_SRC_DIR/customfeeds.conf $OPKG_CFEED_FN
	echo "" >> $OPKG_CFEED_FN
	fant_luci="src/gz  fantastic_packages_luci      https://fantastic-packages.github.io/packages/releases/<<VER>>/packages/<<ARCH>>/luci"
	echo "$fant_luci" >> $OPKG_CFEED_FN
	fant_pkgs="src/gz  fantastic_packages_packages  https://fantastic-packages.github.io/packages/releases/<<VER>>/packages/<<ARCH>>/packages"
	echo "$fant_pkgs" >> $OPKG_CFEED_FN
	TARGET_ARCH_PACKAGES=$( get_cfg_opt_value $CFG TARGET_ARCH_PACKAGES )
	[ -z "$TARGET_ARCH_PACKAGES" ] && die "Cannot find TARGET ARCH"
	sed -i "s/<<VER>>/23.05/g" $OPKG_CFEED_FN
	sed -i "s/<<ARCH>>/$TARGET_ARCH_PACKAGES/g" $OPKG_CFEED_FN
	logmsg "Added support of Fantastic packages [https://fantastic-packages.github.io/packages]"
fi

if [ -z "$MAKE_JOBS" ]; then
	MAKE_JOBS=$( grep processor /proc/cpuinfo | tail -n 1 | awk '{print $3}' )
fi

#make tools/install -j$MAKE_JOBS
#make toolchain/install -j$MAKE_JOBS

make PARALLEL_BUILD=1 -j $MAKE_JOBS download world

