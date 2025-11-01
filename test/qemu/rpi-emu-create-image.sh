#!/bin/bash
#

VERSION_DIR="raspios_lite_arm64-2024-11-19"
IMAGE="2024-11-19-raspios-bookworm-arm64-lite"
IMAGE_NAME="${IMAGE}.img"
IMAGE_DIR="images"
FINAL_IMAGE_NAME="$IMAGE_DIR/bookworm.img"
FINAL_IMAGE_NAME="images/bookworm.img"
TEMP_IMAGE_NAME="disk.img"
EXPAND_DISK_SIZE="+3G"
EXPAND_SECOND_PARTITION_SIZE="+1G"
THIRD_PARTITION_SIZE="+1G"
PWD_FILE="$(dirname "$0")/passwd.conf"
KEYS_FILE="$(dirname "$0")/keys.conf"

if [[ ! -f $PWD_FILE ]]; then
	echo "Missing $PWD_FILE"
	exit 1
fi
source $PWD_FILE

if [[ ! -f $KEYS_FILE ]]; then
	echo "Missing $KEYS_FILE"
	exit 1
fi

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

	echo "Copying keys ..."
	sudo losetup -P $LOOP $TEMP_IMAGE_NAME
	sudo mount ${LOOP}p2 /mnt
	sudo mkdir -p /mnt/home/pi/.ssh
	sudo mkdir -p /mnt/root/.ssh
	sudo cp $KEYS_FILE /mnt/home/pi/.ssh/authorized_keys &>/dev/null
	sudo cp $KEYS_FILE /mnt/root/.ssh/authorized_keys &>/dev/null

	#echo "Updating fstab"
	#sudo sed -i "s/default/default,x-systemd.device-timeout=300/g" /mnt/etc/fstab
	sudo umount /mnt
	sudo losetup -d $LOOP

	echo "Moving image into image dir ..."
	[[ ! -d $IMAGE_DIR ]] && mkdir $IMAGE_DIR
	cp disk.img $FINAL_IMAGE_NAME
else
	echo "$FINAL_IMAGE_NAME found"
fi
#rm $TEMP_IMAGE_NAME
#rm ${IMAGE_NAME}
