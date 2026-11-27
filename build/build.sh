#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Build raspiBackup Debian package
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

        build.sh [options] [<version>]
        build.sh [options] --fix <try>

That simple call builds a Debian package from raspiBackup.
Then it runs `lintian` to check the package for compliance.
That is a reduced check to fit this package not being a "real" Debian package.
Finally the package is added to the signed apt repository in 'repo' (see buildRepo.sh).

--fix builds a fix of a fix branch for one tester, e.g. on branch m_972 with
VERSION="0.7.5-m_972" in raspiBackup.sh. Its version is the newest published release
plus +m<branch>.<try>, e.g. 0.7.5-m1+m972.1 or 0.7.5-0+m972.1. It's above that release
and below every later one, so the tester gets the release with the fix with
raspiBackupConfig -U. The fix isn't added to any suite of the repository but to
'repo/fixes/m_972', publishRepo.sh publishes it there. The tester installs it with
raspiBackupConfig -F m_972. Every try needs a new, higher number.

Options:

    --dry-run      show what would be built (versions, suite, fix branches) and possible problems,
                   then exit. Nothing is built, signed or added to the repository.
    --no-check     don't check anything with `lintian`
    --no-repo      don't add the package to the apt repository
    --fix <try>    build try <try> (1, 2, ...) of the fix of the current fix branch, see above
    -h | --help    display this short help

In file 'build.conf' you can configure some aspects of the build process.

EOF_USAGE
}


# shellcheck disable=1091
source ./common.sh

if [[ ! -f ./build.conf ]] ; then
    echo "Error: Configuration file 'build.conf' not found."
    echo "Creating one for you now. Please check/edit it and try again..."

    cat <<EOF_CONF > ./build.conf
# BRANCH_TO_DEB
# The branch used to build the Debian package from.
# If empty then the curent branch is used.
# Note: Always only the commited changes are taken into account!
# BRANCH_TO_DEB="master"
# BRANCH_TO_DEB="m_972"
BRANCH_TO_DEB=""

# VERSION_RASPIBACKUP, VERSION_RASPIBACKUPCONFIG
# Versions inserted into raspiBackup and raspiBackupConfig of the package (VERSION="...").
# VERSION_RASPIBACKUP is also the version of the Debian package.
# If empty then the version of the script in the git branch is used.
# -alpha, -beta, -rc, -hotfix or -dev suffixes possible, e.g. "0.7.5-beta1"
VERSION_RASPIBACKUP=""
VERSION_RASPIBACKUPCONFIG=""

# DEB_REVISION
# Debian revision appended to the package version, e.g. "1" -> 0.7.5-1.
# Use it for a minor fix (small code fix, packaging, maintainer scripts, ...) without changing
# VERSION of raspiBackup: increase it for every rebuild and empty it again for the next release.
# raspiBackup doesn't report a minor fix to users of the same version, apt upgrade installs it.
# Not used if a version is passed as argument to build.sh.
DEB_REVISION=""

# FIXES
# Fix branches contained in the package, e.g. "m_972 m_965". Written into the package (field Fixes,
# apt-cache show raspibackup) and into the GitHub release created by publishRepo.sh.
# If empty then the branches m_<issue> merged since the last tag are used.
FIXES=""

# GITHUB_RELEASES
# "1": publishRepo.sh creates a GitHub release for every published release, hotfix and beta.
# GitHub releases are public, so set it only if the apt repository is in production.
# Empty: publishRepo.sh only creates the git tags.
GITHUB_RELEASES=""

# DEPRECATED
# Published versions with a severe bug, separated by blanks or commas, e.g. "0.7.5 0.7.6~beta1".
# An entry includes all versions derived from it: "0.7.5" also 0.7.5-1, 0.7.5-m1, 0.7.5~beta1, but not 0.7.50.
# buildRepo.sh marks them in the signed package index (field Deprecated). raspiBackup warns their users
# at the start of every run and never reports them as update, raspiBackupConfig never offers them.
# Change it and run publishRepo.sh (it runs buildRepo.sh), no package has to be built.
DEPRECATED=""

# Note: Some of the following variables need to be exported
#       because they are used in/with envsubst.

# Debian wants to have all-lowercase package names
export PACKAGE_NAME="raspibackup"

