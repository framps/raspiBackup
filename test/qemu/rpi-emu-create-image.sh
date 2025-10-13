#!/bin/bash
#

VERSION_DIR="raspios_lite_arm64-2024-11-19"
IMAGE="2024-11-19-raspios-bookworm-arm64-lite"
IMAGE_NAME="${IMAGE}.img"

if [[ ! -f ${IMAGE_NAME}.xz ]]; then
	wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/$VERSION_DIR/${IMAGE_NAME}.xz
	echo "Unzip image..."
	unxz ${IMAGE_NAME}.xz
fi

echo "Copying $IMAGE_NAME ..."
cp $IMAGE_NAME disk.img

echo "Truncating ..."
truncate -s +3G disk.img

echo "Resizing ..."
sudo virt-resize --expand /dev/sda2 $IMAGE_NAME disk.img

echo "Configuring password ..."
LOOP=$(sudo losetup -f)
sudo losetup -P $LOOP disk.img
sudo mount ${LOOP}p1 /mnt
PW=$(openssl passwd -6)
echo "pi:$PW" | sudo tee /mnt/userconf.txt
sudo touch /mnt/ssh
sudo umount /mnt
sudo losetup -d /dev/loop0

echo "Converting to qcow2 ..."
qemu-img convert -f raw -O qcow2 disk.img bookworm.qcow2

[[ ! -d images ]] && mkdir images
echo "Moving image into image dir ..."
mv bookworm.qcow2 images/bookworm.qcow2

#rm disk.img
#rm ${IMAGE_NAME}
