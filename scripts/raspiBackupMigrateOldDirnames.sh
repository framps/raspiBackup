#!/bin/bash

set -eou pipefail

declare -r PS4='|${LINENO}> \011${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

readonly VERSION="v0.1"
readonly GITREPO="https://github.com/framps/raspberryTools"
readonly UNKNOWN="unknownOS"

#shellcheck disable=SC2155
# (warning): Declare and assign separately to avoid masking return values.			
readonly MYSELF="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

function show_help() {
    cat << EOH
$MYSELF $VERSION ($GITREPO)

Rename raspiBackup backup directory names without OS release name created by all raspiBackup releases before 0.7.0 to get the OS release into the directory name. 
That way the old directories are included in the backup recycle process of raspiBackup release 0.7.0 and bejond and don't have to be deleted manually.

NOTE: If the retrieval of the OS release fails the directory is not renamed

Usage: $MYSELF -r | -? | -h | -v
	Dryrun. Display how the directories will be renamed with option -r
-d: Detailed output
-r: Rename the directories
-h: Display this help
-v: Display version
EOH
}

function yesNo() {

    local answer=${1:0:1}
    answer=${1:-"n"}

    [[ "Yy" =~ $answer ]]
    return
}

function getOSRelease() { # directory

	local os_release_file
	local os_release
	local dir="$1"

	# search for os-release(s). For -P backup it's not in the root directory but in mmcblk0p1, sda1 or other subdirectories
	os_release_file="$(find "$dir" -maxdepth 3 -name os-release | head -n 1)"

	#shellcheck disable=SC2181
	#Check exit code directly with e.g. 'if mycmd;', not indirectly with $?.
	if (( $? )) || [[ -z $os_release_file ]]; then
		os_release="$UNKNOWN"
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
	echo "${os_release:-$UNKNOWN}"          # handle empty result
}

MODE_RENAME=0
MODE_DETAILS=0

while getopts "dhrv?" opt; do

    case "$opt" in
		d) MODE_DETAILS=1
			;;
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

if (( UID != 0 && MODE_RENAME )); then
	echo "!!! Invoke script with sudo"
	exit 42
fi

# /backup/idefix/idefix-rsync-backup-20250119-105022_some_comment

if [[ ! -d $1 ]]; then 
	echo "??? Invalid dir $1"
	exit 42
fi	

hostName=$(basename "$1")
newDirs=0

if (( MODE_RENAME )); then
	read -r -p "--- Do you have you verified without option -r the renaming is OK ? (y/N) " answer
	if ! yesNo "$answer"; then
		exit 1
	fi
fi

for dir in "$1"/*; do

	if grep -q -E "@.+[dd|ddz|tar|tgz|rsync]-backup" <<< "$dir"; then
		set +e
		(( newDirs++ ))
		set -e
		continue
	fi

	if grep -q -P "[dd|ddz|tar|tgz]-backup" <<< "$dir"; then
		echo "!!! $(basename $dir): dd, ddz, tar and tgz backups are not supported"
		continue
	fi
	
	release="$(getOSRelease "$dir")"
	if [[ $release == "unknownOS" ]]; then
		echo "??? Unknown OS $dir skipped"
		continue
	fi
	dirName="$(dirname "$dir")"
	newDirHostPart="${hostName}@${release//[ \/\\\:\.\-_]/\~}"
	newTypeAndSnapshotPart=$(cut -d "-" -f 2- <<< $(basename $dir))	
	newDirName="${newDirHostPart}-${newTypeAndSnapshotPart}"
	
	if (( ! MODE_RENAME )); then
		echo "--- $(basename "$dir") => $newDirName"
	else
		echo "--- $(basename "$dir") => $newDirName"
		mv "$dir" "$dirName/$newDirName"
	fi
	
done

echo "$newDirs new directories detected and skipped"
