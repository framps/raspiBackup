#!/bin/bash
#

set -euo pipefail

source common.sh

#trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT
trap 'err $?' ERR

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm build.log || true
show "Establish gpg ..."
DEBFULLNAME=framp
DEBEMAIL=framp@linux-tips-and-tricks.de
#KEYID=8517A08D66D5D9B6
DEBSIGN_KEYID=4B9E02DBACA4DD24
# Export public key
# gpg --armor --export 8517A08D66D5D9B6 > 8517A08D66D5D9B6.pub.asc
show "Build package"
dpkg-deb --root-owner-group --build raspiBackup_0.7.2
show "Sign package"
debsigs --sign origin -k $DEBSIGN_KEYID raspiBackup_0.7.2.deb
show "Extract sign"
gpg --yes --detach-sign raspiBackup_0.7.2.deb
# debsign raspibackup_0.7.2.deb
show "Show files which will be installed"
dpkg-deb -c raspiBackup_0.7.2.deb



