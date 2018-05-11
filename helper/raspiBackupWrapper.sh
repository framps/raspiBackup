#!/bin/bash

#######################################################################################################################
#
# 	Sample script to wrap raspiBackup.sh in order to mount and unmount the backup device
# 	and start and stop services
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#######################################################################################################################
#
#   Copyright # (C) 2013,2016 - framp at linux-tips-and-tricks dot de
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


MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.2.3"

GIT_DATE="$Date: 2018-04-07 23:55:15 +0200$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1: 7b1f3b5$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

BACKUP_MOUNT_POINT="/remote/backup"							 # ===> adapt to your environment
BACKUP_PATH="$BACKUP_MOUNT_POINT/myraspberries"              # ===> adapt to your environment

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
}

# main program

trapWithArg cleanup SIGINT SIGTERM EXIT

# check if mountpoint is mounted
if ! isMounted $BACKUP_MOUNT_POINT; then
	WAS_MOUNTED=0
	echo "--- Mounting $BACKUP_MOUNT_POINT"
	mount $BACKUP_MOUNT_POINT	# no, mount it
else
	# was already mounted, don't unmount it at script end
	WAS_MOUNTED=1
	echo "--- $BACKUP_MOUNT_POINT already mounted"
fi

# now stop all active services  					===> adapt to your environment

service nfs-kernel-server stop
service samba stop
service apache2 stop
service mysql stop

# create backup
. raspiBackup.sh -a ":" -o ":" $BACKUP_PATH     	  # ===> insert all additional parameters or use /usr/local/etc/raspiBackup.conf to pass all parameters
rc=$?

# now start all services again in reverse order 	===> adapt to your environment

service mysql start
service apache2 start
service samba start
service nfs-kernel-server start

# $BACKUP_MOUNT_POINT unmounted when script terminates only if it was mounted by this script

if [[ $rc == 0 ]]; then
	echo "Backup succeeded :-)"						# do whatever has to be done in case of success
else
	echo "Backup failed with rc $rc :-("			# do whatever has to be done in case of backup failure
	exit $rc
fi

# now variable $BACKUPTARGET_DIR refers to the new backupdirectory and can be used for further backup data processing 
