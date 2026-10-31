#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Test updates and reversals of the raspiBackup Debian package with apt and raspiBackupConfig
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

set -uo pipefail

usage() {
    cat <<"EOF_USAGE"
Usage:

        sudo ./testPackageUpdates.sh [options]

Builds test packages with build.sh, publishes them in a local signed apt repository
(file://, signed with a temporary GPG key) and checks with apt, raspiBackupInstall.sh
and raspiBackupConfig -U/-R that

    1. a release is updated to a new release and reverted to the previous one
    2. a beta is installed and updated only on request and reverted to the release
    3. a hotfix is updated and reverted
    4. an individual fix for one user (.deb, not in the repository) is installed,
       reverted and replaced by the next public fix or release

Only committed changes are tested: the sources are cloned from git.

At the end a summary report is displayed and saved in /tmp/raspiBackupPkgTest.*.report
(result per section, version history, packages built, failures and duration).

RUN IT ON A TEST SYSTEM ONLY (VM, spare Raspberry). It installs, downgrades and purges
the package 'raspibackup' and its dependencies. It refuses to run if raspibackup is
installed or its repository is configured, unless --force is used.
The system repositories have to be reachable to install the dependencies.

Options:

    -s | --source <ref>  git branch, tag or commit to test (default: HEAD)
    -l | --lintian       check the packages with lintian (slow)
    -f | --force         purge an installed raspibackup and remove its repository first
    -k | --keep          keep the work directory, package and repository afterwards
    -x | --fail-fast     stop at the first failed check
    -h | --help          display this short help

EOF_USAGE
}

SOURCE_REF="HEAD"
LINTIAN=0
FORCE=0
KEEP=0
FAIL_FAST=0

while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -s|--source) SOURCE_REF="${2:?missing git reference}"; shift 2 ;;
        -l|--lintian) LINTIAN=1; shift ;;
        -f|--force) FORCE=1; shift ;;
        -k|--keep) KEEP=1; shift ;;
        -x|--fail-fast) FAIL_FAST=1; shift ;;
        *) echo "Unknown option $1"; usage; exit 1 ;;
    esac
done

readonly PACKAGE_NAME=raspibackup
readonly SOURCES="/etc/apt/sources.list.d/${PACKAGE_NAME}.sources"
readonly KEYRING="/usr/share/keyrings/${PACKAGE_NAME}-archive-keyring.gpg"
readonly CONFIG="/usr/local/etc/raspiBackup.conf"
readonly RASPIBACKUP="/usr/local/bin/raspiBackup"
readonly RASPIBACKUPCONFIG="/usr/local/bin/raspiBackupConfig"
# value set in the configuration after the first installation, has to survive all version changes
readonly CONFIG_MARKER="DEFAULT_KEEPBACKUPS=13"

export LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

#######################################################################################################################
# preconditions
#######################################################################################################################

if (( EUID != 0 )); then
    echo "Run as root: sudo $0 $*"
    exit 1
fi

missing=()
for req in git@git gpg@gnupg dpkg-deb@dpkg apt-ftparchive@apt-utils envsubst@gettext-base script@bsdutils curl@curl; do
    command -v "${req%@*}" > /dev/null || missing+=("${req#*@}")
