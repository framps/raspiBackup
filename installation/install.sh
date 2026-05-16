#!/bin/bash 

#######################################################################################################################
#
# Script to download and start the raspiBackup apt installer.
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2020-2022 framp at linux-tips-and-tricks dot de
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

MYSELF="install"
VERSION="0.1.4"

[[ -n $URLTARGET ]] && URLTARGET="/$URLTARGET"
INSTALLER="raspiBackupInstall.sh"
INSTALLER_DOWNLOAD_URL="https://raw.githubusercontent.com/framps/raspiBackup/master/build/$INSTALLER"

CURRENT_DIR=$(pwd)

LOG_FILE="$CURRENT_DIR/$MYSELF.log"

GIT_DATE="$Date$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

function cleanup() {
	[[ -f "$INSTALLER" ]] && rm -f "$INSTALLER" &>/dev/null
	cd "$CURRENT_DIR" || exit
	[[ -f "$CURRENT_DIR/$MYSELF" ]] && rm -f "$CURRENT_DIR/$MYSELF" &>/dev/null
}

if [[ $# == 1 && ( $1 == "-v" || $1 == "--version" ) ]]; then
	echo $GIT_CODEVERSION
	exit 0
fi

trap cleanup SIGINT SIGTERM EXIT

cd ~ || exit
# download and invoke installer
echo "Downloading $INSTALLER_DOWNLOAD_URL ..." > "$LOG_FILE"
curl -L "$INSTALLER_DOWNLOAD_URL" -o $INSTALLER &>> "$LOG_FILE"
rc=$?

if (( $rc )); then
	echo "??? Download error for $INSTALLER_DOWNLOAD_URL. RC: $rc" >> "$LOG_FILE"
	cat "$LOG_FILE"
	exit 1
fi

echo "Starting ./$INSTALLER ..." >> "$LOG_FILE"
bash "./$INSTALLER" "$@"
rc=$?
if (( $rc )); then
	echo "??? $INSTALLER failed. RC: $rc" >> "$LOG_FILE"
	cat "$LOG_FILE"
	exit 1
else
	rm "$LOG_FILE"
fi
