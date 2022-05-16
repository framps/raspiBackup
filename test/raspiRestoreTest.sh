#!/bin/bash

#######################################################################################################################
#
# raspiBackup backup restore regression test
#
#######################################################################################################################
#
#    Copyright (c) 2013, 2020 framp at linux-tips-and-tricks dot de
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

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)
source $SCRIPT_DIR/constants.sh

if [[ $UID != 0 ]]; then
	sudo $0 $@
	exit $?
fi

#set -e

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
CURRENT_DIR=$(pwd)

GIT_DATE="$Date$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

function sshexec() { # cmd
	echo "Executing $@"
	ssh root@$VM_IP "$@"
}

function log() { # text
	if (( $DEBUG )); then
		echo "$@"
	else
		echo "$@" >> ${MYNAME}.log
	fi
}

if [[ $UID != 0 ]]; then
	echo "Invoke script as root"
	exit 127
fi

exec 1> >(tee -a raspiBackup.log)
exec 2> >(tee -a raspiBackup.log)

DEBUG=0

VMs=$CURRENT_DIR/qemu

BACKUP1="/disks/VMware/raspibackupTest_P/*"
BACKUP2="/disks/VMware/raspibackupTest_N/*"

BACKUPS_TO_RESTORE="$BACKUP2 $BACKUP1"

#RESTORE_DISK_SIZE=$((1024*1024*1024*2-1024*1024*250))
RESTORE_DISK_SIZE=4G

echo "---> Restore disk size: $RESTORE_DISK_SIZE"

OLDIFS="$IFS"
IFS=$'\n'

losetup -D

LOOP=$(losetup -f)

OPTS="-m 1 -l 1 -Z"

IFS="$OLDIFS"

failures=0

umount ${LOOP}p2 &>/dev/null || true
umount ${LOOP}p1 &>/dev/null || true

for backup in $BACKUPS_TO_RESTORE; do

	echo "Processing backup $backup ..."

	IMAGES_TO_RESTORE=( $(ls -d "$backup"*"/raspberrypi-"*"-backup-"* | grep -v ".log$") )
#	IMAGES_TO_RESTORE=( $(ls -d "$backup"*"/raspberrypi-"*"dd-backup-"* | grep -v ".log$") )
#	IMAGES_TO_RESTORE=( $(ls -d "$backup"*"/raspberrypi-"*"tar-backup-"* | grep -v ".log$") )
#	IMAGES_TO_RESTORE=( $(ls -d "$backup"*"/raspberrypi-*"*"rsync-backup-"* | grep -v ".log$") )

	log "Number of images: ${#IMAGES_TO_RESTORE[@]}"
	i=1
	for image in "${IMAGES_TO_RESTORE[@]}"; do
		log "$i: $image"
		(( i++ ))
	done

	for image in "${IMAGES_TO_RESTORE[@]}"; do

		log "Processing image $image"

		if [[ ! $image =~ -dd.?- ]]; then
			MBR_FILE=$(ls -d "$image/"*".mbr")		# check for mbr in dir

			if [[ -z $MBR_FILE ]]; then
				echo "??? No mbr file found"
				ls -d "$backup/"*".mbr"
				exit 127
			fi
		fi

		retry=1

		while (( retry > 0 )); do
			log "Removing old image"
			rm $VMs/raspiBackupRestore.img &>/dev/null

			echo "Creating image $VMs/raspiBackupRestore.img of size $RESTORE_DISK_SIZE"
			qemu-img create -f raw $VMs/raspiBackupRestore.img $RESTORE_DISK_SIZE

			log "mounting image"
			sudo losetup -vP $LOOP $VMs/raspiBackupRestore.img
			if [[ ! $image =~ -dd.?- ]]; then
				dd if=$MBR_FILE of=$LOOP count=1 # prime loop partitions
			fi

			[[ $image =~ -sdbootonly- ]]
			SDBOOTONLY=$((! $? ))

			if (( ! $SDBOOTONLY )); then

				echo "Starting restore of $image"

				../raspiBackup.sh -d $LOOP $OPTS -Y "$image"
				rc=$?

				if [[ $rc != 0 ]]; then
					echo "Error running script: $rc"
					exit 127
				fi

				losetup -D

				LOOP=$(losetup -f)
				losetup -vP $LOOP "$VMs/raspiBackupRestore.img"
				log "Updating fake-hwclock on restored image"
				mount ${LOOP}p2 /mnt
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

				losetup -d $LOOP
				log "Syncing"
				sync
				sleep 3
			else # sdbootonly
				echo "Starting SDONLY restore of $image"

				echo "Creating image $VMs/raspiBackupRestoreEXT.img of size $RESTORE_DISK_SIZE"
				qemu-img create -f raw $VMs/raspiBackupRestoreEXT.img $RESTORE_DISK_SIZE

				log "mounting EXT image"
				LOOPEXT=$(losetup -f)

				sudo losetup -vP $LOOPEXT $VMs/raspiBackupRestoreEXT.img
				if [[ ! $image =~ -dd.?- ]]; then
					dd if=$MBR_FILE of=$LOOPEXT count=1 # prime loop partitions
				fi

				../raspiBackup.sh -d $LOOP -R $LOOPEXT $OPTS -Y "$image"
				rc=$?

				if [[ $rc != 0 ]]; then
					echo "Error running script: $rc"
					exit 127
				fi

			fi

			echo "Starting restored vm"
			$VMs/start.sh raspiBackupRestore.img &
			pid=$!
			echo "Qemu pid: $pid"

			log "Waiting for $pid"
			while ! ps -p $pid &>/dev/null; do
				sleep 1
				log "Waiting for $pid"
			done

			log "Waiting for VM $DEPLOYED_IP to come up"
			RETRY=0
			while ! ping -c 1 $DEPLOYED_IP &>/dev/null; do
				echo -n "."
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
			echo
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

		if (( ! $error )); then
			echo "ping 8.8.8.8 as user pi ..."
			ssh $DEPLOYED_IP 'su - pi -l -c "ping 8.8.8.8 -c 3 -w 3"'
			rc=$?
			if [[ $rc != 0  ]]; then
				echo "ping failed with rc $rc"
				error=1
			fi
		fi

		if (( ! $error )); then
			echo "service --status-all as user pi ..."
			ssh $DEPLOYED_IP 'su - pi -l -c "service --status-all | grep "+" | wc -l > /tmp/srvrces.num"'
			scp root@$DEPLOYED_IP:/tmp/srvrces.num .
			if [[ $(cat srvrces.num) != 15 ]]; then
				echo "Missing active services. Expected 15. Detected $(cat srvrces.num)"
				error=1
			else
				echo "Active services detected: $(cat srvrces.num)"
			fi
			rm ./srvrces.num &>/dev/null || true
		fi

		if (( error )); then
			echo "@@@@@ Restore of $image failed"
			(( failures+=error ))
		else
			echo "@@@@@ Restore successfull"
		fi

		echo "Shutdown VM pid $pid ..."

		# get firstly created child process id, which is running all tasks
		PID_CHILD=$(pgrep -o -P $pid)
		PID_CHILD2=$(pgrep -o -P $PID_CHILD)

		kill -9 $PID_CHILD2

	done

done

rm $VMs/raspiBackupRestore.img &>/dev/null

if (( failures > 0 )); then
	echo "??? Restore failures: $failures"
	(( $EXIT_ON_FAILURE )) && exit 127 || exit 0
else
	echo "--- Restore test finished successfully"
	exit 0
fi
