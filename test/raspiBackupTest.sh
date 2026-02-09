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

TEST_SCRIPT="testRaspiBackup.sh"
BACKUP_MOUNT_POINT="$MOUNT_HOST:$EXPORT_DIR"
BOOT_ONLY=0	# just boot vm and then exit
KEEP_VM=1 # don't destroy VM at test end
RASPBIAN_OS="bookworm"
CLEANUP=0

VM_IP="$DEPLOYED_IP"

environment="${1}"
environment="${environment,,}"
type="${2}"
type="${type,,}"
mode="${3}"
mode="${mode,,}"
bootmode="${4}"
bootmode="${bootmode,,}"
options="${5}"

echo "Executing test with following options: $environment $type $mode $bootmode $options"

echo "Checking for VM $VM_IP already active and start VM otherwise with environment $environment"

function d() {
	echo "$(date +%Y%m%d-%H%M%S)"
}

if ! ping -c 1 $VM_IP; then

	case $environment in
		# USB boot only
		usb)
			echo "Starting VM ${RASPBIAN_OS}.img"
			rpi-emu-start.sh ${RASPBIAN_OS}.img -snapshot &
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

sshexec "time ~/$TEST_SCRIPT $BACKUP_MOUNT_POINT \"$BACKUP_DIR\" \"$environment\" \"$type\" \"$mode\" \"$bootmode\" \"$options\""

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
	echo "??? Backup failed $1 $2 $3 $4 $5"
	(( $EXIT_ON_FAILURE )) && exit 127 || exit 0
else
	echo "--- Backup successfull $1 $2 $3 $4 $5"
	exit 0
fi
