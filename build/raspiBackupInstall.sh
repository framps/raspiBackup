#!/bin/bash
#######################################################################################################################
#
# Script to download and install the raspiBackup package
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
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

set -eo pipefail

LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE

# REPO_OWNER=framps
# REPO_OWNER_GPG_FINGERPRINT=4B9E02DBACA4DD24
# BRANCH=master
REPO_OWNER=rpi-simonz
REPO_OWNER_GPG_FINGERPRINT=367CB21160F2403E
BRANCH=m_972

readonly REPO_OWNER
readonly REPO_OWNER_GPG_FINGERPRINT
readonly BRANCH

RASPIBACKUP=raspiBackup
PACKAGE_NAME=raspibackup
readonly RASPIBACKUP
readonly PACKAGE_NAME

GITHUB_URL_VERSION="https://raw.githubusercontent.com/${REPO_OWNER}/${RASPIBACKUP}/refs/heads/${BRANCH}/build/deb"
GITHUB_URL_DEB="https://github.com/${REPO_OWNER}/${RASPIBACKUP}/raw/refs/heads/${BRANCH}/build/deb"
readonly GITHUB_URL_VERSION
readonly GITHUB_URL_DEB


err() {
	local rc="$1"
	echo ""
	echo "??? Unexpected error occured with RC $rc"
	local i=0
	local FRAMES=${#BASH_LINENO[@]}
	for ((i = FRAMES - 2; i >= 0; i--)); do
		echo '  File' \""${BASH_SOURCE[i + 1]}"\", line ${BASH_LINENO[i]}, in "${FUNCNAME[i + 1]}"
		sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i + 1]}"
	done
	exit 42
}

ask_yes_no() {
	# $1 -n  set "no" as default, else it's "yes"
	# $2.. prompt
	local default choices
	default=y
	choices="Yn"
	if [[ "$1" == -n ]] ; then
		shift
		default=n
		choices="yN"
	fi

	read -r -n 1 -p "$* [${choices}] " answer

	if [[ "${answer}" =~ [yYjJ] ]] || [[ "${answer}${default}" == "y" ]]; then
		true
	else
		false
	fi
}

cleanup() {
	# Delete all(?) raspibackup package files
	# rm -f ${PACKAGE_NAME}*.deb
	# rm -f ${PACKAGE_NAME}*.deb.sig
	if (( $1 == 0 )); then
		: rm -f "$LOG_FILE"
	else
		echo "??? Installation failed (or has been cancelled)"
		echo "!!! Check $LOG_FILE for details"
	fi
}

check_required_tools() {
	if ! command -v curl > /dev/null ; then
		# TODO: Check for 'gpg' too?
		echo ""
		echo "Problem: Required command 'curl' is not installed!"
		ask_yes_no -n "Should 'curl' being installed now (otherwise you have to do it manually)?" || exit 42
		echo "--- Installing 'curl'"
		sudo apt install curl
	fi
}

get_gpg_key() {
	# retrieve and import ${REPO_OWNER} gpg key from github if it doesn't exist already in keyring
	if ! gpg --list-keys ${REPO_OWNER_GPG_FINGERPRINT} > /dev/null; then
		echo ""
		echo "--- Retrieving ${REPO_OWNER}'s GPG key from github"
		echo ""
		curl -fsSLO https://github.com/${REPO_OWNER}.gpg
		gpg --show-keys ${REPO_OWNER}.gpg
		echo ""
		ask_yes_no -n "Is that key / are those keys okay to be imported to your local keyring" || exit 42  # TODO: What to do better here?
		echo ""
		echo "--- Importing ${REPO_OWNER} key"
		gpg --import  ${REPO_OWNER}.gpg
		if ask_yes_no "Should the downloaded and already imported key file '${REPO_OWNER}.gpg' be deleted now?" ; then
			rm -f ${REPO_OWNER}.gpg
		fi
	fi
}

