#!/bin/bash
VERSION=6.6.49

wget https://cdn.kernel.org/pub/linux/kernel/v${VERSION//.*/.x}/linux-${VERSION}.tar.xz
tar -xvJf linux-${VERSION}.tar.xz

cd linux-${VERSION}

ARCH=arm64 CROSS_COMPILE=/bin/aarch64-linux-gnu- make defconfig
ARCH=arm64 CROSS_COMPILE=/bin/aarch64-linux-gnu- make kvm_guest.config
ARCH=arm64 CROSS_COMPILE=/bin/aarch64-linux-gnu- make -j8

cp arch/arm64/boot/Image ../kernel
cd ..

