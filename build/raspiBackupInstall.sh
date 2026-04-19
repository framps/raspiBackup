#!/bin/bash
#######################################################################################################################
#
# Script to download and install the raspiBackup oackage
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2026 framp at linux-tips-and-tricks dot de
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

readonly LOG_FILE="build.log"
readonly GITHUB_URL="https://raw.githubusercontent.com/framps/raspiBackup/refs/heads/master/build/package"

function err() {
    local rc="$1"
    echo "??? Unexpected error occured with RC $rc"
    local i=0
    local FRAMES=${#BASH_LINENO[@]}
    for ((i = FRAMES - 2; i >= 0; i--)); do
        echo '  File' \"${BASH_SOURCE[i + 1]}\", line ${BASH_LINENO[i]}, in ${FUNCNAME[i + 1]}
        sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i + 1]}"
    done
    exit 42
}

cleanup() {
	rm -f framps.gpg.asc
	rm -f raspiBackup_0.7.2.deb
	rm -f raspiBackup_0.7.2.deb.sig
	if (( $1 == 0 )); then
		rm -f $LOG_FILE
	else
		echo "??? Installation failed"
		echo "!!! Check $LOG_FILE for details"
	fi
}

trap 'err $?' ERR
trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

if ! gpg --list-keys | grep -q framps; then
	echo "--- Retrieve key from github"
	curl https://github.com/framps.gpg | gpg --yes --dearmor -o framps.gpg.asc
	echo "--- Import framps key"
	gpg --import  framps.gpg.asc
fi

echo "--- Downloading raspiBackup package"
curl -fsSL $GITHUB_URL/raspiBackup_0.7.2.deb -o raspiBackup_0.7.2.deb
echo "--- Downloading raspiBackup package signature"
curl -fsSL $GITHUB_URL/raspiBackup_0.7.2.deb.sig -o raspiBackup_0.7.2.deb.sig

echo "--- Verify package"
gpg --verbose --verify raspiBackup_0.7.2.deb.sig raspiBackup_0.7.2.deb

echo "--- Install raspiBackup package and all dependencies"
sudo apt-get install -y ./raspiBackup_0.7.2.deb &>>$LOG_FILE
