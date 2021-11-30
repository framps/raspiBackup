#!/bin/bash
#
#######################################################################################################################
#
# 	Create an image file which can be restored with dd or win32diskimager from a tar or rsync backup created by raspiBackup
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup to get more details about raspiBackup
#
#	NOTE: This is sample code how to extend functionality of raspiBackup and is provided as is with no support.
#
#######################################################################################################################
#
#   Copyright (c) 2017-2020 framp at linux-tips-and-tricks dot de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#	Kudos for kmbach who suggested to create this helper and who helped to improve it
#
#######################################################################################################################

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}

VERSION="v0.1.7"

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[\^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

GIT_DATE="$Date$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

echo "$GIT_CODEVERSION"

NL=$'\n'
MAIL_EXTENSION_AVAILABLE=0
[[ $(which raspiImageMail.sh) ]] && MAIL_EXTENSION_AVAILABLE=1

if (( $MAIL_EXTENSION_AVAILABLE )); then
	# output redirection for email
	MSG_FILE=/tmp/msg$$.txt
	exec 1> >(stdbuf -i0 -o0 -e0 tee -a "$MSG_FILE" >&1)
	exec 2> >(stdbuf -i0 -o0 -e0 tee -a "$MSG_FILE" >&2)
fi

function usage() {
	echo "Syntax: $MYSELF <BackupDirectory> [<ImageFileDirectory>]"
}

# query invocation parms

if [[ $# < 1 ]]; then
	echo "??? Missing parameter Backupdirectory"
	usage
	exit 1
fi

BACKUP_DIRECTORY="$1"

if [[ ! -d $BACKUP_DIRECTORY ]]; then
	echo "??? Backupdirectory $BACKUP_DIRECTORY not found"
	usage
	exit 1
fi

IMAGE_DIRECTORY="${2:-$BACKUP_DIRECTORY}"

if [[ ! -d $IMAGE_DIRECTORY ]]; then
	echo "??? Imagedirectory $IMAGE_DIRECTORY not found"
	usage
	exit 1
fi

SFDISK_FILE="$(ls $BACKUP_DIRECTORY/*.sfdisk 2>/dev/null)"
if [[ -z "$SFDISK_FILE" ]]; then
	echo "??? Incorrect backup path. .sfdisk file of backup not found"
	usage
	exit 1
fi
IMAGE_FILENAME="${SFDISK_FILE%.*}.dd"
LOOP=$(losetup -f)

function cleanup() {
	local rc=$?
	echo "--- Cleaning up"
	(( $rc )) && rm $IMAGE_FILENAME &>/dev/null
	if losetup $LOOP &>/dev/null; then
		losetup -d "$LOOP"
	fi
    rm -f $MSG_FILE &>/dev/null
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

    (( sumSize = ((sumSize - 1)/8 + 1)*4096 ))	# align on 4096 boundary to speedup pishrink, kudos for kmbach

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

# wheezy does not discover more than one partition as default
if grep -q "wheezy" /etc/os-release; then
	if ! grep -q "loop.max_part=" /boot/cmdline.txt; then
		echo "Add 'loop.max_part=15' in /boot/cmndline.txt first and reboot"
		exit 1
	fi
fi

# cleanup

trap cleanup SIGINT SIGTERM EXIT

rm "$IMAGE_FILENAME" &>/dev/null

# calculate required image dis size

SOURCE_DISK_SIZE=$(calcSumSizeFromSFDISK $SFDISK_FILE)

mb=$(( $SOURCE_DISK_SIZE / 1024 / 1024 )) # calc MB
echo "===> Backup source disk size: $mb (MiB)"

# create image file

dd if=/dev/zero of="$IMAGE_FILENAME" bs=1024k seek=$(( $mb )) count=0
losetup $LOOP $IMAGE_FILENAME

# prime partitions

sfdisk -uSL -f $LOOP < "$SFDISK_FILE"

echo "===> Reloading new partition table"
partprobe $LOOP
udevadm settle
sleep 3

# restore backup into image

echo "===> Restoring backup into $IMAGE_FILENAME"
raspiBackup.sh -1 -Y -d $LOOP "$BACKUP_DIRECTORY"
RC=$?

# The disk identifier is the Partition UUID (PTUUID displayed in blkid) and is stored just prior to the partition table in the MBR
# The PARTUUID's aren't actually stored anywhere, they're simply PTUUID-01 for partition 1 and PTUUID-02 for partition 2
# You can change PTUUID on a live system with fdisk
# Extract from https://www.raspberrypi.org/forums/viewtopic.php?t=191775

mount ${LOOP}p2 /mnt
PTUUID=$(grep -E "^[^#]+\s(/)\s.*" /mnt/etc/fstab | cut -f 1 -d ' ' | sed 's/PARTUUID=//;s/\-.\+//')
umount /mnt
losetup -d $LOOP

if [[ -z $PTUUID ]]; then
	echo "??? Unrecoverable error. Unable to find PARTUUID of / in image"
	RC=1
fi

# now shrink image

if (( ! $RC )); then
	echo "===> PARTUUID to patch into image after pishrink: $PTUUID"
	echo
	echo "===> Shrinking Image $IMAGE_FILENAME"
	pishrink.sh "$IMAGE_FILENAME"
	RC=$?
	if (( $RC )); then
		echo "??? Error $RC received from piShrink"
	    	RC=1
		exit 42
	fi
else
	echo "??? Error $RC received"
	RC=1
fi

if (( $MAIL_EXTENSION_AVAILABLE )); then
    IMAGE_FILENAME=${IMAGE_FILENAME##*/}
    HOST_NAME=${IMAGE_FILENAME%%-*}
    if (( $RC )); then
        status="with errors finished"
    else
        status="finished successfully"
    fi
    BODY="raspiBackupRestore2Image.sh $IMAGE_FILENAME$NL$NL$(echo -e "$(cat $MSG_FILE)")"
    raspiImageMail.sh "$HOSTNAME - Restore $status"  "$BODY"
    if [[ $? = 0 ]]; then
        echo "-- Send email succeeded!"
        RC=0
    fi
fi

# pishrink destroyes PARTUUID with resizsefs, restore original PTUUID now

LOOP=$(losetup -f)

echo "===> Patching image PARTUUID with $PTUUID"

losetup -P $LOOP $IMAGE_FILENAME
printf "x\ni\n0x$PTUUID\nr\nw\nq\n" | fdisk $LOOP
partprobe $LOOP
udevadm settle
sleep 3

exit $RC

