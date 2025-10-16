#!/bin/bash

#######################################################################################################################
#
# raspiBackup backup creation regression test
#
#######################################################################################################################
#
#    Copyright (c) 2013, 2025 framp at linux-tips-and-tricks dot de
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

source ./env.defs

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)
source $SCRIPT_DIR/constants.sh

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
CURRENT_DIR=$(pwd)

#if (( $# < 4 )); then
#	echo "Parms: environment type mode bootmode"
#	exit
#fi

LOG_FILE="$CURRENT_DIR/${MYNAME}.log"
#rm -f "$LOG_FILE" 2>&1 1>/dev/null
exec 1> >(tee -a "$LOG_FILE" >&1)
exec 2> >(tee -a "$LOG_FILE" >&2)

VMs=$CURRENT_DIR
IMAGES=$QEMU_IMAGES

TEST_SCRIPT="testRaspiBackup.sh"
BACKUP_ROOT_DIR="$BACKUP_DIRECTORY"
BACKUP_MOUNT_POINT="$MOUNT_HOST:$BACKUP_ROOT_DIR"
BACKUP_DIR="raspiBackupTest"
BOOT_ONLY=0	# just boot vm and then exit
KEEP_VM=0 # don't destroy VM at test end
RASPBIAN_OS="bookworm"
CLEANUP=0

VM_IP="$DEPLOYED_IP"

if (( $CLEANUP )); then
	echo "Cleaning up backup directories"
	rm -rf $BACKUP_ROOT_DIR/${BACKUP_DIR}_N > /dev/null
	rm -rf $BACKUP_ROOT_DIR/${BACKUP_DIR}_P > /dev/null
fi

echo "Creating target backup directies"
mkdir -p $BACKUP_ROOT_DIR/${BACKUP_DIR}_N
mkdir -p $BACKUP_ROOT_DIR/${BACKUP_DIR}_P

environment=${1:-"usb"}
environment=${environment,,}
type=${2:-"dd ddz tar tgz rsync"}
type=${type,,}
mode=${3:-"n p"}
mode=${mode,,}
bootmode=${4:-"d t"}
bootmode=${bootmode,,}

echo "Executing test with following options: $environment $type $mode $bootmode"

echo "Checking for VM $VM_IP already active and start VM otherwise with environment $environment"

if ! ping -c 1 $VM_IP; then

	echo "Creating snapshot"

	case $environment in
		# USB boot only
		usb)
#			qemu-img create -f qcow2 -F qcow2 -b $IMAGES/${RASPBIAN_OS}.qcow2 $IMAGES/${RASPBIAN_OS}-snap.qcow2
#			qemu-img create -f raw -b $IMAGES/${RASPBIAN_OS}.img -F qcow2 $IMAGES/${RASPBIAN_OS}-snap.qcow2
			echo "Starting VM in $IMAGES/${RASPBIAN_OS}.img"
			rpi-emu-start.sh ${RASPBIAN_OS}.img -snapshot &
			;;
		# no SD card, USB boot
		usb_) qemu-img create -f qcow2 -o backing_file -b $IMAGES/raspianRaspiBackup-Nommcblk-${RASPBIAN_OS}.qcow $IMAGES/raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow
			echo "Starting VM in raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow"
			$VMs/start.sh raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow &
			;;
		nvme_) qemu-img create -f qcow2 -o backing_file -b $IMAGES/raspianRaspiBackup-nvme-${RASPBIAN_OS}.qcow $IMAGES/raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow
			echo "Starting VM in raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow"
			$VMs/start.sh raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow &
			;;
			# boot on SD card but use external root filesystem
		sdbootonly_) qemu-img create -f qcow2 -b $IMAGES/raspianRaspiBackup-BootSDOnly-${RASPBIAN_OS}.qcow $IMAGES/raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow
			qemu-img create -f qcow2 -b $IMAGES/raspianRaspiBackup-RootSDOnly-${RASPBIAN_OS}.qcow $IMAGES/raspianRaspiBackup-RootSDOnly-snap-${RASPBIAN_OS}.qcow
			echo "Starting VM in raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow"
			$VMs/startStretchBootSDOnly.sh raspianRaspiBackup-snap-${RASPBIAN_OS}.qcow raspianRaspiBackup-RootSDOnly-snap-${RASPBIAN_OS}.qcow &
			types="tar"
			modes="n"
			bootModes="d"
			;;
		*) echo "invalid environment $environment"
			exit 42
	esac

	echo "Waiting for VM with IP $VM_IP to come up"
	while ! ping -c 1 $VM_IP &>/dev/null; do
		sleep 3
	done
fi

SCRIPTS="$GIT_REPO/raspiBackup.sh $TEST_SCRIPT constants.sh raspiBackup.conf"

for file in $SCRIPTS; do
	filename=$(basename -- "$file")
	target="root@$VM_IP:/root/$filename"
	[[ $file == "raspiBackup.conf" ]] && target="root@$VM_IP:/usr/local/etc"
	echo "Uploading $file to $target"
	while ! scp $file $target; do
		sleep 3
	done
done

if (( $BOOT_ONLY )); then
	echo "Finished"
	exit 0
fi

function sshexec() { # cmd
	echo "Executing $@"
	ssh root@$VM_IP "$@"
}

sshexec "chmod +x ~/$TEST_SCRIPT"

sshexec "time ~/$TEST_SCRIPT $BACKUP_MOUNT_POINT \"$BACKUP_DIR\" \"$environment\" \"$type\" \"$mode\" \"$bootmode\""

tmp=$(mktemp)

echo "Downloading testRaspiBackup log"
scp root@$VM_IP:/root/testRaspiBackup.log $tmp 1>/dev/null
cat $tmp >> raspiBackup.log

grep "Backup test finished successfully" $tmp
rc=$?

echo "Downloading raspiBackup.log log"
scp root@$VM_IP:/root/raspiBackup.log $tmp 1>/dev/null
cat $tmp >> raspiBackup.log

if (( ! $KEEP_VM )); then
	echo "Shuting down"
	sshexec "shutdown -h now"
	sudo pkill qemu
fi

if (( $rc != 0 )); then
	echo "??? Backup failed $1 $2 $3 $4"
	(( $EXIT_ON_FAILURE )) && exit 127 || exit 0
else
	echo "--- Backup successfull $1 $2 $3 $4"
	exit 0
fi
