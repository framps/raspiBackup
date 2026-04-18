#!/bin/bash
#
function show() {
	echo "==============================="
	echo "@@@ $@ ..."
	echo "==============================="
}
show "Establish gpg ..."
export DEBFULLNAME=framp
export DEBSIGN_KEYID=8517A08D66D5D9B6
export DEBEMAIL=framp@linux-tips-and-tricks.de
# Export public key
# gpg --armor --export 8517A08D66D5D9B6 > 8517A08D66D5D9B6.pub
show "Build package"
dpkg-deb --root-owner-group --build raspiBackup_0.7.2
show "Sign package"
gpg --yes --detach-sign raspiBackup_0.7.2.deb
show "Show files which will be installed"
dpkg-deb -c raspiBackup_0.7.2.deb

./install.sh



