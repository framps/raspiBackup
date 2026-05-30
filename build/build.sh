#!/bin/bash
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

# shellcheck disable=1091
source ./common.sh

GITSRC=$(mktemp --tmpdir -d raspiBackup_gitsrc4deb.XXXXXX)
# shellcheck disable=2034
readonly GITSRC

# The branch used to build the Debian package from.
# If empty then the curent branch is used.
# Note: Always only the commited changes are taken into account!
# BRANCH_TO_DEB="master"
# BRANCH_TO_DEB="m_972"
BRANCH_TO_DEB=""

CURRENT_BRANCH=$(git branch --show-current)

BRANCH_TO_DEB="${BRANCH_TO_DEB:-${CURRENT_BRANCH}}"
show "Using branch '$BRANCH_TO_DEB' as source for the build"

if [[ "$CURRENT_BRANCH" == "$BRANCH_TO_DEB" ]] ; then
    git worktree add --detach "$GITSRC"
else
    git worktree add "$GITSRC" "$BRANCH_TO_DEB"
fi

export VERSION
LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE

GPG_KEYID=""
if [[ -f gpg.conf ]] ; then
	# fill GPG_KEYID with existing local key
	# shellcheck disable=1091
	source ./gpg.conf
fi

trap 'err $?' ERR

# extract version number from raspiBackup script
version="$(grep "^VERSION=" "$GITSRC/raspiBackup.sh" 2>/dev/null) | cut -f 2 -d "=" )"
REGEX='.*="([^"]*)"'
if [[ $version =~ $REGEX ]]; then
	VERSION=${BASH_REMATCH[1]}
fi

