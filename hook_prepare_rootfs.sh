#!/usr/bin/env bash

CURDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ROOTFSDIR="$1"
TOPDIR="$2"
OUTDIR=

[ -z "$OUTDIR" ] && OUTDIR=$TOPDIR

if [ -t 8 ]; then
	BUILD_STATE=true
	OUTPUT_PIPE=8
else
	BUILD_STATE=false
	OUTPUT_PIPE=2
fi

log_msg() {
	printf "%s\n" "$1" >&$OUTPUT_PIPE
}

log_err() {
	local msg="$1"
	local _Y _R _N
	if [ "$IS_TTY" == "1" -a "$NO_COLOR" != "1" ]; then
		_Y=\\033[33m
		_R=\\033[31m
		_N=\\033[m
	fi
	printf "$_R%s$_N\n" "ERROR: $msg" >&$OUTPUT_PIPE
}

die() {
	log_err "$1"
	exit 1
}

get_param_q() {
	local param=$1
	local filename="$2"
	echo $( grep -o -P "^$param='\K[^']+" "$filename" 2>/dev/null | tr -d '\n' )
	#echo $( grep -o -P "(?<=^$param=').*(')" "$filename" 2>/dev/null )
}

del_last_word() {
	echo -n "${@:1:$#-1}"
}


log_msg "hook_prepare_rootfs.sh"
#log_msg "TOPDIR: '$TOPDIR'"
#log_msg "ROOTFSDIR: '$ROOTFSDIR'"

if [ ! -d "$ROOTFSDIR" ]; then
	die "RootFS dir not found!"
fi

FW_VER_FN="$ROOTFSDIR/etc/openwrt_release"
if [ ! -f "$FW_VER_FN" ]; then
	die "File '/etc/openwrt_release' not found!"
fi

FULL_VERSION=$( get_param_q DISTRIB_RELEASE "$FW_VER_FN" )
#log_msg "FULL_VERSION: '$FULL_VERSION'"
if [ -z "$FULL_VERSION" ]; then
	die "Firmware version not found!"
fi

CURDATE=$( date --utc +%y%m%d | tr -d '\n' )

DISTR_REV=$( get_param_q DISTRIB_REVISION "$FW_VER_FN" )
DISTR_DESC=$( get_param_q DISTRIB_RELEASE "$FW_VER_FN" )
DISTR_DATE_LEN=$( echo -n "$DISTR_DESC" | awk '{print $NF}' | tr -d '\n' | wc -c )
if [ "$DISTR_DATE_LEN" = 6 ]; then
	DISTR_DESC=$( del_last_word $DISTR_DESC )
fi
sed -i "/DISTRIB_DESCRIPTION=/d" "$FW_VER_FN"
echo "DISTRIB_DESCRIPTION='$DISTR_DESC $CURDATE'" >> "$FW_VER_FN"
log_msg "Option DISTRIB_DESCRIPTION patched (DATE = $CURDATE)"

BANNER_FN="$ROOTFSDIR/etc/banner"
BANNER_VER=$( grep -F "$DISTR_REV" "$BANNER_FN" 2>/dev/null )
if [ -n "$BANNER_VER" ]; then
	BANNER_SUFFIX=$( echo -n "$BANNER_VER" | awk '{print $NF}' | tr -d '\n' )
	if [ $( echo -n "$BANNER_SUFFIX" | wc -c ) = 6 ]; then
		sed -i "s/, $BANNER_SUFFIX/, $CURDATE/g" "$BANNER_FN"
	else
		sed -i "s/$DISTR_REV/&, $CURDATE/" "$BANNER_FN"
	fi
fi
log_msg "Banner patched (DATE = $CURDATE)"

FW_ARCH=$( get_param_q DISTRIB_ARCH "$FW_VER_FN" )
#log_msg "FW_ARCH: '$FW_ARCH'"
if [ -z "$FW_ARCH" ]; then
	die "Firmware arch not found!"
fi

DIS_SVC_FN="$TOPDIR/disabled_services.lst"
if [ -f "$DIS_SVC_FN" ]; then
	DIS_SVC_LST="$( cat ""$DIS_SVC_FN"" )"
	for svc in $DIS_SVC_LST; do
		[ -z "$svc" ] && continue
		svc_xx=$(find "$ROOTFSDIR/etc/rc.d" -maxdepth 1 -name ???$svc -printf 1 -quit)
 	    if [ -n "$svc_xx" ]; then
			log_msg "Service '$svc' disabled."
		fi
		rm -f "$ROOTFSDIR"/etc/rc.d/S??$svc
		rm -f "$ROOTFSDIR"/etc/rc.d/K??$svc
	done
fi

NEXTDNSCFG="$ROOTFSDIR/etc/config/nextdns"
if [ -f "$NEXTDNSCFG" ]; then
	sed -i "s/option enabled '1'/option enabled '0'/g" "$NEXTDNSCFG"
	log_msg "Service 'nextdns' disabled."
fi

IS_SNAPSHOT=false
if echo "$FULL_VERSION" | grep snapshot >/dev/null ; then
	IS_SNAPSHOT=true
	log_msg "Snapshot detected."
fi