# absolute pathes for the files in the package
# will be used relatively and absolutely
export DIR_BIN="/usr/local/bin"
export DIR_ETC="/usr/local/etc"
export DIR_LIB="/usr/local/lib"
export DIR_SHARE="/usr/local/share"

# LINTIAN_CHECK
#   - "full"    : all checks
#   - "reduced" : intentionally suppress some checks (default here)
#   - ""        : no checks at all
LINTIAN_CHECK=reduced

# LINTIAN_OPTIONS
#   - "--info" : display more details on failed checks
LINTIAN_OPTIONS="--verbose --info --color always --fail-on error"

# VERBOSITY
#   - normal
#   - debug
VERBOSITY=normal

# GPG_KEYID
# The full GPG key fingerprint used for signing the built package and the repository. Required!
GPG_KEYID=

# GPG_KEY_UID
# Only user IDs of the key matching this regular expression are published with the key, e.g. to hide
# other identities. Empty publishes all user IDs. The fingerprint doesn't change.
GPG_KEY_UID=

# REPO_SUITE, REPO_BETA_SUITE, REPO_COMPONENT, REPO_ARCHITECTURES
# Layout of the signed apt repository created by buildRepo.sh.
# Versions with '~' (e.g. 0.7.5~beta1) go into REPO_BETA_SUITE, all others into REPO_SUITE.
# raspiBackupInstall.sh has to use the same suites.
REPO_SUITE=stable
REPO_BETA_SUITE=beta
REPO_COMPONENT=main
REPO_ARCHITECTURES="armhf arm64 amd64 i386"
EOF_CONF

    exit 1
fi


source ./build.conf

[[ -v LINTIAN_CHECK ]] || LINTIAN_CHECK=reduced
[[ -v LINTIAN_OPTIONS ]] || LINTIAN_OPTIONS="--verbose --info --color always"

VERBOSITY="${VERBOSITY:-debug}"

if [[ -z "$GPG_KEYID" ]] ; then
    echo ""
    echo "Error: The package can't be signed due to missing GPG_KEYID!"
    echo "       Please set GPG_KEYID in 'build.conf' to the ID to be used"
    echo "       for signing the built package."
    echo ""
    exit 1
fi


## For the transition of older gpg.conf to build.conf:
#
# if [[ -f gpg.conf ]] ; then
#     # fill GPG_KEYID with existing local key
#     # shellcheck disable=1091
#     source ./gpg.conf
#     cat ./gpg.conf >> build.conf
#     mv gpg.conf gpg.conf.bak
#     echo "Note: Moved the GPG_KEYID from 'gpg.conf' into 'build.conf'!"
# fi


UPDATE_REPO=1
DRY_RUN=0
FIX_TRY=""
while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage
                   exit
                   ;;
        --dry-run) DRY_RUN=1
                   shift
                   ;;
        --no-check) LINTIAN_CHECK=""
                    shift
                    ;;
        --no-repo) UPDATE_REPO=0
                   shift
                   ;;
        --fix) if [[ ! "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
                   echo "Error: --fix requires the number of the try, e.g. --fix 1" >&2
                   exit 1
               fi
               FIX_TRY="$2"
               shift 2
               ;;
        *) break
           ;;
    esac
done

LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE

DEBUG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")")-debug.log
readonly DEBUG_FILE

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm -f "$LOG_FILE" || true
rm -f "$DEBUG_FILE" || true

trap 'err $?' ERR


GITSRC=$(mktemp --tmpdir -d raspiBackup_gitsrc4deb.XXXXXX)
# shellcheck disable=2034
readonly GITSRC
trap 'git worktree remove --force "$GITSRC" 2>/dev/null || true' EXIT

CURRENT_BRANCH=$(git branch --show-current)

BRANCH_TO_DEB="${BRANCH_TO_DEB:-${CURRENT_BRANCH}}"
if [[ -z "$BRANCH_TO_DEB" ]] ; then
    # e.g. in a worktree with detached HEAD for a test repository
    echo "Error: No branch checked out (detached HEAD). Set BRANCH_TO_DEB in 'build.conf' to the branch to build." >&2
    exit 1
fi
show "Using branch '$BRANCH_TO_DEB' as source for the build"

# detached because a branch can't be checked out in two worktrees
git worktree add --detach "$GITSRC" "$BRANCH_TO_DEB"

