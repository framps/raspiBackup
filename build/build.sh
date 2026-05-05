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

# clone github code to get current commit sha into code
# should be done finally all the time
if [[ ! -d "$GITSRC" ]]; then
	git clone https://github.com/framps/raspiBackup.git "$GITSRC"
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

# allow to pass another version number for upgrade/downgrade tests
if (( $# > 0 )); then
	VERSION="$1"
fi

# dots are not allowed in debian version numbers
VERSION_FILES="_$(sed -E 's/\./_/g' <<< "$VERSION")"

show "Building deb package for raspiBackup $VERSION"

rm -rf "$TGT"
mkdir -p "$DEB_TGT"

# copy source files
install -m755 -D -t "$TGT/usr/local/bin" "$GITSRC/raspiBackup.sh" "$GITSRC/installation/raspiBackupInstallUI.sh"

# create links
pushd "$TGT/usr/local/bin" > /dev/null
ln -s -r raspiBackup.sh raspiBackup
ln -s -r raspiBackupInstallUI.sh raspiBackupInstallUI
popd > /dev/null

# copy config files
install -m644 -D -t "$TGT/usr/local/etc" "$GITSRC/config/raspiBackup_de.conf"
install -m644 -D "$GITSRC/config/raspiBackup_en.conf" "$TGT/usr/local/etc/raspiBackup.conf"

# copy systemd files
install -m755 -D -t "$TGT/etc/systemd/system" "$GITSRC/installation/raspiBackup.service" "$GITSRC/installation/raspiBackup.timer"

# copy extension files
for file in "$GITSRC"/extensions/raspiBackup_*; do
	install -m755 "$file" "$TGT/usr/local/bin"
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

show "Build package"
dpkg-deb --root-owner-group --build "$TGT" "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

if [[ -n "$GPG_KEYID" ]] ; then
	show "Sign package"
	gpg --verbose --yes --detach-sign -u "$GPG_KEYID" "$DEB_TGT/raspiBackup$VERSION_FILES.deb"
fi

show "Show files which will be installed"
dpkg-deb -c "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

show "raspiBackup $VERSION package information"
dpkg-deb -I "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

# create links
pushd "$DEB_TGT" > /dev/null
ln -sf "raspiBackup$VERSION_FILES.deb" "raspiBackup.deb"
if [[ -n "$GPG_KEYID" ]] ; then
	ln -sf "raspiBackup$VERSION_FILES.deb.sig" "raspiBackup.deb.sig"
fi
popd > /dev/null

show "Check package with lintian "

if command -v lintian > /dev/null ; then
	# Note: The default behaviour for rc=2 is: `--fail-on error`
	#       But since there are still several know errors we ignore them for now.
	lintian --color always --fail-on pedantic "$DEB_TGT/raspiBackup.deb"
fi
