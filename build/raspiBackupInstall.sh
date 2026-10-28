#!/bin/bash
# vim: set ts=4 sts=4 expandtab:
#######################################################################################################################
#
# Script to install raspiBackup from its signed apt repository
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
# The trust anchor: Only a repository signed with this key is accepted
readonly REPO_OWNER_GPG_FINGERPRINT="${REPO_OWNER_GPG_FINGERPRINT:-23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24}"

readonly RASPIBACKUP=raspiBackup
readonly PACKAGE_NAME=raspibackup

readonly REPO_URL="${REPO_URL:-https://${REPO_OWNER}.github.io/${RASPIBACKUP}}"
readonly REPO_SUITE="${REPO_SUITE:-stable}"
readonly REPO_COMPONENT="${REPO_COMPONENT:-main}"

readonly KEYRING="/usr/share/keyrings/${PACKAGE_NAME}-archive-keyring.gpg"
readonly SOURCES="/etc/apt/sources.list.d/${PACKAGE_NAME}.sources"

MYSELF=$(basename "$0")


usage() {
    cat <<-EOF_USAGE
Installation script for ${RASPIBACKUP}

It executes the following steps (could be done manually as well, of course):

    - download the package maintainer's public GPG key and accept it only
      if its fingerprint is ${REPO_OWNER_GPG_FINGERPRINT}
    - store the key in ${KEYRING}
    - add the ${RASPIBACKUP} apt repository in ${SOURCES},
      trusting only this key for this repository (Signed-By)
    - install the package via 'sudo apt-get install ${PACKAGE_NAME}'

apt verifies the repository signature and the package checksums then.
Later updates are installed with 'sudo apt-get update && sudo apt-get upgrade'.

Usage:

    ${MYSELF} [-v|--verbose] [-y|--yes] [<file.deb>]

The option '-v|--verbose' lets the script print more details
about the steps taken. In case the user would like to learn a bit or
to check the results manually...

The option '-y|--yes' doesn't ask for confirmation.

The optional argument <file.deb> installs an already downloaded package
without adding the repository. Its signature is expected in <file.deb>.sig
and is verified against the key above. Updates have to be installed manually then.

Additionally the download source can be modified by setting the environment:

    Variable                     | Default value
    -----------------------------|-----------------------------------------
    REPO_OWNER                   | framps
    REPO_OWNER_GPG_FINGERPRINT   | 23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24
    REPO_URL                     | https://<REPO_OWNER>.github.io/${RASPIBACKUP}
    REPO_SUITE                   | stable
    REPO_COMPONENT               | main

To uninstall ${RASPIBACKUP} and remove the repository:

    sudo apt-get purge ${PACKAGE_NAME}
    sudo rm ${SOURCES} ${KEYRING}

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

    if (( ASSUME_YES )) ; then
        echo "$* [${choices}] y"
        return 0
    fi

    # read from terminal, stdin might be the script itself (curl ... | bash)
    read -r -s -n 1 -p "$* [${choices}] " answer < /dev/tty

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
    rm -rf "${TMP_DIR}"
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

    # And what about 'apt/apt-get'? Is this a Debian system?
    is_debian=y
    command -v apt-get > /dev/null || is_debian=n
    grep -e "^ID=" -e "^ID_LIKE=" /etc/os-release | grep "debian" > /dev/null || is_debian=n
    if [[ "$is_debian" != y ]] ; then
        echo "Doesn't seem to be a Debian system. This script won't work!"
        return 42
    fi

    for req_cmd in  curl@curl  gpg@gnupg ; do
        cmd="${req_cmd%@*}"
        pkg="${req_cmd#*@}"
        if ! command -v "${cmd}" > /dev/null ; then
            echo ""
            echo "Problem: Required command '${cmd}' is not installed!"
            ask_yes_no -n "Should '${cmd}' from package '${pkg}' being installed now (otherwise you have to do it manually)?" || return 42
            echo "--- Installing '${pkg}'"
            $SUDO apt-get install -y "${pkg}"
        fi
    done
}