CHECK_PACKAGE=1
if (( $# > 0 )); then
	if [[ "$1" == "--no-check" ]] ; then
		CHECK_PACKAGE=0
		shift
	fi
fi

# allow to pass another version number for upgrade/downgrade tests
if (( $# > 0 )); then
	VERSION="$1"
fi

# Debian wants to have all-lowercase package names
export PACKAGE_NAME="raspibackup"

# absolute pathes for the files in the package
# will be used relatively below and absolutely in envsubst results
export DIR_BIN="/usr/local/bin"
export DIR_ETC="/usr/local/etc"
export DIR_LIB="/usr/local/lib"
export DIR_SHARE="/usr/local/share"

# underscores are not allowed in Debian version numbers
# change m_972 to m-972
VERSION="$(sed -E 's/_/-/g' <<< "$VERSION")"
VERSION_FILES="_$(sed -E 's/_/./g' <<< "$VERSION")"

show "Building deb package '${PACKAGE_NAME}' for raspiBackup $VERSION"

rm -rf "$TGT"
rm -rf "$DEB_TGT"
mkdir -p "$DEB_TGT"

# copy source files
install -m755 -D -t "$TGT/$DIR_BIN" "$GITSRC/raspiBackup.sh" "$GITSRC/installation/raspiBackupInstallUI.sh"

# and get rid of .sh extension
pushd "$TGT/$DIR_BIN" > /dev/null
mv raspiBackup.sh raspiBackup
mv raspiBackupInstallUI.sh raspiBackupInstallUI
popd > /dev/null

# copy config files - Note: They may contain credentials - therefore change to 600 during installation
install -m644 -D -t "$TGT/$DIR_ETC/${PACKAGE_NAME}" "$GITSRC/config/raspiBackup_de.conf" "$GITSRC/config/raspiBackup_en.conf"
# make the english version the default
mv "$TGT/$DIR_ETC/${PACKAGE_NAME}/raspiBackup_en.conf" "$TGT/$DIR_ETC/${PACKAGE_NAME}/raspiBackup.conf"

# copy systemd files
install -m644 -D -t "$TGT/$DIR_LIB/systemd/system" "$GITSRC/installation/raspiBackup.service" "$GITSRC/installation/raspiBackup.timer"

# copy extension files
for file in "$GITSRC"/extensions/raspiBackup_*; do
	install -m755 -D -t "$TGT/$DIR_SHARE/${PACKAGE_NAME}" "$file"
done

# get current commit sha and date into code
pushd "$GITSRC" > /dev/null
last_date=$(git log --pretty=format:"%ai" -1)
sha1=$(git log --pretty=format:"%h" -1)
popd > /dev/null

# the gitsrc worktree is no longer needed here
git worktree remove "$GITSRC"

# Insert commit date and sha1 into the scripts
sed -i -e "s/\\\$Date\\\$/\\\$Date: $last_date\\\$/g" -e "s/\\\$Sha1\\\$/\\\$Sha1: $sha1\\\$/g" "$TGT/$DIR_BIN"/raspiBackup* "$TGT/$DIR_SHARE/${PACKAGE_NAME}"/*

# copy doc files (copyright in this case)
install -m644 -D -t "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}" "$PACKAGE/DEBIAN/copyright"
# The above locations isn't accepted by lintian, the one below is okay:
#   install -m644 -D -t "$TGT/usr/share/doc/${PACKAGE_NAME}" "$PACKAGE/DEBIAN/copyright"
# But perhaps we should keep the first location and just silence lintian a bit... See below.

mkdir -p "$TGT/DEBIAN"
# create DEBIAN package files and insert version number in control file
envsubst < "$PACKAGE/DEBIAN/control"   > "$TGT/DEBIAN/control"
envsubst < "$PACKAGE/DEBIAN/conffiles" > "$TGT/DEBIAN/conffiles"
envsubst < "$PACKAGE/DEBIAN/postinst"  > "$TGT/DEBIAN/postinst"
chmod 644 "$TGT/DEBIAN/conffiles" "$TGT/DEBIAN/control"
chmod 755 "$TGT/DEBIAN/postinst"

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

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm "$LOG_FILE" || true
rc=0

show "Build package"
LC_ALL=C dpkg-deb --root-owner-group --build "$TGT" "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

if [[ -n "$GPG_KEYID" ]] ; then
	show "Sign package"
	gpg --verbose --yes --detach-sign -u "$GPG_KEYID" "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"
	rc=$?
else
	echo ""
	echo "Error: The package can't be signed!"
	if [[ -f gpg.conf ]] ; then
		echo "         File 'gpg.conf' not set up correctly!"
	else
		echo "         File 'gpg.conf' not found!"
		echo "         Creating a template 'gpg.conf' now."
		cat >> ./gpg.conf <<EOF_GPG
# Please set GPG_KEYID to the ID to be used for signing the built package.
GPG_KEYID=""
EOF_GPG
	fi
	echo "         Please fill in the correct ID and build again!"
	echo ""
	rc=1
fi

if [[ "$rc" -ne 0 ]] ; then
    exit "$rc"
fi

show "Show files which will be installed"
dpkg-deb -c "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

show "The final package in $DEB_TGT"
ls -l "$DEB_TGT"

show "${PACKAGE_NAME} $VERSION package information"
dpkg-deb -I "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

# create links
pushd "$DEB_TGT" > /dev/null
ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb" "${PACKAGE_NAME}.deb"
if [[ -n "$GPG_KEYID" ]] ; then
	ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}.deb.sig"
fi
popd > /dev/null

if (( CHECK_PACKAGE != 0 )) ; then
	show "Check package with lintian "

	if command -v lintian > /dev/null ; then
		# Note: The default behaviour for lintian exiting with rc=2 is:
		#         `--fail-on error`
		#       Since this packet isn't a real Debian one there are some
		#       "accepted" errors. We simply **could** ignore all of the
		#       failing checks by using option '--fail-on pedantic'.
		#       But the cleaner way is:
		#       Only suppress the unwanted checks via --suppress_tags:
		SUPPRESS_TAGS="--suppress-tags file-in-unusual-dir"
		SUPPRESS_TAGS="$SUPPRESS_TAGS,dir-in-usr-local,file-in-usr-local"
		SUPPRESS_TAGS="$SUPPRESS_TAGS,file-in-usr-marked-as-conffile,non-etc-file-marked-as-conffile"
		SUPPRESS_TAGS="$SUPPRESS_TAGS,no-changelog"
		SUPPRESS_TAGS="$SUPPRESS_TAGS,no-copyright-file"
		#
		# shellcheck disable=2086  # Double quote to prevent globbing and word splitting
		lintian --verbose --info --color always $SUPPRESS_TAGS "$DEB_TGT/${PACKAGE_NAME}.deb"
		rc=$?
	else
		echo "Warning: Can't check package because 'lintian' isn't installed!"
	fi
fi


exit "$rc"

