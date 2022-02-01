#!/bin/bash

#######################################################################################################################
#
# Retrieve and check PARTUUIDs of a Raspberry SD card
# and check if they match with BLKID
#
#######################################################################################################################
#
#    Copyright (c) 2022 framp at linux-tips-and-tricks dot de
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

set -euo pipefail

function reportRootCause() {
	[[ $cmdUUID != ${UUIDs[1]} ]] && echo "cmdUUIDs are different: $cmdUUID - ${cmdUUID UUIDs[1]}"
	[[ ${fstabUUIDs[0]} != ${UUIDs[0]} ]] && echo "fstabUUIDs[0] are different: ${fstabUUIDs[0]} - ${UUIDs[0]}"
	[[ ${fstabUUIDs[1]} != ${UUIDs[1]} ]] && echo "fstabUUIDs[1] are different: ${fstabUUIDs[1]} - ${UUIDs[1]}"
}

if [[ $USER != "root" ]]; then
        echo "Call me as root"
        exit 255
fi

if (( $# < 1 )); then
        echo "Missing SD card device of Raspian image (Example /dev/sda), /dev/mmcblk1p"
        exit 255
fi

device="$1"

echo "Checking PARTUUIDs"
UUIDs=( $(blkid | grep "$device" | grep -E -o 'PARTUUID=".*"' | sed -e "s/PARTUUID=//" -e "s/\"//g") )

echo "UUID[0]: ${UUIDs[0]}"
echo "UUID[1]: ${UUIDs[1]}"

mount "${device}1" /mnt
if (( $? )); then
	echo "Error mounting $device"
	exit 255
fi

cmdUUID=$(grep -Eo "root=PARTUUID=\S+" /mnt/cmdline.txt | sed "s/root=PARTUUID=//" )
echo "cmdUUID: $cmdUUID"
echo "########################################"
cat /mnt/cmdline.txt
echo "########################################"
umount /mnt

mount "${device}2" /mnt
fstabUUIDs=( $(grep -E "/boot\s|/\s" /mnt/etc/fstab | grep -Eo 'PARTUUID=\S+' | sed "s/PARTUUID=//") )
echo "fstabUUID[0]: ${fstabUUIDs[0]}"
echo "fstabUUID[1]: ${fstabUUIDs[1]}"
echo "########################################"
cat /mnt/etc/fstab
echo "########################################"

umount /mnt

if [[ $cmdUUID != ${UUIDs[1]} ]] \
|| [[ ${fstabUUIDs[0]} != ${UUIDs[0]} ]] \
|| [[ ${fstabUUIDs[1]} != ${UUIDs[1]} ]]; then
        echo "??? Mismatch ???"
        reportRootCause
else
        echo "!!! Match  !!!"
fi
