#!/bin/bash

# Just some code to get familiar with remote ssh and rsync daemon

source ./.credentials

USE_SSH=1
USE_DAEMON=$((! $USE_SSH ))

checkrc() {
	if (( $1 != 0 )); then
		echo "Error $1"
		exit 1
	fi
}

echo -n "@@@ Syning with "

if (( $USE_SSH )); then
	echo "SSH ..."
	# use user key
	rsync -av --delete -e "ssh -i $ssh_key" $1 $ssh_user@$host:/disks/raid1/test
	checkrc $?
fi

if (( $USE_DAEMON )); then
	echo "rsync daemon ..."
	# use rsync daemon
	export RSYNC_PASSWORD="$daemon_password"
	rsync -pv $1 rsync://$daemon_user@$host:/Test-Backup # points to /disks/raid1/test
	checkrc $?
fi

echo -e "\n@@@ ls -la"
ssh $ssh_user@$host -i $ssh_key "ls -la /disks/raid1/test"
checkrc $?

echo -e "\n@@@ sudo rm *"
ssh $ssh_user@$host -i $ssh_key "sudo rm /disks/raid1/test/*"
checkrc $?

echo -e "\n@@@ ls"
ssh $ssh_user@$host -i $ssh_key "ls /disks/raid1/test"
checkrc $?

