#!/bin/bash

# Just some code to get familiar with remote ssh command execution and rsync daemon

declare -r PS4='|${LINENO}> \011${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# @@@ test scenarios @@@
#
### Rsync functions
#
## - rsync to -
# 1) Copy local files to other local destination
# 2) Copy local files to remote destination via ssh (ACLs will not be preserved)
# 3) Copy local files to remote destination via rsync daemon

# - Test File attributes and ACLs are transferred correctly
# - Test RCs are transferred correctly

## - rsync from -
# 1) Copy local files to other local destination
# 2) Copy remote files from remote destination to local via ssh (ACLs will not be preserved)
# 3) Copy remote files from remote destination to local via rsync daemon

# - Test File attributes and ACLs are transferred correctly
# - Test RCs are transferred correctly

### Command execution
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
#SSH_USER= # root
#SSH_KEY_FILE= # public key of user

#DAEMON_HOST=
#DAEMON_MODULE="Test-Backup" # uses DAEMON_DIR
#DAEMON_MODULE_DIR="/disks/raid1/test"
#DAEMON_USER=
#DAEMON_PASSWORD=

readonly TARGET_HOST="TARGET_HOST" # ssh and daemon
readonly TARGET_USER="TARGET_USER" # ssh and daemon
readonly TARGET_KEY="TARGET_KEY" # ssh
readonly TARGET_PASSWORD="TARGET_PASSWORD" # daemon
readonly TARGET_MODULE="TARGET_MODULE" # daemon
readonly TARGET_MODULE_DIR="TARGET_MODULE_DIR" # daemon

readonly TARGET_TYPE="TARGET_TYPE"
readonly TARGET_TYPE_DAEMON="TARGET_TYPE_DAEMON"
readonly TARGET_TYPE_SSH="TARGET_TYPE_SSH"
readonly TARGET_TYPE_LOCAL="TARGET_TYPE_LOCAL"

readonly TARGET_DIRECTION_TO="TARGET_DIRECTION_TO"	# from local to remote
readonly TARGET_DIRECTION_FROM="TARGET_DIRECTION_FROM" # from remote to local

declare -A sshTarget
sshTarget[$TARGET_TYPE]="$TARGET_TYPE_SSH"
sshTarget[$TARGET_HOST]="$SSH_HOST"
sshTarget[$TARGET_USER]="$SSH_USER"
sshTarget[$TARGET_KEY]="$SSH_KEY_FILE"

declare -A localTarget
localTarget[$TARGET_TYPE]="$TARGET_TYPE_LOCAL"

declare -A rsyncTarget
rsyncTarget[$TARGET_TYPE]="$TARGET_TYPE_DAEMON"
rsyncTarget[$TARGET_HOST]="$DAEMON_HOST"
rsyncTarget[$TARGET_USER]="$DAEMON_USER"
rsyncTarget[$TARGET_PASSWORD]="$DAEMON_PASSWORD"
rsyncTarget[$TARGET_MODULE]="$DAEMON_MODULE"
rsyncTarget[$TARGET_MODULE_DIR]="$DAEMON_MODULE_DIR"

RSYNC_OPTIONS="-aHAxvp --delete"

LOGFILE="./rsyncServer.log"

rm -f $LOGFILE

LOG="&>> $LOGFILE"
#LOG=""

#f (( $# < 1 )); then
#	echo "Missing directory to sync"
#	exit -1
#fi

SOURCE_DIR=Test-Backup
TARGET_DIR="/srv/rsync/$SOURCE_DIR"

if (( $UID != 0 )); then
	echo "Call me as root"
	exit -1
fi

function checkrc() {
	if (( $1 != 0 )); then
		echo "Error $1"
		exit 1
	fi
}

function createTestData() { # directory

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

		$TARGET_TYPE_LOCAL | $TARGET_TYPE_SSH)
			echo "$2"
			;;

		$TARGET_TYPE_DAEMON)
			echo "${target[$TARGET_MODULE_DIR]}"
			;;

		*) echo "Unknown target ${target[$TARGET_TYPE]}"
			exit -1
			;;
	esac

}

# invoke command either local or remote via ssh
function invokeCommand() { # target command

	local rc reply

	local -n target=$1

	echo "-> $1: $2" $LOG

	case ${target[$TARGET_TYPE]} in

		$TARGET_TYPE_LOCAL)
			echo "Local targethost: $(hostname)" $LOG
			reply="$($2)"
			rc=$?
			echo "<- %rc: $reply" $LOG
			;;

		$TARGET_TYPE_SSH)
			echo "SSH targethost: ${target[$TARGET_USER]}@${target[$TARGET_HOST]}" $LOG
			reply="$(ssh "${target[$TARGET_USER]}@${target[$TARGET_HOST]}" "$2" 2>&1)"
			rc=$?
			echo "<- $rc: $reply" $LOG
			;;

		*) echo "Unknown target ${target[$TARGET_TYPE]}"
			exit -1
			;;

	esac

	return $rc
}

