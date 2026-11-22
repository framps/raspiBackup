#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Create or update the signed apt repository for raspiBackup
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

        buildRepo.sh [--allow-empty] [<package.deb> ...]

Adds the given Debian packages to the pool of the apt repository in 'repo'
and (re)creates and signs the repository index files. Without arguments
only the index files are recreated and signed again.

Packages already in the pool are kept, so older versions stay installable
(e.g. 'apt-get install raspibackup=0.7.3' to downgrade).

All packages share one pool but are listed in two suites:

    <REPO_SUITE>       (stable) all versions without '~', e.g. 0.7.4, 0.7.4-1, 0.7.4-m1
    <REPO_BETA_SUITE>  (beta)   all versions with '~', e.g. 0.7.5~beta1, 0.7.5~rc1

Fixes of branches for one tester (build.sh --fix, e.g. 0.7.4-m1+m972.1) are in no suite.
They are in 'repo/fixes/<branch>', the file 'latest' there names the newest one.
Builds of a fix branch with its VERSION (0.7.4-m_972 -> 0.7.4-m-972) are refused.

Versions listed in DEPRECATED of build.conf get the field 'Deprecated: yes' in the package index.
raspiBackup warns their users at the start of every run and never reports them, raspiBackupConfig never offers them.
They stay in the pool, so apt still knows them and the users of a deprecated version get the warning.

The beta suite is marked 'NotAutomatic' and 'ButAutomaticUpgrades'. So apt never
installs a beta by itself, but updates an installed beta to newer betas:

    apt-get install -t beta raspibackup     # install the latest beta
    apt-get install raspibackup/stable      # revert to the stable version

Chain of trust which is checked by apt on the user's system:

    InRelease (signed with GPG_KEYID)
      -> SHA256 of dists/<suite>/main/binary-<arch>/Packages
         -> SHA256 of pool/.../raspibackup_<version>_all.deb

Options:

    -h | --help      display this short help
    --allow-empty    create the index files also without any package in the pool,
                     e.g. after publishRepo.sh --remove removed the last version

EOF_USAGE
}

# shellcheck disable=1091
source ./common.sh
# shellcheck disable=1091
source ./build.conf

REPO_SUITE="${REPO_SUITE:-stable}"
REPO_BETA_SUITE="${REPO_BETA_SUITE:-beta}"
REPO_COMPONENT="${REPO_COMPONENT:-main}"
REPO_ARCHITECTURES="${REPO_ARCHITECTURES:-armhf arm64 amd64 i386}"

ALLOW_EMPTY=0
while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage
                   exit
                   ;;
        --allow-empty) ALLOW_EMPTY=1
                   shift
                   ;;
        *) break
                   ;;
    esac
done

if [[ -z "${GPG_KEYID:-}" ]] ; then
    echo "Error: Missing GPG_KEYID in 'build.conf'. The repository can't be signed!"
    exit 1
fi

trap 'err $?' ERR

POOL="pool/$REPO_COMPONENT/${PACKAGE_NAME:0:1}/$PACKAGE_NAME"

mkdir -p "$REPO/$POOL"

for deb in "$@"; do
    name="$(dpkg-deb -f "$deb" Package)"
    version="$(dpkg-deb -f "$deb" Version)"
    arch="$(dpkg-deb -f "$deb" Architecture)"
    if [[ "$name" != "$PACKAGE_NAME" ]] ; then
        echo "Error: $deb contains package '$name' but '$PACKAGE_NAME' is expected"
        exit 1
    fi
    # a suite reaches all its users: apt would install it and raspiBackup would announce it
    if is_fix_version "$version" ; then
        echo "Error: $version is a fix for one tester and doesn't belong into a suite. Build it with build.sh --fix."
        exit 1
    fi
    if is_fix_branch_build "$version" ; then
        echo "Error: $version is a build of a fix branch (VERSION=\"...-m_<n>\"). Build a fix for the tester"
        echo "       with build.sh --fix <try>, or set a release or hotfix version for everybody."
        exit 1
    fi
    pooled="$REPO/$POOL/${name}_${version}_${arch}.deb"
    if [[ -f "$pooled" ]] && ! cmp -s "$deb" "$pooled" ; then
        # Systems which already installed the old one won't get the new one
        echo "Warning: Replacing different package with same version $version in repository."
        echo "         Systems which installed the old one won't update. Better increase the version."
    fi
    show "Add $name $version to repository"
    install -m644 "$deb" "$pooled"
