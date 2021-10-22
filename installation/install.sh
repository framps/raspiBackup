#!/usr/bin/env bash
#######################################################################################################################
#
# Script to download, install and configure raspiBackup.sh.
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2020 framp at linux-tips-and-tricks dot de
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
VERSION="0.1.1"

URL="https://www.linux-tips-and-tricks.de"
INSTALLER="raspiBackupInstallUI.sh"
INSTALLER_DOWNLOAD_URL="$URL/$INSTALLER"
TO_BE_INSTALLED="raspiBackup.sh"

GIT_DATE="$Date$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
GIT_COMMIT="$Sha1$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

function cleanup() {
	[[ -f "$MYSELF" ]] && rm -f "$MYSELF" &>/dev/null
	[[ -f "./$INSTALLER" ]] && rm -f "./$INSTALLER" &>/dev/null
	cd "$CURRENT_DIR"
}

if [[ $# == 1 && ( $1 == "-v" || $1 == "--version" ) ]]; then
	echo $GIT_CODEVERSION
	exit 0
fi

if (( $UID != 0 )) && [[ $1 != "-h" ]]; then
	echo "Root access required to install $TO_BE_INSTALLED. Please use 'sudo ./$MYSELF'."
	exit 1
fi

CURRENT_DIR=$(pwd)

trap cleanup SIGINT SIGTERM EXIT

cd ~
# download and invoke installer
curl -sLO "$INSTALLER_DOWNLOAD_URL" && sudo bash "./$INSTALLER" "$1"
