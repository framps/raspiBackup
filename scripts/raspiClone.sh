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

function parseSfdisk() { # device, e.g. /dev/mmcblk0

	local sourceValues=( $(awk '/[0-9]+ :/ { v=$4 $6; gsub(","," ",v); printf "%s",v }' <<< "$(sfdisk -d $1)") )

	local s=${#sourceValues[@]}

	echo "${sourceValues[@]}"
}

partitions=( $(parseSfdisk $1) )

for (( i=0; i<${#partitions[@]}; i+=2 )); do

	echo "Partition $(( i/2 )): Size $(bytesToHuman $(( ${partitions[$((i+1))]} * 512 )) )"

done
