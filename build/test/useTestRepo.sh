#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Test system: switch between the test repository of the build machine and the real repository
#
#    Downloaded from the build machine, 'testRepo.sh serve' inserts the URL of the test repository:
#        curl -fsSL http://<build machine>:8000/useTestRepo.sh | sudo bash -s -- on|refresh|status|off
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

TEST_REPO_URL="${TEST_REPO_URL:-@TEST_REPO_URL@}"
readonly REAL_REPO_URL="https://framps.github.io/raspiBackup"
readonly PACKAGE=raspibackup
readonly SOURCES="/etc/apt/sources.list.d/${PACKAGE}.sources"
# raspiBackup updates the package index once a day after a backup, without it the next backup updates it
readonly INDEX_STAMP="/var/lib/raspiBackup/package.index"

usage() {
    cat <<EOF_USAGE
Usage: useTestRepo.sh on|refresh|status|off

    on       use the test repository $TEST_REPO_URL instead of the real one.
             Without the repository raspiBackupInstall.sh adds it and installs raspiBackup from it.
    refresh  update the package index after a new build on the build machine
    status   show the repository used and the versions
    off      use the real repository $REAL_REPO_URL again. A test version which is newer than
             the latest published release is replaced by that release.

After on and refresh raspiBackupConfig offers the test versions and the next backup of raspiBackup
reports them.
EOF_USAGE
}

error() {
    echo "Error: $*" >&2
    exit 1
}

current_url() {
    awk '$1 == "URIs:" { print $2 }' "$SOURCES" 2>/dev/null || true
}

installed_version() {
    dpkg-query -W -f '${db:Status-Status} ${Version}' "$PACKAGE" 2>/dev/null | awk '$1 == "installed" { print $2 }' || true
}

refresh() { # update the package index of the raspiBackup repository only and let raspiBackup report news now
    apt-get update -o Dir::Etc::sourcelist="$SOURCES" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
    rm -f "$INDEX_STAMP"
}

set_url() {
    sed -i "s|^URIs:.*|URIs: $1|" "$SOURCES"
    echo "--- Repository: $1"
}

status() {
    echo "--- Repository: $(current_url)"
    echo "--- Installed:  $(installed_version)"
    apt-cache policy "$PACKAGE" | sed -n '/Version table/,$p'
}

cmd_on() {
    [[ "$TEST_REPO_URL" != @* ]] || error "Download this script from the build machine ('testRepo.sh serve') or set TEST_REPO_URL"
    if [[ ! -f "$SOURCES" ]]; then
        echo "--- No raspiBackup repository yet, installing raspiBackup from the test repository"
        curl -fsSL "$TEST_REPO_URL/raspiBackupInstall.sh" | REPO_URL="$TEST_REPO_URL" bash -s -- -y
        rm -f "$INDEX_STAMP"
    else
        set_url "$TEST_REPO_URL"
        refresh
    fi
    status
}

cmd_refresh() {
    [[ -f "$SOURCES" ]] || error "No raspiBackup repository, use 'on' first"
    refresh
    status
}

latest_release() { # latest version of the suite stable in the package index
    local version latest=""
    while read -r version; do
        if [[ -z "$latest" ]] || dpkg --compare-versions "$version" gt "$latest"; then
            latest="$version"
        fi
    done < <(apt-cache madison "$PACKAGE" | awk -F'|' '$3 ~ / stable\// { gsub(/ /, "", $2); print $2 }')
    echo "$latest"
}

cmd_off() {
    [[ -f "$SOURCES" ]] || error "No raspiBackup repository"
    set_url "$REAL_REPO_URL"
    refresh

    local installed release
    installed="$(installed_version)"
    release="$(latest_release)"
    if [[ -n "$installed" ]] && [[ -n "$release" ]] && dpkg --compare-versions "$installed" gt "$release"; then
        echo "--- Test version $installed is newer than release $release, replacing it"
        apt-get install -y --allow-downgrades --allow-change-held-packages "$PACKAGE=$release"
        apt-mark unhold "$PACKAGE" > /dev/null
    elif [[ -n "$installed" && -z "$release" ]]; then
        echo "--- No release published, test version $installed stays installed"
    fi
    status
}

case "${1:-}" in
    on|refresh|status|off) ;;
    -h|--help) usage; exit 0 ;;
    *)         usage; exit 1 ;;
esac

(( EUID == 0 )) || error "Call it with sudo"

case "$1" in
    on)      cmd_on ;;
    refresh) cmd_refresh ;;
    status)  status ;;
    off)     cmd_off ;;
esac
