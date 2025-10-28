#!/bin/bash
#

VERSION_DIR="raspios_lite_arm64-2024-11-19"
IMAGE="2024-11-19-raspios-bookworm-arm64-lite"
IMAGE_NAME="${IMAGE}.img"
FINAL_IMAGE_NAME="images/bookworm.img"
TEMP_IMAGE_NAME="disk.img"
EXPAND_DISK_SIZE="+3G"
EXPAND_SECOND_PARTITION_SIZE="+1G"
THIRD_PARTITION_SIZE="+1G"
PWD_FILE="$(dirname "$0")/./passwd.conf"

if [[ ! -f $PWD_FILE ]]; then
	echo "Missing $PWD_FILE"
	exit 1
fi

source $PWD_FILE

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

	sudo losetup -D

	echo "Copying $IMAGE_NAME ..."
	cp $IMAGE_NAME $TEMP_IMAGE_NAME
	echo "Expanding disk $EXPAND_DISK_SIZE ..."
	truncate -s $EXPAND_DISK_SIZE $TEMP_IMAGE_NAME

	echo "Expanding 2nd partition $EXPAND_SECOND_PARTITION_SIZE ..."
	sudo virt-resize --resize /dev/sda2=$EXPAND_SECOND_PARTITION_SIZE $IMAGE_NAME $TEMP_IMAGE_NAME

	echo "Creating 3nd partition $THIRD_PARTITION_SIZE ..."
	LOOP=$(sudo losetup -f)
	sudo losetup -P $LOOP $TEMP_IMAGE_NAME
	echo "Formatting 3nd partition ..."
	sudo mkfs.ext4 ${LOOP}p3

	printf "n\np\n3\n\n$THIRD_PARTITION_SIZE\w\n" | sudo fdisk $LOOP
	sudo fdisk -l $LOOP
	sudo losetup -d $LOOP

	echo "Configuring password ..."
	LOOP=$(sudo losetup -f)
	sudo losetup -P $LOOP $TEMP_IMAGE_NAME
	sudo mount ${LOOP}p1 /mnt
	PW=$(openssl passwd -6 -- $PASSWD )
	echo "pi:$PW" | sudo tee /mnt/userconf.txt
	sudo touch /mnt/ssh
	sudo umount /mnt
	echo "Creating file on 3rd paritition ..."
	sudo mount ${LOOP}p3 /mnt
	sudo echo "Hello partition 3" | tee /mnt/partition3.txt &>/dev/null
	sudo umount /mnt
	sudo losetup -d $LOOP

	echo "Moving image into image dir ..."
	mv disk.img $FINAL_IMAGE_NAME
else
	echo "$FINAL_IMAGE_NAME found"
fi
#rm $TEMP_IMAGE_NAME
#rm ${IMAGE_NAME}
