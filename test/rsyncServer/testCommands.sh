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

TEST_DIR="Test-Backup"

declare -A localTarget
localTarget[RSYNC_TARGET_TYPE]="$RSYNC_TARGET_TYPE_LOCAL"
localTarget[RSYNC_TARGET_BASE]="."
localTarget[RSYNC_TARGET_DIR]="${TEST_DIR}_tgt"

declare -A sshTarget
sshTarget[RSYNC_TARGET_TYPE]="$RSYNC_TARGET_TYPE_SSH"
sshTarget[RSYNC_TARGET_HOST]="$SSH_HOST"
sshTarget[RSYNC_TARGET_USER]="$SSH_USER"
sshTarget[RSYNC_TARGET_KEY_FILE]="$SSH_KEY_FILE"
sshTarget[RSYNC_TARGET_DIR]="$DAEMON_MODULE_DIR"

declare -A rsyncTarget
rsyncTarget[RSYNC_TARGET_TYPE]="$RSYNC_TARGET_TYPE_DAEMON"
rsyncTarget[RSYNC_TARGET_HOST]="$SSH_HOST"
rsyncTarget[RSYNC_TARGET_USER]="$SSH_USER"
rsyncTarget[RSYNC_TARGET_KEY_FILE]="$SSH_KEY_FILE"
rsyncTarget[RSYNC_TARGET_DIR]="$DAEMON_MODULE_DIR"
rsyncTarget[RSYNC_TARGET_DAEMON_MODULE]="$DAEMON_MODULE"
rsyncTarget[RSYNC_TARGET_DAEMON_USER]="$DAEMON_USER"
rsyncTarget[RSYNC_TARGET_DAEMON_PASSWORD]="$DAEMON_PASSWORD"

RSYNC_OPTIONS="-aArv"

ECHO_REPLIES=

if (( $UID != 0 )); then
	echo "Call me as root"
	exit -1
fi

function checkrc() {
	logEntry "$1"
	local rc="$1"
	if (( $rc != 0 )); then
		echo "Error $rc"
		echo $stderr
	else
		: echo "OK: $rc"
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

	case ${target[RSYNC_TARGET_TYPE]} in

		$RSYNC_TARGET_TYPE_LOCAL | $RSYNC_TARGET_TYPE_SSH | $RSYNC_TARGET_TYPE_DAEMON)
			echo "${target[RSYNC_TARGET_DIR]}"
			;;

		*) echo "Unknown target ${target[RSYNC_TARGET_TYPE]}"
			exit -1
			;;
	esac
}

function testRsync() {

	local reply

	declare t=(sshTarget rsyncTarget)
	#declare t=(sshTarget)
	#declare t=(rsyncTarget)
	#declare t=(localTarget)

	for (( target=0; target<${#t[@]}; target++ )); do

		tt="${t[$target]}"
		local -n tgt=$tt

		echo
		echo "@@@ ---> Target: $tt TargetDir: ${tgt[RSYNC_TARGET_DIR]}"

		echo "@@@ Creating test data in local dir $TEST_DIR"
		targetDir="$(getRemoteDirectory "${t[$target]}" ${tgt[RSYNC_TARGET_DIR]})"
		createTestData $TEST_DIR

		echo "@@@ Copy local data $TEST_DIR to remote $TEST_DIR"
		invokeRsync ${t[$target]} stdout stderr "$RSYNC_OPTIONS" RSYNC_TARGET_DIRECTION_TO "$TEST_DIR/" "$TEST_DIR/"
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ Verify remote data in ${tgt[RSYNC_TARGET_DIR]}"
#		See https://unix.stackexchange.com/questions/87405/how-can-i-execute-local-script-on-remote-machine-and-include-arguments
		printf -v args '%q ' "${tgt[RSYNC_TARGET_DIR]}/$TEST_DIR"
		invokeCommand ${t[$target]} stdout stderr "bash -s -- $args"  < ./testRemote.sh
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		# cleanup local dir
		echo "@@@ Clear local data dir $TEST_DIR"
		rm ./$TEST_DIR/*

		echo "@@@ Copy remote data $TEST_DIR to local $TEST_DIR"
		invokeRsync ${t[$target]} stdout stderr "$RSYNC_OPTIONS" RSYNC_TARGET_DIRECTION_FROM "$TEST_DIR/" "$TEST_DIR/"
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ Verify local data in $TEST_DIR"
		verifyTestData "$TEST_DIR"

		# cleanup local dir
		echo "@@@ Clear local data $TEST_DIR"
		rm ./$TEST_DIR/*

		echo "@@@ List remote data"
		invokeCommand ${t[$target]} stdout stderr "ls -la "${tgt[RSYNC_TARGET_DIR]}/$TEST_DIR""
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ Clear remote data"
		invokeCommand ${t[$target]} stdout stderr "rm "${tgt[RSYNC_TARGET_DIR]}/$TEST_DIR/*""
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ List cleared remote data"
		invokeCommand ${t[$target]} stdout stderr "ls -la "${tgt[RSYNC_TARGET_DIR]}/$TEST_DIR""
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

	done

}

# test whether ssh configuration is OK and all required commands can be executed via ssh

function verifyRemoteSSHAccessOK() {
	logEntry

	local reply rc

	declare t=sshTarget

	# test root access
	cmd="mkdir -p /root/raspiBackup/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	# cleanup
	cmd="rm -rf /root/raspiBackup/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

}

# test whether daemon configuration is OK and all required commands can be executed via ssh

function verifyRemoteDaemonAccessOK() {
	logEntry

	local reply rc

	verifyRemoteSSHAccessOK

	declare t=rsyncTarget

	# check existance of module and access
	local moduleDir=${rsyncTarget[RSYNC_TARGET_DIR]}
	cmd="mkdir -p $moduleDir/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	cmd="touch $moduleDir/dummy/dummy.txt"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	# cleanup
	cmd="rm $moduleDir/dummy/dummy.txt"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	#cleanup
	cmd="rmdir $moduleDir/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

}

function testCommand() {

	logEntry

	local reply rc

	declare t=(localTarget sshTarget rsyncTarget)

	cmds=("ls -b" "ls -la /" "mkdir /dummy" "ls -la /dummy" "rmdir /dummy" "ls -la /forceError" "lsblk")

	for (( target=0; target<${#t[@]}; target++ )); do
		tt="${t[$target]}"
		echo "@@@ ---> Target: $tt"
		for cmd in "${cmds[@]}"; do
			echo "Command: $cmd "
			export RSYNC_TARGET_TYPE=$tt
			invokeCommand ${t[$target]} stdout stderr "$cmd"
			rc=$?
			checkrc $rc
			(( ECHO_REPLIES )) && echo "stdout: $stdout"
			(( ECHO_REPLIES )) && echo "stderr: $stderr"
		done
		echo
	done

	logExit $rc
}

reset
echo "##################### daemon access ok ##################"
verifyRemoteDaemonAccessOK
echo "##################### ssh access ok ##################"
verifyRemoteSSHAccessOK
echo "##################### rsync ##################"
testRsync
echo "##################### command ##################"
testCommand

