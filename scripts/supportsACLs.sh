#!/bin/bash

#######################################################################################################################
#
# Check if a filesystem supports Linux ACLs
#
#######################################################################################################################
#
#    Copyright (c) 2021 framp at linux-tips-and-tricks dot de
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
	return 
}

function supportsACLs() {	# directory
	local rc
	touch $1/$MYNAME.acls &>>"$LOG_FILE"
	setfacl -m $USER:rwx $1/$MYNAME.acls &>>"$LOG_FILE"
	return
}

function hasDefaultACLs() {
	getfacl -p $1 | grep -q -E "^(user|group|other):[^+]+:|^(mask|default)"
	return
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

if supportsACLs $1; then
	echo "*** $1 supports ACLs"
	if hasACLs $1; then
		echo "*** $1 has ACLs"
	else
		echo "*** $1 has NO ACLs"
	fi
	
	echo
	echo "@@@ getfacl -p $1"
	getfacl -p $1
	
	if hasDefaultACLs $1; then
		echo "*** $1 has default ACLs"
	else
		echo "*** $1 has NO default ACLs"
	fi
else
	echo "??? setfacl Fails on $1"
	echo @@@ LOG @@@
	cat $LOG_FILE
fi

rm $1/$MYNAME.acls &>/dev/null
