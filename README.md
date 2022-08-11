# OpenWrt builder

For OpenWrt >= 21.02

## Install dependencies

```
sudo apt-get install git git-core curl rsync
sudo apt-get install build-essential subversion libncurses5-dev zlib1g-dev gawk gcc-multilib flex gettext libssl-dev unzip
```

## Build firmware

```
git clone https://github.com/openwrt-xiaomi/builder -b v21 openwrt-v21
cd openwrt-v21
./xcreate.sh -v xq-21.02.1
cd xq-21.02.1
./xupdate.sh -f
./xmake.sh -f -t r3d
```
