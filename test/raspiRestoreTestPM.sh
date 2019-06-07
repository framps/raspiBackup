#!/bin/bash
#######################################################################################################################
#
# raspiBackup backup restore PM test
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

VMs=~/vmware/kvm

BACKUP="/disks/bigdata/raspibackup Test/raspibackup"

OLDIFS="$IFS"
IFS=$'\n'

MBR_FILE=$(ls -d "$BACKUP/"*".mbr")

IMAGES_TO_RESTORE=( $(ls -d "$BACKUP/raspibackup-"*"-backup-"* | grep -v ".log$") )
#IMAGES_TO_RESTORE=( $(ls -d "$BACKUP/raspibackup-tar-backup-"* | grep -v ".log$") )
IFS="$OLDIFS"

RESTORE_DEVICE="/dev/loop0"
#RESTORE_DEVICE="/dev/sdf"

OPTS="-m 1 -l 1"

DEPLOYED_IP="192.168.0.102"

echo "Number of images: ${#IMAGES_TO_RESTORE[@]}"
i=1
for image in "${IMAGES_TO_RESTORE[@]}"; do
	echo "$i: $image"
	(( i++ ))
done

for image in "${IMAGES_TO_RESTORE[@]}"; do

	echo "Processing image $image"

	echo "Removing old image"
	rm $VMs/raspiBackupRestore.img

	echo "Creating image"
	qemu-img create -f raw $VMs/raspiBackupRestore.img 2G

	if [[ $RESTORE_DEVICE = "/dev/loop0" ]]; then
		echo "mounting image"
		sudo losetup -d /dev/loop0
		sudo losetup /dev/loop0 $VMs/raspiBackupRestore.img
		kpartx -av /dev/loop0
		echo "Restoring mbr"
		dd of=$RESTORE_DEVICE if="$MBR_FILE" count=1
		parted /dev/loop0 print
	fi

	echo "Starting restore of $image"
	../raspiBackup.sh -d $RESTORE_DEVICE $OPTS -r "$image" -Y
	rc=$?

	if [[ $rc != 0 ]]; then
		echo "Error running script: $rc"
		exit 127
	fi

	echo "Updating fake-hwclock on restored image"
	mount /dev/loop0p2 /mnt
	echo $(date +"%Y-%m-%d %T") > /mnt/etc/fake-hwclock.data
	echo "Addin my key"
	cat /root/.ssh/id_rsa.pub >> /mnt/root/.ssh/authorized_keys
#	cat /mnt/etc/fake-hwclock.data
#	echo "Setting hostname"
#	echo "raspirestore" > /mnt/etc/hostname

	umount -l /mnt

	echo "kpartx -d"
	kpartx -dv /dev/loop0
	echo "Syncing"
	sync

	echo "Starting restored vm"
	$VMs/start.sh raspiBackupRestore.img &
	pid=$!

	echo "Waiting for VM $DEPLOYED_IP to come up"
	while ! ping -c 1 $DEPLOYED_IP &>/dev/null; do
	        sleep 3
	done

	echo "Waiting for ssh to come up at $DEPLOYED_IP"
	while ! ssh $DEPLOYED_IP shutdown -h now; do
		sleep 3
	done

	pkill -TERM -P $pid
	echo "Waiting for VM to terminate. PID: $pid"
	wait $pid
done
