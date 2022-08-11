#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export XDIR=$SCRIPT_DIR

. ./xcommon.sh

[ -z "$*" ] && die "No options found!"

while getopts "v:" opt; do
	case $opt in
		v ) TARGET_BRANCH=$OPTARG;;
	esac
done 

[ -z "$TARGET_BRANCH" ] && TARGET_BRANCH=$XDEFBRANCH

[ -d "$XDIR/$TARGET_BRANCH" ] && die "Directory '$TARGET_BRANCH' already exist!"

XREPOWRT=$XREPOADDR/openwrt.git
git clone $XREPOWRT -b $TARGET_BRANCH $TARGET_BRANCH
if [ "$?" != "0" ]; then
	rm -rf ./$TARGET_BRANCH
	die "Repository '$XREPOWRT' not found!"
fi

XTOPDIR=$XDIR/$TARGET_BRANCH

#find . -maxdepth 1 -type f -name "*.sh" -exec chmod 775 -- {} + >/dev/null
find . -maxdepth 1 -type f -name "*.sh" -exec cp {} $XTOPDIR \; >/dev/null
find . -maxdepth 1 -type f -name "*.config" -exec cp {} $XTOPDIR \; >/dev/null

echo "Repository '$TARGET_BRANCH' created!"
#cd $XTOPDIR

