#!/bin/bash

PGM=`basename $0`

if [ `id -u` != 0 ]
then
    echo -e "$PGM needs to be run as root.\n"
    exit 1
fi

source ../../../raspiBackup.sh

DEVICE_FILE="device.dd"
SFDISK_FILE="mkfs.sfdisk"
LOOP_DEVICE=""
FILE_SYSTEMS=(fat16 fat32 ext2 ext3 ext4 btrfs f2fs)
LABELS=(fat16Label fat32Label ext2Label ext3Label ext4Label btrfsLabel f2fsLabel)

trap "{ losetup -D; rm $DEVICE_FILE; }" SIGINT SIGTERM SIGHUP EXIT 

function createDeviceWithPartition() {

	LOOP_DEVICE="$(losetup -f)"

	truncate -s 1G $DEVICE_FILE &>> $LOG_FILE
	sfdisk -f $DEVICE_FILE < $SFDISK_FILE &>> $LOG_FILE
	losetup -P $LOOP_DEVICE	$DEVICE_FILE &>> $LOG_FILE

}

error=0
createDeviceWithPartition

for (( i=0; i<${#FILE_SYSTEMS[@]}; i++ )); do
	fs=${FILE_SYSTEMS[$i]}
	label=${LABELS[$i]}
	echo "Creating and labeling -${fs}- ..."
	makeFilesystemAndLabel $LOOP_DEVICE $fs $label
	crtFs=$(blkid -o udev $LOOP_DEVICE | grep "ID_FS_TYPE=" | cut -f 2 -d "=")
	if [[ "$crtFs" != "$fs" ]]; then
		if [[ $fs =~ "fat" && $crtFs == "vfat" ]]; then
			:
		else
			echo "Error fs $fs. Detected: $crtFs"
			(( error ++ ))
		fi
	fi
	crtLb=$(blkid -o udev $LOOP_DEVICE | grep "ID_FS_LABEL=" | cut -f 2 -d "=")
	if [[ "$crtLb" != "$label" ]]; then
		echo "Error label -${label}-. Detected: -${crtLb}-"
		(( error ++ ))
	fi
done

echo
if (( error )); then
	echo "Test failed"
	exit 1
else
	echo  "Test OK"
	exit 0 
fi	
