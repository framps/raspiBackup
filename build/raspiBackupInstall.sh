#!/bin/bash
# vim: set ts=4 sts=4 expandtab:
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

readonly REPO_OWNER="${REPO_OWNER:-framps}"
readonly REPO_OWNER_GPG_FINGERPRINT="${REPO_OWNER_GPG_FINGERPRINT:-23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24}"
readonly BRANCH="${BRANCH:-master}"

readonly RASPIBACKUP=raspiBackup
readonly PACKAGE_NAME=raspibackup

readonly GITHUB_URL_VERSION="https://raw.githubusercontent.com/${REPO_OWNER}/${RASPIBACKUP}/refs/heads/${BRANCH}/build/deb"
readonly GITHUB_URL_DEB="https://github.com/${REPO_OWNER}/${RASPIBACKUP}/raw/refs/heads/${BRANCH}/build/deb"

MYSELF=$(basename "$0")


usage() {
    cat <<-EOF_USAGE
Installation script for ${RASPIBACKUP}

It executes the following steps (could be done manually as well, of course):

    - download the ${RASPIBACKUP} Debian package named '${PACKAGE_NAME}'
      and its signature file from the appropriate GitHub repo
    - download and import the package maintainer's public GPG key
    - verify the package against the signature/key
    - install the package via
          'sudo apt-get install --allow-downgrades ${PACKAGE_NAME}'

Usage:

    ${MYSELF} [-v|--verbose] [<directory>]


The option '-v|--verbose' lets the script print more details
about the steps taken. In case the user would like to learn a bit or
to check the results manually...

The optional argument <directory> specifies an existing directory
with the already downloaded Debian package and its signature file.
Use '.' for the current directory.

Additionally the download source can be modified by setting the environment:

    Variable                     | Default value
    -----------------------------|-----------------------------------------
    REPO_OWNER                   | framps
    REPO_OWNER_GPG_FINGERPRINT   | 23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24
    BRANCH                       | master


Note:

    The former script 'raspiBackupInstallUI' no longer exists as such
    and has been (will be) replaced by 'raspiBackupConfig'.

    'raspiBackupConfig' can be used after installation
    to configure ${RASPIBACKUP} for individual needs.

EOF_USAGE
}


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
    local default choices answer
    default=y
    choices="Yn"
    if [[ "$1" == -n ]] ; then
        shift
        default=n
        choices="yN"
    fi

    read -r -s -n 1 -p "$* [${choices}] " answer

    # The -s above and the following echo "..." handle
    #   - a single 'Enter' keystroke with its newline
    #   - compared to the missing newline otherwise
    echo "${answer}"
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
        echo ""
        echo "??? Installation failed (or has been cancelled)"
        echo "!!! Check $LOG_FILE for details"
    fi
}

check_required_tools() {
    local req_cmd cmd pkg is_debian

    for req_cmd in  curl@curl  gpg@gnupg ; do
        cmd="${req_cmd%@*}"
        pkg="${req_cmd#*@}"
        if ! command -v "${cmd}" > /dev/null ; then
            echo ""
            echo "Problem: Required command '${cmd}' is not installed!"
            ask_yes_no -n "Should '${cmd}' from package '${pkg}' being installed now (otherwise you have to do it manually)?" || return 42
            echo "--- Installing '${pkg}'"
            sudo apt-get install "${pkg}"
        fi
    done

    # And what about 'apt/apt-get'? Is this a Debian system?
    is_debian=y
    command -v apt-get > /dev/null || is_debian=n
    grep -e "^ID=" -e "^ID_LIKE=" /etc/os-release | grep "debian" > /dev/null || is_debian=n
    if [[ "$is_debian" != y ]] ; then
        echo "Doesn't seem to be a Debian system. This script won't work!"
        return 42
    fi
}

