#!/bin/bash
#######################################################################################################################
#
# raspiBackup restore test
#
#######################################################################################################################
#
#    Copyright (C) 2013-2019 framp at linux-tips-and-tricks dot de
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

if [[ $UID != 0 ]]; then
	sudo $0 $@
	exit $?
fi

set -e

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
CURRENT_DIR=$(pwd)

GIT_DATE="$Date: 2015-02-20 19:40:08 +0100$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1: 4cd2d9b$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

function log() { # text
	if (( $DEBUG )); then
		echo "$@"
	else
		echo "$@" >> $LOG_FILE
	fi
}

if [[ $UID != 0 ]]; then
	echo "Invoke script as root"
	exit 127
fi

LOG_FILE="$CURRENT_DIR/${MYNAME}.log"
rm -f "$LOG_FILE" 2>&1 1>/dev/null

exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE")

DEBUG=0

VMs=~/vmware/kvm

BACKUP1="/disks/bigdata/raspibackup/raspibackup-tar-backup-20161212-200654"
BACKUP2="/disks/bigdata/raspibackup/raspibackup-rsync-backup-20161031-205418"

BACKUPS_TO_RESTORE="$BACKUP2"

#RESTORE_DISK_SIZE=$((1024*1024*1024*2-1024*1024*250))
RESTORE_DISK_SIZE=4G

echo "---> Restore disk size: $RESTORE_DISK_SIZE"

OLDIFS="$IFS"
IFS=$'\n'

RESTORE_DEVICE="/dev/loop0"
#RESTORE_DEVICE="/dev/sdf"

OPTS="-m 1 -l 1 -Z"

DEPLOYED_IP="192.168.0.100"

IFS="$OLDIFS"

failures=0

umount /dev/loop0p2 &>/dev/null || true
umount /dev/loop0p1 &>/dev/null || true

for backup in $BACKUPS_TO_RESTORE; do

	echo "Processing backup $backup ..."

	IMAGES_TO_RESTORE=( $BACKUPS_TO_RESTORE )
#	IMAGES_TO_RESTORE=( $(ls -d "$backup/raspibackup-tar-backup-"* "$backup/raspibackup-rsync-backup-"* | grep -v ".log$") )
#	IMAGES_TO_RESTORE=( $(ls -d "$backup/raspibackup-dd-backup-"* | grep -v ".log$") )

	log "Number of images: ${#IMAGES_TO_RESTORE[@]}"
	i=1
	for image in "${IMAGES_TO_RESTORE[@]}"; do
		log "$i: $image"
		(( i++ ))
	done

	for image in "${IMAGES_TO_RESTORE[@]}"; do

#	@@@
#		image="${IMAGES_TO_RESTORE[0]}"

		log "Processing image $image"

#		MBR_FILE=$(ls -d "$image/"*".mbr")		# check for mbr in dir
#
#		if [[ -z $MBR_FILE ]]; then
#			MBR_FILE=$(ls -d "$backup/"*".mbr")
#			if [[ -z $MBR_FILE ]]; then
#				echo "??? No mbr file found"
#				ls -d "$backup/"*".mbr"
#				exit 127
#			fi
#		fi

		retry=3

		while (( retry > 0 )); do
			log "Removing old image"
			rm $VMs/raspiBackupRestore.img &>/dev/null

			echo "Creating image of size $RESTORE_DISK_SIZE"
			qemu-img create -f raw $VMs/raspiBackupRestore.img $RESTORE_DISK_SIZE

			if [[ $RESTORE_DEVICE = "/dev/loop0" ]]; then
				log "mounting image"
				sudo losetup -d /dev/loop0 || true
				sudo losetup /dev/loop0 $VMs/raspiBackupRestore.img
				# kpartx -av /dev/loop0
#			log "Restoring mbr from $MBR_FILE"
#			dd of=$RESTORE_DEVICE if="$MBR_FILE" count=1
#			sync
#			parted /dev/loop0 print
			fi

			echo "Starting restore of $image"
#		rm -rf trace.log
#		mount > trace.log
#		ps -ef >> trace.log

			/home/peter/raspiBackup/raspiBackup.sh -d $RESTORE_DEVICE $OPTS -Y "$image"
			rc=$?
#		echo "-----------" >> trace.log
#		mount >> trace.log
#		ps -ef >> trace.log
#		echo "===========" >> trace.log

			if [[ $rc != 0 ]]; then
				echo "Error running script: $rc"
				exit 127
			fi

			kpartx -av /dev/loop0
			log "Updating fake-hwclock on restored image"
			mount /dev/mapper/loop0p2 /mnt
			echo $(date +"%Y-%m-%d %T") > /mnt/etc/fake-hwclock.data
			log "Adding my key"
			cat /root/.ssh/id_rsa.pub >> /mnt/root/.ssh/authorized_keys
			log "Adding my issue"
			echo "*** $image ***" >> /mnt/etc/issue
			sync

			log "Waiting for umount"
			while :; do
				umount /mnt &>/dev/null
				rc=$?
				if [[ $rc == 0 || $rc == 1 ]]; then  # umount OK
					break
				fi
				sleep 3
			done
			log "Done"

			log "kpartx -d"
			kpartx -dv /dev/loop0
			log "Syncing"
			sync
			sleep 3

			echo "Starting restored vm"
			$VMs/start.sh raspiBackupRestore.img &
			pid=$!

			while ! ps -p $pid &>/dev/null; do
				log "Waiting for $pid"
				sleep 1
			done

			log "Waiting for VM $DEPLOYED_IP to come up"
			RETRY=0
			while ! ping -c 1 $DEPLOYED_IP &>/dev/null; do
				if ! ps -p $pid &>/dev/null; then
					echo "@@@ Retry $retry"
					(( retry-- ))
					RETRY=1
					break
				fi
		        sleep 3
			done
			if (( ! $RETRY )); then
				break
			fi
		done

		if (( $retry == 0 )); then
			echo "Failed to start vm with image $image"
			exit 127
		fi

		sleep 3

		loopCnt=10
		error=0
		echo "Waiting for ssh to come up on $DEPLOYED_IP"
		while ! ssh $DEPLOYED_IP ls -la &>/dev/null; do
			sleep 3
			(( loopCnt-- ))
			if (( $loopCnt == 0 )); then
				error=1
				break
			fi
		done

#		log "$(ssh root@$DEPLOYED_IP 'fdisk -l; df -h')"
		echo "$(ssh root@$DEPLOYED_IP 'df')"

		log "Checking for /boot/cmdline.txt ..."
		scp root@$DEPLOYED_IP:/boot/cmdline.txt .
		rc=$?
		if [[ $rc != 0 || ! -e cmdline.txt ]]; then
			echo "Download of /boot/cmdline.txt failed with rc $rc"
			error=1
		else
			rm cmdline.txt
		fi

		if (( ! $error )); then
			echo "Checking for /etc/fstab ..."
			scp root@$DEPLOYED_IP:/etc/fstab .
			rc=$?
			if [[ $rc != 0 || ! -e fstab ]]; then
				echo "Download of /etc/fstab failed with rc $rc"
				error=1
			else
				rm fstab
			fi
		fi

		if (( error )); then
			echo "Restore of $image failed"
			(( failures+=error ))
		else
			echo "Restore successfull"
		fi

#		echo "Aborting"
#		exit 42

		pkill -TERM -P $pid
		log "Waiting for VM to terminate. PID: $pid"
		wait $pid

	done

done

if (( failures > 0 )); then
	echo "??? Restore failures: $failures"
	exit 127
else
	echo "--- Restore test finished successfully"
	exit 0
fi
