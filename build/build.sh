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

version="0.7.2"
TGT="./src"
PACKAGE="./package"

SRC="$HOME/depl"
CURRENT_DIR=$PWD

rm -rf $TGT

mkdir -p $PACKAGE
mkdir -p "$TGT/DEBIAN"
mkdir -p "$TGT/usr/local/bin"
mkdir -p "$TGT/usr/local/etc"

# copy files
install -Dm665 $SRC/raspiBackup.sh "$TGT/usr/local/bin/raspiBackup.sh"
install -Dm665 $SRC/raspiBackupInstallUI.sh "$TGT/usr/local/bin/raspiBackupInstallUI.sh"
install -Dm664 $SRC/raspiBackup_de.conf "$TGT/usr/local/etc/raspiBackup_de.conf"
install -Dm664 $SRC/raspiBackup_en.conf "$TGT/usr/local/etc/raspiBackup_en.conf"
# create links
cd $TGT/usr/local/bin
ln -s -r raspiBackup.sh raspiBackup
ln -s -r raspiBackupInstallUI.sh raspiBackupInstallUI
cd $CURRENT_DIR

cat > "$TGT/DEBIAN/control" <<EOF
Package: raspiBackup
Version: $version
Section: base
Priority: optional
Architecture: all
Depends: bash,parted,e2fsprogs,rsync,whiptail,dosfstools,fdisk,util-linux,fdisk,curl
Maintainer: framp <framp@linux-tips-and-tricks.de>
Description: Hello world
EOF

cat > "$TGT/DEBIAN/postinst" <<"EOF"
#!/bin/bash

function containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

SUPPORTED_LANGUAGES=("EN" "DE" "FI" "FR" "ZH")

[[ -z "${LANG}" ]] && LANG="en_US.UTF-8"
LANG_EXT="${LANG,,*}"
LANG_SYSTEM="${LANG_EXT:0:2}"
if ! containsElement "${LANG_SYSTEM^^*}" "${SUPPORTED_LANGUAGES[@]}"; then
        LANG_SYSTEM="en"
fi

echo "Configuring raspiBackup.conf"
mv /usr/local/etc/raspiBackup_$LANG_SYSTEM.conf /usr/local/etc/raspiBackup.conf
chmod 660 /usr/local/etc/raspiBackup.conf
rm /usr/local/etc/raspiBackup_*
EOF
chmod 775 $TGT/DEBIAN/postinst

cat > "$TGT/DEBIAN/postrm" <<"EOF"
#!/bin/bash

echo "Cleaning up temp dir"
rm -f /tmp/raspiBackup*
EOF
chmod 775 $TGT/DEBIAN/postrm

source common.sh

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
dpkg-deb --root-owner-group --build $TGT $PACKAGE/raspiBackup_0.7.2.deb

show "Sign package"
gpg --verbose --yes --detach-sign -u $KEYID $PACKAGE/raspiBackup_0.7.2.deb

show "Show files which will be installed"
dpkg-deb -c $PACKAGE/raspiBackup_0.7.2.deb
