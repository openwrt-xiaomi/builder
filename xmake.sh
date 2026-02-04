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
ONLY_INIT=false

while getopts "j:t:fiskTI" opt; do
	case $opt in
		j) MAKE_JOBS=$OPTARG;;
		t) XTARGET=$OPTARG;;
		f) OPT_FULL_REBUILD=true;;
		k) KALLSYMS=true;;
		T) TESTING_KERNEL=true;;
		i) BUILD_ONLY_INITRAMFS=true;;
		I) ONLY_INIT=true;;
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
		incfn=$XDIR/_cfginc/$inc
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

	X_VERSION_MK=$XDIR/include/version.mk
	X_VERSION_NUMBER=$( grep -o -P '(?<=,\$\(VERSION_NUMBER\),).*(?=\))' $X_VERSION_MK 2>/dev/null )
	[ -z "$X_VERSION_NUMBER" ] && { echo "ERROR: Cannot determine VERSION_NUMBER"; exit 30; }
	echo "VERSION_NUMBER = $X_VERSION_NUMBER"

	X_BOARD_NAME=$( sed -n 's/^CONFIG_TARGET_\([^_=\n]\+\)=y$/\1/p' $CFG )
	[ -z "$X_BOARD_NAME" ] && { echo "ERROR: cannot found BOARD_NAME"; exit 31; }
	X_SUBTARGET_NAME=$( sed -n 's/^CONFIG_TARGET_[^_=\n]\+_\([^_=\n]\+\)=y$/\1/p' $CFG )
	[ -z "$X_SUBTARGET_NAME" ] && { echo "ERROR: cannot found SUBTARGET"; exit 31; }
	echo "BOARD_NAME = $X_BOARD_NAME   SUBTARGET = $X_SUBTARGET_NAME"
	
	VERMAGIC_FN=$XDIR/vermagic-$X_BOARD_NAME-$X_SUBTARGET_NAME-$X_VERSION_NUMBER.list
	if [ ! -f $VERMAGIC_FN -a -f $XDIR/vermagic_update.sh ]; then
		bash $XDIR/vermagic_update.sh $X_BOARD_NAME $X_SUBTARGET_NAME
		if [ ! -f $VERMAGIC_FN ]; then
			echo "ERROR: cannot create file $VERMAGIC_FN"
			exit 41
		fi 
	fi

	if [ 1 = 1 ]; then
		MK_IMAGE=$XDIR/include/image.mk
		CURDATE=$( date --utc +%y%m%d )
		if ! grep -q "(VERSION_NUMBER))-$CURDATE" $MK_IMAGE ; then
			############ change images prefix ############
			# IMG_PREFIX:=$(VERSION_DIST_SANITIZED)-$(IMG_PREFIX_VERNUM)$(IMG_PREFIX_VERCODE)$(IMG_PREFIX_EXTRA)$(BOARD)$(if $(SUBTARGET),-$(SUBTARGET))
			sed -i -e 's/^IMG_PREFIX:=.*/IMG_PREFIX:=$(VERSION_DIST_SANITIZED)-$(call sanitize,$(VERSION_NUMBER))-'$CURDATE'/g' $MK_IMAGE
			echo ">>> image.mk patched !!! (IMG_PREFIX)"
		fi
	fi
	if [ 1 = 1 ]; then
		############ remove "squashfs" suffix ############
		MK_IMAGE=$XDIR/include/image.mk
		if grep -q 'DEVICE_IMG_NAME = $$(DEVICE_IMG_PREFIX)-$$(1)-$$(2)' $MK_IMAGE ; then
			sed -i -e 's/.*DEVICE_IMG_NAME =.*/  DEVICE_IMG_NAME = $$(DEVICE_IMG_PREFIX)-$$(2)/g' $MK_IMAGE
			echo ">>> image.mk patched !!! (DEVICE_IMG_NAME)"
		fi
		if grep -q "squashfs-sys" $XDIR/target/linux/mediatek/image/filogic.mk ; then
			sed -i 's/ squashfs-sys/ sys/g' $XDIR/target/linux/mediatek/image/filogic.mk
			sed -i 's/ squashfs-sys/ sys/g' $XDIR/target/linux/mediatek/image/mt7622.mk
			sed -i 's/ squashfs-sys/ sys/g' $XDIR/target/linux/mediatek/image/mt7623.mk
		fi
	fi
	
	if ! grep '^CONFIG_BUILD_ALL_HOST_TOOLS=y' $CFG ; then
		MK_HOST_TOOLS=$XDIR/tools/Makefile
		# tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_USES_MINOR),y) += yafut
		if grep -q '(CONFIG_USES_MINOR),y)' $MK_HOST_TOOLS ; then
			# disable build yafut - not support devices with yaffs !!!
			sed -i 's/\$(CONFIG_USES_MINOR),y)/,y)/g' $MK_HOST_TOOLS
			echo ">>> tools/Makefile patched !!! (disable yafut)"
		fi
	fi

	BATADV_DIR=$XDIR/feeds/luci/protocols/luci-proto-batman-adv/htdocs/luci-static/resources/protocol
	if [ -d $BATADV_DIR ]; then
		if [ ! -f $BATADV_DIR/batadv_vlan.js ]; then
			BATADV_VLAN_URL="https://github.com/luminem/luci/raw/4e0612a45e4be8c58de2bbd21c3bffbcf5252be4/protocols/luci-proto-batman-adv/htdocs/luci-static/resources/protocol/batadv_vlan.js"
			curl -sSL "$BATADV_VLAN_URL" -o "$BATADV_DIR/batadv_vlan.js"
			echo ">>> batman_adv patched !!!"
		fi
	fi
	
	RAB_LUCI_MK=$XDIR/package/feeds/_ruantiblock/luci-app-ruantiblock/Makefile
	if [ -f $RAB_LUCI_MK ]; then
		if ! grep "PKG_PROVIDES" $RAB_LUCI_MK >/dev/null ; then
			sed -i 's/LUCI_PKGARCH:=all/LUCI_PKGARCH:=all\nPKG_PROVIDES:=luci-app-ruantiblock/g' $RAB_LUCI_MK
			echo ">>> ruantiblock patched !!!"
		fi
	fi

	AWG_KMOD_MK=$XDIR/package/feeds/_amneziawg/kmod-amneziawg/Makefile
	if [ -f $AWG_KMOD_MK ]; then
		if grep "876bf7571e47e349d0e86b70c244330b470d9642" $AWG_KMOD_MK >/dev/null ; then
			sed -i 's/PKG_SOURCE_VERSION:=876bf7571e47e349d0e86b70c244330b470d9642/PKG_SOURCE_VERSION:=b96e12d00112dbee9d51d18d8438aa991cec0f6a/g' $AWG_KMOD_MK
		fi
	fi

	PODKOP_DIR=$XDIR/package/feeds/_podkop
	if [ -d $PODKOP_DIR ]; then
		PODKOP_PATCH=
		PODKOP_MK=$PODKOP_DIR/podkop/Makefile
		if [ -f $PODKOP_MK ] && grep -q '+sing-box' $PODKOP_MK ; then
			sed -i 's/+sing-box / /g' $PODKOP_MK
			sed -i 's/CONFLICTS:=.*/CONFLICTS:=/g' $PODKOP_MK
			PODKOP_PATCH="$PODKOP_PATCH (del depend sing-box)"
		fi
		PODKOP_SH=$PODKOP_DIR/podkop/files/usr/bin/podkop
		if [ -f $PODKOP_SH ] && ! grep -q '(which sing-box)' $PODKOP_SH ; then
			sed -i '/,\\"dns_configured\\":/i [ -z "$(which sing-box)" ] && status="not installed"' $PODKOP_SH
			PODKOP_PATCH="$PODKOP_PATCH (status for sing-box)"
		fi
		if [ -f $PODKOP_MK ] && grep -q 'PODKOP_VERSION' $PODKOP_MK ; then
			PKGVERLIST=$( git ls-remote --tags https://github.com/itdoginfo/podkop.git | awk -F/ '{print $3}' | grep -Ev '^v' | sort -V | tail -n 2 )
			VER_PREV=$( sed -n '1p' <<< "$PKGVERLIST" )
			VER_LATEST=$( sed -n '2p' <<< "$PKGVERLIST" )
			[ -z "$VER_LATEST" ] && { echo "ERROR: cannot detect version of podkop!"; exit 1; }
			sed -i 's/PKG_VERSION :=.*/PKG_VERSION:='$VER_LATEST'/g' $PODKOP_MK
			PODKOP_PATCH="$PODKOP_PATCH (set ver $VER_LATEST)"
		fi
		PODKOP_MK=$PODKOP_DIR/luci-app-podkop/Makefile
		if [ -f $PODKOP_MK ] && grep -q 'PODKOP_VERSION' $PODKOP_MK ; then
			PKGVERLIST=$( git ls-remote --tags https://github.com/itdoginfo/podkop.git | awk -F/ '{print $3}' | grep -Ev '^v' | sort -V | tail -n 2 )
			VER_PREV=$( sed -n '1p' <<< "$PKGVERLIST" )
			VER_LATEST=$( sed -n '2p' <<< "$PKGVERLIST" )
			[ -z "$VER_LATEST" ] && { echo "ERROR: cannot detect version of podkop!"; exit 1; }
			sed -i 's/PKG_VERSION :=.*/PKG_VERSION:='$VER_LATEST'/g' $PODKOP_MK
			PODKOP_PATCH="$PODKOP_PATCH (Set Ver $VER_LATEST)"
		fi
		[ "$PODKOP_PATCH" != "" ] && echo ">>> podkop patched !!! $PODKOP_PATCH"
	fi

	DROPBEAR_MK=$XDIR/package/network/services/dropbear/Makefile
	if [ -f $DROPBEAR_MK ]; then
		# patch: Disable MODERN and enable RSA/DH-SHA1
		sed -i 's/^PKG_RELEASE:=.*/PKG_RELEASE:=0/g' $DROPBEAR_MK
		sed -i '/,CONFIG_DROPBEAR_MODERN_ONLY,/d' $DROPBEAR_MK
		sed -i 's/\tCONFIG_DROPBEAR_MODERN_ONLY/ /g' $DROPBEAR_MK
		sed -i 's/ CONFIG_DROPBEAR_MODERN_ONLY/ /g' $DROPBEAR_MK
		sed -i 's/DROPBEAR_DH_GROUP14_SHA1,0/ /g' $DROPBEAR_MK
		sed -i 's/DROPBEAR_SHA1_HMAC,0/ /g' $DROPBEAR_MK
		echo ">>> dropbear patched !!! (disable MODERN_ONLY)"
	fi

	HOST_TOOLS_DIR=$XDIR/staging_dir/host
	HOST_TOOLS_STAGE=0
	[ -d $HOST_TOOLS_DIR ] && HOST_TOOLS_STAGE=1

	make defconfig
	
	if [ -d $HOST_TOOLS_DIR -a $HOST_TOOLS_STAGE = 0 ]; then
		ls -la $HOST_TOOLS_DIR/bin | awk '{print $9 " -> " $11}' | sort > $HOST_TOOLS_DIR/.prereq-build-list
		#cat $HOST_TOOLS_DIR/.prereq-build-list | cksum | awk '{print $1}' > $HOST_TOOLS_DIR/.prereq-build-list.crc
	fi

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
	DASHBRDPO=$XDIR/package/feeds/luci/luci-mod-dashboard/po/ru/dashboard.po
	if [ -f $DASHBRDPO ]; then
		sed -i 's/msgid "Dashboard"/msgid "__dash_board__"/g' $DASHBRDPO
	fi
	
	LUCI_CFG=$XDIR/package/feeds/luci/luci-base/root/etc/config/luci
	if [ -f $LUCI_CFG ]; then
		sed -i 's/option lang auto/option lang en/g' $LUCI_CFG
	fi
	
	LUCISTATCONF=$XDIR/package/feeds/luci/luci-app-statistics/root/etc/config/luci_statistics
	if [ -f $LUCISTATCONF ]; then
		sed -i "/config statistics 'collectd_sensors'/{n; s/option enable '0'/option enable '1'/}" $LUCISTATCONF
		sed -i "/config statistics 'collectd_thermal'/{n; s/option enable '0'/option enable '1'/}" $LUCISTATCONF
	fi

	if [ 1 = 1 ]; then
		########### disable some kmod from x-wrt packages ##########
		sed -i 's/^CONFIG_PACKAGE_kmod-exfat-linux=/###CONFIG_PACKAGE_kmod-exfat-linux=/g' $CFG
		sed -i 's/^CONFIG_PACKAGE_kmod-qmi-wwan-q=/###CONFIG_PACKAGE_kmod-qmi-wwan-q=/g' $CFG
		sed -i 's/^CONFIG_PACKAGE_kmod-rtw8852cu=/###CONFIG_PACKAGE_kmod-rtw8852cu=/g' $CFG
		sed -i 's/^CONFIG_PACKAGE_kmod-rproxy=/###CONFIG_PACKAGE_kmod-rproxy=/g' $CFG
		sed -i 's/^CONFIG_PACKAGE_kmod-natcap=/###CONFIG_PACKAGE_kmod-natcap=/g' $CFG
	fi

	sed -i 's/^CONFIG_PACKAGE_base-config-setting=/###CONFIG_PACKAGE_base-config-setting=/g' $CFG
	sed -i 's/^CONFIG_BASE_CONFIG_SETTING_LUCI_LOGIN=/###CONFIG_BASE_CONFIG_SETTING_LUCI_LOGIN=/g' $CFG
	sed -i 's/^CONFIG_PACKAGE_base-config-setting-ext4fs=/###CONFIG_PACKAGE_base-config-setting-ext4fs=/g' $CFG

	XWRTDIR=$XDIR/package/feeds/_xwrt_packages
	if [ -d $XWRTDIR ]; then
		[ -f $XWRTDIR/natflow/files/hostacl.config ] && sed -i 's/192.168.15./192.168.1./g' $XWRTDIR/natflow/files/hostacl.config
		[ -f $XWRTDIR/natflow/files/natflow.config ] && sed -i 's/192.168.15./192.168.1./g' $XWRTDIR/natflow/files/natflow.config
		[ -f $XWRTDIR/lua-ipops/src/ipops.lua      ] && sed -i 's/192.168.15./192.168.1./g' $XWRTDIR/lua-ipops/src/ipops.lua
		XWRTJSDIR=$XWRTDIR/luci-app-natflow-users/htdocs/luci-static/resources/view
		[ -f $XWRTJSDIR/network/hostacl.js         ] && sed -i 's/192.168.15./192.168.1./g' $XWRTJSDIR/network/hostacl.js
		[ -f $XWRTJSDIR/network/natflow-qos.js     ] && sed -i 's/192.168.15./192.168.1./g' $XWRTJSDIR/network/natflow-qos.js
		[ -f $XWRTJSDIR/system/natflow-users.js    ] && sed -i 's/192.168.15./192.168.1./g' $XWRTJSDIR/system/natflow-users.js
		USERS_MENU=$XWRTDIR/luci-app-natflow-users/root/usr/share/luci/menu.d/luci-app-natflow-users.json
		if [ -f $USERS_MENU ]; then
			if grep -q -F '"admin/system/users": {' $USERS_MENU ; then
				sed -i '/"admin\/system\/users": {/i "admin\/system\/users"  :  {' $USERS_MENU
				sed -i '/"admin\/system\/users": {/,+2d' $USERS_MENU
				sed -i '/"admin\/system\/users"  :  {/a "order": 89,' $USERS_MENU
				sed -i '/"admin\/system\/users"  :  {/a "title": "Users",' $USERS_MENU
			fi
		fi
	fi	
	
	NTFS3G=$XDIR/package/feeds/packages/ntfs-3g/Makefile
	if [ -f $NTFS3G ]; then
		if grep -q -F '$(INSTALL_DIR) $(1)/usr/{bin,sbin}' $NTFS3G ; then
			sed -i  '/\$(INSTALL_DIR) \$(1)\/usr\/{bin,sbin}/a \\t\$(INSTALL_DIR) \$(1)\/usr\/bin' $NTFS3G
			sed -i  '/\$(INSTALL_DIR) \$(1)\/usr\/{bin,sbin}/a \\t\$(INSTALL_DIR) \$(1)\/usr\/sbin' $NTFS3G
			sed -i 's/\$(INSTALL_DIR) \$(1)\/usr\/{bin,sbin}/#\$(INSTALL_DIR) \$(1)\/usr\/__bin_sbin__/g' $NTFS3G
		fi
	fi
	
	XPATCHES=$XDIR/patches
	for incfn in $XPATCHES/*.patch; do
		[ ! -f "$incfn" ] && continue
		inc=`patch -p1 -N -r - < "$incfn"`
		if [ $? != 0 ]; then
			if ! echo "$inc" | grep -q "patch detected!  Skipping patch."; then
				echo "Patch '$(basename $incfn)' FAILED"
				exit 1
			fi
		fi
		echo "Patch '$(basename $incfn)' result: OK"
	done
	
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
		PKG_LINK="https://fantastic-packages.github.io/packages/releases/<<VER>>/packages/<<ARCH>>"
		echo "" >> $OPKG_CFEED_FN
		echo "src/gz  fantastic_packages_luci      $PKG_LINK/luci"      >> $OPKG_CFEED_FN
		echo "src/gz  fantastic_packages_packages  $PKG_LINK/packages"  >> $OPKG_CFEED_FN
		echo "src/gz  fantastic_packages_special   $PKG_LINK/special"   >> $OPKG_CFEED_FN
		TARGET_ARCH_PACKAGES=$( get_cfg_opt_value $CFG TARGET_ARCH_PACKAGES )
		[ -z "$TARGET_ARCH_PACKAGES" ] && die "Cannot find TARGET ARCH"
		sed -i "s/<<VER>>/24.10/g" $OPKG_CFEED_FN
		sed -i "s/<<ARCH>>/$TARGET_ARCH_PACKAGES/g" $OPKG_CFEED_FN
		logmsg "Added support of Fantastic packages [https://fantastic-packages.github.io/packages]"
	fi
	if [ $BUILD_ONLY_INITRAMFS = true ]; then
		rm -f $OPKG_DIR/customfeeds.conf
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

	[ "$ONLY_INIT" = "true" ] && return 0

	make -j $make_jobs download world
}

function build_config {
	local cfg=$1
	local cfg_name=$( basename $cfg )
	local target_name=${cfg_name%.*}
	local initramfs=false
	local board=$( get_cfg_board $cfg )
	local subtarget=$( get_cfg_subtarget $cfg $board )
	local device=$( get_cfg_dev_lst $cfg $board $subtarget )
	local outdir=$XDIR/bin/targets/$board/$subtarget	

	if echo "$cfg" | grep -q '_initramfs/' ; then
		initramfs=true
		target_name=${target_name}_initramfs
	fi
	echo Start build for target $target_name "($board-$subtarget-$device)"

	build_target $cfg
	
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
	if [ $BUILD_ONLY_INITRAMFS = true ]; then
		TARGETCFG=$XDIR/_initramfs/$XTARGET
	fi
	XTARGET_EXT="${XTARGET##*.}"
	[ $XTARGET_EXT != config ] && TARGETCFG=$TARGETCFG.config
	[ ! -f $TARGETCFG ] && die "File '"`basename $TARGETCFG`"' not found!"
	
	[ $OPT_FULL_REBUILD = true ] && clean_all
	
	build_target $TARGETCFG
	exit 0
fi

XOUT=$XDIR/xout

if [ $BUILD_ONLY_INITRAMFS = true ]; then
	CFG_LIST=$( find $XDIR/_initramfs/* -maxdepth 1 -name '[a-z0-9]*.config' )
else
	CFG_LIST=$( find $XDIR/* -maxdepth 1 -name '[a-z0-9]*.config' )
fi

rm -rf $XOUT

if [ -z "$CFG_LIST" ]; then
	echo "ERROR: Cannot found supported configs!"
	exit 1
fi

if [ $BUILD_ONLY_INITRAMFS = true ]; then
	echo "Start make initramfs configs!"
else
	echo "Start make non initramfs configs!"
fi	
	
clean_all

for CFG in $CFG_LIST; do
   build_config $CFG
done

echo "All targets was builded!" 
