#!/bin/bash

# Sample script which checks whether a nfsserver is available and exports
# a specific directory and then starts raspiBackup

# (C) 2017,2018 - framp at linux-tips-and-tricks dot de

NFSSERVER="raspifix"
NFSDIRECTORY="/disks/silver/backup"
MOUNTPOINT="/backup"

VERSION="0.0.3"

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

function cleanup() {
	umount -f $MOUNTPOINT
}

trap cleanup SIGINT SIGTERM EXIT

if ping -c1 -w3 $NFSSERVER &>/dev/null; then
	if showmount -e $NFSSERVER | grep -q $NFSDIRECTORY; then
		echo "Mouting $NFSSERVER:$NFSDIRECTORY to $MOUNTPOINT"
		mount $NFSSERVER:$NFSDIRECTORY $MOUNTPOINT
		raspiBackup.sh
	else
		echo "Server $NFSSERVER does not provide $NFSDIRECTORY"
		exit 1
	fi
else
	echo "Server $NFSSERVER not online"
	exit 1
fi
