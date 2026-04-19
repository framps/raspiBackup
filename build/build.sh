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
KEYID=4B9E02DBACA4DD24
# Export public key
# gpg --armor --export $KEYID > $KEYID.pub.asc

show "Build package"
dpkg-deb --root-owner-group --build raspiBackup_0.7.2

show "Sign package"
gpg --verbose --yes --detach-sign -u $KEYID raspiBackup_0.7.2.deb

show "Show files which will be installed"
dpkg-deb -c raspiBackup_0.7.2.deb



