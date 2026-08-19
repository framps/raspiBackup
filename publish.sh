#!/bin/bash
#######################################################################################################################
#
#    Publish raspiBackup
#
#	 Steps:
#	 1) Call publish.sh
#	 2) Add published to git
#	 3) Commit published directory
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

    publish.sh [branch] [subdirectory]

Arguments:

    branch          branch to publish 
					default: current branch
					'local' will use current local code
					
    subdirectory    subdirectory below published/

Options:

    -h, --help      display this help
EOF_USAGE
}

FILES=(
	"raspiBackup.sh"
	"installation/raspiBackupInstallUI.sh"
	"installation/install.sh"
	"config/raspiBackup_de.conf"
	"config/raspiBackup_en.conf"
	"config/raspiBackup_sample_notify.conf"
	"properties/raspiBackup.properties"
)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH_DIR="$REPO_DIR/published"

function cleanup() {

	if [[ "${WORKTREE_CREATED:-false}" == true ]]; then
		git worktree remove --force "$GITSRC" 2>/dev/null || true
	fi
}

function error() {

	local rc=$1

	echo "ERROR: command failed with exit code $rc" >&2

	local i
	for ((i = 1; i < ${#FUNCNAME[@]} - 1; i++)); do
		printf '  at %s:%s in %s()\n' \
			"${BASH_SOURCE[i]}" \
			"${BASH_LINENO[i - 1]}" \
			"${FUNCNAME[i]}"
	done
}

function main() {

	if (($# > 2)); then
		printf 'ERROR: Too many arguments\n\n' >&2
		usage >&2
		exit 2
	fi

	current_branch=$(git branch --show-current)

	if [[ -z "$current_branch" ]]; then
		echo "??? HEAD is detached; no current branch available" >&2
		exit 1
	fi

	publish_branch=$current_branch

	if (($# > 0)); then
		case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		*)
			publish_branch="$1"
			;;
		esac
		if (($# > 1)); then

			if [[ ! "$2" =~ ^[[:alnum:]_.-]+$ ]]; then
				printf 'ERROR: Invalid subdirectory: %s\n' "$2" >&2
				exit 2
			fi

			PUBLISH_DIR="$PUBLISH_DIR/$2"
		fi

	fi

	trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT
	trap 'error $?' ERR

	if [[ ! -d $PUBLISH_DIR ]]; then
		echo "??? $PUBLISH_DIR does not exist" >&2
		exit 1
	fi

	if [[ "$publish_branch" == "local" ]]; then
		GITSRC="$REPO_DIR"
	else
		GITSRC=$(mktemp --tmpdir -d raspiBackup_git.XXXXXX)
		git worktree add --detach "$GITSRC" "$publish_branch"
		WORKTREE_CREATED=true
	fi

	printf 'Publishing %s into %s\n' "$publish_branch" "${PUBLISH_DIR#"$REPO_DIR"/}"

	# retrieve sha and date for release
	release_sha="$(git -C "$GITSRC" rev-parse --short HEAD)"
	release_date="$(git -C "$GITSRC" log -1 --format='%ci' HEAD)"

	(
		cd "$GITSRC"
		for file in "${FILES[@]}"; do

			# remove path
			tgtFile="${file##*/}"

			destination="$PUBLISH_DIR/$tgtFile"

			if [[ -f $file ]]; then

				sed \
					-e "s/\\\$Sha1\\\$/$release_sha/g" \
					-e "s/\\\$Date\\\$/$release_date/g" \
					"$file" >"$destination"
			else
				echo "??? Missing $file" >&2
				exit 1
			fi

		done

		printf 'Publishing extensions into %s\n' "${PUBLISH_DIR#"$REPO_DIR"/}"

		extensions_tmp="$(mktemp --tmpdir -d raspiBackup_extensions.XXXXXX)"
		trap 'rm -rf "$extensions_tmp"' RETURN

		for file in extensions/*; do
			if [[ ! -f "$file" ]]; then
				continue
			fi

			tgtFile="${file##*/}"

			sed \
				-e "s/\\\$Sha1\\\$/$release_sha/g" \
				-e "s/\\\$Date\\\$/$release_date/g" \
				"$file" >"$extensions_tmp/$tgtFile"
		done

		file="$PUBLISH_DIR/raspiBackupSampleExtensions.tgz"
		tar --owner=root --group=root -czf "$file" -C "$extensions_tmp" .
	)

	printf '\nPublished files:\n'
	ls -lh "$PUBLISH_DIR"
}

main "$@"
