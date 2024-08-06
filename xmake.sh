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
KALLSYMS=false
TESTING_KERNEL=false
BUILD_ONLY_INITRAMFS=false
BUILD_SKIP_INITRAMFS=false

while getopts "j:t:fiskT" opt; do
	case $opt in
		j) MAKE_JOBS=$OPTARG;;
		t) XTARGET=$OPTARG;;
		f) OPT_FULL_REBUILD=true;;
		k) KALLSYMS=true;;
		T) TESTING_KERNEL=true;;
		i) BUILD_ONLY_INITRAMFS=true;;
		s) BUILD_SKIP_INITRAMFS=true;;
	esac
done

[ -z "$XTARGET" ] && die "Target config not specified!"

if echo "$XTARGET" | grep -E '[ "]' >/dev/null ;then
	die "Target config filename cannot contain spaces!"
fi

CUR_BRANCH=$( git rev-parse --abbrev-ref HEAD )
if [ "$CUR_BRANCH" = master ]; then
	KALLSYMS=true
fi 


function clean_all {
	local cfg=$XDIR/.config
	[ -f $cfg ] && make clean
	rm -rf $XDIR/tmp
	rm -rf $XDIR/feeds/luci.tmp
	rm -rf $XDIR/feeds/packages.tmp
	rm -rf $XDIR/feeds/nss.tmp
	rm -rf $XDIR/staging_dir/packages
	rm -rf $XDIR/staging_dir
	rm -rf $XDIR/build_dir
	[ "$XTARGET" = "*" ] && rm -rf $XDIR/bin/*
}

function build_target {
	local target_cfg=$1
	local CFG=$XDIR/.config
	local inc
	local inclst
	local incfn

	rm -f $CFG
	cp -f $target_cfg $CFG
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

	LUCI_XRAY_MK=$XDIR/package/addons/luci-app-xray/core/Makefile
	if [ -f $LUCI_XRAY_MK ]; then
		pkg_xray_core=$( get_cfg_pkg_flag $CFG xray-core )
		if [ "$pkg_xray_core" != "y" ]; then
			# Forced disable xray-core package
			sed -i '/CONFIG_PACKAGE_xray-core=/d' $CFG
			sed -i 's/ +xray-core / /g' $LUCI_XRAY_MK
		fi
	fi
	
	if [ "$KALLSYMS" = true ]; then
		echo "CONFIG_KERNEL_KALLSYMS=y" >> $CFG
	fi
	if [ "$TESTING_KERNEL" = true ]; then
		echo "CONFIG_TESTING_KERNEL=y" >> $CFG
	fi

	if [ 1 = 1 ]; then
		CURDATE=$( date --utc +%y%m%d )
		############ change images prefix ############
		# IMG_PREFIX:=$(VERSION_DIST_SANITIZED)-$(IMG_PREFIX_VERNUM)$(IMG_PREFIX_VERCODE)$(IMG_PREFIX_EXTRA)$(BOARD)$(if $(SUBTARGET),-$(SUBTARGET))
		sed -i -e 's/^IMG_PREFIX:=.*/IMG_PREFIX:=$(VERSION_DIST_SANITIZED)-$(call sanitize,$(VERSION_NUMBER))-'$CURDATE'/g' $XDIR/include/image.mk
	fi
	if [ 1 = 1 ]; then
		############ remove "squashfs" suffix ############
		#   DEVICE_IMG_NAME = $$(DEVICE_IMG_PREFIX)-$$(1)-$$(2)
		sed -i -e 's/.*DEVICE_IMG_NAME =.*/  DEVICE_IMG_NAME = $$(DEVICE_IMG_PREFIX)-$$(2)/g' $XDIR/include/image.mk
		if grep "squashfs-sys" $XDIR/target/linux/mediatek/image/filogic.mk >/dev/null ; then
			sed -i 's/ squashfs-sys/ sys/g' $XDIR/target/linux/mediatek/image/filogic.mk
			sed -i 's/ squashfs-sys/ sys/g' $XDIR/target/linux/mediatek/image/mt7622.mk
			sed -i 's/ squashfs-sys/ sys/g' $XDIR/target/linux/mediatek/image/mt7623.mk
		fi
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

	if [ "$TARGET_INITRAMFS_FORCE" = y ]; then
		sed -i '/_DEFAULT_ipq-wifi-/d' $CFG
		sed -i '/_PACKAGE_ipq-wifi-/d' $CFG
		sed -i '/_PACKAGE_ath11k-firmware-/d' $CFG
	fi

	wpad_openssl=$( get_cfg_pkg_flag $XDIR/__current.config wpad-openssl )
	if [ "$wpad_openssl" = y ]; then
		logmsg "Forced using wpad-openssl !!!"
		sed -i 's/CONFIG_PACKAGE_wpad-basic-mbedtls=/# CONFIG_PACKAGE_wpad-basic-mbedtls=/g' $CFG
		sed -i '/CONFIG_PACKAGE_wpad-openssl=/d' $CFG
		echo -e "\nCONFIG_PACKAGE_wpad-openssl=y\n" >> $CFG
	fi

	DASHBRDPO=$XDIR/feeds/luci/modules/luci-mod-dashboard/po/ru/dashboard.po
	if [ -f $DASHBRDPO ]; then
		sed -i 's/msgid "Dashboard"/msgid "__dash_board__"/g' $DASHBRDPO
	fi
	
	LUCI_CFG=$XDIR/package/feeds/luci/luci-base/root/etc/config/luci
	if [ -f $LUCI_CFG ]; then
		sed -i 's/option lang auto/option lang en/g' $LUCI_CFG
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

	SYSCTLCONF_FN=$XDIR/files/etc/sysctl.conf
	if [ -f $SYSCTLCONF_FN ]; then
		rm -f $SYSCTLCONF_FN
	fi
	kmod_nf_nathelper_extra=$( get_cfg_pkg_flag $XDIR/__current.config kmod-nf-nathelper-extra )
	if [ "$kmod_nf_nathelper_extra" = y ]; then
		[ ! -d $XDIR/files ] && mkdir -p $XDIR/files/etc
		echo "" >> $SYSCTLCONF_FN
		echo net.netfilter.nf_conntrack_helper=1 >> $SYSCTLCONF_FN
	fi

	local make_jobs=$MAKE_JOBS
	if [ -z "$make_jobs" ]; then
		make_jobs=$( grep processor /proc/cpuinfo | tail -n 1 | awk '{print $3}' )
	fi

	#make tools/install -j$make_jobs
	#make toolchain/install -j$make_jobs

	make -j $make_jobs download world
}