get_gpg_key() {
    # Retrieve and import ${REPO_OWNER} gpg key from github if it doesn't exist already in keyring
    if ! gpg --no-options --list-keys "${REPO_OWNER_GPG_FINGERPRINT}" > /dev/null; then
        echo ""
        if (( VERBOSE )) ; then
            echo "    > The repo owners GPG key isn't in the local keyring, checked via command:"
            echo "    >     gpg --list-keys ${REPO_OWNER_GPG_FINGERPRINT}"
            echo ""
        fi

        echo "--- Retrieving ${REPO_OWNER}'s GPG key from https://github.com/${REPO_OWNER}.gpg"

        if (( VERBOSE )) ; then
            echo ""
            echo "    > That's not optimal because it's the same source as the complete package."
            echo "    > If that source is untrusted/hacked the verification against this key might be too."
            echo "    >"
            echo "    > It would be better to download ${REPO_OWNER}'s GPG key from elsewhere and check it carefully manually."
            echo "    > For example from ${REPO_OWNER}'s web site (might be not yet available there!)."
            echo "    > Check the fingerprint at least!"  # TODO: What else should/can be recommended?
            echo "    >"
            echo "    > Then you could import the key into your local keyring using the command:"
            echo "    >     gpg --import <downloaded-keyfile.gpg>"
        fi

        echo ""
        curl -fsSLO https://github.com/"${REPO_OWNER}".gpg
        gpg --show-keys "${REPO_OWNER}".gpg
        echo ""
        echo "Please check the fingerprint(s) above against ${REPO_OWNER_GPG_FINGERPRINT}"
        echo ""
        ask_yes_no -n "Is that key / are those keys okay to be imported into your local keyring" || return 42  # TODO: What to do better here?
        echo ""
        echo "--- Importing ${REPO_OWNER} GPG key (showing the shortened fingerprint only)"
        # The import could print the following messages if there is no .gnupg directory existing yet:
        #     gpg: keyblock resource '/home/username/.gnupg/pubring.kbx': No such file or directory
        #     gpg: Fatal: /home/username/.gnupg: directory does not exist!
        #     gpg: directory '/home/username/.gnupg' created
        #     gpg: keybox '/home/username/.gnupg/pubring.kbx' created
        #     gpg: /home/username/.gnupg/trustdb.gpg: trustdb created
        gpg --import  "${REPO_OWNER}".gpg
        echo ""
        echo "The downloaded and already imported key file '${REPO_OWNER}.gpg' is no longer needed."
        ask_yes_no "Should it be deleted now?" && rm -f "${REPO_OWNER}".gpg
    fi
}

download_package_files() {
    echo ""
    VERSION_FILES=$(curl -fsS "${GITHUB_URL_VERSION}/VERSION")
    if [[ -z "${VERSION_FILES}" ]] ; then
        echo "Error: The repository/branch doesn't have the required file '${GITHUB_URL_VERSION}/VERSION' (yet)!"
        return 42
    fi
    echo "--- Downloading ${PACKAGE_NAME}${VERSION_FILES} Debian package from github.com/${REPO_OWNER}"
    if (( VERBOSE )) ; then
        echo "    > Found VERSION file at ${GITHUB_URL_VERSION}/VERSION"
        echo "    >     with contents: ${VERSION_FILES}"
        echo "    > Downloading using the commands:"
        echo "    >     curl -fsSLO ${GITHUB_URL_DEB}/${PACKAGE_NAME}${VERSION_FILES}.deb"
        echo "    >     curl -fsSLO ${GITHUB_URL_DEB}/${PACKAGE_NAME}${VERSION_FILES}.deb.sig"
    fi
    curl -fsSLO "${GITHUB_URL_DEB}/${PACKAGE_NAME}${VERSION_FILES}.deb" || return 42
    curl -fsSLO "${GITHUB_URL_DEB}/${PACKAGE_NAME}${VERSION_FILES}.deb.sig" || return 42
    # Create unversioned links for some easier handling  TODO: not yet foolproof!
    ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb" "${PACKAGE_NAME}.deb"
    ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}.deb.sig"
}

use_provided_or_download_packages() {
    if [[ -n "$1" && -d "$1" ]]; then
        cd "$1" || return 42
        if [[ ! -f "${PACKAGE_NAME}.deb" ]]; then
            echo "??? $1/${PACKAGE_NAME}.deb not found"
            return 42
        fi
        if [[ ! -f "${PACKAGE_NAME}.deb.sig" ]]; then
            echo "??? $1/${PACKAGE_NAME}.deb.sig not found"
            return 42
        fi
    else
        download_package_files || return $?
    fi
}

