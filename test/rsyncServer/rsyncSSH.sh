#!/bin/bash

# Just some code to get familiar with remote ssh and rsync daemon

source ~/.ssh/rsyncServer.creds

LOGFILE="./rsyncServer.log"

rm $LOGFILE

#SSH_HOST=
#SSH_USER=
#SSH_KEY_FILE=

#DAEMON_HOST=
#DAEMON_MODULE=
#DAEMON_USER=
#DAEMON_PASSWORD=

for (( useSSH=0; useSSH<2; useSSH++ )); do

USE_SSH=$useSSH
USE_DAEMON=$((! $USE_SSH ))

RSYNC_OPTIONS="-arAvp"

# invoke command either local or remote via ssh
function invoke() { # command [host]

	local rc reply

	echo "-> $1" >> $LOGFILE

	if [[ -z $2 ]]; then
		# $2
		local host="$(hostname)"
		reply="$(ssh "${SSH_USER}@$host" "$1")"
		rc=$?
		echo "<- $reply" >> $LOGFILE
	else
		reply="$(ssh "$2" "$1" 2>&1)"
		rc=$?
		echo "<- $reply" >> $LOGFILE
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
	echo "rsync SSH ..."
	# use user key
	reply="$(rsync $RSYNC_OPTIONS --delete -e "ssh -i ${SSH_KEY_FILE}" $1 ${SSH_USER}@${SSH_HOST}:/disks/raid1/test)"
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
invoke "ls -la /disks/raid1/test" ${SSH_HOST}
checkrc $?

echo -e "\n@@@ sudo rm *"
invoke "sudo rm /disks/raid1/test/*" ${SSH_HOST}
checkrc $?

echo -e "\n@@@ ls -la"
invoke "ls -la /disks/raid1/test"  ${SSH_HOST}
checkrc $?

echo "+========================"
cat $LOGFILE
echo "-========================"

done
