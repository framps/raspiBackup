#!/bin/bash

#######################################################################################################################
#
# Retrieve and check PARTUUIDs of an Raspberry dd Backup image
# and check if they match with BLKID
#
#######################################################################################################################
#
#    Copyright (c) 2021 framp at linux-tips-and-tricks dot de
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

if [[ $USER != "root" ]]; then
        echo "Call me as root"
        exit 255
fi

if [[ -z $1 ]]; then
        echo "Missing image file"
        exit 255
fi

echo "Mounting image $1"
kpartx -av $1
rc=$?
if (( $rc != 0 )); then
        echo "kpartx error: $rc"
        exit 255
fi
echo

echo "Checking PARTUUIDs"
loopUUIDs=( $(blkid | grep "/dev/mapper/loop" | grep -E -o 'PARTUUID=".*"' | sed -e "s/PARTUUID=//" -e "s/\"//g") )

echo "loopUUID[0]: ${loopUUIDs[0]}"
echo "loopUUID[1]: ${loopUUIDs[1]}"

mount /dev/mapper/loop0p1 /mnt
cmdUUID=$(grep -Eo "root=PARTUUID=\S+" /mnt/cmdline.txt | sed "s/root=PARTUUID=//" )
echo "cmdLineUUID: $cmdUUID"
umount /mnt

mount /dev/mapper/loop0p2 /mnt
fstabUUIDs=( $(grep -E "/boot\s|/\s" /mnt/etc/fstab | grep -Eo 'PARTUUID=\S+' | sed "s/PARTUUID=//") )
echo "fstabUUID[0]: ${fstabUUIDs[0]}"
echo "fstabUUID[1]: ${fstabUUIDs[1]}"

umount /mnt

if [[ $cmdUUID != ${loopUUIDs[1]} ]] \
|| [[ ${fstabUUIDs[0]} != ${loopUUIDs[0]} ]] \
|| [[ ${fstabUUIDs[1]} != ${loopUUIDs[1]} ]]; then
        echo "??? Mismatch ???"
else
        echo "!!! Match  !!!"
fi
