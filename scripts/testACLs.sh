#!/bin/bash

#######################################################################################################################
#
# Test if a filesystem supports Linux ACLs
#
#######################################################################################################################
#
#    Copyright (c) 2025 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
LOG_FILE="$MYNAME.log"

function hasACLs() {
	getfacl -p $1 | grep -q -E "^(user|group|other):[^+]+:|^(mask|default)"
	local rc=$?
	(( ! $rc )) && echo "$1 has ACLs" || echo "$1 has NO ACLs"
	return $rc
}

function hasDefaultACLs() {
	getfacl -p $1 | grep -q -E "^default"
	local rc=$?
	(( ! $rc )) && echo "$1 has default ACLs" || echo "$1 has NO default ACLs"
	return $rc
}

function supportsACLs() {	# directory

	local rc
	touch $1/$MYNAME.acls &>>"$LOG_FILE"
	setfacl -m $USER:rwx $1/$MYNAME.acls &>>"$LOG_FILE"
	rc=$?
	rm $1/$MYNAME.acls &>/dev/null
	return $rc
}

function setACLs() {	# directory

	local rc
	touch $1/$MYNAME.acls &>>"$LOG_FILE"
	getfacl -p $1/$MYNAME.acls &>>"$LOG_FILE"
	getfacl -p $1 &>>"$LOG_FILE"
	if ! setfacl -m $USER:rwx $1/$MYNAME.acls &>>"$LOG_FILE"; then
		echo "setfacl on file fails"
	    return 1
	fi
	hasACLs $1/$MYNAME.acls &>>"$LOG_FILE"
	if ! setfacl -m d:u:$USER:rwx $1 &>>$LOG_FILE; then
		echo "setfacl on dir fails"
	    return 1
	fi
	return 0
}

rm "$LOG_FILE" &>>"$LOG_FILE"

trap "rm -f $LOG_FILE" EXIT

if (( $# < 1 )); then
	echo "??? Missing directory"
	exit -1
fi

if ! which setfacl &>/dev/null; then
	echo "??? Package acl not installed"
	exit -1
fi

if [[ ! -d $1 ]]; then
	echo "??? Directory $1 does not exist"
	exit -1
fi

echo "@@@ Status @@@"
getfacl -p $1  &>>"$LOG_FILE"
hasACLs $1
hasDefaultACLs $1

supportsACLs $1
aclsSupported=$((! $? ))

if (( aclsSupported )); then
	setACLs $1
	echo "@@@ Updated @@@"
	getfacl -p $1/$MYNAME.acls &>>"$LOG_FILE"
	hasACLs $1/$MYNAME.acls
	getfacl -p $1  &>>"$LOG_FILE"
	hasACLs $1
	hasDefaultACLs $1

	echo "@@@ New @@@"	
	touch $1/$MYNAME.acls2 &>>"$LOG_FILE"
	setfacl -m $USER:rwx $1/$MYNAME.acls2 &>>"$LOG_FILE"
	hasACLs $1/$MYNAME.acls2

	echo "@@@ Reset @@@"
	setfacl -b $1  &>>"$LOG_FILE"
	setfacl -b $1/$MYNAME.acls  &>>"$LOG_FILE"

	getfacl -p $1/$MYNAME.acls  &>>"$LOG_FILE"
	hasACLs $1/$MYNAME.acls
	getfacl -p $1  &>>"$LOG_FILE"
	hasACLs $1
	hasDefaultACLs $1
	
else
	echo "ACLs not supported"
fi

rm $1/$MYNAME.acls &>/dev/null
rm $1/$MYNAME.acls2 &>/dev/null

echo
echo "@@@@@@ LOG @@@@@@"
cat $LOG_FILE
