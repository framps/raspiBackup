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

readonly LOG_FILE=$(cut -d'.' -f1 <<< $(basename "$0")).log
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
	rm -f raspiBackup.deb
	rm -f raspiBackup.deb.sig
	if (( $1 == 0 )); then
		: rm -f $LOG_FILE
	else
		echo "??? Installation failed"
		echo "!!! Check $LOG_FILE for details"
	fi
}

trap 'err $?' ERR
trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm -f $LOG_FILE

echo "--- Downloading raspiBackup Debian package from github"
curl -fsSL $GITHUB_URL/raspiBackup.deb -o raspiBackup.deb
curl -fsSL $GITHUB_URL/raspiBackup.deb.sig -o raspiBackup.deb.sig

version=$(dpkg -I package/raspiBackup.deb | grep "^ Version" | cut -f 3 -d ' ')

echo -n "--- Installing raspiBackup $version. Are you sure? (y|N) "

read -r -n 1 answer

if [[ -n "${str//[[:space:]]/}" ]]; then
	echo
fi

if [[ ! $answer =~ [yYjJ] ]]; then
	echo "!!! Installation of raspiBackup $version aborted"
	exit 0
fi

echo "--- Verifying Debian package was created by framp"
gpg --verbose --verify raspiBackup.deb.sig raspiBackup.deb

if ! gpg --list-keys | grep -q framps; then
	echo "--- Retrieve framps key from github"
	curl https://github.com/framps.gpg | gpg --yes --dearmor -o framps.gpg.asc
	echo "--- Import framps key"
	gpg --import  framps.gpg.asc
fi

echo "--- Installing raspiBackup package and all dependencies"
sudo apt-get install --allow-downgrades -y ./raspiBackup.deb &>>$LOG_FILE

dpkg --list | grep raspibackup | awk '{ print "--- raspiBackup", $3, "installed successfully"; }'

