#!/bin/bash

#######################################################################################################################
#
# 	 Unit test for sfdisk resize of last partition
#
#######################################################################################################################
#
#    Copyright (c) 2024 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

source ../../../raspiBackup.sh

testFile=$(mktemp)

(( GIB = 1024*1024*1024 ))

GB128=128035676160 # sectors 250069680
GB32=31268536320 # sectors 61071360

function test_createResizedSFDisk() { # sfdisk_file target_size new_partition_size

	local targetSize=$2
	local targetPartitionSize=$3

	local partitionSizes=($(createResizedSFDisk "$1" "$targetSize" "$testFile"))
	local old=${partitionSizes[0]}
	local new=${partitionSizes[1]}

	local fail=0

	resizedSize="$(calcSumSizeFromSFDISK "$testFile")"

	if (( resizedSize != targetSize )); then
		if [[ -z $4 ]] || (( new > 0 )); then
			echo -n "??? --- "
			echo "$1: Expected disk size: $targetSize ($(bytesToHuman $targetSize)) - Received: $resizedSize ($(bytesToHuman $resizedSize))"
			fail=1
			(( errors ++ ))
			return
		fi
	fi

	if (( new != targetPartitionSize )); then
		echo -n "??? --- "
		fail=1
		echo "$1: Expected partition size: $targetPartitionSize ($(bytesToHuman $targetPartitionSize)) - Received: $new ($(bytesToHuman $new))"
		(( errors ++ ))
		return
	fi

	if [[ -n $4 ]]; then
		echo -n "OKN --- "
	else
		echo -n "OKP --- "
	fi

	echo "$1: $resizedSize ($(bytesToHuman $resizedSize)) Old partition size: $old ($(bytesToHuman $old)) New partitionSize: $new ($(bytesToHuman $new))"

}

function test_calcSumSizeFromSFDISK() { # sfdisk_file expected_size

	local size="$(calcSumSizeFromSFDISK "$1")"

	if (( size != $2 )); then
		echo -ne "??? --- $1: Expected: $2 ($(bytesToHuman $2)) - Received: $size ($(bytesToHuman $size))\n"
		(( errors ++ ))
	else
		echo -ne "OK --- $1: $size ($(bytesToHuman $size))\n"
	fi

}

errors=0
executeCalcTest=1
executeResizeTest=1

if (( executeCalcTest )); then
	echo
	echo "--- test_calcSumSizeFromSFDISK ---"
	echo
	test_calcSumSizeFromSFDISK "$PWD/32GB.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "32GB.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "32GB_nosecsize.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "128GB.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "128GB_nosecsize.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "10+22GB.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "10+22GB-1ext.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "10+10+12GB.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "10+10+12GB-1ext.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "100+28GB.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "100+28GB-1ext.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "28+100GB.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "28+100GB-1ext.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "28+5+95GB-2ext.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "28+95+5GB-2ext.sfdisk" 128035676160
	test_calcSumSizeFromSFDISK "mmcblk0.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "mmcblk0-2ext.sfdisk" 31268536320
	test_calcSumSizeFromSFDISK "$PWD/nvme0n1.sfdisk" 128035676160
fi

if (( executeResizeTest )); then
	echo
	echo "--- test_createResizedSFDisk ---"
	echo
	# shrink
	test_createResizedSFDisk "18-11GB.sfdisk" $((32000000000 - ( 11999461376 - 512) )) 512
	test_createResizedSFDisk "18-11GB.sfdisk" $((32000000000 - ( 11999461376 + 1) )) -512 FAIL
	test_createResizedSFDisk "128GB.sfdisk" 31268536320 30727471104
	test_createResizedSFDisk "128GB_nosecsize.sfdisk" 31268536320 30727471104
	test_createResizedSFDisk "28+100GB.sfdisk" 31268536320 10607042560
	test_createResizedSFDisk "28+100GB-1ext.sfdisk" 31268536320 10607042560
	test_createResizedSFDisk "28+5+95GB-2ext.sfdisk" 31268536320 5776605184
	test_createResizedSFDisk "28+95+5GB-2ext.sfdisk" 31268536320 -90860159488 FAIL
	test_createResizedSFDisk "100+28GB.sfdisk" 31268536320 -76646711808 FAIL
	# extend
	test_createResizedSFDisk "32GB.sfdisk" 128035676160 127494610944
	test_createResizedSFDisk "32GB_nosecsize.sfdisk" 128035676160 127494610944
#	test_createResizedSFDisk "10+22GB.sfdisk" 128035676160 116757192704#
#	test_createResizedSFDisk "10+22GB-1ext.sfdisk" 128035676160 116757192704
fi

rm $testFile
#mv $testFile test.sfdisk

echo
if (( errors > 0 )); then
	echo "??? Test failed with $errors errors"
	exit 1
else
	echo "!!! Test completed without errors"
	exit 0
fi