done

if ! compgen -G "$REPO/$POOL/*.deb" > /dev/null ; then
    if (( ! ALLOW_EMPTY )) ; then
        echo "Error: No packages in $REPO/$POOL"
        exit 1
    fi
    echo "Warning: No packages in $REPO/$POOL, the repository is empty. New installations fail until a version is published."
fi

# versions of the pool marked as deprecated in the package index, raspiBackup warns their users and never reports them
DEPRECATED_VERSIONS=""
if [[ -n "$(xargs <<< "${DEPRECATED:-}")" ]] ; then
    show "Mark deprecated versions: ${DEPRECATED}"
    for deb in "$REPO/$POOL"/*.deb; do
        [[ -e "$deb" ]] || continue     # empty pool
        version="$(dpkg-deb -f "$deb" Version)"
        is_deprecated "$version" "$DEPRECATED" && DEPRECATED_VERSIONS+="$version "
    done
    for entry in ${DEPRECATED//,/ }; do
        matched=0
        for version in $DEPRECATED_VERSIONS; do
            is_deprecated "$version" "$entry" && matched=1
        done
        (( matched )) || echo "Warning: DEPRECATED entry $entry matches no version in the repository"
    done
    echo "Deprecated: ${DEPRECATED_VERSIONS:-none}"
fi

create_suite() {
    # $1 suite, $2 "beta" to list only versions with '~', otherwise only the ones without
    local suite="$1" beta="$2" dist="dists/$1" arch release filter
    local -a options=()

    if [[ "$beta" == beta ]] ; then
        filter='/(^|\n)Version: [^\n]*~/'
        # apt installs from this suite only on request (-t beta), but keeps an installed beta updated
        options=(-o APT::FTPArchive::Release::NotAutomatic=yes -o APT::FTPArchive::Release::ButAutomaticUpgrades=yes)
    else
        filter='!/(^|\n)Version: [^\n]*~/'
    fi

    show "Create package indices of suite $suite"

    # Don't delete dists, older by-hash files are still needed by clients with an outdated InRelease
    for arch in $REPO_ARCHITECTURES; do
        mkdir -p "$REPO/$dist/$REPO_COMPONENT/binary-$arch"
        # 'Filename:' entries have to be relative to the repository root
        (cd "$REPO" && apt-ftparchive --arch "$arch" packages "$POOL") \
            | awk 'BEGIN { RS = ""; ORS = "\n\n" } '"$filter" \
            | awk -v deprecated="$DEPRECATED_VERSIONS" 'BEGIN { RS = ""; ORS = "\n\n"; split(deprecated, d, " "); for (i in d) dep[d[i]] = 1 }
                { v = ""; n = split($0, line, "\n"); for (i = 1; i <= n; i++) if (line[i] ~ /^Version: /) v = substr(line[i], 10)
                  if (v in dep) $0 = $0 "\nDeprecated: yes"
                  print }' > "$REPO/$dist/$REPO_COMPONENT/binary-$arch/Packages"
        gzip -9nc "$REPO/$dist/$REPO_COMPONENT/binary-$arch/Packages" > "$REPO/$dist/$REPO_COMPONENT/binary-$arch/Packages.gz"
    done
    grep -E "^(Package|Version|Filename|Deprecated):" "$REPO/$dist/$REPO_COMPONENT/binary-${REPO_ARCHITECTURES%% *}/Packages" || echo "No packages"

    show "Create and sign Release file of suite $suite"

    # Acquire-By-Hash avoids hash mismatches while CDN caches (e.g. GitHub) are partially outdated
    release="$(mktemp)"
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin="raspiBackup" \
        -o APT::FTPArchive::Release::Label="raspiBackup" \
        -o APT::FTPArchive::Release::Suite="$suite" \
        -o APT::FTPArchive::Release::Codename="$suite" \
        -o APT::FTPArchive::Release::Architectures="$REPO_ARCHITECTURES" \
        -o APT::FTPArchive::Release::Components="$REPO_COMPONENT" \
        -o APT::FTPArchive::Release::Description="raspiBackup - Backup your Raspberry Pi systems" \
        -o APT::FTPArchive::DoByHash=true \
        "${options[@]}" \
        release "$REPO/$dist" > "$release"
    install -m644 "$release" "$REPO/$dist/Release"
    rm -f "$release"

    gpg --yes --local-user "$GPG_KEYID" --digest-algo SHA512 --clearsign \
        --output "$REPO/$dist/InRelease" "$REPO/$dist/Release"
    gpg --yes --local-user "$GPG_KEYID" --digest-algo SHA512 --armor --detach-sign \
        --output "$REPO/$dist/Release.gpg" "$REPO/$dist/Release"
}

# both suites always exist, raspiBackupInstall.sh adds both to the sources
create_suite "$REPO_SUITE" stable
create_suite "$REPO_BETA_SUITE" beta

# fixes of branches for one tester: in no suite, raspiBackupConfig -F reads the file 'latest' of the branch
if [[ -d "$REPO/$FIXES_DIR" ]] ; then
    show "Index fixes of branches in $REPO/$FIXES_DIR"
    for dir in "$REPO/$FIXES_DIR"/*/; do
        dir="${dir%/}"
        [[ -d "$dir" ]] || continue
        while read -r deb; do
            if [[ ! -f "$deb.sig" ]] ; then
                echo "Error: Signature $deb.sig missing"
                exit 1
            fi
        done < <(find "$dir" -maxdepth 1 -name '*.deb')
        update_fix_index "$dir"
        if [[ -f "$dir/latest" ]] ; then
            echo "${dir##*/}: $(cat "$dir/latest")"
        else
            echo "${dir##*/}: no fix, removed"
            rm -rf "$dir"
        fi
    done