# extract version number from a script
extractVersion() { # file
    local version REGEX='.*="([^"]*)"'
    version="$(grep "^VERSION=" "$1" 2>/dev/null)"
    if [[ $version =~ $REGEX ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# versions from build.conf, if empty the versions of the scripts
VERSION_RASPIBACKUP="${VERSION_RASPIBACKUP:-$(extractVersion "$GITSRC/raspiBackup.sh")}"
VERSION_RASPIBACKUPCONFIG="${VERSION_RASPIBACKUPCONFIG:-$(extractVersion "$GITSRC/installation/raspiBackupConfig.sh")}"
show "raspiBackup version: $VERSION_RASPIBACKUP, raspiBackupConfig version: $VERSION_RASPIBACKUPCONFIG"

export VERSION="$VERSION_RASPIBACKUP"

# allow to pass another version number for upgrade/downgrade tests
if (( $# > 0 )); then
    if [[ -n "$FIX_TRY" ]]; then
        echo "Error: --fix computes the version, don't pass one" >&2
        exit 1
    fi
    VERSION="$1"
    DEB_REVISION=""
fi

# underscores are not allowed in Debian version numbers
# change m_972 to m-972
VERSION="$(sed -E 's/_/-/g' <<< "$VERSION")"
# pre-releases have to sort before the release and go into the beta suite
# change 0.7.5-beta1 to 0.7.5~beta1
VERSION="$(sed -E 's/-(alpha|beta|rc)/~\L\1/I' <<< "$VERSION")"
# package only fix: 0.7.5 -> 0.7.5-1, 0.7.5 < 0.7.5-1 < 0.7.5-2 < 0.7.5-m1 < 0.7.6
if [[ -n "${DEB_REVISION:-}" ]]; then
    if [[ ! "$DEB_REVISION" =~ ^[0-9]+$ ]]; then
        echo "DEB_REVISION has to be a number: '$DEB_REVISION'" >&2
        exit 1
    fi
    VERSION="$VERSION-$DEB_REVISION"
fi

# highest published release (no pre-release, no fix): in the local repository and on the Pages branch
highest_published_release() {
    {
        find "$REPO/pool" -name '*.deb' -printf '%f\n' 2>/dev/null || true
        if git -C "$GITSRC" fetch -q "${PAGES_REMOTE:-origin}" "${PAGES_BRANCH:-gh-pages}" 2>/dev/null; then
            git -C "$GITSRC" ls-tree -r --name-only --full-tree FETCH_HEAD pool 2>/dev/null | sed 's|.*/||' || true
        fi
    } | sed -n -E 's/^[^_]*_([^_]*)_.*\.deb$/\1/p' | while read -r v; do
        [[ "$v" == *"~"* ]] || is_fix_version "$v" || is_fix_branch_build "$v" || echo "$v"
    done | highest_debian_version
}

# fix of a fix branch for one tester: VERSION="0.7.5-m_972" -> newest release 0.7.5-m1 + "+m972.<try>"
fix_branch=""
fix_file=""
if [[ -n "$FIX_TRY" ]]; then
    if [[ ! "$VERSION_RASPIBACKUP" =~ ^(.+)-m_([0-9]+)$ ]]; then
        echo "Error: --fix requires VERSION of a fix branch like \"0.7.5-m_972\" in raspiBackup.sh (or VERSION_RASPIBACKUP), not \"$VERSION_RASPIBACKUP\"" >&2
        exit 1
    fi
    fix_release="${BASH_REMATCH[1]}"
    fix_branch="m_${BASH_REMATCH[2]}"
    fix_base="$(highest_published_release)"
    if [[ -z "$fix_base" ]]; then
        echo "Error: No published release found to base the fix on, neither in $REPO nor on the Pages branch" >&2
        exit 1
    fi
    # the fix sorts above its base and below every later version: 0.7.5 -> 0.7.5-0+m972.1, 0.7.5-m1 -> 0.7.5-m1+m972.1
    if [[ "$fix_base" == *-* ]]; then
        VERSION="$fix_base+m${fix_branch#m_}.$FIX_TRY"
    else
        VERSION="$fix_base-0+m${fix_branch#m_}.$FIX_TRY"
    fi
    DEB_REVISION=""
    UPDATE_REPO=0       # never in a suite, apt would offer it to everybody
    FIXES="${FIXES:-$fix_branch}"
    fix_file="$REPO/$FIXES_DIR/$fix_branch/${PACKAGE_NAME}_${VERSION}_all.deb"
    show "Fix $fix_branch try $FIX_TRY based on release $fix_base: $VERSION"
    if [[ "${fix_base%-*}" != "$fix_release" ]]; then
        echo "Warning: Branch $fix_branch has VERSION $VERSION_RASPIBACKUP, but the newest release is $fix_base."
        echo "         The fix replaces $fix_base for the tester. Merge or rebase the branch on $fix_base."
    fi
    if [[ -f "$fix_file" ]]; then
        echo "Error: Try $FIX_TRY of $fix_branch exists already ($fix_file). Use a higher try." >&2
        exit 1
    fi
fi

VERSION_FILES="_$(sed -E 's/_/./g' <<< "$VERSION")"

# last release tag, used for the changelog and the fix branches
last_tag=$(git -C "$GITSRC" describe --tags --abbrev=0 2>/dev/null || true)
# commit of the package, publishRepo.sh tags it
git_commit=$(git -C "$GITSRC" rev-parse HEAD)
# fix branches merged since the last tag, e.g. "Merge branch 'm_972'" or "Merge pull request #1 from framps/m_972"
if [[ -z "${FIXES:-}" && -n "$last_tag" ]]; then
    FIXES=$(git -C "$GITSRC" log --merges --pretty=format:"%s%n" "$last_tag..HEAD" \
        | sed -nE "s/^Merge (remote-tracking )?branch '([^']*\/)?(m_[0-9]+)'.*/\3/p; s/^Merge pull request #[0-9]+ from [^\/]+\/(m_[0-9]+)$/\1/p" \
        | sort -u -V | tr '\n' ' ')
fi
FIXES="$(xargs <<< "${FIXES:-}")"
show "Fix branches: ${FIXES:-none}"
suite="$REPO_SUITE"
[[ "$VERSION" == *"~"* ]] && suite="$REPO_BETA_SUITE"
[[ -n "$fix_branch" ]] && suite="$fix_branch"

if (( DRY_RUN )); then
    show "Dry run: nothing is built, signed or added to the repository"
    echo "Branch:              $BRANCH_TO_DEB, commit $git_commit"
    echo "Package:             ${PACKAGE_NAME} $VERSION -> $DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"
    echo "raspiBackup:         $VERSION_RASPIBACKUP"
    echo "raspiBackupConfig:   $VERSION_RASPIBACKUPCONFIG"
    echo "Fix branches:        ${FIXES:-none}"
    echo "Last tag:            ${last_tag:-none}"
    if [[ -n "$fix_branch" ]]; then
        echo "Repository:          in no suite, $fix_file, published by publishRepo.sh"
        echo "                     The tester installs it with: sudo raspiBackupConfig -F $fix_branch"
    elif (( UPDATE_REPO )); then
        echo "Repository:          added to $REPO, suite $suite, published by publishRepo.sh"
    else
        echo "Repository:          not added (--no-repo)"
    fi

    # problems a real run wouldn't notice
    problems=0
    if (( UPDATE_REPO )) && [[ "$VERSION" =~ -m-[0-9]+ ]]; then
        echo "Warning: $VERSION is a build of a fix branch. It's for one tester only, but would go into"
        echo "         suite $suite and be installed and announced to everybody. Use --no-repo."
        problems=1
    fi
    if (( UPDATE_REPO )) && [[ -d "$REPO/pool" ]]; then
        if [[ -n "$(find "$REPO/pool" -name "${PACKAGE_NAME}_${VERSION}_*.deb")" ]]; then
            echo "Warning: $VERSION is already in $REPO. Systems which installed it won't get the rebuild."
            problems=1
        fi
        # highest version of the same suite in the local repository, see publishRepo.sh --dry-run for the published ones
        highest=""
        # same suite only: pre-releases with '~' are in the beta suite
        is_beta=0
        [[ "$VERSION" == *"~"* ]] && is_beta=1
        while read -r v; do
            v_beta=0
            [[ "$v" == *"~"* ]] && v_beta=1
            (( v_beta == is_beta )) || continue
            if [[ -z "$highest" ]] || dpkg --compare-versions "$v" gt "$highest"; then
                highest="$v"
            fi
        done < <(find "$REPO/pool" -name '*.deb' -printf '%f\n' | sed -E 's/^[^_]*_([^_]*)_.*/\1/')
        if [[ -n "$highest" && "$highest" != "$VERSION" ]] && dpkg --compare-versions "$VERSION" lt "$highest"; then
            echo "Warning: $VERSION is lower than $highest in suite $suite. apt doesn't install it as an update."
            problems=1
        fi
    fi
    (( problems )) || echo "No problems found."
    exit 0
fi

# a suite reaches all its users, buildRepo.sh refuses a build of a fix branch anyway, but only after building and signing
if (( UPDATE_REPO )) && is_fix_branch_build "$VERSION"; then
    echo "Error: $VERSION is a build of fix branch (VERSION=\"$VERSION_RASPIBACKUP\") and would be installed and announced" >&2
    echo "       to everybody. Build a fix for the tester with --fix <try>, or use --no-repo." >&2
    exit 1
fi

show "Building deb package '${PACKAGE_NAME}' for raspiBackup $VERSION"

rm -rf "$TGT"
rm -rf "$DEB_TGT"
mkdir -p "$DEB_TGT"

# copy source files
install -m755 -D -t "$TGT/$DIR_BIN" "$GITSRC/raspiBackup.sh" "$GITSRC/installation/raspiBackupConfig.sh"

# and get rid of .sh extension
pushd "$TGT/$DIR_BIN" > /dev/null
mv raspiBackup.sh raspiBackup
mv raspiBackupConfig.sh raspiBackupConfig
popd > /dev/null

# copy config templates - postinst creates $DIR_ETC/raspiBackup.conf from them if it doesn't exist.
# The config isn't a conffile, so dpkg never touches the users config on update.
install -m644 -D -t "$TGT/$DIR_SHARE/${PACKAGE_NAME}" "$GITSRC/config/raspiBackup_de.conf" "$GITSRC/config/raspiBackup_en.conf"

# copy systemd files
install -m644 -D -t "$TGT/$DIR_LIB/systemd/system" "$GITSRC/installation/raspiBackup.service" "$GITSRC/installation/raspiBackup.timer"

# copy sample extensions and their README - raspiBackupConfig links them into $DIR_BIN
install -m755 -D -t "$TGT/$DIR_SHARE/${PACKAGE_NAME}/extensions" "$GITSRC"/extensions/raspiBackup_*.sh
install -m644 -D -t "$TGT/$DIR_SHARE/${PACKAGE_NAME}/extensions" "$GITSRC/extensions/README.md"

# copy man pages - version and date are inserted and the pages compressed below
install -m644 -D -t "$TGT/$DIR_SHARE/man/man1" "$GITSRC/man/raspiBackup.1" "$GITSRC/man/raspiBackupConfig.1"
install -m644 -D -t "$TGT/$DIR_SHARE/man/man5" "$GITSRC/man/raspiBackup.conf.5"

# copy bash completions, bash-completion loads them on demand from $DIR_SHARE/bash-completion/completions
install -m644 -D -t "$TGT/$DIR_SHARE/bash-completion/completions" "$GITSRC/installation/completion/raspiBackup" "$GITSRC/installation/completion/raspiBackupConfig"

# copy full license text (GPLv3) next to the copyright file installed below
install -m644 -D -t "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}" "$GITSRC/LICENSE"

# get current commit sha and date into code
pushd "$GITSRC" > /dev/null
last_date=$(git log --pretty=format:"%ai" -1)
sha1=$(git log --pretty=format:"%h" -1)

# Debian changelog (apt changelog, apt-listchanges): one entry with the commits since the last release tag
changelog=$(
    echo "${PACKAGE_NAME} ($VERSION) $suite; urgency=medium"
    echo ""
    echo "  * raspiBackup $VERSION_RASPIBACKUP, raspiBackupConfig $VERSION_RASPIBACKUPCONFIG"
    echo "  * Release notes: https://github.com/framps/raspiBackup/releases"
    if [[ -n "$FIXES" ]]; then
        echo "  * Fixes: $(sed -E 's/m_([0-9]+)/#\1/g' <<< "$FIXES")"
    fi
    if [[ -n "$last_tag" ]]; then
        echo "  * Changes since $last_tag:"
        git log --no-merges -n 100 --pretty=format:"%s" "$last_tag..HEAD" | sed 's/^/    - /'
        echo ""
    fi
    echo ""
    echo " -- framp <framp@linux-tips-and-tricks.de>  $(LC_ALL=C date -R -d "$last_date")"
)
popd > /dev/null

# the gitsrc worktree is no longer needed here
git worktree remove "$GITSRC"

# Insert versions into the scripts
sed -i -E "s/^VERSION=\"[^\"]*\"/VERSION=\"$VERSION_RASPIBACKUP\"/" "$TGT/$DIR_BIN/raspiBackup"
sed -i -E "s/^VERSION=\"[^\"]*\"/VERSION=\"$VERSION_RASPIBACKUPCONFIG\"/" "$TGT/$DIR_BIN/raspiBackupConfig"

# Insert commit date and sha1 into the scripts
sed -i -e "s/\\\$Date\\\$/\\\$Date: $last_date\\\$/g" -e "s/\\\$Sha1\\\$/\\\$Sha1: $sha1\\\$/g" "$TGT/$DIR_BIN"/raspiBackup* "$TGT/$DIR_SHARE/${PACKAGE_NAME}"/*.conf "$TGT/$DIR_SHARE/${PACKAGE_NAME}"/extensions/*

# Insert version and commit date into the man pages and compress them as Debian requires
sed -i -e "s/@VERSION@/$VERSION/g" -e "s/@DATE@/${last_date%% *}/g" "$TGT/$DIR_SHARE"/man/man?/*
gzip -9n "$TGT/$DIR_SHARE"/man/man?/*

# keep the old name for raspiBackupConfig, crontabs and systemd units of former installations
# (created after sed -i, which would replace the link by a file)
ln -s raspiBackup "$TGT/$DIR_BIN/raspiBackup.sh"
# keep the old names of raspiBackupConfig for users used to them. raspiBackupInstallUI.sh also replaces
# the installer of a former installation without apt, dpkg overwrites files not owned by any package
ln -s raspiBackupConfig "$TGT/$DIR_BIN/raspiBackupInstallUI"
ln -s raspiBackupConfig "$TGT/$DIR_BIN/raspiBackupInstallUI.sh"

# completions are looked up by the name of the command, so the old names need links too
ln -s raspiBackup "$TGT/$DIR_SHARE/bash-completion/completions/raspiBackup.sh"
ln -s raspiBackupConfig "$TGT/$DIR_SHARE/bash-completion/completions/raspiBackupInstallUI"
ln -s raspiBackupConfig "$TGT/$DIR_SHARE/bash-completion/completions/raspiBackupInstallUI.sh"

# copy doc files (copyright in this case)
install -m644 -D -t "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}" "$PACKAGE/DEBIAN/copyright"
echo "$changelog" > "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}/changelog"
chmod 644 "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}/changelog"
gzip -9n "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}/changelog"
# The above locations isn't accepted by lintian, the one below is okay:
#   install -m644 -D -t "$TGT/usr/share/doc/${PACKAGE_NAME}" "$PACKAGE/DEBIAN/copyright"
# But perhaps we should keep the first location and just silence lintian a bit... See below.

mkdir -p "$TGT/DEBIAN"
# dpkg-deb neither computes Installed-Size (KiB) nor creates md5sums (used by dpkg --verify and debsums)
INSTALLED_SIZE=$(du -sk --apparent-size --exclude=DEBIAN "$TGT" | cut -f1)
export INSTALLED_SIZE
(cd "$TGT" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0 md5sum) > "$TGT/DEBIAN/md5sums"
chmod 644 "$TGT/DEBIAN/md5sums"
# create DEBIAN package files and insert version number in control file
envsubst < "$PACKAGE/DEBIAN/control"   > "$TGT/DEBIAN/control"
# own fields, shown by apt-cache show and used by publishRepo.sh for the git tag and the GitHub release
sed -i "/^Description:/i Git-Commit: $git_commit" "$TGT/DEBIAN/control"
if [[ -n "$FIXES" ]]; then
    sed -i "/^Description:/i Fixes: $FIXES" "$TGT/DEBIAN/control"
fi
chmod 644 "$TGT/DEBIAN/control"
# substitute only the build variables, the maintainer scripts use shell variables too
for script in preinst postinst prerm postrm; do
    # shellcheck disable=2016
    envsubst '${DIR_BIN} ${DIR_ETC} ${DIR_LIB} ${DIR_SHARE} ${PACKAGE_NAME}' < "$PACKAGE/DEBIAN/$script" > "$TGT/DEBIAN/$script"
    chmod 755 "$TGT/DEBIAN/$script"
done

show "Build (and sign) package"
LC_ALL=C dpkg-deb --root-owner-group --build "$TGT" "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"
echo "${VERSION_FILES}" > "$DEB_TGT/VERSION"

## Start of special debug block ##

# With non-debug output the details of the following commands
# are collected in a debug log and later added to the build.log.
# They are displayed on the terminal only when in debug mode.

if [[ "$VERBOSITY" != debug ]] ; then
    exec 3> "$DEBUG_FILE" 4>&1 5>&2 1>&3 2>&1
fi

show "Resulting DEBIAN package files ..."

for f in "$TGT"/DEBIAN/* ; do
    echo ""
    show "... $f"
    cat "$f"
done

show "Resulting systemd files ..."

for f in "$TGT/$DIR_LIB"/systemd/system/* ; do
    echo ""
    show "... $(realpath --relative-to . "$f")"
    cat "$f"
done

show "${PACKAGE_NAME} $VERSION package information"
dpkg-deb -I "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

show "Show files which will be installed"
dpkg-deb -c "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

show "Sign package"
gpg --verbose --yes --detach-sign -u "$GPG_KEYID" "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb" || exit $?

if [[ "$VERBOSITY" != debug ]] ; then
    if [[ -f "$DEBUG_FILE" ]] ; then
        cat "$DEBUG_FILE" >> "$LOG_FILE"
        rm "$DEBUG_FILE"
    fi
    exec 3>&- 1>&4- 2>&5-
fi

## End of special debug block ##


if [[ -n "$LINTIAN_CHECK" ]] ; then
    show "Check package with lintian "

    if ! command -v lintian > /dev/null ; then
        echo "Error: Can't check package because 'lintian' isn't installed!"
        echo "       Install it or skip the check with option --no-check."
        exit 1
    else
        # Note: The default behaviour for lintian exiting with rc=2 is:
        #         `--fail-on error`
        #       Since this packet isn't a real Debian one there are some
        #       "accepted" errors. We simply **could** ignore all of the
        #       failing checks by using option '--fail-on pedantic'.
        #       But the cleaner way is:
        #       Only suppress the unwanted checks via --suppress_tags.
        case "$LINTIAN_CHECK" in
            full) # Sometimes we might want to do a full check
                  echo "Note: Reports all errors, even the accepted/known ones!"
                  echo ""
                  SUPPRESS_TAGS=""
                  ;;

               *) # "reduced" checks is the default
                  SUPPRESS_TAGS="--suppress-tags file-in-unusual-dir"
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,dir-in-usr-local,file-in-usr-local"
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,file-in-usr-marked-as-conffile,non-etc-file-marked-as-conffile"
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,no-changelog"
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,no-copyright-file"
                  # the read is in revertMigration.sh created by preinst, not run by dpkg
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,read-in-maintainer-script"
                  # no debhelper and Raspberry Pi OS always runs systemd
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,maintainer-script-calls-systemctl"
                  # own control fields Fixes and Git-Commit
                  SUPPRESS_TAGS="$SUPPRESS_TAGS,unknown-field"
                  ;;
        esac

        # shellcheck disable=2086  # Double quote to prevent globbing and word splitting
        if lintian $LINTIAN_OPTIONS $SUPPRESS_TAGS "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb" ; then
            echo "o.k."
        else
            exit $?
        fi
    fi
fi


show "The final package in $DEB_TGT"
ls -l "$DEB_TGT"

if (( UPDATE_REPO )) ; then
    ./buildRepo.sh "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"
fi

if [[ -n "$fix_branch" ]] ; then
    show "Fix $VERSION for the tester of $fix_branch"
    install -m644 -D "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb" "$fix_file"
    install -m644 "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "$fix_file.sig"
    update_fix_index "${fix_file%/*}"
    ls -l "${fix_file%/*}"
    echo ""
    echo "Publish it with ./publishRepo.sh, the tester installs it with: sudo raspiBackupConfig -F $fix_branch"
fi
