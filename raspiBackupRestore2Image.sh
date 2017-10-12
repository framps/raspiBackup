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

# query invocation parms

BACKUPPATH="$1"
IMAGE_DIRECTORY="${2:-$BACKUPPATH}"
SFDISK_FILE="$(ls $BACKUPPATH/*.sfdisk)"
if [[ -z "$SFDISK_FILE" ]]; then
	echo "??? Incorrect backup path. .sfdisk file not found"
	exit 1
fi
DEFAULT_IMAGE_FILENAME="${SFDISK_FILE%.*}.dd"
IMAGE_FILENAME="${3:-$DEFAULT_IMAGE_FILENAME}"
LOOP=$(losetup -f)

function usage() {
	echo "\$1: Path of backup directory"
	echo "\$2: Image file directory (optional). Default is backup directory"
	echo "\$3: Image file name (optional). Default is raspiBackup.img"
}	

function cleanup() {
	echo "--- Cleaning up"
	rm $IMAGE_FILENAME &>/dev/null
	losetup -D $LOOP &>/dev/null
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

	done < "$file"

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

if [[ ! -d "$BACKUPPATH" ]]; then
	echo "??? $BACKUPPATH does not exist"
	exit 1
fi	

# cleanup

trap cleanup SIGINT SIGTERM
        
rm "$IMAGE_FILENAME" &>/dev/null

# calculate required image dis size

SOURCE_DISK_SIZE=$(calcSumSizeFromSFDISK $SFDISK_FILE)

mb=$(( $SOURCE_DISK_SIZE / 1024 / 1024 )) # calc MB
echo "===> Backup source disk size: $mb (MiB)"

# create image file

dd if=/dev/zero of="$IMAGE_FILENAME" bs=1024k seek=$(( $mb )) count=0
losetup -f $IMAGE_FILENAME

# prime partitions

sfdisk -uSL $LOOP < "$SFDISK_FILE"

echo "===> Reloading new partition table"
partprobe $LOOP
udevadm settle
sleep 3

# restore backup into image

echo "===> Restoring backup into $IMAGE_FILENAME"
#raspiBackup.sh -1 -Y -F -l debug -d $LOOP "$BACKUPPATH"
RC=$?

# cleanup

losetup -d $LOOP

# now shrink image

if (( ! $RC )); then
	pishrink.sh "$IMAGE_FILENAME"
else
	echo "??? Restore error $RC received from raspiBackup"
fi	
