#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Publish the signed raspiBackup apt repository on GitHub Pages
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

        publishRepo.sh [options]

Publishes the apt repository in 'repo' together with raspiBackupInstall.sh
on the GitHub Pages branch, i.e. https://<owner>.github.io/raspiBackup

Steps:

    - fetch the Pages branch from GitHub (created on first use)
    - copy packages already published there but missing in 'repo' back into 'repo',
      so no published version gets lost when building on another system
    - recreate and sign the repository index (buildRepo.sh)
    - replace the contents of the Pages branch by 'repo' and push it

GitHub Pages has to be enabled once for the Pages branch:
Repository settings -> Pages -> Deploy from a branch -> gh-pages, / (root)

Options:

    --no-push      create the commit but don't push it
    -h | --help    display this short help

EOF_USAGE
}

# shellcheck disable=1091
source ./common.sh
# shellcheck disable=1091
source ./build.conf

PAGES_REMOTE="${PAGES_REMOTE:-origin}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"

PUSH=1
while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage
                   exit
                   ;;
        --no-push) PUSH=0
                   shift
                   ;;
        *) echo "Error: Unknown option '$1'!"
           exit 1
           ;;
    esac
done

trap 'err $?' ERR

PAGES=$(mktemp --tmpdir -d raspiBackup_pages.XXXXXX)
readonly PAGES
trap 'git worktree remove --force "$PAGES" 2>/dev/null || true; rm -rf "$PAGES"' EXIT

show "Fetch $PAGES_REMOTE/$PAGES_BRANCH"

parent=""
if git fetch "$PAGES_REMOTE" "$PAGES_BRANCH" 2>/dev/null ; then
    parent="$(git rev-parse FETCH_HEAD)"
    git worktree add --detach "$PAGES" "$parent"
    # get back published packages and by-hash files missing locally
    mkdir -p "$REPO"
    for dir in pool dists ; do
        if [[ -d "$PAGES/$dir" ]] ; then
            cp -a -n "$PAGES/$dir" "$REPO/"
        fi
    done
else
    echo "$PAGES_BRANCH doesn't exist yet and will be created"
    git worktree add --detach "$PAGES"
fi

./buildRepo.sh

show "Create commit for $PAGES_BRANCH"

git -C "$PAGES" rm -r -q --ignore-unmatch .
git -C "$PAGES" clean -fdxq
cp -a "$REPO/." "$PAGES/"
install -m755 raspiBackupInstall.sh "$PAGES/"
# serve all files as they are
touch "$PAGES/.nojekyll"

git -C "$PAGES" add -A -f
versions="$(cd "$REPO" && find pool -name '*.deb' -printf '%f\n' | sed -E 's/^[^_]*_([^_]*)_.*/\1/' | sort -V | tr '\n' ' ')"
tree="$(git -C "$PAGES" write-tree)"
commit="$(git -C "$PAGES" commit-tree "$tree" ${parent:+-p "$parent"} -m "Publish raspiBackup apt repository" -m "Versions: $versions")"
git log --stat -1 "$commit" | tail -n 25

if (( PUSH )) ; then
    show "Push to $PAGES_REMOTE/$PAGES_BRANCH"
    git push "$PAGES_REMOTE" "$commit:refs/heads/$PAGES_BRANCH"
else
    echo ""
    echo "Not pushed. To push use: git push $PAGES_REMOTE $commit:refs/heads/$PAGES_BRANCH"
fi
