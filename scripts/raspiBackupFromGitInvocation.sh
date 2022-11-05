#!/bin/bash

#######################################################################################################################
#
#  Download and invoke a raspiBackup version available on github
#
#  Example to download latest raspibackup.sh from master branch:
#  curl https://raw.githubusercontent.com/framps/raspiBackup/master/scripts/raspiBackupFromGitInvocation.sh | sudo bash -s -- master
#
#  Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
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

if ! which jq; then
	echo "??? Missing jq. Please install jq first."
	exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "-?" || "$1" == "?" ]]; then
	echo "Download and invoke raspiBackup.sh from github repository."
	echo "First option defines the github repository to use."
	echo "All following options are passed through to raspiBackup."
	exit 1
fi

SHA="JFNoYTE6Cg=="
DATE="JERhdGU6Cg=="

SHA="$(base64 -d <<< "$SHA")"
DATE="$(base64 -d <<< "$DATE")"

branch="$1"
shift

downloadURL="https://raw.githubusercontent.com/framps/raspiBackup/$branch/raspiBackup.sh"

echo "--- Downloading raspiBackup.sh from git branch $branch into current diryctory"
wget $downloadURL -O raspiBackup.sh
rc=$?
trap 'rm -f raspiBackup.sh' SIGINT SIGTERM EXIT

if (( $rc != 0 )); then
	echo "??? Error occured downloading $downloadURL. RC: $rc"
	exit 1
fi	

chmod +x raspiBackup.sh

jsonFile=$(mktemp)
trap 'rm -f raspiBackup.sh; rm -f $jsonFile' SIGINT SIGTERM EXIT

TOKEN=""															# Personal token to get better rate limits 
if [[ -n $TOKEN ]]; then
	HTTP_CODE="$(curl -w "%{http_code}" -o $jsonFile -H "Authorization: token $TOKEN" -s https://api.github.com/repos/framps/raspiBackup/commits/$branch)"
else
	HTTP_CODE="$(curl -w "%{http_code}" -o $jsonFile -s https://api.github.com/repos/framps/raspiBackup/commits/$branch)"
fi
	
rc=$?

if (( $rc != 0 )); then
	echo "??? Error retrieving commit information from github. curl RC: $rc"
	exit 1
fi

if (( $HTTP_CODE != 200 )); then
	echo "??? Error retrieveing commit information from github. HTTP response: $HTTP_CODE"
	jq . $jsonFile
	exit 1
fi	

sha="$(jq -r ".sha" "$jsonFile")"
if [[ -z $sha ]]; then
	echo "??? Error extracting sha from commit JSON"
	exit 1
fi

date="$(jq -r ".commit.author.date" "$jsonFile")"

if [[ -z $date ]]; then
	echo "??? Error extracting date from commit JSON"
	exit 1
fi

shaShort=${sha:0:7}
sed -i "s/\$SHA/\$SHA ${shaShort}/" ./raspiBackup.sh
dateShort="${date:0:10} ${date:11}"
sed -i "s/\$DATE/\$DATE ${dateShort}/" ./raspiBackup.sh

rm -f $jsonFile

trap - SIGINT SIGTERM EXIT

sudo ./raspiBackup.sh $@