function build_config {
	local cfg=$1
	local cfg_name=$( basename $cfg )
	local target_name=${cfg_name%.*}
	local board=$( get_cfg_board $cfg )
	local subtarget=$( get_cfg_subtarget $cfg $board )
	local device=$( get_cfg_dev_lst $cfg $board $subtarget )
	local outdir=$XDIR/bin/targets/$board/$subtarget	
	echo Start build for target $cfg_name "($board-$subtarget-$device)"
	
	build_target $cfg_name
	
	if [ ! -f $outdir/kernel-debug.tar.zst ]; then
		echo "ERROR: cannot build images for target $target_name"
		rm -rf $outdir
		return
	fi
	rm -rf $outdir/packages
	[ ! -d $XOUT/$target_name ] && mkdir -p $XOUT/$target_name
	mv $outdir/* $XOUT/$target_name
}


if [ "$XTARGET" != "*" ]; then
	TARGETCFG=$XDIR/$XTARGET
	XTARGET_EXT="${XTARGET##*.}"
	[ $XTARGET_EXT != config ] && TARGETCFG=$TARGETCFG.config
	[ ! -f $TARGETCFG ] && die "File '"`basename $TARGETCFG`"' not found!"
	
	[ $OPT_FULL_REBUILD = true ] && clean_all
	
	build_target $TARGETCFG
	exit 0
fi

XOUT=$XDIR/xout
CFG_LIST=$( find $XDIR/* -maxdepth 1 -name '[a-z0-9]*.config' )

rm -rf $XOUT

if [ -z "$CFG_LIST" ]; then
	echo "ERROR: Cannot found supported configs!"
	exit 1
fi

INITRAMFS_COUNT=0
for CFG in $CFG_LIST; do
	if [[ "$CFG" == *"_initramfs"* ]]; then
		INITRAMFS_COUNT=$(( INITRAMFS_COUNT + 1 ))
	fi
done

if [ $INITRAMFS_COUNT = 0 ] && [ $BUILD_ONLY_INITRAMFS = true ]; then
	echo "ERROR: Cannot found initramfs configs!"
	exit 1
fi

if [ $INITRAMFS_COUNT -gt 0 ] && [ $BUILD_SKIP_INITRAMFS != true ]; then
	echo "Start make initramfs configs!"
	clean_all
	for CFG in $CFG_LIST; do
	   [[ "$CFG" != *"_initramfs"* ]] && continue  # process only initramfs configs
	   build_config $CFG
	done
fi

if [ $BUILD_ONLY_INITRAMFS != true ]; then
	echo "Start make non initramfs configs!"
	clean_all
	for CFG in $CFG_LIST; do
		[[ "$CFG" == *"_initramfs"* ]] && continue  # skip initramfs configs
		build_config $CFG
	done
fi

echo "All targets was builded!" 

