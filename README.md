[![Github All Releases](https://img.shields.io/github/downloads/openwrt-xiaomi/builder/total.svg)](https://github.com/openwrt-xiaomi/builder/releases)
[![Github Latest Release](https://img.shields.io/github/downloads/openwrt-xiaomi/builder/latest/total.svg)](https://github.com/openwrt-xiaomi/builder/releases)
[![ViewCount](https://views.whatilearened.today/views/github/openwrt-xiaomi/builder.svg)](https://github.com/openwrt-xiaomi/builder/releases)
[![Donations Page](https://github.com/andry81-cache/gh-content-static-cache/raw/master/common/badges/donate/donate.svg)](https://github.com/remittor/donate)

# OpenWrt builder

For OpenWrt >= 21.02

## Install dependencies

```
sudo apt-get install git git-core curl rsync
sudo apt-get install build-essential gawk gcc-multilib flex git gettext libncurses5-dev libssl-dev
sudo apt-get install python3-distutils rsync unzip zlib1g-dev
```

## Build firmware

```
git clone https://github.com/openwrt-xiaomi/builder -b v24 openwrt-v24
cd openwrt-v24

./xcreate.sh -v xq-24.10
cd xq-24.10

./xupdate.sh -f

./xmake.sh -f -t r3d
```
