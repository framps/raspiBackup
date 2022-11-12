#!/bin/bash

#######################################################################################################################
#
#  Download a raspiBackup version available on a github branch into current directory
#
#  Example to download latest raspibackup.sh from master branch:
#  curl -s https://raw.githubusercontent.com/framps/raspiBackup/master/scripts/raspiBackupDownloadFromGit.sh | sudo bash -s -- master
#
#	Next invoke downloaded raspiBackup with sudo ./raspiBackup.sh <options>
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

DOWNLOAD_FILE="raspiBackup.sh"

if [[ -z $1 ]]; then
	echo "??? Missing git branch name"
	exit 1
fi

if ! which jq &>/dev/null; then
	echo "??? Missing jq. Please install jq first."
	exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "-?" || "$1" == "?" ]]; then
	echo "Download $DOWNLOAD_FILE from github repository."
	echo "Option defines the github branch to use."
	exit 1
fi

SHA="XCRTaGExCg=="  	# backslash dollar Sha1
DATE="XCREYXRlCg==" 	# backslash dollar Date

SHA="$(base64 -d <<< "$SHA")"
DATE="$(base64 -d <<< "$DATE")"

branch="$1"
shift

downloadURL="https://raw.githubusercontent.com/framps/raspiBackup/$branch/$DOWNLOAD_FILE"

echo "--- Downloading $DOWNLOAD_FILE from git branch $branch into current directory ..."
wget -q $downloadURL -O raspiBackup.sh
rc=$?
trap "rm -f $DOWNLOAD_FILE" SIGINT SIGTERM EXIT

if (( $rc != 0 )); then
	echo "??? Error occured downloading $downloadURL. RC: $rc"
	exit 1
fi	

chmod +x raspiBackup.sh

jsonFile=$(mktemp)
trap "rm -f $DOWNLOAD_FILE; rm -f $jsonFile" SIGINT SIGTERM EXIT

echo "--- Retrieving commit meta data of $DOWNLOAD_FILE ..."
TOKEN=""															# Personal token to get better rate limits 
if [[ -n $TOKEN ]]; then
	HTTP_CODE="$(curl -sq -w "%{http_code}" -o $jsonFile -H "Authorization: token $TOKEN" -s https://api.github.com/repos/framps/raspiBackup/commits/$branch)"
else
	HTTP_CODE="$(curl -sq -w "%{http_code}" -o $jsonFile -s https://api.github.com/repos/framps/raspiBackup/commits/$branch)"
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

echo "--- Inserting commit meta data into downloaded file $DOWNLOAD_FILE ..."

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
sed -i "s/$SHA/${SHA}: ${shaShort}/" ./$DOWNLOAD_FILE
dateShort="${date:0:10} ${date:11}"
sed -i "s/$DATE/${DATE}: ${dateShort}/" ./$DOWNLOAD_FILE

rm -f $jsonFile

trap - SIGINT SIGTERM EXIT

echo "--- Use 'sudo ./$DOWNLOAD_FILE' now to start $(./$DOWNLOAD_FILE --version)"
