#!/bin/bash
#######################################################################################################################
#
#    This script renames old backup directory names used until raspiBackup 0.6.9.1 into the new directory names
#	 used starting with  0.7.0
#
#######################################################################################################################
#
#    Copyright (c) 2025 framp at linux-tips-and-tricks dot de
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

set -eou pipefail

declare -r PS4='|${LINENO}> \011${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

function getOSRelease() { # directory

	local os_release_file
	local os_release
	local dir="$1"

	for os_release_file in $dir/etc/os-release $dir/usr/lib/os-release /dev/null ; do
		[[ -e "$os_release_file" ]] && break
	done

	# the prefix "osr_" prevents a lonely "local" with its output below when grep is unsuccessful
	unset osr_ID osr_VERSION_ID              # unset possible values used from global scope then

	#Quote this to prevent word splitting.
	#var is referenced but not assigned.
	#shellcheck disable=SC2154,SC2046
	local osr_$(grep -E "^ID="         "$os_release_file")
	#Quote this to prevent word splitting.
	#var is referenced but not assigned.
	#shellcheck disable=SC2154,SC2046
	local osr_$(grep -E "^VERSION_ID=" "$os_release_file")

	set +u
	#var is referenced but not assigned.
	#shellcheck disable=SC2154
	os_release="${osr_ID}${osr_VERSION_ID}"  # e.g. debian12 or even debian"12"
	set -u
	os_release="${os_release//\"/}"          # remove any double quotes
	echo "${os_release:-unknownOS}"          # handle empty result
}

# /backupDir/idefix
# /backupDir/idefix/idefix-rsync-backup-20250119-105022

if [[ ! -d $1 ]]; then 
	echo "Invalid dir $1"
	exit 42
fi	

hostName=$(basename $1)

for dir in $1*; do

	if [[ $dir =~ @.*-[dd|ddz|tar|tgz|sync] ]]; then
		echo "New $dir skipped"
		continue
	fi
	
	release="$(getOSRelease $dir)"
	if [[ $release == "unknownOS" ]]; then
		echo "??? Unknown OS $dir skipped"
		continue
	fi
	newDirHostPart="${hostName}@${release//[ \/\\\:\.\-_]/\~}"
	newTypePart="$(cut -d "-" -f 2-5 <<< "$dir")"

	newDirName="${newDirHostPart}-${newTypePart}"
	
	if [[ $dir =~ "_" ]]; then
		newDirName="${newDirName}_$(cut -d "_" -f 2- <<< "$(basename $dir)")"
	fi

#	echo "$dir => $(dirname $dir)/$newDirName"
	echo "$(basename $dir) => $newDirName"
	
done
