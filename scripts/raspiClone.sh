#!/bin/bash

### under construction

set -euo pipefail

function bytesToHuman() {
	local b d s S
	local sign=1
	b=${1:-0}; d=''; s=0; S=(Bytes {K,M,G,T,E,P,Y,Z}iB)
	if (( b < 0 )); then
		sign=-1
		(( b=-b ))
	fi
	while ((b > 1024)); do
		d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
		b=$((b / 1024))
		let s++
	done
	if (( sign < 0 )); then
		(( b=-b ))
	fi
	echo "$b$d ${S[$s]}"
}

#						label: dos
#						label-id: 0x3c3f4bdb
#						device: /dev/mmcblk0
#						unit: sectors
#						sector-size: 512
#
#						/dev/mmcblk0p1 : start=        8192, size=      524288, type=c
#						/dev/mmcblk0p2 : start=      532480, size=    15196160, type=83

function parseSfdisk() { # device, e.g. /dev/sda

	local device="$1"

	readonly REGEXPARTITIONLINE="($device[a-z0-9]+).*start[^0-9]+([0-9]+).*size[^0-9]+([0-9]+).*(Id|type)=[ ]?([^,]+)"

	partitionInfo=()

	while read line; do

		if [[ $line =~ $REGEXPARTITIONLINE ]]; then
			partition=${BASH_REMATCH[1]}
			start=${BASH_REMATCH[2]}
			size=${BASH_REMATCH[3]}
			type=${BASH_REMATCH[5]}

			local newPartition=( $partition $start $size $type )
			partitionInfo+=( "${newPartition[@]}" )
		fi

	done < <(sfdisk -d $1)

	echo "${partitionInfo[@]}"
}

readonly SOURCE_DEVICE="$1"
readonly TARGET_DEVICE="/dev/sdb"

readonly MIN_FREE_SPACE=$((8*1024*1024*1024))    # 8GB minimum space reuiqred for last partition

partitions=( $(parseSfdisk $SOURCE_DEVICE) )

sourceNumberOfPartitions=$(( ${#partitions[@]} / 4 ))

if (( $sourceNumberOfPartitions < 2 )); then
	echo "At least 2 partitions required"
	exit 42
fi

for (( i=0; i<${#partitions[@]}; i+=4 )); do
	echo "$SOURCE_DEVICE - Partition $(( i/4 )): Start: ${partitions[$((i+1))]} Size $(bytesToHuman $(( ${partitions[$((i+2))]} * 512 )) ) Type: ${partitions[$((i+3))]}"
done

lastUsedPartitionIndex=$(( ${#partitions[@]} - 4 ))
lastUsedSize=$(( ( ${partitions[$((lastUsedPartitionIndex+2))]} ) * 512 ))
lastUsedByte=$(( ( ${partitions[$((lastUsedPartitionIndex+1))]} + ${partitions[$((lastUsedPartitionIndex+2))]} ) * 512 ))
lastUsedStartByte=$(( ${partitions[$((lastUsedPartitionIndex+1))]} * 512 ))

readonly SOURCE_DEVICE_SIZE=$(blockdev --getsize64 $SOURCE_DEVICE)
readonly TARGET_DEVICE_SIZE=$(blockdev --getsize64 $TARGET_DEVICE)

echo "LastUsedStart: $lastUsedStartByte $( bytesToHuman $lastUsedStartByte)"
echo "LastUsed: $lastUsedByte $( bytesToHuman $lastUsedByte)"
echo "Unused: $(( ( SOURCE_DEVICE_SIZE - lastUsedByte ) )) $(bytesToHuman $(( ( SOURCE_DEVICE_SIZE - lastUsedByte ) )) )"

echo "Total source: $SOURCE_DEVICE_SIZE $(bytesToHuman $SOURCE_DEVICE_SIZE)"
echo "Total target: $TARGET_DEVICE_SIZE $(bytesToHuman $TARGET_DEVICE_SIZE)"

newUsedByte=$(( $TARGET_DEVICE_SIZE - lastUsedStartByte ))

echo "NewUsed: $newUsedByte $(bytesToHuman $newUsedByte)"

if (( $newUsedByte <= 0 )); then
	echo "Target device too small"
	exit 42
fi

lastUsedSector=$(( lastUsedSize / 512 ))
newUsedSector=$(( ( newUsedByte - lastUsedStartByte ) / 512 ))

sfdisk -d $SOURCE_DEVICE

sed "s/$lastUsedSector/$newUsedSector/" <<< $(sfdisk -d $SOURCE_DEVICE)
