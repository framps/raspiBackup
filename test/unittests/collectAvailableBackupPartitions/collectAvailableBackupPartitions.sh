#!/bin/bash
#

TAR_FILES="sda1.tar sda2.tar sda5.tar mmcblk0p6.tar nvme0n1p7.tar loop1p8.tar dummy9.tar"
RSYNC_DIRS="sda1 sda2 sda5 mmcblk0p6 nvme0n1p7 loop1p8 dummy9"

error=0

source ../../../raspiBackup.sh

echo "Testing tar"

BACKUPTYPE="$BACKUPTYPE_TAR"

for f in $TAR_FILES; do
	touch $f
done

partitions=$(collectAvailableBackupPartitions ".")

if [ ${#partitions[@]} == 1 ]; then
	if [ '8 6 7 1 2 5' == "${partitions}" ]; then
		:
	else
		echo "Error: Got Size ${#partitions[@]}"
		echo "Contents "${partitions[@]}""
		(( error+=1 ))
	fi
else
		echo "Error: Got Size ${#partitions[@]}"
		echo "Contents "${partitions[@]}""
		(( error+=1 ))
fi

for f in $TAR_FILES; do
	rm $f
done

echo "Testing rsync"

BACKUPTYPE="$BACKUPTYPE_RSYNC"

for d in $RSYNC_DIRS; do
	mkdir $d
done

partitions=$(collectAvailableBackupPartitions ".")

if [ ${#partitions[@]} == 1 ]; then
	if [ '8 6 7 1 2 5' == "${partitions}" ]; then
		:
	else
		echo "Error: Got Size ${#partitions[@]}"
		echo "Contents "${partitions[@]}""
		(( error+=1 ))
	fi
else
		echo "Error: Got Size ${#partitions[@]}"
		echo "Contents "${partitions[@]}""
		(( error+=1 ))
fi

for d in $RSYNC_DIRS; do
	rmdir $d
done

echo
if (( error )); then
	echo "Test failed"
	exit 1
else
	echo  "Test OK"
	exit 0 
fi	
