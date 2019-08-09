#!/bin/bash

#######################################################################################################################
#
# 	Sample script to wrap raspiBackup.sh in order to mount and unmount the backup device
# 	and start postprocessing programs like pishrink or raspiBackupRestore2Image
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#######################################################################################################################
#
#   Copyright # (C) 2013,2019 - framp at linux-tips-and-tricks dot de
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
#######################################################################################################################

set -euf -o pipefail

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.2.5"

set +u;GIT_DATE="$Date: 2019-08-09 20:03:06 +0200$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1: 2f6831f$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

LOOP_DISK_NAME=""
BACKUP_MOUNT_POINT="/remote/backup"							 # ===> adapt to your environment
BACKUP_PATH="$BACKUP_MOUNT_POINT/myraspberries"              # ===> adapt to your environment

#LOOP_DISK_NAME="myacl.img" 								 # ===> uncomment and adapt to your environment if you use a loop device as backup parition to save ACLs
LOOP_MOUNTED=0

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

function trapWithArg() { # function trap1 trap2 ... trapn
	local func
    func="$1" ; shift
    for sig ; do
        trap "$func $sig" "$sig"
    done
}

function isMounted() {
	local path
	path=$1
	while [[ $path != "" ]]; do
		if mountpoint -q $path; then
			return 0
        fi
        path=${path%/*}
	done
    return 1
}

function cleanup() { # trap
	if (( ! $WAS_MOUNTED )); then
		echo "--- Unmounting $BACKUP_MOUNT_POINT"
		umount $BACKUP_MOUNT_POINT
	fi
	if (( $LOOP_MOUNTED )); then
		losetup -d $LOOP_DEVICE
		umount $LOOP_DEVICE
		rmdir $LOOP_MOUNT_POINT
	fi
}

function readVars() {
	if [[ -f /tmp/raspiBackup.vars ]]; then
		source /tmp/raspiBackup.vars						# retrieve some variables from raspiBackup for further processing
# now following variables are available for further backup processing
# BACKUP_TARGETDIR refers to the backupdirectory just created
# BACKUP_TARGETFILE refers to the dd backup file just created
	else
		echo "/tmp/raspiBackup.vars not found"
		exit 42
	fi
}

# store backup in ext4 image on mounted partition to save ACLs
# See http://cintrabatista.net/nfs_with_posix_acl.html for details
#
# create image with following commands
# create myacl.img with 100M*10=1G (change 10 to 200, for example, if you want 20G)
#    sudo dd if=/dev/zero of=myacl.img bs=100M count=10
#    sudo mkfs.ext4 ./myacl.img
#
# mount the backup ext4 image for a restore to /restore_image
#    sudo losetup /dev/loop0 ./myacl.img
#    sudo mkdir /restore_image
#    sudo mount /dev/loop0 /restore_image
function mountLoopDevice() {
	echo "--- Using image $BACKUP_PATH/$LOOP_DISK_NAME via loop device as backup partition"
	LOOP_DEVICE=$(losetup -f) # retrieve free loop devices
	LOOP_MOUNT_POINT=$(mktemp -d) # create a mountpoint for loop device
	losetup "$LOOP_DEVICE" "$BACKUP_PATH/$LOOP_DISK_NAME"
	mount "$LOOP_DEVICE" "$LOOP_MOUNT_POINT"
	LOOP_MOUNTED=1
}

function raspiBackupRestore2Image() {
	if which raspiBackupRestore2Image.sh 2>&1 1>/dev/null; then

		raspiBackupRestore2Image.sh $BACKUP_TARGETDIR
		rc=$?

		if (( $rc == 0 )); then
			echo "raspiBackupRestore2Image.sh succeeded :-)"					# do whatever has to be done in case of success
		else
			echo "raspiBackupRestore2Image.sh failed with rc $rc :-("			# do whatever has to be done in case of backup failure
			exit $rc
		fi
	else
		echo "raspiBackupRestore2Image.sh not found :-("
		exit 42
	fi
}

function pishrink() {
	if which pishrink.sh 2>&1 1>/dev/null; then
		readVars
		pishrink.sh $BACKUP_TARGETFILE
		rc=$?

		if (( $rc == 0 )); then
			echo "pishrink succeeded :-)"					# do whatever has to be done in case of success
		else
			echo "pishrink failed with rc $rc :-("			# do whatever has to be done in case of backup failure
			exit $rc
		fi
	else
		echo "pishrink not found :-("
		exit 42
	fi
}

# main program

trapWithArg cleanup SIGINT SIGTERM EXIT

# check if mountpoint is mounted
if ! isMounted $BACKUP_MOUNT_POINT; then
	WAS_MOUNTED=0
	echo "--- Mounting $BACKUP_MOUNT_POINT"
	mount $BACKUP_MOUNT_POINT	# no, mount it
	if (( $? > 0 )); then
		echo "??? Mount of $BACKUP_MOUNT_POINT failed"
		exit 42
	fi
else
	# was already mounted, don't unmount it at script end
	WAS_MOUNTED=1
	echo "--- $BACKUP_MOUNT_POINT already mounted"
fi

if [[ -n $LOOP_DISK_NAME ]]; then
	# store backup in ext4 image on mounted partition to save ACLs
	mountLoopDevice
	raspiBackup.sh "$LOOP_MOUNT_POINT"   			# ===> configure all options in /usr/local/etc/raspiBackup.conf. Don't forget -a and -o options
	rc=$?
else
	# create backup on BACKUP_MOUNT_POINT
	raspiBackup.sh      	 						# ===> configure all options in /usr/local/etc/raspiBackup.conf. Don't forget -a and -o options
	rc=$?
fi

# $BACKUP_MOUNT_POINT unmounted when script terminates only if it was mounted by this script

if (( $rc == 0 )); then
	echo "Backup succeeded :-)"						# do whatever has to be done in case of success
else
	echo "Backup failed with rc $rc :-("			# do whatever has to be done in case of backup failure
	exit $rc
fi

# enable one of the following two lines if you want to have pishrink or raspiBackupRestore2Image to postprocess the backup

#sudo pishrink
#sudo raspiBackupRestore2Image