get_gpg_key() {
    # Download the key and keep only the key with the expected fingerprint.
    # Uses a temporary GPG home, the user's keyring isn't touched.
    local keyfile="${TMP_DIR}/${PACKAGE_NAME}-archive-keyring.gpg"
    local validity

    echo ""
    echo "--- Retrieving ${REPO_OWNER}'s GPG key from ${REPO_URL}"
    if (( VERBOSE )) ; then
        echo "    > using command:"
        echo "    >     curl -fsSL ${REPO_URL}/${PACKAGE_NAME}-archive-keyring.gpg"
    fi
    curl -fsSL "${REPO_URL}/${PACKAGE_NAME}-archive-keyring.gpg" -o "${keyfile}" || return 42

    export GNUPGHOME="${TMP_DIR}/gnupg"
    mkdir -m 700 "${GNUPGHOME}"
    gpg --batch --quiet --import "${keyfile}" 2>/dev/null || true

    if ! gpg --batch --with-colons --list-keys "${REPO_OWNER_GPG_FINGERPRINT}" 2>/dev/null \
            | grep -q "^fpr:::::::::${REPO_OWNER_GPG_FINGERPRINT}:" ; then
        echo ""
        echo "??? The downloaded key doesn't have the expected fingerprint ${REPO_OWNER_GPG_FINGERPRINT}"
        echo "??? Somebody might have tampered with the key. Installation aborted!"
        echo ""
        gpg --show-keys "${keyfile}" || true
        return 42
    fi

    validity="$(gpg --batch --with-colons --list-keys "${REPO_OWNER_GPG_FINGERPRINT}" | awk -F: '$1 == "pub" { print $2 }')"
    if [[ "${validity}" =~ [rei] ]] ; then
        echo "??? The key ${REPO_OWNER_GPG_FINGERPRINT} is revoked, expired or invalid. Installation aborted!"
        return 42
    fi

    # export just this key, anything else contained in the download is dropped
    gpg --batch --export "${REPO_OWNER_GPG_FINGERPRINT}" > "${TMP_DIR}/keyring.gpg"

    echo "--- Key accepted:"
    gpg --batch --list-keys --keyid-format long "${REPO_OWNER_GPG_FINGERPRINT}" | sed -e 's/^/    /'
}

add_repository() {
    echo "--- Installing key in ${KEYRING}"
    $SUDO install -m 644 -D "${TMP_DIR}/keyring.gpg" "${KEYRING}"

    echo "--- Adding repository ${REPO_URL} in ${SOURCES}"
    $SUDO tee "${SOURCES}" > /dev/null <<-EOF_SOURCES
Types: deb
URIs: ${REPO_URL}
Suites: ${REPO_SUITE}
Components: ${REPO_COMPONENT}
Signed-By: ${KEYRING}
EOF_SOURCES
    $SUDO chmod 644 "${SOURCES}"
    if (( VERBOSE )) ; then
        sed -e 's/^/    > /' "${SOURCES}"
        echo "    > Signed-By: apt accepts this repository only if it's signed with the key in ${KEYRING}"
        echo "    >            and that key isn't trusted for any other repository."
    fi

    echo ""
    echo "--- Updating package lists (verifies the repository signature)"
    # Only refresh the raspiBackup repository, the system ones don't matter here
    mkdir -p "${TMP_DIR}/empty"
    if ! $SUDO apt-get update \
            -o Dir::Etc::sourcelist="${SOURCES}" \
            -o Dir::Etc::sourceparts="${TMP_DIR}/empty" \
            -o APT::Get::List-Cleanup="0" ; then
        echo "??? The repository couldn't be read or its signature isn't valid"
        return 42
    fi
}

install_from_repository() {
    local version
    version="$(apt-cache policy "${PACKAGE_NAME}" | awk '$1 == "Candidate:" { print $2 }')"
    if [[ -z "${version}" || "${version}" == "(none)" ]] ; then
        echo "??? Package ${PACKAGE_NAME} not found in repository ${REPO_URL}"
        return 42
    fi

    echo ""
    if ! ask_yes_no -n "--- Installing ${RASPIBACKUP} ${version}. Are you sure?" ; then
        echo "!!! Installation of ${RASPIBACKUP} ${version} cancelled by user."
        return 42
    fi

    echo ""
    echo "--- Installing ${RASPIBACKUP} package and all dependencies"
    if (( VERBOSE )) ; then
        echo "    > using command:"
        echo "    >     sudo apt-get install -y ${PACKAGE_NAME}"
    fi
    # dependencies come from the system repositories which might be outdated
    $SUDO apt-get update > /dev/null || true
    $SUDO apt-get install -y "${PACKAGE_NAME}" || return 42
}

