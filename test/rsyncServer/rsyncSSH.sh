#!/bin/bash

# Just some code to get familiar with remote ssh and rsync daemon

source ~/.ssh/rsyncServer.creds
#will define
#SSH_HOST=
#SSH_USER=
#SSH_KEY_FILE=

#DAEMON_HOST=
#DAEMON_MODULE=
#DAEMON_USER=
#DAEMON_PASSWORD=

USE_LOCAL=0

if (( $USE_LOCAL )); then
	DIR="./rsynctest"
else
	DIR="/disks/raid1/test"
fi

LOGFILE="./rsyncServer.log"

rm -f $LOGFILE

if (( $# < 1 )); then
	echo "Missing directory to sync"
	exit -1
fi

function checkrc() {
	if (( $1 != 0 )); then
		echo "Error $1"
		exit 1
	fi
}

# invoke command either local or remote via ssh
function invoke() { # command

	local rc reply

	echo "-> $1" >> $LOGFILE

	if (( $USE_LOCAL )); then
		reply="$($1)"
		rc=$?
		echo "<- $reply" >> $LOGFILE
	else
		reply="$(ssh "$2" "$1" 2>&1)"
		rc=$?
		echo "<- $reply" >> $LOGFILE
	fi

	return $rc
}


for (( useSSH=0; useSSH<2; useSSH++ )); do

	USE_SSH=$useSSH
	USE_DAEMON=$((! $USE_SSH ))

	RSYNC_OPTIONS="-arAvp"

	echo -n "@@@ Syning with "

	if (( $USE_SSH )); then
		echo "rsync SSH ..."
		# use user key
		reply="$(rsync $RSYNC_OPTIONS --delete -e "ssh -i ${SSH_KEY_FILE}" $1 ${SSH_USER}@${SSH_HOST}:/${DIR})"
		rc=$?
		echo "$reply" >> $LOGFILE
		checkrc $rc
	fi

	if (( $USE_DAEMON )); then
		echo "rsync daemon ..."
		# use rsync daemon
		export RSYNC_PASSWORD="${DAEMON_PASSWORD}"
		reply="$(rsync $RSYNC_OPTIONS $1 rsync://"${DAEMON_USER}"@${DAEMON_HOST}:/${DAEMON_MODULE})" # points to /disks/raid1/test
		rc=$?
		echo "$reply" >> $LOGFILE
		checkrc $rc
	fi

	echo -e "\n@@@ ls -la"
	invoke "ls -la ${DIR}" ${SSH_HOST}
	checkrc $?

	echo -e "\n@@@ sudo rm *"
	invoke "sudo rm ${DIR}/*" ${SSH_HOST}
	checkrc $?

	echo -e "\n@@@ ls -la"
	invoke "ls -la ${DIR}"  ${SSH_HOST}
	checkrc $?

	echo "+========================"
	cat $LOGFILE
	echo "-========================"

done
