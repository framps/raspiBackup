#!/bin/bash

#######################################################################################################################
#
# 	 Check if a filesystem directory has Linux ACLs
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

function hasACLs() {
	getfacl -p $1 | grep -q -E "^(user|group|other):[^:]+:|^(mask|default)"
	return 
}

function hasDefaultACLs() {
	getfacl -p $1 | grep -q -E "^default"
	return
}

if (( $# < 1 )); then
	echo "??? Missing directory"
	exit -1
fi

if ! which getfacl &>/dev/null; then
	echo "??? Package acl not installed"
	exit -1
fi

dir=$(sed 's:/*$::' <<< "$1")	# remove trailing / so that grep in mount finds directory

if [[ ! -d $dir ]]; then
	echo "??? Directory $dir does not exist or is no directory"
	exit -1
fi

echo
echo "@@@ mount | grep -m 1 $dir"
mount | grep -m 1 $dir

echo
echo "@@@ ls -lad $dir"
if ls -lad "$dir" | grep "+ "; then
	echo "+++ $dir has ACLs according ls"
else	
	ls -lad "$dir"
	echo "--- $dir has NO ACLs according ls"
fi
echo

if hasACLs $dir; then
	echo "+++ $dir has ACLs"
else
	echo "--- $dir has NO ACLs"
fi
	
if hasDefaultACLs $dir; then
	echo "+++ $dir has default ACLs"
else
	echo "--- $dir has NO default ACLs"
fi

echo
echo "@@@ getfacl -p $dir"
getfacl -p $dir