download_package_files() {
	echo ""
	VERSION_FILES=$(curl -fsS "$GITHUB_URL_VERSION/VERSION")
	if [[ -z "${VERSION_FILES}" ]] ; then
		echo "Error: The repository/branch doesn't have the required file '$GITHUB_URL_VERSION/VERSION' (yet)!"
		exit 42
	fi
	echo "--- Downloading ${PACKAGE_NAME}${VERSION_FILES} Debian package from github.com/${REPO_OWNER}"
	curl -fsSLO "$GITHUB_URL_DEB/${PACKAGE_NAME}${VERSION_FILES}.deb" || exit 42
	curl -fsSLO "$GITHUB_URL_DEB/${PACKAGE_NAME}${VERSION_FILES}.deb.sig" || exit 42
	# Create unversioned links for some easier handling  TODO: not yet foolproof!
	ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb" "${PACKAGE_NAME}.deb"
	ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}.deb.sig"
}


# TODO: Really trap ERR in this script?
trap 'err $?' ERR
trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

# enable logging
exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm -f "$LOG_FILE"

check_required_tools

get_gpg_key

if [[ -n "$1" && -d "$1" ]]; then
	cd "$1" || exit
	if [[ ! -f "${PACKAGE_NAME}.deb" ]]; then
		echo "??? $1/${PACKAGE_NAME}.deb not found"
		exit 42
	fi
	if [[ ! -f "${PACKAGE_NAME}.deb.sig" ]]; then
		echo "??? $1/${PACKAGE_NAME}.deb.sig not found"
		exit 42
	fi
else
	download_package_files
fi

# Handle errors manually from here on. Seems to be better (for the user...) TODO: Checkup
trap '' ERR

echo ""
echo "--- Verifying Debian package was created by repo owner (usually framp, or simonz during development)"
if ! gpg --verbose --verify "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}${VERSION_FILES}.deb" ; then
	echo "Error: Verification failed. TODO: What to do now?"
	exit 42
fi

# TODO: The signature verification needs to be improved!
#       The above test is okay, but only if this script here is authentic...
#       Ideally the user checks the output of the above command manually against
#       another source, e.g. the homepage of framps (...) where his correct GPG key
#       could be displayed.
#
#       Here are two example outputs of the above command (in German and English)
#       with the important parts marked with '^':
#
#           gpg: Signatur vom Do 10 Sep 2026 21:08:26 CEST
#           gpg:                mittels EDDSA-Schlüssel 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
#                                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#           gpg: verwende Vertrauensmodell pgp
#           gpg: Korrekte Signatur von "Name <mail@someserver.com>" [ultimativ]
#                ^^^^^^^^^^^^^^^^^      ^^^^^^^^^^^^^^^^^^^^^^^^^^
#           gpg: Binäre Signatur, Hashmethode SHA512, Schlüsselverfahren ed25519
#
#
#           gpg: Signature made Thu Sep 10 21:08:26 2026 CEST
#           gpg:                using EDDSA key 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
#                                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#           gpg: using pgp trust model
#           gpg: Good signature from "Name <mail@someserver.com>" [ultimate]
#                ^^^^^^^^^^^^^^       ^^^^^^^^^^^^^^^^^^^^^^^^^^
#           gpg: binary signature, digest algorithm SHA512, key algorithm ed25519


version=$(dpkg -I ${PACKAGE_NAME}.deb | grep "^ Version" | cut -f 3 -d ' ')

echo ""
if ! ask_yes_no  -n "--- Installing ${RASPIBACKUP} $version. Are you sure?" ; then
	echo ""
	echo "!!! Installation of ${RASPIBACKUP} $version cancelled by user."
	exit 0
fi

echo ""
echo "--- Installing ${RASPIBACKUP} package and all dependencies"
if sudo apt install --allow-downgrades -y "./${PACKAGE_NAME}${VERSION_FILES}.deb" ; then
## TODO: !!! interferes with dpkg's interactive dialogs: | tee -a "$LOG_FILE" 2>&1
	dpkg --list | grep ${PACKAGE_NAME} | awk '{ print "--- ${PACKAGE_NAME}", $3, "installed successfully"; }'
fi

