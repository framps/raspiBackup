#!/bin/bash

#######################################################################################################################
#
#  Download and start a raspiBackup version available on github
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2022 framp at linux-tips-and-tricks dot de
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

if [[ -z $1 ]]; then
	echo "??? Missing git branch name"
	exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "-?" || "$1" == "?" ]]; then
	echo "Download and invoke raspiBackup.sh from github repository."
	echo "First option defined the github repository to use."
	echo "All further options are passed on to raspiBackup."
	exit 1
fi

branch="$1"
shift

downloadURL="https://raw.githubusercontent.com/framps/raspiBackup/$branch/raspiBackup.sh"

echo "--- Downloading raspiBackup.sh from git branch $branch as raspiBackup_$branch.sh"
wget $downloadURL -O raspiBackup_$branch.sh
rc=$?

if (( $rc != 0 )); then
	echo "??? Error occured downloading $downloadURL. RC: $rc"
	exit 1
fi	

chmod +x raspiBackup_$branch.sh

sha="$(curl -s -H "Accept: application/vnd.github.VERSION.sha" "https://api.github.com/repos/framps/raspiBackup/commits/master")"

if (( $? != 0 )); then
	echo "??? Error retrieving sha"
	exit 1
fi	

shaShort=${sha:0:7}
sed -i "s/\$Sha1/\$Sha1${shaShort}/" ./raspiBackup_$branch.sh 

sudo ./raspiBackup_$branch.sh $@

# TODO: use curl https://api.github.com/repos/framps/raspiBackup/branches/master to extract sha and date


