#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Test repository on the build machine: build test versions and serve them to a test system
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

MYSELF="$(basename "$0")"
readonly MYSELF
# the git checkout this script belongs to, its build/build.conf is the template of the test build.conf
GIT_TOP="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
readonly GIT_TOP
TEST_DIR="${TEST_REPO_DIR:-$HOME/raspiBackup-testRepo}"
DEFAULT_PORT=8000

usage() {
    cat <<EOF_USAGE
Usage:

    $MYSELF [-d <dir>] init [<branch>]
    $MYSELF [-d <dir>] build [<version>] [<build.sh options>]
    $MYSELF [-d <dir>] deprecate "<versions>"
    $MYSELF [-d <dir>] list
    $MYSELF [-d <dir>] serve [<port>] [<host>]
    $MYSELF [-d <dir>] remove

Builds test versions of raspiBackup into a separate signed apt repository and serves it to a
test system. The real repository build/repo isn't touched, nothing is published.

    init       creates the test build directory <dir> (a git worktree) with a build.conf copied
               from build/build.conf. <branch> is the branch to build, default the current branch.
    build      builds <version> of the latest commit of the branch, signs it and adds it to the
               test repository, e.g. 0.9.1 or 0.9.2-beta1. Without <version> the VERSION of
               raspiBackup.sh is used, e.g. for a fix: $MYSELF build --fix 1
    deprecate  marks the versions as deprecated in the test repository ("" removes the marks)
    list       lists the versions and fixes in the test repository
    serve      serves the test repository on http://<host>:<port> (default $(hostname):$DEFAULT_PORT)
               until Ctrl-C and prints the command for the test system
    remove     removes the test build directory with its test repository

    -d <dir>   test build directory, default \$TEST_REPO_DIR or $HOME/raspiBackup-testRepo
    -h         display this help

On the test system the repository is used with useTestRepo.sh, which 'serve' offers for download.
EOF_USAGE
}

error() {
    echo "Error: $*" >&2
    exit 1
}

set_conf() { # name value - sets a variable in the test build.conf
    local conf="$TEST_DIR/build/build.conf"
    if grep -q "^$1=" "$conf"; then
        sed -i "s|^$1=.*|$1=\"$2\"|" "$conf"
    else
        echo "$1=\"$2\"" >> "$conf"
    fi
}

get_conf() { # name - value of a variable in the test build.conf
    # shellcheck disable=1090,1091
    (source "$TEST_DIR/build/build.conf" && eval "echo \"\${$1:-}\"")
}

check_initialized() {
    [[ -f "$TEST_DIR/build/build.conf" ]] || error "$TEST_DIR isn't initialized, call '$MYSELF init' first"
}

update_worktree() { # use the build scripts of the latest commit of the branch too
    local branch
    branch="$(get_conf BRANCH_TO_DEB)"
    [[ -n "$branch" ]] || error "BRANCH_TO_DEB isn't set in $TEST_DIR/build/build.conf"
    git -C "$TEST_DIR" checkout -q --detach "$branch"
}

cmd_init() { # [branch]
    local branch="${1:-$(git -C "$GIT_TOP" branch --show-current)}"
    [[ -n "$branch" ]] || error "No branch checked out in $GIT_TOP, pass the branch to build"
    git -C "$GIT_TOP" rev-parse -q --verify "$branch^{commit}" > /dev/null || error "Unknown branch $branch"
    [[ -f "$GIT_TOP/build/build.conf" ]] || error "$GIT_TOP/build/build.conf with GPG_KEYID is missing"
    [[ ! -e "$TEST_DIR" ]] || error "$TEST_DIR exists already. Remove it with '$MYSELF remove' or use -d"

    # detached: a branch can't be checked out in two worktrees
    git -C "$GIT_TOP" worktree add -q --detach "$TEST_DIR" "$branch"
    cp "$GIT_TOP/build/build.conf" "$TEST_DIR/build/build.conf"
    set_conf BRANCH_TO_DEB "$branch"
    set_conf VERSION_RASPIBACKUP ""
    set_conf DEPRECATED ""

    echo "Test build directory $TEST_DIR created, it builds branch $branch."
    echo "Next: $MYSELF build <version>, then $MYSELF serve"
}

cmd_build() { # [version] [build.sh options]
    check_initialized
    local version=""
    if (( $# > 0 )) && [[ "$1" != -* ]]; then
        version="$1"
        shift
    fi
    update_worktree
    set_conf VERSION_RASPIBACKUP "$version"
    (cd "$TEST_DIR/build" && ./build.sh "$@")
}

cmd_deprecate() { # versions
    check_initialized
    (( $# == 1 )) || error "Pass the versions as one argument, e.g. \"0.9.1 0.9.2\", \"\" removes the marks"
    update_worktree
    set_conf DEPRECATED "$1"
    (cd "$TEST_DIR/build" && ./buildRepo.sh)
}

cmd_list() {
    check_initialized
    local repo="$TEST_DIR/build/repo"
    echo "Versions in the test repository $repo:"
    find "$repo/pool" -name '*.deb' -printf '    %f\n' 2>/dev/null | sort -V || true
    if [[ -d "$repo/fixes" ]]; then
        echo "Fixes:"
        find "$repo/fixes" -name '*.deb' -printf '    %P\n' | sort -V
    fi
    local deprecated
    deprecated="$(get_conf DEPRECATED)"
    echo "Deprecated: ${deprecated:-none}"
}

cmd_serve() { # [port] [host]
    check_initialized
    local port="${1:-$DEFAULT_PORT}" host="${2:-$(hostname)}"
    local repo="$TEST_DIR/build/repo" url
    url="http://$host:$port"
    compgen -G "$repo/dists/*/InRelease" > /dev/null || error "The test repository is empty, call '$MYSELF build <version>' first"

    # offered for download to the test system, with the URL of this repository
    sed "s|@TEST_REPO_URL@|$url|" "$GIT_TOP/build/test/useTestRepo.sh" > "$repo/useTestRepo.sh"
    cp "$GIT_TOP/raspiBackupInstall.sh" "$repo/raspiBackupInstall.sh"

    cat <<EOF_SERVE

Serving the test repository $repo on $url until Ctrl-C

On the test system:

    curl -fsSL $url/useTestRepo.sh | sudo bash -s -- on        # use the test repository
    curl -fsSL $url/useTestRepo.sh | sudo bash -s -- refresh   # after a new build here
    curl -fsSL $url/useTestRepo.sh | sudo bash -s -- off       # back to the real repository

If '$host' can't be resolved on the test system, call '$MYSELF serve $port <ip address>'.

EOF_SERVE
    exec python3 -m http.server "$port" --directory "$repo"
}

cmd_remove() {
    [[ -e "$TEST_DIR" ]] || error "$TEST_DIR doesn't exist"
    git -C "$GIT_TOP" worktree remove --force "$TEST_DIR"
    echo "$TEST_DIR removed"
}

while getopts ":d:h" opt; do
    case "$opt" in
        d) TEST_DIR="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
TEST_DIR="$(realpath -m "$TEST_DIR")"
readonly TEST_DIR

(( $# > 0 )) || { usage; exit 1; }
command="$1"
shift

case "$command" in
    init)      cmd_init "$@" ;;
    build)     cmd_build "$@" ;;
    deprecate) cmd_deprecate "$@" ;;
    list)      cmd_list ;;
    serve)     cmd_serve "$@" ;;
    remove)    cmd_remove ;;
    *)         usage; exit 1 ;;
esac
