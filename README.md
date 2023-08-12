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
git clone https://github.com/openwrt-xiaomi/builder -b v23 openwrt-v23
cd openwrt-v23

./xcreate.sh -v xq-23.05.0
cd xq-23.05.0

./xupdate.sh -f

./xmake.sh -f -t r3d
```
