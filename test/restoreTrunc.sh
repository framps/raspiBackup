#!/bin/bash 

if [[ $UID != 0 ]]; then
	sudo $0 $@
	exit $?
fi

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

if [[ $UID != 0 ]]; then
	echo "Invoke script as root"
	exit 127
fi

LOG_FILE="$CURRENT_DIR/${MYNAME}.log"
rm -f "$LOG_FILE" 2>&1 1>/dev/null

exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE")

DEBUG=1

VMs=~/vmware/kvm

IMAGE_TO_RESTORE_TO="raspianTruncate.img"
BACKUP1="/disks/bigdata/raspiBackupTruncTest/raspibackup/raspibackup-tar-backup-20160716-115630/"		# 4GB
BACKUP2="/disks/bigdata/raspiBackupTruncTest/raspibackup/raspibackup-tar-backup-20160716-103304/"		# 2GB
IMAGE_SIZE="$1"

OLDIFS="$IFS"
IFS=$'\n'

RESTORE_DEVICE="/dev/loop0"
#RESTORE_DEVICE="/dev/sdf"

OPTS="-m 1 -l 1 -Z -j -1"

DEPLOYED_IP="192.168.0.100"

BACKUPS_TO_RESTORE="$BACKUP1 $BACKUP2"
IFS="$OLDIFS"

failures=0

for backup in $BACKUPS_TO_RESTORE; do

	(( $DEBUG )) && echo "Processing backup $backup ..."

	IMAGES_TO_RESTORE=( $(ls -d "$backup/raspibackup-"*"-backup-"* | grep -v ".log$") )	

	echo "Number of images: ${#IMAGES_TO_RESTORE[@]}"
	i=1
	for image in "${IMAGES_TO_RESTORE[@]}"; do
		(( $DEBUG )) && echo "$i: $image"
		(( i++ ))
	done
	
	for image in "${IMAGES_TO_RESTORE[@]}"; do

#	@@@	
#		image="${IMAGES_TO_RESTORE[0]}"
	
		(( $DEBUG )) && echo "Processing image $image"

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
			(( $DEBUG )) && echo "Removing old image"
			rm $VMs/$IMAGE_TO_RESTORE_TO &>/dev/null
	
			(( $DEBUG )) && echo "Creating image"
			qemu-img create -f raw $VMs/$IMAGE_TO_RESTORE_TO $IMAGE_SIZE
			rc=$?
			if (( $rc )); then
				echo "image creationg failed with rc $rc"
				exit 127
			fi
	
			if [[ $RESTORE_DEVICE = "/dev/loop0" ]]; then
				(( $DEBUG )) && echo "mounting image"
				sudo losetup -d /dev/loop0
				sudo losetup /dev/loop0 $VMs/raspiBackupRestore.img
				kpartx -av /dev/loop0
#			(( $DEBUG )) && echo "Restoring mbr from $MBR_FILE"
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
	
			(( $DEBUG )) && echo "Updating fake-hwclock on restored image"
			mount /dev/loop0p2 /mnt
			echo $(date +"%Y-%m-%d %T") > /mnt/etc/fake-hwclock.data
			(( $DEBUG )) && echo "Addin my key"
			cat /root/.ssh/id_rsa.pub >> /mnt/root/.ssh/authorized_keys
			(( $DEBUG )) && echo "Addin my issue"
			echo "*** $image ***" >> /mnt/etc/issue
			sync

			(( $DEBUG )) && echo "Waiting for umount"
			while :; do
				umount /mnt &>/dev/null
				rc=$?
				if [[ $rc == 0 || $rc == 1 ]]; then  # umount OK
					break
				fi
				sleep 3
			done
			(( $DEBUG )) && echo "Done"
	
			(( $DEBUG )) && echo "kpartx -d"
			kpartx -dv /dev/loop0
			(( $DEBUG )) && echo "Syncing"
			sync
			sleep 3
			
			echo "Starting restored vm"
			$VMs/start.sh $IMAGE_TO_RESTORE_TO &
			pid=$!
			
			while ! ps -p $pid &>/dev/null; do
				(( $DEBUG )) && echo "Waiting for $pid"
				sleep 1
			done
			
			echo "Waiting for VM $DEPLOYED_IP to come up"
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
	
		(( $DEBUG )) && sleep 3
	
		loopCnt=10	
		error=0
		echo "Waiting for ssh to come up at $DEPLOYED_IP"
		while ! ssh $DEPLOYED_IP shutdown -h now 2>/dev/null; do
			sleep 3
			(( loopCnt-- ))
			if (( $loopCnt == 0 )); then
				error=1
				break
			fi 
		done
	
		echo "Checking for /boot/cmdline.txt ..."
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

		echo "... waiting"
		read
	
		pkill -TERM -P $pid	
		(( $DEBUG )) && echo "Waiting for VM to terminate. PID: $pid"
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
