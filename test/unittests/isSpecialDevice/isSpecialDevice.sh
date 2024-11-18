#!/bin/bash

source ../../../raspiBackup.sh

IS_SPECIAL_DEVICE="/dev/mmcblk0p1 mmcblk0p1 /dev/mmcblk0 mmcblk0 /dev/mmcblk mmcblk loop nvme"
IS_NOSPECIAL_DEVICE="/dev/sda1 sda1 /dev/sda sda"
PARTITION_PREFIX="mmcblk0 nvme0n1"
PARTITION_PREFIX_NOP="sda"

error=0

echo "Testing special block devices"
for d in ${IS_SPECIAL_DEVICE[@]}; do
	echo "Testing $d ..."
	if ! isSpecialBlockDevice "$d"; then
		echo "Error $d"
		error=1
	fi
done

echo
echo "Testing non special block devices"
for d in ${IS_NOSPECIAL_DEVICE[@]}; do
	echo "Testing $d ..."
	if isSpecialBlockDevice "$d"; then
		echo "Error $d"
		error=1
	fi
done

echo
echo "Testing getPartitionPrefix"
for p in ${PARTITION_PREFIX[@]}; do
	echo "Testing $p ..."
	pref="$(getPartitionPrefix "$p")"
	if [[ "$pref" != "${p}p" ]]; then
		echo "Error $p - got $pref"
		error=1
	fi
done

echo
echo "Testing getPartitionPrefix - no prefix"
for p in ${PARTITION_PREFIX_NOP[@]}; do
	echo "Testing $p ..."
	pref="$(getPartitionPrefix "$p")"
	if [[ "$pref" != "$p" ]]; then
		echo "Error $p - got $pref"
		error=1
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