done
(( LINTIAN )) && ! command -v lintian > /dev/null && missing+=(lintian)
if (( ${#missing[@]} )); then
    echo "Missing tools. Install them with: sudo apt-get install ${missing[*]}"
    exit 1
fi

# the repository is owned by the user, not by root
git() { command git -c safe.directory='*' "$@"; }

GIT_TOP="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || exit 1
SOURCE_COMMIT="$(git -C "$GIT_TOP" rev-parse --verify "${SOURCE_REF}^{commit}")" || { echo "Unknown git reference $SOURCE_REF"; exit 1; }

if dpkg-query -W -f '${Status}' "$PACKAGE_NAME" 2>/dev/null | grep -q "installed" || [[ -e "$SOURCES" || -e "$KEYRING" ]]; then
    if (( ! FORCE )); then
        echo "$PACKAGE_NAME is installed or its repository is configured ($SOURCES, $KEYRING)."
        echo "Run this test on a test system only. Use --force to purge it and remove the repository."
        exit 1
    fi
    echo "--force: purging $PACKAGE_NAME and removing its repository"
    apt-mark unhold "$PACKAGE_NAME" > /dev/null 2>&1 || true
    apt-get purge -y "$PACKAGE_NAME" > /dev/null 2>&1 || true
    rm -f "$SOURCES" "$KEYRING"
fi

#######################################################################################################################
# work directory, cleanup and logging
#######################################################################################################################

WORK="$(mktemp -d /tmp/raspiBackupPkgTest.XXXXXX)"
readonly WORK
chmod 755 "$WORK"   # apt reads the file:// repository
readonly BUILD="$WORK/src/build"
readonly TEST_REPO_URL="file://$BUILD/repo"
readonly DEBS="$WORK/debs"
readonly LOG="$WORK/test.log"
readonly EMPTY_DIR="$WORK/empty"
mkdir -p "$DEBS" "$EMPTY_DIR"
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"

cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    gpgconf --kill all > /dev/null 2>&1 || true
    report "$rc" | tee "$REPORT"
    if (( KEEP )); then
        echo ""
        echo "Kept work directory $WORK, $PACKAGE_NAME and the repository $SOURCES"
        echo "Remove them with: sudo apt-mark unhold $PACKAGE_NAME; sudo apt-get purge -y $PACKAGE_NAME; sudo rm -rf $SOURCES $KEYRING $WORK /var/lib/apt/lists/*raspiBackupPkgTest*"
    else
        apt-mark unhold "$PACKAGE_NAME" > /dev/null 2>&1 || true
        apt-get purge -y "$PACKAGE_NAME" > /dev/null 2>&1 || true
        rm -f "$SOURCES" "$KEYRING" /var/lib/apt/lists/*raspiBackupPkgTest*
        if (( rc != 0 )); then
            cp "$LOG" "/tmp/$(basename "$WORK").log" 2>/dev/null && echo "Log saved in /tmp/$(basename "$WORK").log"
        fi
        rm -rf "$WORK"
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

CURRENT_SECTION="setup"
PASSED=0
FAILED=0
FAILURES=()
SECTIONS=()                 # sections in execution order
declare -A SEC_PASSED=()    # section -> number of passed checks
declare -A SEC_FAILED=()    # section -> number of failed checks
VERSION_HISTORY=()          # installed versions in the order they were seen
BUILT=()                    # packages built
ABORT_REASON=""
FAIL_FAST_STOP=0
START_EPOCH="$(date +%s)"
START_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
REPORT="/tmp/${WORK##*/}.report"
readonly REPORT

log() { echo "$*" >> "$LOG"; }

section() {
    SECTIONS+=("$CURRENT_SECTION")
    SEC_PASSED[$CURRENT_SECTION]=0
    SEC_FAILED[$CURRENT_SECTION]=0
    echo ""
    echo "=== $* ==="
    log ""
    log "=================== $* ==================="
}

step() {
    echo "--- $*"
    log "--- $*"
}

pass() {
    (( PASSED++ ))
    SEC_PASSED[$CURRENT_SECTION]=$(( ${SEC_PASSED[$CURRENT_SECTION]:-0} + 1 ))
    echo "    ok   $*"
    log "    ok   $*"
}

fail() {
    (( FAILED++ ))
    SEC_FAILED[$CURRENT_SECTION]=$(( ${SEC_FAILED[$CURRENT_SECTION]:-0} + 1 ))
    FAILURES+=("$CURRENT_SECTION: $*")
    echo "    FAIL $*"
    log "    FAIL $*"
    if (( FAIL_FAST )); then
        echo "Stopped at first failure (--fail-fast). See $LOG"
        FAIL_FAST_STOP=1
        KEEP=1
        exit 1
    fi
}

abort() { # unrecoverable, e.g. build failed
    ABORT_REASON="$CURRENT_SECTION: $*"
    echo "??? $*"
    log "??? $*"
    echo "See $LOG"
    KEEP=1
    exit 2
}

run() { # command - runs it, output goes into the log
    log "\$ $*"
    "$@" >> "$LOG" 2>&1
    local rc=$?
    log "rc=$rc"
    return $rc
}

noteInstalled() { # version - remember a change of the installed version for the report
    local entry="${1:-none}"
    [[ -n "$1" ]] && isHeld && entry+=" (held)"
    if (( ${#VERSION_HISTORY[@]} == 0 )) || [[ "${VERSION_HISTORY[-1]}" != "$entry" ]]; then
        VERSION_HISTORY+=("$entry")
    fi
}

report() { # rc - summary report of the test run
    local rc="$1" status section state p f duration
    duration=$(( $(date +%s) - START_EPOCH ))

    if [[ -n "$ABORT_REASON" ]]; then
        status="ABORTED"
    elif (( rc == 130 )); then
        status="INTERRUPTED"
    elif (( FAIL_FAST_STOP )); then
        status="FAILED (stopped at first failure)"
    elif (( FAILED || rc != 0 )); then
        status="FAILED"
    else
        status="PASSED"
    fi

    echo ""
    echo "======================================================================================="
    echo " raspiBackup package update test - summary report"
    echo "======================================================================================="
    printf '  %-14s %s\n' "Result:" "$status"
    printf '  %-14s %s passed, %s failed\n' "Checks:" "$PASSED" "$FAILED"
    printf '  %-14s %s (%s)\n' "Source:" "$SOURCE_REF" "${SOURCE_COMMIT:0:12}"
    printf '  %-14s %s\n' "System:" "$( (. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}") ), $(dpkg --print-architecture), $(apt-get --version 2>/dev/null | head -n 1)"
    printf '  %-14s %s\n' "Options:" "lintian=$LINTIAN force=$FORCE keep=$KEEP fail-fast=$FAIL_FAST"
    printf '  %-14s %s, %dm%02ds\n' "Started:" "$START_DATE" $(( duration / 60 )) $(( duration % 60 ))

    echo ""
    echo "  Sections:"
    printf '    %-20s %7s %7s  %s\n' "section" "passed" "failed" "status"
    for section in "${SECTIONS[@]}"; do
        p="${SEC_PASSED[$section]:-0}"
        f="${SEC_FAILED[$section]:-0}"
        if [[ -n "$ABORT_REASON" && "$ABORT_REASON" == "$section:"* ]] || \
           [[ "$section" == "$CURRENT_SECTION" && "$status" != PASSED && "$status" != FAILED ]]; then
            state="incomplete"
        elif (( f )); then
            state="FAIL"
        else
            state="ok"
        fi
        printf '    %-20s %7d %7d  %s\n' "$section" "$p" "$f" "$state"
    done

    if (( ${#BUILT[@]} )); then
        echo ""
        echo "  Packages built:"
        printf '    %s\n' "${BUILT[@]}"
    fi

    if (( ${#VERSION_HISTORY[@]} )); then
        echo ""
        echo "  Installed versions:"
        local line="   " entry
        for entry in "${VERSION_HISTORY[@]}"; do
            if (( ${#line} + ${#entry} > 85 )); then
                echo "$line ->"
                line="   "
            fi
            [[ "$line" == "   " ]] && line+=" $entry" || line+=" -> $entry"
        done
        echo "$line"
    fi

    if [[ -n "$ABORT_REASON" ]]; then
        echo ""
        echo "  Aborted: $ABORT_REASON"
    fi

    if (( ${#FAILURES[@]} )); then
        echo ""
        echo "  Failures:"
        printf '    %s\n' "${FAILURES[@]}"
    fi

    echo ""
    if (( KEEP )); then
        echo "  Log:    $LOG"
    elif (( rc != 0 )); then
        echo "  Log:    /tmp/${WORK##*/}.log"    # saved by cleanup
    fi
    echo "  Report: $REPORT"
    echo "======================================================================================="
}

#######################################################################################################################
# state checks
#######################################################################################################################

installedVersion() { dpkg-query -W -f '${Version}' "$PACKAGE_NAME" 2>/dev/null; }
isHeld() { apt-mark showhold "$PACKAGE_NAME" 2>/dev/null | grep -qx "$PACKAGE_NAME"; }

declare -A SCRIPT_VERSION=()   # Debian version -> VERSION inserted into raspiBackup

assertInstalled() { # debianVersion [held|unheld]
    local expected="$1" hold="${2:-unheld}" actual scriptVersion
    actual="$(installedVersion)"
    noteInstalled "$actual"
    if [[ "$actual" == "$expected" ]]; then
        pass "$PACKAGE_NAME $expected installed"
    else
        fail "$PACKAGE_NAME $expected expected but ${actual:-nothing} installed"
        return
    fi

    if [[ "$hold" == held ]]; then
        isHeld && pass "$expected is held" || fail "$expected isn't held"
    else
        isHeld && fail "$expected is held" || pass "$expected isn't held"
    fi

    scriptVersion="$(sed -n -E 's/^VERSION="([^"]*)".*/\1/p' "$RASPIBACKUP")"
    if [[ "$scriptVersion" == "${SCRIPT_VERSION[$expected]}" ]]; then
        pass "raspiBackup reports version $scriptVersion"
    else
        fail "raspiBackup reports version '$scriptVersion' instead of '${SCRIPT_VERSION[$expected]}'"
    fi

    if grep -qx "$CONFIG_MARKER" "$CONFIG" 2>/dev/null; then
        pass "configuration kept ($CONFIG_MARKER)"
    else
        fail "configuration changed, $CONFIG_MARKER missing in $CONFIG"
    fi
}

assertRc() { # expectedRc description command...
    local expected="$1" description="$2" rc
    shift 2
    run "$@"
    rc=$?
    if (( rc == expected )); then
        pass "$description (rc $rc)"
    else
        fail "$description: rc $rc, expected $expected"
    fi
}

assertInSuite() { # debianVersion suite|none
    local version="$1" suite="$2" suites
    suites="$(apt-cache madison "$PACKAGE_NAME" 2>/dev/null \
        | awk -F'|' -v v="$version" '{ gsub(/ /, "", $2); split($3, a, " "); split(a[2], s, "/"); if ($2 == v) print s[1] }' | sort -u | xargs)"
    if [[ "$suite" == none ]]; then
        [[ -z "$suites" ]] && pass "$version isn't in the repository" || fail "$version is in suite(s) '$suites' of the repository"
    else
        [[ "$suites" == "$suite" ]] && pass "$version is in suite $suite only" || fail "$version is in suite(s) '$suites' instead of $suite"
    fi
}

#######################################################################################################################
# actions
#######################################################################################################################

debianVersion() { # VERSION of raspiBackup -> Debian version, see build.sh
    sed -E -e 's/_/-/g' -e 's/-(alpha|beta|rc)/~\L\1/I' <<< "$1"
}

build() { # version [--no-repo] - builds the package with build.sh, adds it to the repository unless --no-repo
    local version="$1" debVersion
    shift
    debVersion="$(debianVersion "$version")"
    step "build $version (Debian version $debVersion) ${*:+($*)}"

    { cat "$BUILD/build.conf.test"; echo "VERSION_RASPIBACKUP=\"$version\""; } > "$BUILD/build.conf"
    local -a options=("$@")
    (( LINTIAN )) || options+=(--no-check)
    (cd "$BUILD" && run ./build.sh "${options[@]}") || abort "build.sh failed for $version"

    local deb="$BUILD/deb/${PACKAGE_NAME}_${debVersion}.deb"
    [[ -f "$deb" && -f "$deb.sig" ]] || abort "build.sh didn't create $deb and $deb.sig"
    [[ "$(dpkg-deb -f "$deb" Version)" == "$debVersion" ]] || abort "$deb has version $(dpkg-deb -f "$deb" Version)"
    cp "$deb" "$deb.sig" "$DEBS/"
    local where="repository"
    [[ " $* " == *" --no-repo "* ]] && where=".deb only"
    BUILT+=("$(printf '%-22s %s' "$debVersion" "$where")")
    SCRIPT_VERSION[$debVersion]="$version"
}

publish() { # version - build and add to the repository, like build.sh + publishRepo.sh
    build "$1"
    aptUpdate
}

aptUpdate() { # refresh only the raspiBackup repository
    [[ -f "$SOURCES" ]] || return 0     # not added yet by raspiBackupInstall.sh
    run apt-get update -o Dir::Etc::sourcelist="$SOURCES" -o Dir::Etc::sourceparts="$EMPTY_DIR" -o APT::Get::List-Cleanup=0 \
        || abort "apt-get update of the test repository failed"
}

aptUpgrade() { # what 'apt-get upgrade' does to raspibackup, other packages aren't touched
    step "apt-get upgrade"
    aptUpdate
    run apt-get -s upgrade
    if apt-get -s upgrade 2>/dev/null | grep -q "^Inst $PACKAGE_NAME "; then
        run apt-get install -y --only-upgrade "$PACKAGE_NAME" || fail "apt-get upgrade of $PACKAGE_NAME failed"
    fi
}

rbc() { # options - raspiBackupConfig without terminal, so held packages aren't changed
    step "raspiBackupConfig $*"
    # -f: versions are published between the calls, so the package index has to be updated every time
    RASPIBACKUP_INSTALL_DEBUG=1 run "$RASPIBACKUPCONFIG" -f "$@" < /dev/null
}

rbcYes() { # options - raspiBackupConfig with a terminal answering yes
    step "raspiBackupConfig $* (answer yes)"
    log "\$ printf 'y\\n' | script -qec '$RASPIBACKUPCONFIG -f $*' /dev/null"
    printf 'y\n' | RASPIBACKUP_INSTALL_DEBUG=1 timeout 600 script -qec "$RASPIBACKUPCONFIG -f $*" /dev/null >> "$LOG" 2>&1
    local rc=$?
    log "rc=$rc"
    return $rc
}

installer() { # options - raspiBackupInstall.sh using the test repository and key
    step "raspiBackupInstall.sh $*"
    (cd "$WORK" && REPO_URL="$TEST_REPO_URL" REPO_OWNER_GPG_FINGERPRINT="$GPG_FPR" run bash "$BUILD/raspiBackupInstall.sh" -y "$@")
}

#######################################################################################################################
# setup
#######################################################################################################################

CURRENT_SECTION="setup"
section "Setup in $WORK"
echo "Log: $LOG"

step "clone $SOURCE_REF ($SOURCE_COMMIT)"
if [[ -n "$(git -C "$GIT_TOP" status --porcelain --untracked-files=no)" ]]; then
    echo "    Note: uncommitted changes in $GIT_TOP aren't tested"
fi
run git clone -q "$GIT_TOP" "$WORK/src" || abort "git clone failed"
run git -C "$WORK/src" checkout -q --detach "$SOURCE_COMMIT" || abort "git checkout $SOURCE_COMMIT failed"

step "create temporary signing key"
run gpg --batch --passphrase '' --quick-gen-key "raspiBackup package test <test@example.invalid>" rsa3072 sign 1d \
    || abort "gpg key generation failed"
GPG_FPR="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
readonly GPG_FPR
[[ -n "$GPG_FPR" ]] || abort "no fingerprint of the test key found"
log "test key $GPG_FPR"

step "create build.conf"
(cd "$BUILD" && run ./build.sh)   # creates the template and exits
[[ -f "$BUILD/build.conf" ]] || abort "build.sh didn't create build.conf"
cp "$BUILD/build.conf" "$BUILD/build.conf.test"
cat >> "$BUILD/build.conf.test" <<EOF_CONF

# test settings
BRANCH_TO_DEB="HEAD"
VERSION_RASPIBACKUPCONFIG=""
GPG_KEYID="$GPG_FPR"
REPO_ARCHITECTURES="$(dpkg --print-architecture)"
VERBOSITY=normal
EOF_CONF

# versions used, sorted as dpkg sorts them
V_OLD="0.9.0"
V_REL="0.9.1"
V_BETA1="0.9.2-beta1";        D_BETA1="$(debianVersion "$V_BETA1")"
V_BETA2="0.9.2-beta2";        D_BETA2="$(debianVersion "$V_BETA2")"
V_REL2="0.9.2"
V_FIX1="0.9.2-m1"
V_UFIX1="0.9.2-m2~u972.1"
V_UFIX2="0.9.2-m2~u972.2"
V_FIX2="0.9.2-m2"
V_UFIX3="0.9.2-m3~u973.1"
V_REL3="0.9.3"

#######################################################################################################################
# 1. release update and reversal
#######################################################################################################################

CURRENT_SECTION="release"
section "1. Release update and reversal"

publish "$V_OLD"
installer && pass "installation from repository" || fail "installation from repository"
assertInSuite "$V_OLD" stable
sed -i -E "s/^${CONFIG_MARKER%%=*}=.*/$CONFIG_MARKER/" "$CONFIG"
assertInstalled "$V_OLD"

publish "$V_REL"
assertRc 0 "update to new release" rbc -U
assertInstalled "$V_REL"

assertRc 0 "revert to previous release" rbc -R
assertInstalled "$V_OLD" held

aptUpgrade
assertInstalled "$V_OLD" held

assertRc 0 "update of held release without terminal is refused" rbc -U
assertInstalled "$V_OLD" held

assertRc 1 "no release before the oldest one" rbc -R
assertInstalled "$V_OLD" held

assertRc 0 "update of held release confirmed" rbcYes -U
assertInstalled "$V_REL"

step "revert with apt (README section 4)"
run apt-get install -y --allow-downgrades "$PACKAGE_NAME=$V_OLD" && run apt-mark hold "$PACKAGE_NAME" \
    || fail "apt-get install --allow-downgrades $PACKAGE_NAME=$V_OLD"
assertInstalled "$V_OLD" held
run apt-mark unhold "$PACKAGE_NAME"
aptUpgrade
assertInstalled "$V_REL"

#######################################################################################################################
# 2. beta update and reversal
#######################################################################################################################

CURRENT_SECTION="beta"
section "2. Beta update and reversal"

publish "$V_BETA1"
assertInSuite "$D_BETA1" beta

aptUpgrade
assertInstalled "$V_REL"
assertRc 0 "update doesn't install a beta" rbc -U
assertInstalled "$V_REL"

step "apt-get install -t beta"
run apt-get install -y -t beta "$PACKAGE_NAME" || fail "apt-get install -t beta $PACKAGE_NAME"
assertInstalled "$D_BETA1"

publish "$V_BETA2"
aptUpgrade
assertInstalled "$D_BETA2"

step "revert beta to release with apt"
run apt-get install -y --allow-downgrades "$PACKAGE_NAME/stable" || fail "apt-get install $PACKAGE_NAME/stable"
assertInstalled "$V_REL"
aptUpgrade
assertInstalled "$V_REL"

installer --beta && pass "installation of beta with raspiBackupInstall.sh --beta" || fail "installation with --beta"
assertInstalled "$D_BETA2"

publish "$V_REL2"
assertRc 0 "beta updated to release" rbc -U
assertInstalled "$V_REL2"
aptUpgrade
assertInstalled "$V_REL2"

#######################################################################################################################
# 3. hotfix update and reversal
#######################################################################################################################

CURRENT_SECTION="hotfix"
section "3. Hotfix update and reversal"

publish "$V_FIX1"
assertInSuite "$V_FIX1" stable
aptUpgrade
assertInstalled "$V_FIX1"

assertRc 0 "revert hotfix to release" rbc -R
assertInstalled "$V_REL2" held
aptUpgrade
assertInstalled "$V_REL2" held

assertRc 0 "update to hotfix confirmed" rbcYes -U
assertInstalled "$V_FIX1"

#######################################################################################################################
# 4. individual fix for one user
#######################################################################################################################

CURRENT_SECTION="individual fix"
section "4. Individual fix for one user"

build "$V_UFIX1" --no-repo
aptUpdate
assertInSuite "$V_UFIX1" none

installer "$DEBS/${PACKAGE_NAME}_${V_UFIX1}.deb" && pass "installation of individual fix" || fail "installation of individual fix"
assertInstalled "$V_UFIX1"
aptUpgrade
assertInstalled "$V_UFIX1"
assertRc 0 "update keeps individual fix" rbc -U
assertInstalled "$V_UFIX1"

build "$V_UFIX2" --no-repo

step "package with wrong signature is rejected"
cp "$DEBS/${PACKAGE_NAME}_${V_UFIX2}.deb" "$WORK/tampered.deb"
cp "$DEBS/${PACKAGE_NAME}_${V_UFIX1}.deb.sig" "$WORK/tampered.deb.sig"
installer "$WORK/tampered.deb" && fail "package with wrong signature installed" || pass "package with wrong signature rejected"
assertInstalled "$V_UFIX1"

installer "$DEBS/${PACKAGE_NAME}_${V_UFIX2}.deb" && pass "installation of second individual fix" || fail "installation of second individual fix"
assertInstalled "$V_UFIX2"

assertRc 0 "revert individual fix to hotfix" rbc -R
assertInstalled "$V_FIX1" held

publish "$V_FIX2"
aptUpgrade
assertInstalled "$V_FIX1" held
assertRc 0 "update to fixed version confirmed" rbcYes -U
assertInstalled "$V_FIX2"

build "$V_UFIX3" --no-repo
installer "$DEBS/${PACKAGE_NAME}_${V_UFIX3}.deb" && pass "installation of individual fix" || fail "installation of individual fix"
assertInstalled "$V_UFIX3"
publish "$V_REL3"
aptUpgrade
assertInstalled "$V_REL3"

#######################################################################################################################
# uninstall
#######################################################################################################################

CURRENT_SECTION="uninstall"
section "Uninstall"

assertRc 0 "purge" apt-get purge -y "$PACKAGE_NAME"
noteInstalled "$(installedVersion)"
[[ -z "$(installedVersion)" ]] && pass "$PACKAGE_NAME removed" || fail "$PACKAGE_NAME still installed: $(installedVersion)"
[[ ! -e "$CONFIG" ]] && pass "$CONFIG removed" || fail "$CONFIG still exists"

#######################################################################################################################
# result
#######################################################################################################################

# the summary report is written by cleanup, also when the test is aborted or interrupted
if (( FAILED )); then
    KEEP=1
    exit 1
fi
exit 0
