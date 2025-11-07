#!/bin/bash
VERSION=6.6.85
<<<<<<< HEAD
=======

:<<SKIP
>>>>>>> a1bdf9e579b59b2e27ffaac4df2f692309ac5559
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  qemubuilder qemu-system-gui qemu-system-arm qemu-utils qemu-system-data qemu-system \
  bison flex guestfs-tools libssl-dev telnet xz-utils

wget https://cdn.kernel.org/pub/linux/kernel/v${VERSION//.*/.x}/linux-${VERSION}.tar.xz
tar -xvJf linux-${VERSION}.tar.xz
<<<<<<< HEAD

=======
SKIP
>>>>>>> a1bdf9e579b59b2e27ffaac4df2f692309ac5559
cd linux-${VERSION}

ARCH=arm64 CROSS_COMPILE=/bin/aarch64-linux-gnu- make defconfig
ARCH=arm64 CROSS_COMPILE=/bin/aarch64-linux-gnu- make kvm_guest.config
ARCH=arm64 CROSS_COMPILE=/bin/aarch64-linux-gnu- make -j8

cp arch/arm64/boot/Image ../kernel
cd ..

