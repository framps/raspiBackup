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
    - delete the packages of the versions given with --remove from 'repo'
    - delete the fixes of the branches given with --remove-fix from 'repo'
    - recreate and sign the repository index (buildRepo.sh)
    - replace the contents of the Pages branch by 'repo' and push it. That includes the fixes
      of branches for one tester in 'repo/fixes/<branch>' (build.sh --fix), which are in no suite
    - tag the commit of every published package which has no tag yet with a signed tag
      v<version>, e.g. v0.7.5, v0.7.5-1, v0.7.5-m1, v0.7.6-beta1 (a tag can't contain '~')
    - if GITHUB_RELEASES="1" in build.conf: create a GitHub release for every new tag of a
      release, hotfix or beta, with the fix branches of the package (field Fixes).
      Minor fixes (e.g. 0.7.5-1) aren't announced, they get the tag only.
      GitHub releases are public: they are shown to everybody on the releases page
      raspiBackup refers to. Asks before creating them. Requires the GitHub CLI gh.

GitHub Pages has to be enabled once for the Pages branch:
Repository settings -> Pages -> Deploy from a branch -> gh-pages, / (root)

Options:

    --dry-run            show what would be published, removed, tagged and released, then exit.
                         Nothing is signed, changed, committed, pushed or tagged.
    --list               list the versions published on the Pages branch with their suite
                         and the ones in 'repo' not yet published, then exit
    --no-push            create the commit but don't push it, no tags and no GitHub releases
    --remove <version>   unpublish this version, can be used multiple times
                         e.g. --remove 0.8.2-beta or --remove 0.8.2~beta
                         Systems which installed it keep it. Publish a higher version to replace it.
    --remove-fix <branch>
                         unpublish all fixes of a fix branch, e.g. --remove-fix m_972, after the
                         tester installed the release with the fix. Can be used multiple times.
    -h | --help          display this short help

EOF_USAGE
}

# shellcheck disable=1091
source ./common.sh
# shellcheck disable=1091
source ./build.conf

PAGES_REMOTE="${PAGES_REMOTE:-origin}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"

