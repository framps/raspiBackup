#!/bin/bash

# Sample script to wrap raspiBackup.sh in order 
# to mount and unmount the backup device
# and start and stop services
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
# (C) 2013,2016 - framp at linux-tips-and-tricks dot de

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.2.1"

GIT_DATE="$Date: 2016-07-22 21:47:51 +0200$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE) 
GIT_COMMIT="$Sha1: c2b75e1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

BACKUP_MOUNT_POINT="/remote/backup"							 # ===> adapt to your environment
BACKUP_PATH="$BACKUP_MOUNT_POINT/myraspberries"              # ===> adapt to your environment

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/egrep ]]; then
	PATHES="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
	for p in $PATHES; do
		if ! /bin/egrep "^$p|:$p" <<< "$PATH" 2>&1 1>/dev/null; then
			[[ -z "$PATH" ]] && export PATH="$p" || export PATH="$p:$PATH"
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
raspiBackup.sh -p $BACKUP_PATH -a ":" -o ":"      # ===> insert all additional parameters or use /usr/local/etc/raspiBackup.conf to pass all parameters

# now start all services again in reverse order 	===> adapt to your environment

service mysql start
service apache2 start
service samba start
service nfs-kernel-server start

# $BACKUP_MOUNT_POINT unmounted when script terminates only if it was mounted by this script
