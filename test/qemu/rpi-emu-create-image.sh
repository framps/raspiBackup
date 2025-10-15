#!/bin/bash
#

VERSION_DIR="raspios_lite_arm64-2024-11-19"
IMAGE="2024-11-19-raspios-bookworm-arm64-lite"
IMAGE_NAME="${IMAGE}.img"
FINAL_IMAGE_NAME="images/bookworm.img"
TEMP_IMAGE_NAME="disk.img"

if [[ ! -e ${IMAGE_NAME}.xz && ! -e ${IMAGE_NAME} ]]; then
	echo "Downloading ${IMAGE_NAME}.xz"
	wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/$VERSION_DIR/${IMAGE_NAME}.xz
else
	echo "${IMAGE_NAME}.xz found"
fi

if [[ ! -e ${IMAGE_NAME} ]]; then
	echo "Unzipping image..."
	unxz ${IMAGE_NAME}.xz
else
	echo "$IMAGE_NAME found"
fi

if [[ ! -e $FINAL_IMAGE_NAME ]]; then
	echo "Copying $IMAGE_NAME ..."
	cp $IMAGE_NAME $TEMP_IMAGE_NAME
	echo "Truncating ..."
	truncate -s +3G $TEMP_IMAGE_NAME

	echo "Resizing ..."
	sudo virt-resize --expand /dev/sda2 $IMAGE_NAME $TEMP_IMAGE_NAME

	echo "Configuring password ..."
	LOOP=$(sudo losetup -f)
	sudo losetup -P $LOOP $TEMP_IMAGE_NAME
	sudo mount ${LOOP}p1 /mnt
	PW=$(openssl passwd -6)
	echo "pi:$PW" | sudo tee /mnt/userconf.txt
	sudo touch /mnt/ssh
	sudo umount /mnt
	sudo losetup -d /dev/loop0

	[[ ! -d images ]] && mkdir images
	echo "Moving image into image dir ..."
	mv disk.img $FINAL_IMAGE_NAME
else
	echo "$FINAL_IMAGE_NAME found"
fi
#rm $TEMP_IMAGE_NAME
#rm ${IMAGE_NAME}
