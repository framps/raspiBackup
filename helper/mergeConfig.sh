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
VERSION="0.1.1"

set +u;GIT_DATE="$Date: 2020-04-09 20:59:13 +0200$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1: 587d5d8$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

ORIG_CONFIG="/usr/local/etc/raspiBackup.conf"
NEW_CONFIG="/usr/local/etc/raspiBackup.conf.new"

PRFX="# >>>>> OLD OPTION <<<<< "

if (( $UID != 0 )); then
	echo "??? Please call script as root with 'sudo $0 $@'"
	exit 1
fi

if (( $# >= 1 )); then
	if [[ ! -f "$1" ]]; then
		echo "??? Old config file $1 not found"
		exit 42
	fi
	ORIG_CONFIG="$1"
fi

# detect language the config file is in
lang="en"
l=$(grep -e ^VERSION_.*CONF "$ORIG_CONFIG")
if [[ "$l" =~ _DE ]]; then
	lang="de"
fi

downloadURL="https://www.linux-tips-and-tricks.de/downloads/raspibackup-$lang-conf/download"

if (( $# >= 2 )); then
	if [[ ! -f "$2" ]]; then
		echo "??? New config file $1 not found"
		exit 42
	fi
	NEW_CONFIG="$2"
else
	# download new config file
	echo "--- Downloading new raspiBackup config file from $downloadURL"
	curl -sSL $downloadURL > "$NEW_CONFIG"
	if (( $? )); then
		echo "??? Download of config file from $downloadURL failed"
		exit 42
	fi
fi

CONFIG_DIR=$( cd $( dirname $ORIG_CONFIG); pwd | xargs readlink -f)
MERGED_CONFIG="$CONFIG_DIR/raspiBackup.conf.merged"
BACKUP_CONFIG="$CONFIG_DIR/raspiBackup.conf.bak"
rm -f $MERGED_CONFIG &>/dev/null

# save old config
echo "--- Saving old config $ORIG_CONFIG in $BACKUP_CONFIG"
cp $ORIG_CONFIG $BACKUP_CONFIG

# process NEW CONFIG FILE
echo "--- Merging local config $ORIG_CONFIG and new config $NEW_CONFIG"
merges=0
while read line; do
	if [[ -n "$line" && ! "$line" =~ ^# ]]; then
		KW="$(cut -d= -f1 <<< "$line")"
		echo "$line" >> $MERGED_CONFIG

		[[ "$KW" =~ VERSION_.*CONF ]] && continue

		NC="$(grep "^$KW=" $ORIG_CONFIG)"
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

echo ">>> New config file: $NEW_CONFIG"
echo ">>> Backup of local config file: $BACKUP_CONFIG"
echo ">>> Merged config file: $MERGED_CONFIG"
echo ">>> Number of config options which have to be merged manually: $merges"
echo ">>> Now edit $MERGED_CONFIG and copy it to $ORIG_CONFIG"

