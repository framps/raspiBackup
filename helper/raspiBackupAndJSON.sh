#!/bin/bash
#
#######################################################################################################################
#
#  Sample script which calls raspiBackup.sh and finally creates a JSON file with the messages
#
#  Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#  NOTE: This is sample code how to extend functionality of raspiBackup and is provided as is with no support.
#
#######################################################################################################################
#
#   Copyright (c) 2024 framp at linux-tips-and-tricks dot de
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

set -euf -o pipefail

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.1"

set +u;GIT_DATE="$Date$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[\^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

function readVars() {
   if [[ -f /tmp/raspiBackup.vars ]]; then
      source /tmp/raspiBackup.vars                 # retrieve some variables from raspiBackup for further processing
# now following variables are available for further backup processing
# BACKUP_TARGETDIR refers to the backupdirectory just created
# BACKUP_TARGETFILE refers to the dd backup file just created
# MSG_FILE refers to message file just created
# LOG_FILE referes to logfile just created
   else
      echo "??? /tmp/raspiBackup.vars not found"
      exit 42
   fi
}

# main program

if (( $UID != 0 )); then
      echo "--- Call me as root or with sudo"
      exit 1
fi

if ! which raspiBackup &>/dev/null; then
   echo "??? Missing raspiBackup.sh"
   exit 1
fi

if ! which raspiBackupMsg2JSON.sh &>/dev/null; then
   echo "??? Missing raspiBackupMsg2JSON.sh"
   exit 1
fi

# create backup
raspiBackup.sh
if (( ! $? )); then
   readVars
# MSG_FILE refers to message file just created
	raspiBackupMsg2JSON.sh "$MSG_FILE" "${MSG_FILE}.json"
fi
