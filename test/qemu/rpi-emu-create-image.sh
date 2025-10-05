#!/bin/bash
#

VERSION_DIR="raspios_lite_arm64-2024-11-19"
IMAGE_NAME="2024-11-19-raspios-bookworm-arm64-lite.img"

:<<SKIP
wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/$VERSION_DIR/${IMAGE_NAME}.xz
unxz ${IMAGE_NAME}.xz
SKIP

cp $IMAGE_NAME.img disk.img

truncate -s +3G disk.img
sudo virt-resize --expand /dev/sda2 $IMAGE_NAME disk.img
LOOP=$(sudo losetup -f)
sudo losetup -P $LOOP disk.img
sudo mount ${LOOP}p1 /mnt
PW=$(openssl passwd -6)
echo "pi:$PW" | sudo tee /mnt/userconf.txt
sudo touch /mnt/ssh
sudo umount /mnt
sudo losetup -d /dev/loop0

qemu-img convert -f raw -O qcow2 disk.img bookworm.qcow2

[[ ! -e images ]] && mkdie images
mv bookworm.qcow2 images
