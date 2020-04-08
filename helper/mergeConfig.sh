#!/bin/bash

#######################################################################################################################
#
#	Merge raspiBackup config files
#
# 	Helper to create a new config file based on a new config file version and merge with the current local config file
#	The generated config file has to be updated manually and finally copied to /usr/local/etc/raspiBackup.conf.
#
#######################################################################################################################
#
#   Copyright (c) 2020 framp at linux-tips-and-tricks dot de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.1"

set +u;GIT_DATE="$Date: 2020-04-07 20:48:34 +0200$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1: 5a6e009$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

ORIG_CONFIG="/usr/local/etc/raspiBackup.conf"
BACKUP_CONFIG="/usr/local/etc/raspiBackup.conf.bak"
NEW_CONFIG="/usr/local/etc/raspiBackup.conf.new"
MERGED_CONFIG="/usr/local/etc/raspiBackup.conf.merged"

PRFX="# >>>>> OLD OPTION <<<<< "

if (( $# < 1 )); then
	echo "Missing config file language (en or de)"
	exit 1
fi

if [[ "$1" != "de" && "$1" != "en" ]]; then
	echo "Invalid language. Has to be either en or de"
	exit 1
fi

if (( $UID != 0 )); then
	echo "Call script as root with 'sudo $0 $@'"
	exit 1
fi

echo "--- raspiBackup config merge helper ---"
echo "Merges a new config file with the current local config file and creates a new config file which has to be manually updated"

rm -f $MERGED_CONFIG &>/dev/null

# download new config file
echo "Downloading new config file"
curl -sSL https://www.linux-tips-and-tricks.de/downloads/raspibackup-$1-conf/download > "$NEW_CONFIG"
if (( $? )); then
	echo "Download of config file failed"
	exit 42
fi

# save old config
echo "Saving old config $ORIG_CONFIG in $BACKUP_CONFIG"
cp $ORIG_CONFIG $BACKUP_CONFIG

# process NEW CONFIG FILE
echo "Merging local config $ORIG_CONFIG and new config $NEW_CONFIG"
merges=0
while read line; do
	if [[ -n "$line" && ! "$line" =~ ^# ]]; then
		KW="$(cut -d= -f1 <<< "$line")"
		echo "$line" >> $MERGED_CONFIG

		[[ "$KW" =~ VERSION_.*CONF ]] && continue

		NC="$(grep "$KW=" $ORIG_CONFIG)"
		if (( $? == 0 )); then
			if [[ "$line" != "$NC" ]]; then
				NC="$(cut -d= -f2- <<< "$NC" )"
				echo "$PRFX" >> $MERGED_CONFIG
				echo "# $KW=$NC" >> $MERGED_CONFIG
				(( merges += 1 ))
			fi
		fi
	else
		echo "$line" >> $MERGED_CONFIG
	fi
done < "$NEW_CONFIG"

UUID="$(grep "^UUID" $ORIG_CONFIG)"
echo "" >> $MERGED_CONFIG
echo "# GENERATED - DO NOT DELETE" >> $MERGED_CONFIG
echo "$UUID" >> $MERGED_CONFIG

echo "Merged config files"

echo "New config file: $NEW_CONFIG"
echo "Backup of local config file: $BACKUP_CONFIG"
echo "Merged config file: $MERGED_CONFIG"
echo "Config options which have to be manually merged: $merges"
echo "Now edit $MERGED_CONFIG and copy it to $ORIG_CONFIG"