function invokeRsync() { # target direction from to

	local rc reply direction fromDir toDir command module

	local -n target=$1

	shift
	direction="$1"
	fromDir="$2"
	toDir="$3"

	echo "-> Dir: $direction: From: $fromDir to: $toDir " $LOG

	case ${target[$TARGET_TYPE]} in

		$TARGET_TYPE_LOCAL)
			echo "local targethost: $(hostname)" $LOG
			reply="$(rsync $RSYNC_OPTIONS $fromDir $toDir)"
			rc=$?
			echo -e "RC: $rc\n$reply" $LOG
			;;

		$TARGET_TYPE_SSH)
			echo "SSH targethost: ${target[$TARGET_HOST]}" $LOG
			if [[ $direction == $TARGET_DIRECTION_TO ]]; then
				reply="$(rsync $RSYNC_OPTIONS -e "ssh -i ${target[$TARGET_KEY]}" $fromDir ${target[$TARGET_USER]}@${target[$TARGET_HOST]}:/$toDir)"
			else
				reply="$(rsync $RSYNC_OPTIONS -e "ssh -i ${target[$TARGET_KEY]}" ${target[$TARGET_USER]}@${target[$TARGET_HOST]}:/$fromDir $toDir)"
			fi
			rc=$?
			echo -e "RC $rc:\n$reply" $LOG
			;;

		$TARGET_TYPE_DAEMON)
			echo "daemon targethost: ${target[$TARGET_HOST]}" $LOG
			export RSYNC_PASSWORD="${target[$TARGET_PASSWORD]}"
			module="${target[$TARGET_MODULE]}"
			if [[ $direction == $TARGET_DIRECTION_TO ]]; then
				reply="$(rsync $RSYNC_OPTIONS $fromDir rsync://"${target[$TARGET_USER]}"@${target[$TARGET_HOST]}:/$module)" # toDir is actually the rsync server module
			else
				reply="$(rsync $RSYNC_OPTIONS rsync://"${target[$TARGET_USER]}"@${target[$TARGET_HOST]}:/$module $toDir)"
			fi
			rc=$?
			echo -e "RC $rc:\n$reply" $LOG
			;;

		*) echo "Unknown target ${target[$TARGET_TYPE]}"
			exit -1
			;;
	esac

	return $rc
}

function testSSH() {

	declare t=(sshTarget localTarget)

	for (( target=0; target<2; target++ )); do

		echo -e "\n@@@ ls -la" $LOG
		invokeCommand ${t[$target]} "ls -la ${TARGET_DIR}"
		checkrc $?

	done

	if [[ -e $LOGFILE ]]; then
		echo "+========================"
		cat $LOGFILE
		echo "-========================"
		rm -f $LOGFILE
	fi

}

function testRsync() {

	declare t=(localTarget sshTarget rsyncTarget)

	for (( target=1; target<2; target++ )); do


		echo "@@@ Creating test data in local dir"
		targetDir="$(getRemoteDirectory "${t[$target]}" $TARGET_DIR)"

		createTestData $SOURCE_DIR

		echo "@@@ Copy local data to remote"
		invokeRsync ${t[$target]} $TARGET_DIRECTION_TO "$SOURCE_DIR/" "$targetDir"
		checkrc $?

		echo "@@@ Verify remote data"
#		See https://unix.stackexchange.com/questions/87405/how-can-i-execute-local-script-on-remote-machine-and-include-arguments
		printf -v args '%q ' "$targetDir"
		invokeCommand ${t[$target]} "bash -s -- $args"  < "./testRemote.sh"

		# cleanup local dir
		echo "@@@ Clear local data"
		rm $SOURCE_DIR/*

		echo "@@@ Copy remote data to local"
		invokeRsync ${t[$target]} $TARGET_DIRECTION_FROM "$targetDir/" "$SOURCE_DIR"
		checkrc $?

		echo "@@@ Verify local data"
		verifyTestData "$SOURCE_DIR"

		# invokeCommand ${t[$target]} "rm "$SOURCE_DIR/*""

	done

	if [[ -e $LOGFILE ]]; then
		echo "+========================"
		cat $LOGFILE
		echo "-========================"
		rm -f $LOGFILE
	fi

}

reset
testRsync
