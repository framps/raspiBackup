#!/bin/bash

# Just some code to get familiar with remote ssh command execution and rsync daemon

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
#SSH_USER=
#SSH_KEY_FILE=

#DAEMON_HOST=
#DAEMON_MODULE="Test-Backup" # points to /disks/raid1/test
#DAEMON_USER=
#DAEMON_PASSWORD=

readonly TARGET_HOST="TARGET_HOST" # ssh and daemon
readonly TARGET_USER="TARGET_USER" # ssh and daemon
readonly TARGET_KEY="TARGET_KEY" # ssh
readonly TARGET_PASSWORD="TARGET_PASSWORD" # daemon

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

RSYNC_OPTIONS="-arAvp --delete"

LOGFILE="./rsyncServer.log"

rm -f $LOGFILE

LOG="&>> $LOGFILE"
LOG=""

if (( $# < 1 )); then
	echo "Missing directory to sync"
	exit -1
fi

TARGET_DIR="/disks/raid1/test"
SOURCE_DIR="$1"

function checkrc() {
	if (( $1 != 0 )); then
		echo "Error $1"
		exit 1
	fi
}

# invoke command either local or remote via ssh
function invokeCommand() { # target command

	local rc reply

	local -n target=$1

	echo "-> $1: $2" $LOG

	case ${target[$TARGET_TYPE]} in

		$TARGET_TYPE_LOCAL)
			echo "Targethost: $(hostname)" $LOG
			reply="$($2)"
			rc=$?
			echo "<- %rc: $reply" $LOG
			;;

		$TARGET_TYPE_SSH)
			echo "Targethost: ${target[$TARGET_HOST]}" $LOG
			reply="$(ssh "${target[$TARGET_HOST]}" "$2" 2>&1)"
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

	local rc reply direction localDir remoteDir command

	local -n target=$1

	shift
	direction="$1"
	localDir="$2"
	remoteDir="$3"

	echo "-> $direction: $localDir $remoteDir " $LOG

	case ${target[$TARGET_TYPE]} in

		$TARGET_TYPE_LOCAL)
			echo "Targethost: $(hostname)" $LOG
			reply="$(rsync $RSYNC_OPTIONS $localDir $remoteDir)"
			rc=$?
			echo -e "RC: $rc\n$reply" $LOG
			;;

		$TARGET_TYPE_SSH)
			echo "Targethost: ${target[$TARGET_HOST]}" $LOG
			if [[ $direction == $TARGET_DIRECTION_TO ]]; then
				reply="$(rsync $RSYNC_OPTIONS -e "ssh -i ${target[$TARGET_KEY]}" $localDir ${target[$TARGET_USER]}@${target[$TARGET_HOST]}:/$remoteDir)"
			else
				reply="$(rsync $RSYNC_OPTIONS -e "ssh -i ${target[$TARGET_KEY]}" ${target[$TARGET_USER]}@${target[$TARGET_HOST]}:/$remoteDir $localDir)"
			fi
			rc=$?
			echo -e "RC $rc:\n$reply" $LOG
			;;

		$TARGET_TYPE_DAEMON)
			echo "Targethost: ${target[$TARGET_HOST]}" $LOG
			export RSYNC_PASSWORD="${target[$TARGET_PASSWORD]}"
			if [[ $direction == $TARGET_DIRECTION_TO ]]; then
				reply="$(rsync $RSYNC_OPTIONS $localDir rsync://"${target[$TARGET_USER]}"@${target[$TARGET_HOST]}:/$remoteDir)" # remoteDir is actually the rsync server module
			else
				reply="$(rsync $RSYNC_OPTIONS rsync://"${target[$TARGET_USER]}"@${target[$TARGET_HOST]}:/$remoteDir $localDir)"
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

		TARGET_DIR_SPEC="$TARGET_DIR"
		(( $target == 2 )) && TARGET_DIR_SPEC="$DAEMON_MODULE"

		invokeRsync ${t[$target]} $TARGET_DIRECTION_TO "$SOURCE_DIR" "$TARGET_DIR_SPEC"
		checkrc $?

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
