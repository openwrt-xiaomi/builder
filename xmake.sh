#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export XDIR=$SCRIPT_DIR

. ./xcommon.sh

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
CFG=$XDIR/$XTARGET.config
[ ! -f "$CFG" ] && die "File '$XTARGET.config' not found!"

if [ "$OPT_FULL_REBUILD" = "true" ]; then
	[ -f .config ] && make clean
	rm -rf tmp
	rm -rf feeds/luci.tmp
	rm -rf feeds/packages.tmp
	rm -rf feeds/nss.tmp
	rm -rf staging_dir/packages
	rm -rf staging_dir
	rm -rf build_dir
fi

rm -f .config
cp -f "$CFG" .config
inclst=$( get_cfg_inc_lst $CFG )
for inc in $inclst; do
	echo -e "\n\n" >> .config
	[ ! -f "$XDIR/$inc" ] && die "File '$inc' not found!"
	cat $XDIR/$inc >> .config
done

if is_nss_repo "$XDIR"; then
	cat $XDIR/_addons_nss.config >> .config
fi

#cp -f .config current.config

make defconfig

if [ $( grep -q "CONFIG_NSS_DRV_PPPOE_ENABLE=y" $XDIR/.config >/dev/null; echo "$?" ) == "0" ]; then
	sed -i 's/CONFIG_PACKAGE_kmod-qca-nss-drv-pppoe=m/CONFIG_PACKAGE_kmod-qca-nss-drv-pppoe=y/g' $XDIR/.config
fi

if [ $( get_cfg_pkg_flag "$XDIR/.config" "dnsmasq-full" ) = "y" ]; then
	echo "Forced using dnsmasq-full !!!"
	sed -i '/CONFIG_DEFAULT_dnsmasq=y/d' $XDIR/.config
	sed -i '/CONFIG_PACKAGE_dnsmasq=y/d' $XDIR/.config
fi

if [ $( get_cfg_opt_flag "$XDIR/.config" "TARGET_INITRAMFS_FORCE" ) = "y" ]; then
	echo "Forced uses integrated INITRAMFS !!!"
	sed -i '/CONFIG_USES_SEPARATE_INITRAMFS=y/d' $XDIR/.config
	sed -i '/CONFIG_TARGET_ROOTFS_INITRAMFS_SEPARATE=y/d' $XDIR/.config
fi

rm -f $XDIR/luci_aux_menu.json
TARGET_MENU="$XDIR"/"$XTARGET""_menu.json"
if [ -f "$TARGET_MENU" ]; then
	cp -f "$TARGET_MENU" $XDIR/luci_aux_menu.json
fi

NETPORTSDIR=$XDIR/package/addons/luci-app-tn-netports/root/etc/config
if [ -d "$NETPORTSDIR" ]; then
	rm -f $NETPORTSDIR/luci_netports
	TARGET_NETPORTS=$XDIR/$XTARGET.netports
	if [ -f "$TARGET_NETPORTS" ]; then
		cp -f "$TARGET_NETPORTS" $NETPORTSDIR/luci_netports
	fi
fi

DASHBRDPO=$XDIR/feeds/luci/modules/luci-mod-dashboard/po/ru/dashboard.po
if [ -f "$DASHBRDPO" ]; then
	sed -i 's/msgid "Dashboard"/msgid "__dash_board__"/g' $DASHBRDPO
fi

if [ -z "$MAKE_JOBS" ]; then
	MAKE_JOBS=$( grep processor /proc/cpuinfo | tail -n 1 | awk '{print $3}' )
fi

#make tools/install -j$MAKE_JOBS
#make toolchain/install -j$MAKE_JOBS

make PARALLEL_BUILD=1 -j $MAKE_JOBS download world

