#!/bin/bash

# Just some code to get familiar with remote ssh command execution and rsync daemon

source ../../raspiBackup.sh --include

# @@@ test scenarios @@@
#
### Copy functions
#
# - Test File attributes and ACLs are transferred correctly
# - Test RCs are transferred correctly
#
## - Copy to remote -
# 1) Copy local files to other local destination
# 2) Copy local files to remote destination via ssh
# 3) Copy local files to remote destination via rsync daemon

## - Copy from remote -
# 1) Copy local files to other local destination
# 2) Copy remote files from remote destination to local via ssh (ACLs will not be preserved)
# 3) Copy remote files from remote destination to local via rsync daemon

# !!! - Test File attributes and ACLs are transferred correctly
# !!! - Test RCs are transferred correctly

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

#
# Required access rights
#
# SSH
# 1) Local user (e.g. framp) calling script via sudo to connect to remote backup system has to have its public key in authorized_hosts of remote user (e.g. pi)
# 2) Remote user (e.g. pi) can call sudo
#
# RSYNC
# 1) See access rights for SSH
# 2) Remote rsync server user has to have full access on module directory
#
# LOCAL_USER: SSH key access to SSH_USER@SSH_HOST
# SSH_USER: Can use sudo on remote host
#
# Suggestion: Use the same remote user for SSH and rsync module

RSYNC_OPTIONS="-aHAxvp --delete"

if (( $UID != 0 )); then
	echo "Call me as root"
	exit -1
fi

function checkrc() {
	logEntry "$1"
	local rc="$1"
	if (( $rc != 0 )); then
		echo "Error $rc"
		exit 1
	fi

	logExit $rc
}

function createTestData() { # directory

	if [[ ! -d $1 ]]; then
		mkdir $1
	fi

	rm -f $1/acl.txt
	rm -f $1/noacl.txt

	touch $1/acl.txt
	setfacl -m u:$USER:rwx $1/acl.txt

	touch $1/noacl.txt

	verifyTestData "$1"
}

function verifyTestData() { # directory

	./testRemote.sh "$1"

}

function getRemoteDirectory() { # target directory

	local -n target=$1

	case ${target[$TARGET_TYPE]} in

		$TARGET_TYPE_SSH | $TARGET_TYPE_DAEMON)
			echo "${target[$TARGET_DIR]}"
			;;

		*) echo "Unknown target ${target[$TARGET_TYPE]}"
			exit -1
			;;
	esac
}

function testCommand() {

	logEntry

	local reply rc

	echo "@@@ testCommand @@@"

	declare t=(localTarget sshTarget)

	cmds=("ls -la /" "sudo cat /etc/shadow")

	for (( target=0; target<${#t[@]}; target++ )); do
		tt="${t[$target]}"
		echo "@@@ ---> Target: $tt"
		for cmd in "${cmds[@]}"; do
			echo "Command: $cmd "
			reply="$(invokeCommand ${t[$target]} "$cmd")"
			rc=$?
			checkrc $rc
			logItem "$reply"
		done
		echo
	done

	logExit $rc
}

function testRsync() {

	local reply

	echo "@@@ testRsync @@@"

	declare t=(localTarget sshTarget rsyncTarget)

	for (( target=2; target<${#t[@]}; target++ )); do

		tt="${t[$target]}"
		echo
		echo "@@@ ---> Target: $tt"

		echo "@@@ Creating test data in local dir"
		if [[ $tt == "localTarget" ]]; then
			targetDir="${TEST_DIR}_tgt"
			mkdir -p $targetDir
		else
			targetDir="$(getRemoteDirectory "${t[$target]}" $TARGET_DIR)"
		fi
		createTestData $TEST_DIR

		echo "@@@ Copy local data to remote"
		invokeRsync ${t[$target]} "$RSYNC_OPTIONS" $TARGET_DIRECTION_TO "$TEST_DIR/" "$targetDir"
		checkrc $?
		logItem "$reply"

		echo "@@@ Verify remote data"
#		See https://unix.stackexchange.com/questions/87405/how-can-i-execute-local-script-on-remote-machine-and-include-arguments
		printf -v args '%q ' "$targetDir"
		reply="$(invokeCommand ${t[$target]} "bash -s -- $args"  < ./testRemote.sh)"
		checkrc $?
		logItem "$reply"

		# cleanup local dir
		echo "@@@ Clear local data"
		rm ./$TEST_DIR/*

		echo "@@@ Copy remote data to local"
		reply="$(invokeRsync ${t[$target]} "$RSYNC_OPTIONS" $TARGET_DIRECTION_FROM "$targetDir/" "$TEST_DIR")"
		checkrc $?
		logItem "$reply"

		echo "@@@ Verify local data"
		verifyTestData "$TEST_DIR"

		echo "@@@ Remote data"
		reply="$(invokeCommand ${t[$target]} "ls -la "$targetDir/*"")"
		logItem "$reply"

		echo "@@@ Clear remote data"
		reply="$(invokeCommand ${t[$target]} "rm "$targetDir/*"")"
		logItem "$reply"

		echo "@@@ Remote data cleared"
		reply="$(invokeCommand ${t[$target]} "ls -la "$targetDir"")"
		logItem "$reply"

#		remote error

		echo "@@@ Error"
		replay="$(invokeRsync ${t[$target]} "$RSYNC_OPTIONS" $TARGET_DIRECTION_TO "${TEST_DIR}Dummy/" "${targetDir}Dummy")"
		checkrc $?
		logItem "$reply"

	done

}

reset
testRsync
#testCommand