PUSH=1
LIST=0
DRY_RUN=0
REMOVE=()
REMOVE_FIXES=()
while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage
                   exit
                   ;;
        --dry-run) DRY_RUN=1
                   shift
                   ;;
        --list) LIST=1
                shift
                ;;
        --no-push) PUSH=0
                   shift
                   ;;
        --remove) if (( $# < 2 )) || [[ -z "$2" ]] ; then
                      echo "Error: Missing version for --remove!"
                      exit 1
                  fi
                  # same conversion as build.sh: 0.7.5-beta1 -> 0.7.5~beta1, 0.7.4-m_972 -> 0.7.4-m-972
                  REMOVE+=("$(sed -E 's/-(alpha|beta|rc)/~\L\1/I; s/_/-/g' <<< "$2")")
                  shift 2
                  ;;
        --remove-fix) if (( $# < 2 )) || [[ ! "$2" =~ ^m_[0-9]+$ ]] ; then
                          echo "Error: --remove-fix requires a fix branch like m_972!"
                          exit 1
                      fi
                      REMOVE_FIXES+=("$2")
                      shift 2
                      ;;
        *) echo "Error: Unknown option '$1'!"
           exit 1
           ;;
    esac
done

trap 'err $?' ERR

# sort Debian versions read from stdin in the order of apt, sort -V doesn't (it sorts 0.7.5 after 0.7.5-m1)
sort_debian_versions() {
    local v i sorted=()
    while read -r v; do
        [[ -z "$v" ]] && continue
        i=${#sorted[@]}
        while (( i > 0 )) && dpkg --compare-versions "${sorted[i-1]}" gt "$v"; do
            sorted[i]="${sorted[i-1]}"
            i=$(( i - 1 ))
        done
        sorted[i]="$v"
    done
    if (( ${#sorted[@]} > 0 )) ; then
        printf '%s\n' "${sorted[@]}"
    fi
}

# list fixes of branches read from stdin as "<branch>/<deb file name>", one per line, as "<version> <branch> [<note>]"
list_fixes() {
    local note="${1:-}" path
    sort -V | while read -r path; do
        [[ -z "$path" ]] && continue
        printf '%-24s %-8s %s\n' "$(sed -E 's/^[^_]*_([^_]*)_.*/\1/' <<< "${path##*/}")" "${path%%/*}" "$note"
    done
}

# fixes in 'repo' as "<branch>/<deb file name>"
local_fixes() {
    if [[ -d "$REPO/$FIXES_DIR" ]] ; then
        (cd "$REPO/$FIXES_DIR" && find . -mindepth 2 -maxdepth 2 -name '*.deb' | sed 's|^\./||')
    fi
}

# fixes published on the fetched Pages branch (FETCH_HEAD) as "<branch>/<deb file name>"
published_fixes() {
    { git ls-tree -r --name-only --full-tree FETCH_HEAD "$FIXES_DIR" 2>/dev/null || true; } | sed -n "s|^$FIXES_DIR/||; /\.deb\$/p"
}

# list deb file names (one per line, without path) as "<version> <suite> [<note>]"
list_versions() {
    local note="${1:-}"
    sed -E 's/^[^_]*_([^_]*)_.*/\1/' | sort -u | sort_debian_versions | while read -r version; do
        if [[ "$version" == *~* ]] ; then
            printf '%-24s %-8s %s\n' "$version" "${REPO_BETA_SUITE:-beta}" "$note"
        else
            printf '%-24s %-8s %s\n' "$version" "${REPO_SUITE:-stable}" "$note"
        fi
    done
}

# git tag of a package version, a tag can't contain '~': 0.7.5~beta1 -> v0.7.5-beta1
tag_name() { # version
    echo "v${1//\~/-}"
}

# GitHub repository "owner/name" of the remote, e.g. framps/raspiBackup
github_repository() {
    git remote get-url "$PAGES_REMOTE" | sed -E 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#; s#\.git$##'
}

# release notes of a package: kind of version and fix branches linked to their issues
release_notes() { # deb version
    local fixes branch
    fixes="$(dpkg-deb -f "$1" Fixes)"
    if [[ "$2" == *~* ]] ; then
        echo "Beta version $2 of raspiBackup."
    elif [[ "$2" =~ -m[0-9]+$ ]] ; then
        echo "Hotfix $2 of raspiBackup."
    else
        echo "Release $2 of raspiBackup."
    fi
    if [[ -n "$fixes" ]] ; then
        echo ""
        echo "Fixes:"
        echo ""
        for branch in $fixes; do
            echo "- #${branch#m_} (branch $branch)"
        done
    fi
}

# packages which get a tag, read as deb files from stdin: prints "<deb> <tag> <release>" per package,
# release is 1 if it also gets a GitHub release. $1 is a file with the existing tags, one per line.
tag_plan() { # existingTagsFile
    local deb version commit tag
    while read -r deb; do
        version="$(dpkg-deb -f "$deb" Version)"
        commit="$(dpkg-deb -f "$deb" Git-Commit)"
        tag="$(tag_name "$version")"
        if [[ -z "$commit" ]] ; then	# built before build.sh recorded the commit
            continue
        fi
        # a build of a fix branch (VERSION="0.7.5-m_972" -> 0.7.5-m-972) is for one tester, never announced
        if [[ "$version" =~ -m-[0-9]+ ]] ; then
            echo "Warning: $version is a build of a fix branch, not tagged and no GitHub release." >&2
            continue
        fi
        if grep -qxF -- "$tag" "$1" ; then
            continue
        fi
        if ! git cat-file -e "$commit^{commit}" 2>/dev/null ; then
            echo "Warning: Commit $commit of $version not found, $tag not created. Fetch it and run publishRepo.sh again." >&2
            continue
        fi
        # minor fixes like 0.7.5-1 aren't announced
        if [[ "$version" =~ -[0-9]+$ ]] ; then
            echo "$deb $tag 0"
        else
            echo "$deb $tag 1"
        fi
    done
}

public_releases_warning() {
    echo "!!! WARNING: GitHub releases are public. They are shown to everybody on"
    echo "!!!          https://github.com/$(github_repository)/releases"
    echo "!!!          which raspiBackup refers to in its update messages."
    echo "!!!          Create them only if the apt repository is in production."
}

show_release_notes() { # deb ...
    local deb version
    for deb in "$@"; do
        version="$(dpkg-deb -f "$deb" Version)"
        echo "--- $(tag_name "$version")"
        release_notes "$deb" "$version" | sed 's/^/    /'
    done
}

# tag the commits of published packages without tag, create GitHub releases if GITHUB_RELEASES="1"
tag_and_release() {
    local deb version tag release existing tags=() releases=() answer repository

    git fetch -q --tags "$PAGES_REMOTE" || true
    existing="$(mktemp)"
    git tag -l > "$existing"

    while read -r deb tag release; do
        version="$(dpkg-deb -f "$deb" Version)"
        git tag -s -u "$GPG_KEYID" -m "raspiBackup $version" "$tag" "$(dpkg-deb -f "$deb" Git-Commit)"
        git push "$PAGES_REMOTE" "refs/tags/$tag"
        tags+=("$tag")
        if (( release )) ; then
            releases+=("$deb")
        fi
    done < <(find "$REPO/pool" -name '*.deb' | sort -V | tag_plan "$existing")
    rm -f "$existing"

    if (( ${#tags[@]} == 0 )) ; then
        echo "No new versions to tag"
        return
    fi
    echo "Created tags: ${tags[*]}"

    if (( ${#releases[@]} == 0 )) ; then
        return
    fi

    repository="$(github_repository)"
    if [[ "${GITHUB_RELEASES:-}" != "1" ]] ; then
        echo ""
        echo "No GitHub releases created, GITHUB_RELEASES isn't \"1\" in build.conf."
        echo "Create them when the apt repository is in production, see build/README.md."
        return
    fi

    echo ""
    public_releases_warning
    echo ""
    show_release_notes "${releases[@]}"
    echo ""
    read -r -p "Create these public GitHub releases? [y/N] " answer || answer=""
    if [[ ! "$answer" =~ ^[yYjJ] ]] ; then
        echo "No GitHub releases created. The tags exist, create the releases later with"
        echo "    gh release create <tag> --verify-tag --title \"raspiBackup <version>\" --notes \"...\""
        return
    fi

    if ! command -v gh > /dev/null ; then
        echo "Error: GitHub CLI 'gh' isn't installed, no GitHub releases created."
        echo "       Install it (sudo apt-get install gh), log in with 'gh auth login' and create them with"
        echo "       gh release create <tag> --verify-tag --title \"raspiBackup <version>\" --notes \"...\""
        exit 1
    fi

    for deb in "${releases[@]}"; do
        version="$(dpkg-deb -f "$deb" Version)"
        tag="$(tag_name "$version")"
        local prerelease=()
        [[ "$version" == *~* ]] && prerelease=(--prerelease)
        gh release create "$tag" --repo "$repository" --verify-tag "${prerelease[@]}" \
            --title "raspiBackup $version" --notes "$(release_notes "$deb" "$version")"
    done
}

# show what a run would publish, remove, tag and release without signing, changing or pushing anything
dry_run() {
    local name path version deb tag release existing note suite
    local published_names=() removed_versions=() plan=() releases=()

    DRY_RUN_DIR="$(mktemp --tmpdir -d raspiBackup_dryrun.XXXXXX)"
    trap 'rm -rf "$DRY_RUN_DIR"' EXIT

    show "Dry run: nothing is signed, changed, committed, pushed or tagged"

    # the packages a run would publish: the published ones, the ones in 'repo' and minus the removed ones
    if git fetch -q "$PAGES_REMOTE" "$PAGES_BRANCH" 2>/dev/null ; then
        while read -r path; do
            name="${path##*/}"
            git show "FETCH_HEAD:$path" > "$DRY_RUN_DIR/$name"
            published_names+=("$name")
        done < <({ git ls-tree -r --name-only --full-tree FETCH_HEAD pool 2>/dev/null || true; } | grep '\.deb$' || true)
        echo "Published on $PAGES_REMOTE/$PAGES_BRANCH: ${#published_names[@]} packages"
    else
        echo "$PAGES_BRANCH doesn't exist yet and would be created"
    fi
    if [[ -d "$REPO/pool" ]] ; then
        find "$REPO/pool" -name '*.deb' -exec cp -f -t "$DRY_RUN_DIR" {} +
    fi

    for version in "${REMOVE[@]}"; do
        mapfile -t debs < <(find "$DRY_RUN_DIR" -name "${PACKAGE_NAME}_${version}_*.deb")
        if (( ${#debs[@]} == 0 )) ; then
            echo "Error: Version $version isn't in the repository. Available versions:"
            find "$DRY_RUN_DIR" -name '*.deb' -printf '%f\n' | list_versions
            exit 1
        fi
        rm -f "${debs[@]}"
        removed_versions+=("$version")
    done

    echo ""
    echo "Would publish:"
    echo ""
    while read -r version; do
        name="$(find "$DRY_RUN_DIR" -name "${PACKAGE_NAME}_${version}_*.deb" -printf '%f\n' | head -n 1)"
        suite="${REPO_SUITE:-stable}"
        [[ "$version" == *~* ]] && suite="${REPO_BETA_SUITE:-beta}"
        note=""
        grep -qxF -- "$name" <<< "$(printf '%s\n' "${published_names[@]}")" || note="(new)"
        is_deprecated "$version" "${DEPRECATED:-}" && note="${note:+$note }deprecated"
        printf '%-24s %-8s %s\n' "$version" "$suite" "$note"
    done < <(find "$DRY_RUN_DIR" -name '*.deb' -printf '%f\n' | sed -E 's/^[^_]*_([^_]*)_.*/\1/' | sort -u | sort_debian_versions)
    if (( ${#removed_versions[@]} > 0 )) ; then
        echo ""
        echo "Would remove: ${removed_versions[*]}"
    fi

    # fixes of branches for one tester: the published ones and the ones in 'repo' minus the removed branches
    local fixes_published path branch
    fixes_published="$(published_fixes)"
    for branch in "${REMOVE_FIXES[@]}"; do
        if ! grep -q "^$branch/" <<< "$fixes_published"$'\n'"$(local_fixes)" ; then
            echo "Error: There are no fixes of branch $branch"
            exit 1
        fi
    done
    { echo "$fixes_published"; local_fixes; } | grep -v '^$' | sort -u | sort -V | while read -r path; do
        grep -qxF -- "${path%%/*}" <<< "$(printf '%s\n' "${REMOVE_FIXES[@]}")" && continue
        if grep -qxF -- "$path" <<< "$fixes_published" ; then
            list_fixes <<< "$path"
        else
            list_fixes "(new)" <<< "$path"
        fi
    done > "$DRY_RUN_DIR/fixes"
    if [[ -s "$DRY_RUN_DIR/fixes" ]] ; then
        echo ""
        echo "Would publish fixes for testers (in no suite, installed with raspiBackupConfig -F <branch>):"
        echo ""
        cat "$DRY_RUN_DIR/fixes"
    fi
    if (( ${#REMOVE_FIXES[@]} > 0 )) ; then
        echo ""
        echo "Would remove the fixes of: ${REMOVE_FIXES[*]}"
    fi

    # tags: the local ones and the ones on GitHub
    existing="$DRY_RUN_DIR/tags"
    { git tag -l; git ls-remote --tags "$PAGES_REMOTE" 2>/dev/null | sed -E 's#.*refs/tags/##; s#\^\{\}$##'; } | sort -u > "$existing"
    mapfile -t plan < <(find "$DRY_RUN_DIR" -name '*.deb' | sort -V | tag_plan "$existing")

    echo ""
    if (( ${#plan[@]} == 0 )) ; then
        echo "No new versions to tag"
    else
        echo "Would create and push signed tags:"
        echo ""
        for line in "${plan[@]}"; do
            read -r deb tag release <<< "$line"
            echo "$tag on commit $(dpkg-deb -f "$deb" Git-Commit | cut -c1-12)"
            if (( release )) ; then
                releases+=("$deb")
            fi
        done
    fi

    if (( ${#releases[@]} > 0 )) ; then
        echo ""
        if [[ "${GITHUB_RELEASES:-}" == "1" ]] ; then
            echo "Would ask before creating these GitHub releases (GITHUB_RELEASES=\"1\"):"
            echo ""
            public_releases_warning
        else
            echo "No GitHub releases, GITHUB_RELEASES isn't \"1\" in build.conf. With \"1\" these would be created:"
        fi
        echo ""
        show_release_notes "${releases[@]}"
    fi

    echo ""
    echo "A real run asks for the passphrase of key $GPG_KEYID to sign the repository and the tags."
}

if (( DRY_RUN )) ; then
    dry_run
    exit 0
fi

if (( LIST )) ; then
    published=""
    if git fetch -q "$PAGES_REMOTE" "$PAGES_BRANCH" 2>/dev/null ; then
        published="$({ git ls-tree -r --name-only --full-tree FETCH_HEAD pool 2>/dev/null || true; } | sed -n 's|.*/||; /\.deb$/p')"
        echo "Published on $PAGES_REMOTE/$PAGES_BRANCH ($(git log -1 --format=%cd FETCH_HEAD)):"
        echo ""
        if [[ -n "$published" ]] ; then
            list_versions <<< "$published"
        else
            echo "none"
        fi
    else
        echo "$PAGES_BRANCH doesn't exist yet, nothing published"
    fi
    if [[ -d "$REPO/pool" ]] ; then
        local_only="$(comm -13 <(sort <<< "$published") <(find "$REPO/pool" -name '*.deb' -printf '%f\n' | sort))"
        if [[ -n "$local_only" ]] ; then
            echo ""
            echo "In $REPO but not yet published:"
            echo ""
            list_versions "(local)" <<< "$local_only"
        fi
    fi
    fixes_published="$(published_fixes)"
    fixes_local_only="$(comm -13 <(sort <<< "$fixes_published") <(local_fixes | sort) | grep -v '^$' || true)"
    if [[ -n "$fixes_published$fixes_local_only" ]] ; then
        echo ""
        echo "Fixes for testers (in no suite, installed with raspiBackupConfig -F <branch>):"
        echo ""
        if [[ -n "$fixes_published" ]] ; then
            list_fixes <<< "$fixes_published"
        fi
        if [[ -n "$fixes_local_only" ]] ; then
            list_fixes "(local)" <<< "$fixes_local_only"
        fi
    fi
    exit 0
fi

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
    # keep local files, -n is deprecated since coreutils 9.3 which added --update=none
    cp_keep=(-n)
    if cp --update=none --help > /dev/null 2>&1 ; then
        cp_keep=(--update=none)
    fi
    for dir in pool dists "$FIXES_DIR" ; do
        if [[ -d "$PAGES/$dir" ]] ; then
            cp -a "${cp_keep[@]}" "$PAGES/$dir" "$REPO/"
        fi
    done
else
    echo "$PAGES_BRANCH doesn't exist yet and will be created"
    git worktree add --detach "$PAGES"
fi

removed=""
if (( ${#REMOVE[@]} > 0 )) ; then
    show "Remove versions ${REMOVE[*]}"
    for version in "${REMOVE[@]}"; do
        mapfile -t debs < <(find "$REPO/pool" -name "${PACKAGE_NAME}_${version}_*.deb")
        if (( ${#debs[@]} == 0 )) ; then
            echo "Error: Version $version isn't in the repository. Available versions:"
            find "$REPO/pool" -name '*.deb' -printf '%f\n' | list_versions
            exit 1
        fi
        rm -v "${debs[@]}"
    done
    removed="${REMOVE[*]}"
fi

for branch in "${REMOVE_FIXES[@]}"; do
    show "Remove fixes of $branch"
    if [[ ! -d "$REPO/$FIXES_DIR/$branch" ]] ; then
        echo "Error: There are no fixes of branch $branch. Branches with fixes:"
        local_fixes | list_fixes
        exit 1
    fi
    rm -rv "${REPO:?}/$FIXES_DIR/$branch"
    removed="${removed:+$removed }fixes of $branch"
done

# removing the last version leaves an empty pool, which buildRepo.sh refuses otherwise
./buildRepo.sh ${removed:+--allow-empty}

show "Create commit for $PAGES_BRANCH"

git -C "$PAGES" rm -r -q --ignore-unmatch .
git -C "$PAGES" clean -fdxq
cp -a "$REPO/." "$PAGES/"
install -m755 ../raspiBackupInstall.sh "$PAGES/"
# serve all files as they are
touch "$PAGES/.nojekyll"

git -C "$PAGES" add -A -f
versions="$(cd "$REPO" && find pool -name '*.deb' -printf '%f\n' | sed -E 's/^[^_]*_([^_]*)_.*/\1/' | sort_debian_versions | tr '\n' ' ')"
fixes="$(local_fixes | list_fixes | awk '{ print $1 }' | tr '\n' ' ')"
tree="$(git -C "$PAGES" write-tree)"
# signed, so users can verify the published raspiBackupInstall.sh (commit-tree ignores commit.gpgsign)
commit="$(git -C "$PAGES" commit-tree -S"$GPG_KEYID" "$tree" ${parent:+-p "$parent"} -m "Publish raspiBackup apt repository" -m "Versions: $versions" ${fixes:+-m "Fixes for testers: $fixes"} ${removed:+-m "Removed: $removed"})"
git log --stat -1 "$commit" | tail -n 25

if (( PUSH )) ; then
    show "Push to $PAGES_REMOTE/$PAGES_BRANCH"
    git push "$PAGES_REMOTE" "$commit:refs/heads/$PAGES_BRANCH"

    show "Tag published versions"
    tag_and_release
else
    echo ""
    echo "Not pushed. To push use: git push $PAGES_REMOTE $commit:refs/heads/$PAGES_BRANCH"
    echo "Then run publishRepo.sh again to tag the published versions."
fi