verify_package() {
    echo ""
    echo "--- Verifying Debian package was created by the package maintainer '${REPO_OWNER}'"

    # Note: If the key to be verified isn't in the local keyring at all, the verfication would fail like shown below.
    #       But that shouldn't happen here, because the key has been imported earlier in this script.
    #       (What about a faked/wrong and therefore not imported signature???)
    #
    #     gpg: Signatur vom Di 15 Sep 2026 21:58:04 CEST
    #     gpg:                mittels RSA-Schlüssel 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
    #     gpg: Signatur kann nicht geprüft werden: Kein öffentlicher Schlüssel
    #
    #     gpg: Signature made Tue Sep 15 21:58:04 2026 CEST
    #     gpg:                using RSA key 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
    #     gpg: Can't check signature: No public key
    #
    #     [GNUPG:] NEWSIG
    #     [GNUPG:] ERRSIG OPQRSTUVWXYZ1234  1 10 00 1789502284 9 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
    #     [GNUPG:] NO_PUBKEY OPQRSTUVWXYZ1234
    #     [GNUPG:] FAILURE gpg-exit 33554433

    if (( VERBOSE )) ; then
        echo "    > using command:"
        echo "    >     gpg --batch --verify ${PACKAGE_NAME}${VERSION_FILES}.deb.sig  ${PACKAGE_NAME}${VERSION_FILES}.deb"
        echo "    >"
        if ! gpg --batch --verify "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}${VERSION_FILES}.deb" 2>&1 | sed -e 's/^/    > /' ; then
            echo "ERROR!"
        fi
    fi

    gpgresult=$(gpg --batch --status-fd 1 --verify "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}${VERSION_FILES}.deb"  2>/dev/null)

    if grep "^\[GNUPG:\] GOODSIG " <(echo "${gpgresult}") >/dev/null ; then
        # echo "GOOD SIGNATURE"
        if ! grep "^\[GNUPG:\] VALIDSIG " <(echo "${gpgresult}") >/dev/null ; then
            # echo "SIGNATURE IS VALID"
        # else
            echo ""
            echo "OOPS, SIGNATURE IS NOT VALID?????"
            if ! (( VERBOSE )) ; then
                echo ""
                gpg --batch --verify "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}${VERSION_FILES}.deb"
            fi
            exit 42
        fi
        if (( VERBOSE )) ; then
            if grep "^\[GNUPG:\] TRUST_UNDEFINED " <(echo "${gpgresult}") >/dev/null ; then
                echo ""
                echo "The signature is good and valid but as GPG's warning above indicates:"
                echo ""
                echo "The key has not been checked(?!) and then *signed with trust state* in the local keyring by yourself."
                echo "That is no problem, it's recommended to do that but it is optional."
                echo "TODO: Describe procedure here!?"

                # Since the installation and the signature check will happen
                # on random Raspberry Pis that will be the usual situation
                # and is therefore acceptable.
                # Ideally the user checks the output of the above command manually
                # against another source, e.g. the homepage of framp (...)
                # where his correct GPG key could be displayed.
            fi
        fi
    else
        echo "OOPS, SIGNATURE IS NOT GOOD!!!???"
        if ! (( VERBOSE )) ; then
            echo ""
            gpg --batch --verify "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}${VERSION_FILES}.deb"
        fi
        exit 42
    fi

    # Here are two example outputs of the above commands (in German and English)
    # with the important parts marked with '^':
    #
    # gpg --batch --verify package.deb.sig" package.deb"
    #
    #     gpg: Signatur vom Do 10 Sep 2026 21:08:26 CEST
    #     gpg:                mittels EDDSA-Schlüssel 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
    #                                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    #     gpg: Korrekte Signatur von "Name <mail@someserver.com>" [unbekannt]
    #          ^^^^^^^^^^^^^^^^^      ^^^^^^^^^^^^^^^^^^^^^^^^^^
    #     gpg: WARNUNG: Dieser Schlüssel trägt keine vertrauenswürdige Signatur!
    #     gpg:          Es gibt keinen Hinweis, daß die Signatur wirklich dem vorgeblichen Besitzer gehört.
    #     Haupt-Fingerabdruck  = 1234 5678 90AB CDEF GHIJ  KLMN OPQR STUV WXYZ 1234
    #
    #
    #
    #     gpg: Signature made Tue Sep 15 21:58:04 2026 CEST
    #     gpg:                using RSA key 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
    #                                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    #     gpg: Good signature from "Name <mail@someserver.com>" [unknown]
    #          ^^^^^^^^^^^^^^       ^^^^^^^^^^^^^^^^^^^^^^^^^^
    #     gpg: WARNING: This key is not certified with a trusted signature!
    #     gpg:          There is no indication that the signature belongs to the owner.
    #     Primary key fingerprint: 1234 5678 90AB CDEF GHIJ  KLMN OPQR STUV WXYZ 1234
    #
    # Or in machine readable format:
    #
    # gpg --batch --status-fd 1 --verify package.deb.sig" package.deb"  2>/dev/null
    #
    #     [GNUPG:] NEWSIG
    #     [GNUPG:] KEY_CONSIDERED 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234 0
    #     [GNUPG:] SIG_ID xxxxyyyghtqqgssnn87aj111889 2026-09-15 1789502284
    #     [GNUPG:] GOODSIG OPQRSTUVWXYZ1234 name <mail@someserver.com>
    #     [GNUPG:] VALIDSIG 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234 2026-09-15 1789502284 0 4 0 1 10 00 1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ1234
    #     [GNUPG:] TRUST_UNDEFINED 0 pgp
}

