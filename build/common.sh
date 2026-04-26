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

BUILD_HOME="$HOME/github.com/framps/raspiBackup/build"
readonly BUILD_HOME
PACKAGE="$BUILD_HOME/package"
readonly PACKAGE
TGT="$PACKAGE/src"
readonly TGT
DEB_TGT="$BUILD_HOME/deb"
readonly DEB_TGT
SRC="$BUILD_HOME/gitsrc"
readonly SRC
CURRENT_DIR=$PWD
readonly CURRENT_DIR

function show() {
	local l=${#1}
	local s
	s=$(printf '=%.0s' $(seq 1 $(( l+8 )) ) )
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

