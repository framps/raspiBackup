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

# BRANCH_TO_DEB="m_972"
BRANCH_TO_DEB="master"
CURRENT_BRANCH=$(git branch --show-current)

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

# underscores are not allowed in debian version numbers
# change m_972 to m-972
VERSION="$(sed -E 's/_/-/g' <<< "$VERSION")"
VERSION_FILES="_$(sed -E 's/_/./g' <<< "$VERSION")"

show "Building deb package for raspiBackup $VERSION"

rm -rf "$TGT"
rm -rf "$DEB_TGT"
mkdir -p "$DEB_TGT"

# copy source files
install -m755 -D -t "$TGT/usr/share/raspiBackup" "$GITSRC/raspiBackup.sh" "$GITSRC/installation/raspiBackupInstallUI.sh"

# create links
pushd "$TGT/usr/share/raspiBackup" > /dev/null
ln -s -r raspiBackup.sh raspiBackup
ln -s -r raspiBackupInstallUI.sh raspiBackupInstallUI
popd > /dev/null

# copy config files - Note: They may contain credentials - therefore change to 600 during installation
install -m644 -D -t "$TGT/etc/raspiBackup" "$GITSRC/config/raspiBackup_de.conf" "$GITSRC/config/raspiBackup_en.conf"

# copy systemd files
install -m644 -D -t "$TGT/usr/lib/systemd/system" "$GITSRC/installation/raspiBackup.service" "$GITSRC/installation/raspiBackup.timer"

# copy extension files
for file in "$GITSRC"/extensions/raspiBackup_*; do
	install -m755 "$file" "$TGT/usr/share/raspiBackup"
done

# get current commit sha and date into code
pushd "$GITSRC" > /dev/null
last_date=$(git log --pretty=format:"%ai" -1)
sha1=$(git log --pretty=format:"%h" -1)
popd > /dev/null

# the gitsrc worktree is no longer needed here
git worktree remove "$GITSRC"

# echo ">>> $last_date  $sha1"
for f in "$TGT"/usr/share/raspiBackup/* ; do
    # cp -p "$f" "${f}.sav"
    sed -i -e "s/\\\$Date\\\$/\\\$Date: $last_date\\\$/g" -e "s/\\\$Sha1\\\$/\\\$Sha1: $sha1\\\$/g" "$f"
    # diff "${f}.sav" "$f" || true
done


# copy doc files (copyright in this case)
# TODO: Fix copyright file to make lintian happy
install -m644 -D -t "$TGT/usr/share/doc/raspiBackup" "$PACKAGE/DEBIAN/copyright"

# create DEBIAN package files and insert version number in control file
envsubst < "$PACKAGE/DEBIAN/control" > /tmp/control
install -m644 -D /tmp/control "$TGT/DEBIAN/control"
rm /tmp/control
install -m644  "$PACKAGE/DEBIAN/conffiles" "$TGT/DEBIAN"
install -m755  "$PACKAGE/DEBIAN/postinst" "$TGT/DEBIAN"
install -m755  "$PACKAGE/DEBIAN/postrm" "$TGT/DEBIAN"

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm "$LOG_FILE" || true
rc=1

show "Build package"
dpkg-deb --root-owner-group --build "$TGT" "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

if [[ -n "$GPG_KEYID" ]] ; then
	show "Sign package"
	gpg --verbose --yes --detach-sign -u "$GPG_KEYID" "$DEB_TGT/raspiBackup$VERSION_FILES.deb"
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

show "Show files which will be installed"
dpkg-deb -c "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

show "The final package in $DEB_TGT"
ls -l "$DEB_TGT"

show "raspiBackup $VERSION package information"
dpkg-deb -I "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

# create links
pushd "$DEB_TGT" > /dev/null
ln -sf "raspiBackup$VERSION_FILES.deb" "raspiBackup.deb"
if [[ -n "$GPG_KEYID" ]] ; then
	ln -sf "raspiBackup$VERSION_FILES.deb.sig" "raspiBackup.deb.sig"
fi
popd > /dev/null

if (( CHECK_PACKAGE != 0 )) ; then
	show "Check package with lintian "

	if command -v lintian > /dev/null ; then
		# Note: The default behaviour for rc=2 is: `--fail-on error`
		#       But since there are still several know errors we ignore them for now.
		lintian --color always --fail-on pedantic "$DEB_TGT/raspiBackup.deb"
		rc=$?
	else
		echo "Warning: Can't check package because 'lintian' isn't installed!"
	fi
fi


exit "$rc"

