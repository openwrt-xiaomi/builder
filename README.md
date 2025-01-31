[![Github All Releases](https://img.shields.io/github/downloads/openwrt-xiaomi/builder/total.svg)](https://github.com/openwrt-xiaomi/builder/releases)
[![ViewCount](https://views.whatilearened.today/views/github/openwrt-xiaomi/builder.svg)](https://github.com/openwrt-xiaomi/builder/releases)
[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2Fopenwrt-xiaomi%2Fbuilder&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://github.com/openwrt-xiaomi/builder/releases)
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
