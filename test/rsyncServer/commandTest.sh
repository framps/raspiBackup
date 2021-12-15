#!/bin/bash

# Just some code to get familiar with remote ssh command execution and rsync daemon

source ../../raspiBackup.sh --include

### Command execution
#
# See https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables how to capture stdout and stderr and rc into different variables
#
## - local command execution -
# 1) Test local result (stdout and stderr) returned correctly
# 2) Test local RCs are returned correctly
#
## - remote command execution via ssh -
# 1) Test remote result (stdout and stderr) received correctly locally
# 2) Test remote execution RCs are returned correctly

source ~/.ssh/rsyncServer.creds
#will define
#SSH_HOST=
#SSH_USER= # pi
#SSH_KEY_FILE= # public key of user

#DAEMON_HOST=
#DAEMON_MODULE="Rsync-Test" # uses DAEMON_MODULE_DIR
#DAEMON_MODULE_DIR="/srv/rsync"
#DAEMON_USER=
#DAEMON_PASSWORD=

if (( $UID != 0 )); then
	echo "Call me as root"
	exit -1
fi

function checkrc() {
	logEntry "$1"
	local rc="$1"
	if (( $rc != 0 )); then
		echo "Error $rc"
	fi

	logExit $rc
}

function testCommand() {

	logEntry

	local reply rc

	declare t=(localTarget sshTarget)

	cmds=("ls -b") # "ls -la /" "sudo cat /etc/shadow" "ls -la /forceError" "lsblk")

	for (( target=0; target<${#t[@]}; target++ )); do
		tt="${t[$target]}"
		echo "@@@ ---> Target: $tt"
		for cmd in "${cmds[@]}"; do
			echo "Command: $cmd "
			invokeCommand ${t[$target]} stdout stderr "$cmd"
			rc=$?
			checkrc $rc
			echo "stdout: $stdout"
			echo "stderr: $stderr"
		done
		echo
	done

	logExit $rc
}

reset
testCommand


