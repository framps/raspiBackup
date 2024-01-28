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

partitions=( $(parseSfdisk $1) )

for (( i=0; i<${#partitions[@]}; i+=4 )); do

	echo "Partition $(( i/4 )): Start: ${partitions[$((i+1))]} Size $(bytesToHuman $(( ${partitions[$((i+2))]} * 512 )) ) Type: ${partitions[$((i+3))]}"

done
