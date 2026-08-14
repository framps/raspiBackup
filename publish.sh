#!/bin/bash
#######################################################################################################################
#
#    Publish raspiBackup
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

usage() {
	cat <<"EOF_USAGE"
Usage:

	publish.sh [options]

Options:

    $1: branch to publish (default: Current branch)
    $2: subdirectory name is published into
    -h | --help    display this short help

EOF_USAGE
}

function error() {
   echo "??? $*" >/dev/tty
   exit 1
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH_DIR="$REPO_DIR/published"
CURRENT_BRANCH=$(git branch --show-current)
PUBLISH_BRANCH=$CURRENT_BRANCH
GITSRC=$(mktemp --tmpdir -d raspiBackup_git.XXXXXX)

FILES=(
    "raspiBackup.sh"
    "installation/raspiBackupInstallUI.sh"
    "installation/install.sh"
    "config/raspiBackup_de.conf"
    "config/raspiBackup_en.conf"
    "config/raspiBackup_sample_notify.conf"
    "properties/raspiBackup.properties"
)

if (( $# > 0 )); then
	case "$1" in
	    -h|--help) usage
		       exit
		       ;;
		*) PUBLISH_BRANCH="$1"
			;;
	esac
	if (( $# > 1 )); then
		case "$2" in
			*) PUBLISH_DIR="$PUBLISH_DIR/$2"			
				;;
		esac
	fi
	
fi

#trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT
#trap 'error $?' ERR

if [[ "$CURRENT_BRANCH" == "$PUBLISH_BRANCH" ]] ; then
    git worktree add --detach "$PUBLISH_BRANCH"
else
    git worktree add "$GITSRC" "$PUBLISH_BRANCH"
fi

if [[ ! -d $PUBLISH_DIR ]]; then
	echo "??? $PUBLISH_DIR does not exist"
	exit
fi	

d="$(sed -e "s@$REPO_DIR@\.@" <<< "$PUBLISH_DIR")"

echo "Publishing $PUBLISH_BRANCH into $d"
	
# Current repository HEAD
pushd "$GITSRC" > /dev/null
sha="$(git rev-parse --short HEAD)"
date="$(git log -1 --format='%ci' HEAD)"
	
for file in "${FILES[@]}"; do

	# remove path
	tgtFile=${file##*/}  

    destination="$PUBLISH_DIR/$tgtFile"

    sed \
        -e "s/\\\$Sha1\\\$/$sha/g" \
        -e "s/\\\$Date\\\$/$date/g" \
        "$file" > "$destination"

done

file=$PUBLISH_DIR/raspiBackupSampleExtensions.tgz
tar --owner=root --group =root -cvzf $file  extensions/* >/dev/null

git worktree remove "$GITSRC"
