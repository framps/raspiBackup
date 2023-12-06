#!/bin/bash

#######################################################################################################################
#
#  Download any latest file available on any raspiBackup github repository branch into current directory
#
#  Example to download latest raspiBackup.sh from master branch:
#  curl -s https://raw.githubusercontent.com/framps/raspiBackup/master/scripts/raspiBackupDownloadFromGit.sh | bash -s -- master
#
#  Example to download latest raspiBackupWrapper.sh from master branch:
#  curl -s https://raw.githubusercontent.com/framps/raspiBackup/master/scripts/raspiBackupDownloadFromGit.sh | bash -s -- master helper/raspiBackupWrapper.sh
#
#  Example to download latest raspiBackupInstallUI.sh from beta branch:
#  curl -s https://raw.githubusercontent.com/framps/raspiBackup/master/scripts/raspiBackupDownloadFromGit.sh | bash -s -- master beta/raspiBackupInstallUI.sh
#
#  Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (c) 2022-2023 framp at linux-tips-and-tricks dot de
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

MYSELF="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"					# use linked script name if the link is used
MYNAME=${MYSELF%.*}

FILE_RASPIBACKUP="raspiBackup.sh"
FILE_RASPIBACKUP_INSTALLER="raspiBackupInstallUI.sh"

updateGitInfo=1

if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" || "$1" == "-?" || "$1" == "?" ]]; then
	echo "Purpose: Download any file from any raspiBackup github repository branch."
	echo "Syntax:  $MYSELF branchName [fileName]"
	echo "Example: $MYSELF master helper/raspiBackupWrapper.sh"
	echo "Default for fileName is $FILE_RASPIBACKUP"
	echo "If the file resides in a subdirectory prefix fileName with the directories."
	exit 1
fi

if [[ -n "$2" ]]; then
	DOWNLOAD_FILE="$2"
	if [[ $(basename $DOWNLOAD_FILE) != $FILE_RASPIBACKUP_INSTALLER && $(basename $DOWNLOAD_FILE) != $FILE_RASPIBACKUP ]]; then
		updateGitInfo=0
	fi
else
	DOWNLOAD_FILE="$FILE_RASPIBACKUP"
fi

if (( $updateGitInfo )); then
	if ! which jq &>/dev/null; then
		echo "... Installing jq required by $MYNAME."
		sudo apt install jq
		if ! which jq &>/dev/null; then
			echo "??? jq required by $MYNAME. Automatic jq installation failed. Please install jq manually."
			exit 1
		fi
	fi
fi

SHA="XCRTaGExCg=="  	# backslash dollar Sha1
DATE="XCREYXRlCg==" 	# backslash dollar Date

SHA="$(base64 -d <<< "$SHA")"
DATE="$(base64 -d <<< "$DATE")"

branch="$1"
shift

downloadURL="https://raw.githubusercontent.com/framps/raspiBackup/$branch/$DOWNLOAD_FILE"
targetFilename="$(basename "$DOWNLOAD_FILE")"

rm -f "$targetFilename"

trap "rm -f $targetFilename" SIGINT SIGTERM EXIT

echo "--- Downloading $DOWNLOAD_FILE from git branch $branch into current directory ..."
wget -q $downloadURL -O "$targetFilename"
rc=$?

if (( $rc != 0 )); then
	echo "??? Error occured downloading $downloadURL. RC: $rc"
	exit 1
fi

echo "--- Download finished successfully"

if (( $updateGitInfo )); then

	jsonFile=$(mktemp)
	trap "rm -f $DOWNLOAD_FILE; rm -f $jsonFile" SIGINT SIGTERM EXIT

	echo "--- Retrieving commit meta data of $DOWNLOAD_FILE from $branch ..."
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
		echo "??? Error retrieving commit information from github. HTTP response: $HTTP_CODE"
		jq . $jsonFile
		exit 1
	fi

	echo "--- Inserting commit meta data into downloaded file $targetFilename ..."

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
	sed -i "s/$SHA/${SHA}: ${shaShort}/" $targetFilename
	dateShort="${date:0:10} ${date:11}"
	sed -i "s/$DATE/${DATE}: ${dateShort}/" $targetFilename

	rm -f $jsonFile
fi

trap - SIGINT SIGTERM EXIT

if [[ "$targetFilename" == *\.sh ]]; then
	chmod +x "$targetFilename"
fi

if (( updateGitInfo )); then
	echo "--- $(./$targetFilename --version)"
fi

SDO=""
if [[ $targetFilename == "$FILE_RASPIBACKUP" || $targetFilename == "$FILE_RASPIBACKUP_INSTALLER" ]]; then
	SDO="sudo "
fi

echo "--- Start $targetFilename with \`$SDO./$targetFilename\` now"