verify_local_package() {
    # $1 deb file, signature in $1.sig
    local deb="$1" signer
    echo ""
    echo "--- Verifying $(basename "${deb}") was created by the package maintainer '${REPO_OWNER}'"

    if [[ ! -f "${deb}.sig" ]] ; then
        echo "??? Signature file ${deb}.sig not found"
        return 42
    fi

    if (( VERBOSE )) ; then
        echo "    > using command:"
        echo "    >     gpg --verify ${deb}.sig ${deb}"
        gpg --batch --verify "${deb}.sig" "${deb}" 2>&1 | sed -e 's/^/    > /' || true
    fi

    # VALIDSIG <signing key fpr> ... <primary key fpr>, only the downloaded key is in GNUPGHOME
    signer="$(gpg --batch --status-fd 1 --verify "${deb}.sig" "${deb}" 2>/dev/null \
        | awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }')" || true

    if [[ "${signer}" != "${REPO_OWNER_GPG_FINGERPRINT}" ]] ; then
        echo "??? SIGNATURE IS NOT VALID. The package wasn't created by ${REPO_OWNER} or was modified!"
        if ! (( VERBOSE )) ; then
            gpg --batch --verify "${deb}.sig" "${deb}" || true
        fi
        return 42
    fi
    echo "--- Signature is valid"
}

install_local_package() {
    local deb version
    deb="$(realpath "$1")"
    version="$(dpkg-deb -f "${deb}" Version)"

    echo ""
    if ! ask_yes_no -n "--- Installing ${RASPIBACKUP} ${version}. Are you sure?" ; then
        echo "!!! Installation of ${RASPIBACKUP} ${version} cancelled by user."
        return 42
    fi

    echo ""
    echo "--- Installing ${RASPIBACKUP} package and all dependencies"
    if (( VERBOSE )) ; then
        echo "    > using command:"
        echo "    >     sudo apt-get install --allow-downgrades -y ${deb}"
    fi
    $SUDO apt-get update > /dev/null || true
    $SUDO apt-get install --allow-downgrades -y "${deb}" || return 42
}

finish() {
    dpkg-query -W -f '--- ${Package} ${Version} installed successfully\n' "${PACKAGE_NAME}"

    # Due to systemd components in the installed debian package there is the following warning shown by apt-get:
    #
    #   Warning: The unit file, source configuration file or drop-ins of raspiBackup.service changed on disk.
    #            Run 'systemctl daemon-reload' to reload units.
    #
    # So doing as advised now:
    if command -v systemctl > /dev/null ; then
        echo "--- Reload systemd units"
        $SUDO systemctl daemon-reload || true
    fi
}


VERBOSE=0
ASSUME_YES=0
while (( $# > 0 )) ; do
    case "$1" in
           -h|--help) usage
                      exit 0
                      ;;
        -v|--verbose) VERBOSE=1
                      shift
                      continue
                      ;;
            -y|--yes) ASSUME_YES=1
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

LOCAL_DEB="$1"
if [[ -n "${LOCAL_DEB}" && ! -f "${LOCAL_DEB}" ]] ; then
    echo "Error: Package file '${LOCAL_DEB}' not found!"
    exit 42
fi

SUDO=""
if (( EUID != 0 )) ; then
    SUDO="sudo"
fi

TMP_DIR="$(mktemp -d)"

trap 'err $?' ERR
trap 'cleanup $?' SIGINT SIGTERM SIGHUP EXIT

# enable logging
rm -f "$LOG_FILE"
exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

check_required_tools || exit $?
get_gpg_key || exit $?

# Handle errors manually from here on. Seems to be better (for the user...)
trap '' ERR

if [[ -n "${LOCAL_DEB}" ]] ; then
    verify_local_package "${LOCAL_DEB}" || exit $?
    install_local_package "${LOCAL_DEB}" || exit $?
else
    add_repository || exit $?
    install_from_repository || exit $?
fi
finish

cat <<EOF_RBC

To configure ${RASPIBACKUP} for individual needs use

    sudo raspiBackupInstallUI
EOF_RBC
