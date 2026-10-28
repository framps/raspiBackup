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

        buildRepo.sh [<package.deb> ...]

Adds the given Debian packages to the pool of the apt repository in 'repo'
and (re)creates and signs the repository index files. Without arguments
only the index files are recreated and signed again.

Packages already in the pool are kept, so older versions stay installable
(e.g. 'apt-get install raspibackup=0.7.3' to downgrade).

Chain of trust which is checked by apt on the user's system:

    InRelease (signed with GPG_KEYID)
      -> SHA256 of dists/<suite>/main/binary-<arch>/Packages
         -> SHA256 of pool/.../raspibackup_<version>_all.deb

Options:

    -h | --help    display this short help

EOF_USAGE
}

# shellcheck disable=1091
source ./common.sh
# shellcheck disable=1091
source ./build.conf

REPO_SUITE="${REPO_SUITE:-stable}"
REPO_COMPONENT="${REPO_COMPONENT:-main}"
REPO_ARCHITECTURES="${REPO_ARCHITECTURES:-armhf arm64 amd64 i386}"

if (( $# > 0 )); then
    case "$1" in
        -h|--help) usage
                   exit
                   ;;
    esac
fi

if [[ -z "${GPG_KEYID:-}" ]] ; then
    echo "Error: Missing GPG_KEYID in 'build.conf'. The repository can't be signed!"
    exit 1
fi

trap 'err $?' ERR

POOL="pool/$REPO_COMPONENT/${PACKAGE_NAME:0:1}/$PACKAGE_NAME"
DIST="dists/$REPO_SUITE"

mkdir -p "$REPO/$POOL"

for deb in "$@"; do
    name="$(dpkg-deb -f "$deb" Package)"
    version="$(dpkg-deb -f "$deb" Version)"
    arch="$(dpkg-deb -f "$deb" Architecture)"
    if [[ "$name" != "$PACKAGE_NAME" ]] ; then
        echo "Error: $deb contains package '$name' but '$PACKAGE_NAME' is expected"
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
    echo "Error: No packages in $REPO/$POOL"
    exit 1
fi

show "Create package indices"

# Don't delete dists, older by-hash files are still needed by clients with an outdated InRelease
for arch in $REPO_ARCHITECTURES; do
    mkdir -p "$REPO/$DIST/$REPO_COMPONENT/binary-$arch"
    # 'Filename:' entries have to be relative to the repository root
    (cd "$REPO" && apt-ftparchive --arch "$arch" packages "$POOL") > "$REPO/$DIST/$REPO_COMPONENT/binary-$arch/Packages"
    gzip -9nc "$REPO/$DIST/$REPO_COMPONENT/binary-$arch/Packages" > "$REPO/$DIST/$REPO_COMPONENT/binary-$arch/Packages.gz"
done
grep -E "^(Package|Version|Filename):" "$REPO/$DIST/$REPO_COMPONENT/binary-${REPO_ARCHITECTURES%% *}/Packages"

show "Create and sign Release file"

# Acquire-By-Hash avoids hash mismatches while CDN caches (e.g. GitHub) are partially outdated
release="$(mktemp)"
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="raspiBackup" \
    -o APT::FTPArchive::Release::Label="raspiBackup" \
    -o APT::FTPArchive::Release::Suite="$REPO_SUITE" \
    -o APT::FTPArchive::Release::Codename="$REPO_SUITE" \
    -o APT::FTPArchive::Release::Architectures="$REPO_ARCHITECTURES" \
    -o APT::FTPArchive::Release::Components="$REPO_COMPONENT" \
    -o APT::FTPArchive::Release::Description="raspiBackup - Backup your Raspberry Pi systems" \
    -o APT::FTPArchive::DoByHash=true \
    release "$REPO/$DIST" > "$release"
install -m644 "$release" "$REPO/$DIST/Release"
rm -f "$release"

gpg --yes --local-user "$GPG_KEYID" --digest-algo SHA512 --clearsign \
    --output "$REPO/$DIST/InRelease" "$REPO/$DIST/Release"
gpg --yes --local-user "$GPG_KEYID" --digest-algo SHA512 --armor --detach-sign \
    --output "$REPO/$DIST/Release.gpg" "$REPO/$DIST/Release"

show "Export public key"

# Users get the key from here, but raspiBackupInstall.sh accepts it only if it matches its built-in fingerprint
gpg --export --export-options export-minimal "$GPG_KEYID" > "$REPO/${PACKAGE_NAME}-archive-keyring.gpg"
gpg --armor --export --export-options export-minimal "$GPG_KEYID" > "$REPO/${PACKAGE_NAME}-archive-keyring.asc"
chmod 644 "$REPO/${PACKAGE_NAME}-archive-keyring".*

show "Verify repository signature"

keyring="$(realpath "$REPO/${PACKAGE_NAME}-archive-keyring.gpg")"
signer="$(gpgv --status-fd 1 --keyring "$keyring" "$REPO/$DIST/InRelease" 2>/dev/null \
    | awk '$2 == "VALIDSIG" { print $NF }')"
if [[ "$signer" != "${GPG_KEYID^^}" ]] ; then
    echo "Error: InRelease isn't signed by $GPG_KEYID (got '${signer}')"
    exit 1
fi
gpgv --keyring "$keyring" "$REPO/$DIST/Release.gpg" "$REPO/$DIST/Release"
echo "o.k."

show "Repository in $REPO - publish this directory as it is"
find "$REPO" -path '*/by-hash' -prune -o -type f -print | sort