fi

show "Export public key"

# Users get the key from here, but raspiBackupInstall.sh accepts it only if it matches its built-in fingerprint
gpg --export --export-options export-minimal "$GPG_KEYID" > "$REPO/${PACKAGE_NAME}-archive-keyring.gpg"
gpg --armor --export --export-options export-minimal "$GPG_KEYID" > "$REPO/${PACKAGE_NAME}-archive-keyring.asc"
chmod 644 "$REPO/${PACKAGE_NAME}-archive-keyring".*

show "Verify repository signatures"

keyring="$(realpath "$REPO/${PACKAGE_NAME}-archive-keyring.gpg")"
for suite in "$REPO_SUITE" "$REPO_BETA_SUITE"; do
    dist="dists/$suite"
    signer="$(gpgv --status-fd 1 --keyring "$keyring" "$REPO/$dist/InRelease" 2>/dev/null \
        | awk '$2 == "VALIDSIG" { print $NF }')"
    if [[ "$signer" != "${GPG_KEYID^^}" ]] ; then
        echo "Error: $dist/InRelease isn't signed by $GPG_KEYID (got '${signer}')"
        exit 1
    fi
    gpgv --keyring "$keyring" "$REPO/$dist/Release.gpg" "$REPO/$dist/Release"
    echo "$suite o.k."
done

show "Repository in $REPO - publish this directory as it is"
find "$REPO" -path '*/by-hash' -prune -o -type f -print | sort
