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

readonly VERSION="v0.1"
readonly GITREPO="https://github.com/framps/raspberryTools"

#shellcheck disable=SC2155
# (warning): Declare and assign separately to avoid masking return values.			
readonly MYSELF="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
readonly MYNAME=${MYSELF%.*}

function show_help() {
    cat << EOH
$MYSELF $VERSION ($GITREPO)

Rename raspiBackup backup directory names without OS release name created by all raspiBackup releases before 0.7.0 to get the OS release into the directory name. 
That way the old directories are included in the backup recycle process of raspiBackup release 0.7.0 and bejond and don't have to be deleted manually.

NOTE: If the retrieval of the OS release fails the directory is not renamed

Usage: $MYSELF -r | -? | -h | -v
-d: Dryrun. Display how the directories will be renamed with option -r
-r: Rename the directories
-h: Display this help
-v: Display version
EOH
}

function getOSRelease() { # directory

	local os_release_file
	local os_release
	local dir="$1"
	local rc

	os_release_file="$(find $dir -maxdepth 3 -name os-release | head -n 1)"
	
	if (( $? )); then
		os_release="unknownOS"
	else	

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
	fi
	echo "${os_release:-unknownOS}"          # handle empty result
}

MODE_RENAME=0

while getopts ":dhrv?" opt; do

    case "$opt" in
		d) ;;
  		r) MODE_RENAME=1
			;;
        h|\?)
            show_help
            exit 0
            ;;
        v) echo "$MYSELF $VERSION"
            exit 0
            ;;
        *) echo "Unknown option $opt"
            show_help
            exit 1
            ;;
    esac

done

shift $((OPTIND-1))

# /backup/idefix/idefix-rsync-backup-20250119-105022_some_comment

if [[ ! -d $1 ]]; then 
	echo "??? Invalid dir $1"
	exit 42
fi	

hostName=$(basename $1)

for dir in $1/*; do

	if grep -E "@.+[dd|ddz|tar|tgz|rsync].+backup" <<< "$dir"; then
		echo "--- New $dir skipped"
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

	if (( ! $MODE_RENAME )); then
		echo "--- $(basename $dir) => $newDirName"
	else
		echo "mv $dir $(dirname $dir)/$newDirName"
	fi
	
done
