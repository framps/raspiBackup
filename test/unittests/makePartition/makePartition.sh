#!/bin/bash

IS_SPECIAL_DEVICE="/dev/mmcblk0p1 mmcblk0p1 /dev/mmcblk0 mmcblk0 /dev/mmcblk mmcblk loop nvme"
IS_NOSPECIAL_DEVICE="/dev/sda1 sda1 /dev/sda sda"

error=0

source ../../../raspiBackup.sh

echo "Testing makePartition"
for p in ${IS_SPECIAL_DEVICE[@]}; do
	echo "Testing $p ..."
	pref="$(makePartition "$p")"
	if [[ "$pref" != "${p}p" ]]; then
		echo "Error $p - got $pref"
		error=1
	fi
	echo "Testing $p 1 ..."
	pref="$(makePartition "$p" 1)"
	if [[ "$pref" != "${p}p1" ]]; then
		echo "Error $p - got $pref"
		error=1
	fi
done

echo
echo "Testing makePartition - no prefix"
for p in ${IS_NOSPECIAL_DEVICE[@]}; do
	echo "Testing $p ..."
	pref="$(makePartition "$p")"
	if [[ "$pref" != "$p" ]]; then
		echo "Error $p - got $pref"
		error=1
	fi
	echo "Testing $p 2 ..."
	pref="$(makePartition "$p" 2)"
	if [[ "$pref" != "${p}2" ]]; then
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
