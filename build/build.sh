#!/bin/bash
#######################################################################################################################
#
# 	Build raspiBackup Debian package
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

export VERSION="0.7.2"
readonly VERSION
LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE
source ./common.sh

rm -rf $TGT

mkdir -p $PACKAGE
mkdir -p "$TGT/DEBIAN"
mkdir -p "$TGT/usr/local/bin"
mkdir -p "$TGT/usr/local/etc"

# copy source files
install -m755 "$SRC"/raspiBackup.sh $TGT/usr/local/bin/raspiBackup.sh
install -m755 "$SRC"/raspiBackupInstallUI.sh $TGT/usr/local/bin/raspiBackupInstallUI.sh
install -m600 "$SRC"/raspiBackup_de.conf $TGT/usr/local/etc/raspiBackup_de.conf
install -m600 "$SRC"/raspiBackup_en.conf $TGT/usr/local/etc/raspiBackup.conf

# create links
cd $TGT/usr/local/bin
ln -s -r raspiBackup.sh raspiBackup
ln -s -r raspiBackupInstallUI.sh raspiBackupInstallUI
cd "$CURRENT_DIR"
tar -x -f "$SRC"/raspiBackupSampleExtensions.tgz -C $TGT/usr/local/bin

# create DEBIAN package files
envsubst < $PACKAGE/DEBIAN/control > /tmp/control
install -m755  /tmp/control $TGT/DEBIAN/control
rm /tmp/control
install -m755  $PACKAGE/DEBIAN/postinst $TGT/DEBIAN
install -m755  $PACKAGE/DEBIAN/postrm $TGT/DEBIAN
install -m755  $PACKAGE/DEBIAN/conffiles $TGT/DEBIAN

function show() {
	local l=${#1}
	local s
	s=$(printf '=%.0s' $(seq 1 $(( l+8 )) ) )
	echo "$s"
	echo "=== $* ==="
	echo "$s"
}

#trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT
trap 'err $?' ERR

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm build.log || true
show "Establish gpg ..."
KEYID=4B9E02DBACA4DD24
# Export public key
# gpg --armor --export $KEYID > $KEYID.pub.asc

show "Build package"
dpkg-deb --root-owner-group --build $TGT $PACKAGE/raspiBackup.deb

show "Sign raspiBackup package"
gpg --verbose --yes --detach-sign -u $KEYID $PACKAGE/raspiBackup.deb

show "Show files which will be installed"
dpkg-deb -c $PACKAGE/raspiBackup.deb

show "raspiBackup package information"
dpkg-deb -I $PACKAGE/raspiBackup.deb
