#!/bin/bash

#######################################################################################################################
#
# Check if a filesystem supports Linux fileattributes
#
# For example NTFS does not support Linux fileattributes
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

if (( $UID != 0 )); then
	echo	"$MYSELF has to be called with sudo. Try \"sudo $MYNAME.sh\""
	exit 42
fi

function supportsFileAttributes() {	# directory

	local attrs owner group r x
	local attrsT ownerT groupT
	local result=1	# no

	touch /tmp/$MYNAME.fileattributes
	chown 65534:65534 /tmp/$MYNAME.fileattributes
	chmod 057 /tmp/$MYNAME.fileattributes

	# ls -la output
	# ----r-xrwx 1 nobody nogroup 0 Oct 30 19:06 /tmp/supportsFileattributes.fileattributes

	read attrs x owner group r <<< $(ls -la /tmp/$MYNAME.fileattributes)
	echo "Fileattributes of local file:"
	echo "   Attributes: $attrs"
	echo "   Owner: $owner"
	echo "   Group: $group"

	# following command will return an error and message
	# cp: failed to preserve ownership for '/mnt/supportsFileattributes.fileattributes': Operation not permitted
	cp -a /tmp/$MYNAME.fileattributes /$1 
	
	read attrsT x ownerT groupT r <<< $(ls -la /$1/$MYNAME.fileattributes)
	# attrsT="$(sed 's/+$//' <<< $attrsT)" # delete + sign present for extended security attributes
	# Don't delete ACL mark. Target backup directory should not have any ACLs. Otherwise all files in the backup dircetory will inherit ACLs
	# and a restored backup will populate these ACLs on the restored system which is wrong!

	echo "Fileattributes of remote file:"
	echo "   Attributes: $attrsT"
	echo "   Owner: $ownerT"
	echo "   Group: $groupT"
	
	# check fileattributes and ownerships are identical
	[[ "$attrs" == "$attrsT" && "$owner" == "$ownerT" && "$group" == "$groupT" ]] && result=0

	rm /tmp/$MYNAME.fileattributes
	rm /$1/$MYNAME.fileattributes 

	return $result
}

if [[ -z "$1" ]]; then
	echo "Missing directory to check for Linux filesystem support"
	exit 42
fi	

if [[ ! -d "$1" ]]; then
	echo "$1 is no directory"
	exit 42
fi	

if supportsFileAttributes "$1"; then
	echo "Success: Filesystem on $1 supports Linux fileattributes"
else
	echo "Error: Filesystem on $1 does NOT supports Linux fileattributes"
fi
