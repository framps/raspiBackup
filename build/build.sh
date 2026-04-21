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

if [[ ! -d gitsrc ]]; then
	git clone git@github.com:framps/raspiBackup.git gitsrc
fi

export VERSION
LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE
source ./common.sh

# fill GPG_KEYID with existing local key
source ./gpg.conf

trap 'err $?' ERR

# extract version number from raspiBackup script
version="$(grep "^VERSION=" "gitsrc/raspiBackup.sh" 2>/dev/null) | cut -f 2 -d "=" )"
REGEX='.*="([^"]*)"'
if [[ $version =~ $REGEX ]]; then
	VERSION=${BASH_REMATCH[1]}
fi

VERSION_FILES="_$(sed -E 's/\./_/g' <<< "$VERSION")"

show "Building deb package for raspiBackup $VERSION"

rm -rf "$TGT"
rm -rf "$DEB_TGT"

mkdir -p "$PACKAGE"
mkdir -p "$DEB_TGT"
mkdir -p "$TGT/DEBIAN"
mkdir -p "$TGT/usr/local/bin"
mkdir -p "$TGT/usr/local/etc"
mkdir -p "$TGT/etc/systemd/system"

# copy source files
install -m755 "$SRC/raspiBackup.sh" "$TGT/usr/local/bin"
install -m755 "$SRC/installation/raspiBackupInstallUI.sh" "$TGT/usr/local/bin"

# create links
cd "$TGT/usr/local/bin"
ln -s -r raspiBackup.sh raspiBackup
ln -s -r raspiBackupInstallUI.sh raspiBackupInstallUI
cd "$CURRENT_DIR"

# copy config files
install -m600 "$SRC/config/raspiBackup_de.conf" "$TGT/usr/local/etc"
install -m600 "$SRC/config/raspiBackup_en.conf" "$TGT/usr/local/etc/raspiBackup.conf"

# copy systemd files
install -m655 "$SRC/installation/raspiBackup.service" "$TGT/etc/systemd/system"
install -m655 "$SRC/installation/raspiBackup.timer" "$TGT/etc/systemd/system"

# copy extension files
for file in $SRC/extensions/raspiBackup_*; do
	install -m755 "$file" "$TGT/usr/local/bin"
done

# create DEBIAN package files
envsubst < "$PACKAGE/DEBIAN/control" > /tmp/control
install -m655  /tmp/control "$TGT/DEBIAN/control"
rm /tmp/control
install -m655  "$PACKAGE/DEBIAN/conffiles" "$TGT/DEBIAN"
install -m755  "$PACKAGE/DEBIAN/postinst" "$TGT/DEBIAN"
install -m755  "$PACKAGE/DEBIAN/postrm" "$TGT/DEBIAN"

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm $LOG_FILE || true

show "Build package"
dpkg-deb --root-owner-group --build "$TGT" "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

show "Sign raspiBackup package"
gpg --verbose --yes --detach-sign -u "$GPG_KEYID" "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

show "Show files which will be installed"
dpkg-deb -c "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

show "raspiBackup package information"
dpkg-deb -I "$DEB_TGT/raspiBackup$VERSION_FILES.deb"

cd $DEB_TGT
ln -s "raspiBackup$VERSION_FILES.deb" "raspiBackup.deb"
ln -s "raspiBackup$VERSION_FILES.deb.sig" "raspiBackup.deb.sig"
cd ..

