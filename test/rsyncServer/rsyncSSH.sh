#!/bin/bash

# Just some code to get familiar with remote ssh and rsync daemon

source ./.credentials

USE_SSH=0
USE_DAEMON=$((! $USE_SSH ))

# invoke command either local or remote via ssh
function invoke() { # command [host]

	local rc

	if [[ -z $2 ]]; then
		# $2
		local host="$(hostname)"
		ssh "${USER}@$host" "$1"
		rc=$?
	else
		ssh "$2" "$1"
		rc=$?
	fi

	return $rc
}

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
	rsync -av --delete -e "ssh -i ${SSH_TARGET[$SSH_KEY]}" $1 ${SSH_TARGET[$SSH_USER]}@${SSH_TARGET[$SSH_HOST]}:/disks/raid1/test
	checkrc $?
fi

if (( $USE_DAEMON )); then
	echo "rsync daemon ..."
	# use rsync daemon
	export RSYNC_PASSWORD="${DAEMON_TARGET[$DAEMON_PASSWORD]}"
	rsync -pv $1 rsync://"${DAEMON_TARGET[$DAEMON_USER]}"@${SSH_TARGET[$SSH_HOST]}:/Test-Backup # points to /disks/raid1/test
	checkrc $?
fi

echo -e "\n@@@ ls -la"
invoke "ls -la /disks/raid1/test" ${SSH_TARGET[$SSH_HOST]}
#ssh ${SSH_TARGET[$SSH_USER]}@${SSH_TARGET[$SSH_HOST]} -i ${SSH_TARGET[$SSH_KEY]} "ls -la /disks/raid1/test"
checkrc $?

#echo -e "\n@@@ sudo rm *"
#ssh ${SSH_TARGET[$SSH_USER]}@${SSH_TARGET[$SSH_HOST]} -i ${SSH_TARGET[$SSH_KEY]} "sudo rm /disks/raid1/test/*"
#checkrc $?

#echo -e "\n@@@ ls"
#ssh ${SSH_TARGET[$SSH_USER]}@${SSH_TARGET[$SSH_HOST]} -i ${SSH_TARGET[$SSH_KEY]} "ls /disks/raid1/test"
#checkrc $?

