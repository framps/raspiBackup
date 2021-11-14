#!/bin/bash

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
LOG_FILE="$MYNAME.log"

function supportsACLs() {	# directory

	local rc
	touch $1/$MYNAME.acls &>>"$LOG_FILE"
	setfacl -m $USER:rwx $1/$MYNAME.acls &>>"$LOG_FILE"
	return
}

rm "$LOG_FILE" &>>"$LOG_FILE"

trap "rm -f $LOG_FILE" EXIT

if (( $# < 1 )); then
	echo "??? Missing directory"
	exit -1
fi

if ! which setfacl; then
	echo "??? Package acl not installed"
	exit -1
fi

if [[ ! -d $1 ]]; then
	echo "??? Directory $1 does not exist"
	exit -1
fi

if supportsACLs $1; then
	echo "*** $1 supports ACLs"
	getfacl $1/$MYNAME.acls
else
	echo "??? setfacl Fails on $1 with RC $?"
	cat $LOG_FILE
fi





