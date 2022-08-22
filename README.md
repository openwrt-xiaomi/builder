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
git clone https://github.com/openwrt-xiaomi/builder -b v21 openwrt-v21
cd openwrt-v21

./xcreate.sh -v xq-21.02.3
cd xq-21.02.3

./xupdate.sh -f

./xmake.sh -f -t r3d
```
