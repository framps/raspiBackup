#!/bin/bash

# Sample script which checks whether a nfsserver is available and exports 
# a specific directory and then starts raspiBackup

# (C) 2017 - framp at linux-tips-and-tricks dot de

NFSSERVER="raspifix"
NFSDIRECTORY="/disks/silver/photos"

if ping -c1 -w3 $NFSSERVER &>/dev/null; then
	if showmount -e $NFSSERVER | grep -q $NFSDIRECTORY; then
		echo "Server $NFSSERVER provides $NFSDIRECTORY"
		/usr/local/bin/raspiBackup.sh
	else
		echo "Server $NFSSERVER does not provide $NFSDIRECTORY"
		exit 1
	fi
else 
	echo "Server $NFSSERVER not online"
	exit 1
fi
