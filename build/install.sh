#!/bin/bash

#######################################################################################################################
#
# 	 Install built raspiBackup Debian package
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

set -euo pipefail

source common.sh
LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE

cleanup() {
	show "Cleanig up"
	if (( $1 == 0 )); then
		rm -f "$LOG_FILE"
	else
		echo "??? Installation failed"
		echo "Check $LOG_FILE for details"
	fi
}

trap 'err $?' ERR
#trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

cmd=${1:-i}	# install without clean
if [[ $cmd == "c" ]]; then
	show "Clean installation of raspiBackup and rsync"
	sudo apt remove -y raspibackup rsync || true
fi

echo "Package verification"
gpg --verbose --verify "$DEB_TGT"/raspiBackup.deb.sig "$DEB_TGT"/raspiBackup.deb

echo "Install package and all dependencies"
sudo apt-get install --allow-downgrades -y "$DEB_TGT"/raspiBackup.deb

echo "Show installation result"
apt-cache policy raspibackup

echo "Files provided"
dpkg -L raspibackup

dpkg --list | grep raspibackup



