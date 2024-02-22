#!/bin/bash
#
#######################################################################################################################
#
# 	Either create an image file in backupdirectory with extension .dd which can be restored with dd or win32diskimager
# 	from a tar or rsync backup created by raspiBackup
#   or restore the backup to another device, e.g. SD card or USB flashdrive to have a cold SD backup
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup to get more details about raspiBackup
#
#	NOTE: This is sample code how to extend functionality of raspiBackup and is provided as is with no support.
#
#######################################################################################################################
#
#   Copyright (c) 2017-2024 framp at linux-tips-and-tricks dot de
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

VERSION="v0.2.1"

function usage() {	
	echo "Syntax: $MYSELF <BackupDirectory> [ <restoredevice> (e.g. /dev/sda, /dev/mmcblk1, /dev/nvme0n1) ]"
}

function cleanup() {
	local rc=$?
	echo "--- Cleaning up"
	if (( CREATE_DD_BACKUP )); then
		(( $rc )) && rm $IMAGE_FILENAME &>/dev/null
		if losetup $RBRI_RESTOREDEVICE &>/dev/null; then
			losetup -d "$RBRI_RESTOREDEVICE"
		fi
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

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[\^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

NL=$'\n'
MAIL_EXTENSION_AVAILABLE=0
[[ $(which raspiImageMail.sh) ]] && MAIL_EXTENSION_AVAILABLE=1

if (( $MAIL_EXTENSION_AVAILABLE )); then
	# output redirection for email
	MSG_FILE=/tmp/msg$$.txt
	exec 1> >(stdbuf -i0 -o0 -e0 tee -a "$MSG_FILE" >&1)
	exec 2> >(stdbuf -i0 -o0 -e0 tee -a "$MSG_FILE" >&2)
fi


GIT_CODEVERSION="$MYSELF $VERSION"

echo "$GIT_CODEVERSION"

if (( $UID != 0 )); then
	echo "$MYSELF has to be invoked via sudo"
	exit
fi

# query invocation parms

if (( $# < 1 )); then
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

SFDISK_FILE="$(ls $BACKUP_DIRECTORY/*.sfdisk 2>/dev/null)"
if [[ -z "$SFDISK_FILE" ]]; then
	echo "??? Incorrect backup path. .sfdisk file of backup not found"
	usage
	exit 1
fi

if (( $# < 2 )); then
	CREATE_DD_BACKUP=1
	IMAGE_FILENAME="${SFDISK_FILE%.*}.dd"
	RBRI_RESTOREDEVICE=$(losetup -f)
else
	CREATE_DD_BACKUP=0
	RBRI_RESTOREDEVICE="$2"
	if [[ ! -b $RBRI_RESTOREDEVICE ]]; then
		echo "??? Incorrect restore device"
		usage
		exit 1
	fi
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

if (( CREATE_DD_BACKUP )); then
	# wheezy does not discover more than one partition as default
	if grep -q "wheezy" /etc/os-release; then
		if ! grep -q "RBRI_RESTOREDEVICE.max_part=" /boot/cmdline.txt; then
			echo "Add 'RBRI_RESTOREDEVICE.max_part=15' in /boot/cmndline.txt first and reboot"
			exit 1
		fi
	fi
fi

# cleanup

trap cleanup SIGINT SIGTERM EXIT

if (( CREATE_DD_BACKUP )); then
	rm "$IMAGE_FILENAME" &>/dev/null

	# calculate required image dis size

	SOURCE_DISK_SIZE=$(calcSumSizeFromSFDISK $SFDISK_FILE)

	mb=$(( $SOURCE_DISK_SIZE / 1024 / 1024 )) # calc MB
	echo "===> Backup source disk size: $mb (MiB)"

	# create image file

	dd if=/dev/zero of="$IMAGE_FILENAME" bs=1024k seek=$(( $mb )) count=0
	losetup $RBRI_RESTOREDEVICE $IMAGE_FILENAME
fi

# restore backup now

if (( CREATE_DD_BACKUP )); then
	echo "===> Restoring backup into $IMAGE_FILENAME"
else
	echo "===> Restoring backup into $RBRI_RESTOREDEVICE"
fi

# prime partitions

sfdisk -uSL -f $RBRI_RESTOREDEVICE < "$SFDISK_FILE"

echo "===> Reloading new partition table"
partprobe $RBRI_RESTOREDEVICE
udevadm settle
sleep 3

f=$(mktemp)
echo 'DEFAULT_YES_NO_RESTORE_DEVICE=""' > $f
raspiBackup.sh -1 -Y -d $RBRI_RESTOREDEVICE -f $f "$BACKUP_DIRECTORY"
RC=$?
rm $f

if (( CREATE_DD_BACKUP )); then
	# The disk identifier is the Partition UUID (PTUUID displayed in blkid) and is stored just prior to the partition table in the MBR
	# The PARTUUID's aren't actually stored anywhere, they're simply PTUUID-01 for partition 1 and PTUUID-02 for partition 2
	# You can change PTUUID on a live system with fdisk
	# Extract from https://www.raspberrypi.org/forums/viewtopic.php?t=191775

	mkdir -p /mnt1
	mount ${RBRI_RESTOREDEVICE}p2 /mnt1
	PTUUID=$(grep -E "^[^#]+\s(/)\s.*" /mnt1/etc/fstab | cut -f 1 -d ' ' | sed 's/PARTUUID=//;s/\-.\+//')
	umount /mnt1
	losetup -d $RBRI_RESTOREDEVICE

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
			echo "Program ends wihn error 42"
		fi
	else
		echo "??? Error $RC received"
		RC=1
	fi

	# pishrink destroyes PARTUUID with resizsefs, restore original PTUUID now
	if (( ! $RC )); then
	  RBRI_RESTOREDEVICE=$(losetup -f)

	  echo "===> Patching image PARTUUID with $PTUUID"

	  losetup -P $RBRI_RESTOREDEVICE $IMAGE_FILENAME
	  printf "x\ni\n0x$PTUUID\nr\nw\nq\n" | fdisk $RBRI_RESTOREDEVICE
	  partprobe $RBRI_RESTOREDEVICE
	  udevadm settle
	  sleep 3
	fi
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

exit $RC