install_package() {
    local version
    version=$(dpkg -I ${PACKAGE_NAME}.deb | grep "^ Version" | cut -f 3 -d ' ')

    echo ""
    if ! ask_yes_no  -n "--- Installing ${RASPIBACKUP} ${version}. Are you sure?" ; then
        echo "!!! Installation of ${RASPIBACKUP} ${version} cancelled by user."
        return 42
    fi

    echo ""
    echo "--- Installing ${RASPIBACKUP} package and all dependencies"
    if (( VERBOSE )) ; then
        echo "    > using command:"
        echo "    >     sudo apt-get install --allow-downgrades -y ./${PACKAGE_NAME}${VERSION_FILES}.deb"
    fi
    if ! sudo apt-get install --allow-downgrades -y "./${PACKAGE_NAME}${VERSION_FILES}.deb" ; then
    ## TODO: !!! interferes with dpkg's interactive dialogs: | tee -a "$LOG_FILE" 2>&1
    ## TODO: --allow-downgrades might be dangerous. See 'man apt-get'
        return $?
    fi

    dpkg --list | grep ${PACKAGE_NAME} | awk '{ print "--- ${PACKAGE_NAME}", $3, "installed successfully"; }'

    # Due to systemd components in the installed debian package there is the following warning shown by apt-get:
    #
    #   Warning: The unit file, source configuration file or drop-ins of raspiBackup.service changed on disk.
    #            Run 'systemctl daemon-reload' to reload units.
    #
    # So doing as advised now:
    echo "--- Reload systemd units"
    sudo systemctl daemon-reload
}


# TODO: Really trap ERR in this script at all?
trap 'err $?' ERR
trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

# enable logging
exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

VERBOSE=0
while true ; do
    case "$1" in
           -h|--help) usage
                      exit 0
                      ;;
        -v|--verbose) VERBOSE=1
                      shift
                      continue
                      ;;
    esac

    if [[ "$1" =~ ^- ]] ; then
        echo "Error: Unknown option '$1'!"
        exit 42
    fi

    break
done

rm -f "$LOG_FILE"

check_required_tools || exit $?

get_gpg_key || exit $?
use_provided_or_download_packages "$@" || exit $?

# Handle errors manually from here on. Seems to be better (for the user...) TODO: Checkup
trap '' ERR

verify_package || exit $?
install_package || exit $?


cat <<EOF_RBC

To configure ${RASPIBACKUP} for individual needs there will be a tool
named "raspiBackupConfig"...
EOF_RBC

