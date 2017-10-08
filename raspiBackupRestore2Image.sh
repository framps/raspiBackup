#!/bin/bash
#
#######################################################################################################################
#
# Create an image file which can be restored with dd or win32diskimager from a tar or rsync backup created by raspiBackup
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup to get more details about raspiBackup
#
#######################################################################################################################
#
#    Copyright (C) 2017 framp at linux-tips-and-tricks dot de
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

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

# query invocation pams

BACKUPPATH="$1"
TARGET_DIRECTORY="$2"

if [[ $IMAGE_DIRECTORY == "" ]]; then
	IMAGE_DIRECTORY="."
	IMAGE_FILENAME="raspiBackup.img"
fi	
		
IMAGE_ABSOLUT_FILENAME="$IMAGE_DIRECTORY/$IMAGE_FILENAME"

function usage() {
	echo "\$1: raspiBackup Backuppath"
	echo "\$2: Image file directory (optional). Default is current directory"
}	

function calcSumSizeFromSFDISK() { # sfdisk filename

	local file="$1"

	local partitionregex="/dev/.*[p]?([0-9]+)[^=]+=[^0-9]*([0-9]+)[^=]+=[^0-9]*([0-9]+)[^=]+=[^0-9a-z]*([0-9a-z]+)"
	local lineNo=0
	local sumSize=0

	while IFS="" read line; do
		(( lineNo++ ))
		if [[ -z $line ]]; then
			continue
		fi

		if [[ $line =~ $partitionregex ]]; then
			local p=${BASH_REMATCH[1]}
			local start=${BASH_REMATCH[2]}
			local size=${BASH_REMATCH[3]}
			local id=${BASH_REMATCH[4]}

			if [[ $id == 85 || $id == 5 ]]; then
				continue
			fi

			if [[ $sumSize == 0 ]]; then
				sumSize=$((start+size))
			else
				(( sumSize+=size ))
			fi
		fi

	done < $file

	(( sumSize *= 512 ))

	echo "$sumSize"

}

if (( $# < 1 )); then
	usage
	exit 0
fi	

if (( $UID != 0 )); then
	echo "$MYSELF has to be invoked via sudo"
	exit
fi

# check for prerequisites

if [[ ! $(which raspiBackup.sh) ]]; then
	echo "raspiBackup.sh not found"
	exit 1
fi

if [[ ! $(which pishrink.sh) ]]; then
	echo "pishrink.sh not found"
	exit 1
fi

# cleanup

rm "$IMAGE_ABSOLUT_FILENAME"

# calculate required image dis size

SFDISK_FILE=$(ls $BACKUPPATH/*.sfdisk)
SOURCE_DISK_SIZE=$(calcSumSizeFromSFDISK $SFDISK_FILE)

mb=$(( $SOURCE_DISK_SIZE / 1024 / 1024 )) # calc MB
echo "===> Backup source disk size: $mb (MiB)"

# create image file

dd if=/dev/zero of="$IMAGE_ABSOLUT_FILENAME" bs=1024k seek=$(( $mb )) count=0
losetup -f "$IMAGE_ABSOLUT_FILENAME"
sfdisk -uSL /dev/loop0 < "$BACKUPPATH/jessie-small-backup.sfdisk"

# restore backup into image

raspiBackup.sh -1 -Y -F -l debug -d /dev/loop0 "$BACKUPPATH"

# cleanup

losetup -d /dev/loop0

# now shrink image

pishrink.sh "$IMAGE_ABSOLUT_FILENAME"
