#!/bin/bash
#######################################################################################################################
#
# 	Common definitions to build raspiBackup Debian package
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

BUILD_HOME="."
readonly BUILD_HOME
PACKAGE="$BUILD_HOME/package"
readonly PACKAGE
TGT="$PACKAGE/src"
# shellcheck disable=2034
readonly TGT
DEB_TGT="$BUILD_HOME/deb"
# shellcheck disable=2034
readonly DEB_TGT
# signed apt repository, publish the whole directory as it is
REPO="$BUILD_HOME/repo"
# shellcheck disable=2034
readonly REPO
# fixes of branches for one tester, published with the repository but in no suite (build.sh --fix)
FIXES_DIR="fixes"
# shellcheck disable=2034
readonly FIXES_DIR

function show() {
	local l=${#1}
	local s
	s=$(printf '=%.0s' $(seq 1 $(( l+8 )) ) )
	echo ""
	echo "$s"
	echo "=== $* ==="
	echo "$s"
}

function err() {
    local rc="$1"
    echo "??? Unexpected error occured with RC $rc"
    local i=0
    local FRAMES=${#BASH_LINENO[@]}
    for ((i = FRAMES - 2; i >= 0; i--)); do
        echo '  File' \""${BASH_SOURCE[i + 1]}"\", line ${BASH_LINENO[i]}, in "${FUNCNAME[i + 1]}"
        sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i + 1]}"
    done
    exit 42
}

# fix of a branch for one tester, built with build.sh --fix: 0.7.5-m1+m972.1, 0.7.5-0+m972.2
function is_fix_version() { # version
    [[ "$1" =~ \+m[0-9]+\.[0-9]+$ ]]
}

# build of a fix branch with its VERSION 0.7.5-m_972 -> 0.7.5-m-972, never published
function is_fix_branch_build() { # version
    [[ "$1" =~ -m-[0-9]+ ]]
}

# highest Debian version read from stdin
function highest_debian_version() {
    local v highest=""
    while read -r v; do
        [[ -z "$v" ]] && continue
        if [[ -z "$highest" ]] || dpkg --compare-versions "$v" gt "$highest"; then
            highest="$v"
        fi
    done
    echo "$highest"
}

# writes the file name of the newest fix of a fix directory into its file 'latest', raspiBackupConfig -F reads it
function update_fix_index() { # directory of a fix branch, e.g. repo/fixes/m_972
    local latest
    latest="$(find "$1" -maxdepth 1 -name '*.deb' -printf '%f\n' | sed -E 's/^[^_]*_([^_]*)_.*/\1/' | highest_debian_version)"
    if [[ -z "$latest" ]]; then
        rm -f "$1/latest"
        return
    fi
    find "$1" -maxdepth 1 -name "*_${latest}_*.deb" -printf '%f\n' | head -n 1 > "$1/latest"
    chmod 644 "$1/latest"
}
