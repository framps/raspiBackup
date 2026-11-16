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
and raspiBackupConfig -U/-R/-b/-S that

    1. a release is updated to a new release and reverted to the previous one
    2. a beta is installed and updated only on request and reverted to the release
    3. a hotfix is updated and reverted
    4. an individual fix for one user (.deb, not in the repository) is installed,
       reverted and replaced by the next public fix or release
    5. updates and downgrades skip or step over several versions, a beta is reverted
       to an older hotfix
    6. raspiBackup reports new versions, minor fixes (DEB_REVISION) and deprecated versions
       according to DEPRECATED of raspiBackup.properties
    In sections 1, 2, 3 and 9 raspiBackup (after a backup) and raspiBackupConfig (update menu M3)
    have to report the new versions available.
    7. an installation without apt (raspiBackupInstallUI.sh, install.sh) is migrated to the
       package and the migration is reverted with revertMigration.sh
    8. a plain apt-get upgrade to a version with a newer config template merges the
       configuration (postinst calls raspiBackupConfig -m), a downgrade doesn't change it
    9. the pre-release cycle alpha1, alpha2, beta1, beta2, rc1, rc2 and the release:
       suites, updates of testers, no updates for stable users, news and reversal.
       raspiBackup reports betas to users of a release. Users of a pre-release get a new release
       first, otherwise newer betas and rcs, users of an alpha also newer alphas.
       raspiBackupConfig offers all of them.

Only committed changes are tested: the sources are cloned from git.

At the end a summary report is displayed and saved in <workdir>/raspiBackupPkgTest.*.report
(result per section, version history, packages built, failures and duration).

RUN IT ON A TEST SYSTEM ONLY (VM, spare Raspberry). It installs, downgrades and purges
the package 'raspibackup' and its dependencies. It refuses to run if raspibackup is
installed or its repository is configured, unless --force is used.
It always refuses to run if raspiBackup is installed without apt or a saved installation
without apt exists in /var/backups/raspiBackup-legacy, --force doesn't delete them.
The system repositories have to be reachable to install the dependencies.

Options:

    -s | --source <ref>  git branch, tag or commit to test (default: HEAD)
    -w | --workdir <dir> directory for the work directory, report and log (default: /var/tmp)
                         /tmp is often a small tmpfs, e.g. on Debian 13 half of the RAM
    -l | --lintian       check the packages with lintian (slow)
    -f | --force         purge an installed raspibackup and remove its repository first
    -k | --keep          keep the work directory, package and repository afterwards
    -x | --fail-fast     stop at the first failed check
    -h | --help          display this short help

EOF_USAGE
}

SOURCE_REF="HEAD"
WORK_BASE="/var/tmp"   # /tmp is a tmpfs on Debian 13, too small on systems with little RAM
LINTIAN=0
FORCE=0
KEEP=0
FAIL_FAST=0

while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -s|--source) SOURCE_REF="${2:?missing git reference}"; shift 2 ;;
        -w|--workdir) WORK_BASE="${2:?missing directory}"; shift 2 ;;
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
# installation without apt, see preinst
readonly LEGACY_DIR="/var/backups/raspiBackup-legacy"
readonly LEGACY_SCRIPT="/usr/local/bin/raspiBackup.sh"
readonly LEGACY_INSTALLER="/usr/local/bin/raspiBackupInstallUI.sh"
readonly LEGACY_EXTENSION="/usr/local/bin/raspiBackup_test_pre.sh"
readonly LEGACY_UNITS=(/etc/systemd/system/raspiBackup.service /etc/systemd/system/raspiBackup.timer)
readonly LEGACY_CRON="/etc/cron.d/raspiBackup"
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

# never deleted, not even with --force: it may be a real installation of the user
if [[ -e "$LEGACY_DIR" ]] || [[ -f "$LEGACY_SCRIPT" && ! -L "$LEGACY_SCRIPT" ]]; then
    echo "raspiBackup is installed without apt ($LEGACY_SCRIPT) or a saved installation exists in $LEGACY_DIR."
    echo "Run this test on a test system only. If it's left over from a test run remove it with:"
    echo "    sudo systemctl disable raspiBackup.timer; sudo rm -rf $LEGACY_DIR $LEGACY_SCRIPT $LEGACY_INSTALLER $LEGACY_EXTENSION ${LEGACY_SCRIPT%.sh} ${LEGACY_INSTALLER%.sh} ${LEGACY_UNITS[*]} $LEGACY_CRON"
    exit 1
fi

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

[[ -d "$WORK_BASE" ]] || { echo "Work directory $WORK_BASE doesn't exist"; exit 1; }
WORK="$(mktemp -d "$WORK_BASE/raspiBackupPkgTest.XXXXXX")"
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

LEGACY_CREATED=0   # installation without apt created by section 5, removed by cleanup

removeLegacy() { # installation without apt and its saved copy created by the test
    (( LEGACY_CREATED )) || return 0
    if [[ -d /run/systemd/system ]]; then
        systemctl disable --now raspiBackup.timer > /dev/null 2>&1 || true
    fi
    rm -rf "$LEGACY_DIR"
    rm -f "$LEGACY_SCRIPT" "$LEGACY_INSTALLER" "$LEGACY_EXTENSION" "${LEGACY_SCRIPT%.sh}" "${LEGACY_INSTALLER%.sh}" \
        "${LEGACY_UNITS[@]}" "$LEGACY_CRON" "$CONFIG" "$CONFIG~" "$CONFIG.package"
    if [[ -d /run/systemd/system ]]; then
        systemctl daemon-reload > /dev/null 2>&1 || true
    fi
}

cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    gpgconf --kill all > /dev/null 2>&1 || true
    report "$rc" | tee "$REPORT"
    if (( KEEP )); then
        echo ""
        echo "Kept work directory $WORK, $PACKAGE_NAME and the repository $SOURCES"
        echo "Remove them with: sudo apt-mark unhold $PACKAGE_NAME; sudo apt-get purge -y $PACKAGE_NAME; sudo rm -rf $SOURCES $KEYRING $WORK /var/lib/apt/lists/*raspiBackupPkgTest*"
        if (( LEGACY_CREATED )); then
            echo "and the installation without apt with: sudo systemctl disable raspiBackup.timer; sudo rm -rf $LEGACY_DIR $LEGACY_SCRIPT $LEGACY_INSTALLER $LEGACY_EXTENSION ${LEGACY_SCRIPT%.sh} ${LEGACY_INSTALLER%.sh} ${LEGACY_UNITS[*]} $LEGACY_CRON"
        fi
    else
        apt-mark unhold "$PACKAGE_NAME" > /dev/null 2>&1 || true
        apt-get purge -y "$PACKAGE_NAME" > /dev/null 2>&1 || true
        rm -f "$SOURCES" "$KEYRING" /var/lib/apt/lists/*raspiBackupPkgTest*
        removeLegacy
        if (( rc != 0 )); then
            cp "$LOG" "$WORK.log" 2>/dev/null && echo "Log saved in $WORK.log"
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
REPORT="$WORK.report"
readonly REPORT

log() { echo "$*" >> "$LOG"; }

SECTION_NO=0
TOTAL_SECTIONS="$(grep -c '^section ' "${BASH_SOURCE[0]}")"
declare -A SEC_TITLE=()     # section -> title for the report

section() { # title [description] - description: what the section checks, in plain words
    SECTIONS+=("$CURRENT_SECTION")
    SEC_PASSED[$CURRENT_SECTION]=0
    SEC_FAILED[$CURRENT_SECTION]=0
    SEC_TITLE[$CURRENT_SECTION]="$1"
    (( SECTION_NO++ ))
    echo ""
    echo "=== [$SECTION_NO/$TOTAL_SECTIONS] $1 ==="
    [[ -n "${2:-}" ]] && fold -s -w 90 <<< "$2" | sed -e 's/ *$//' -e 's/^/    /'
    log ""
    log "=================== [$SECTION_NO/$TOTAL_SECTIONS] $1 ==================="
    [[ -n "${2:-}" ]] && log "    $2"
    return 0
}

step() {
    echo "--- $*"
    log "--- $*"
}

pass() {
    passQuiet "$@"
    echo "    ok   $*"
}

passQuiet() { # counts a passed check, printed by the caller together with others
    (( PASSED++ ))
    SEC_PASSED[$CURRENT_SECTION]=$(( ${SEC_PASSED[$CURRENT_SECTION]:-0} + 1 ))
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
    printf '    %-20s %7s %7s  %-11s %s\n' "section" "passed" "failed" "status" "title"
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
        printf '    %-20s %7d %7d  %-11s %s\n' "$section" "$p" "$f" "$state" "${SEC_TITLE[$section]:-}"
    done

    if (( ${#BUILT[@]} )); then
        echo ""
        echo "  Packages built:"
        printf '    %s\n' "${BUILT[@]}"
    fi

    if (( ${#VERSION_HISTORY[@]} )); then
        echo ""
        echo "  Installed versions (in the order they were installed, held: kept by apt-mark hold, none: purged):"
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
        echo "  Log:    $WORK.log"    # saved by cleanup
    fi
    echo "  Report: $REPORT"
    echo "======================================================================================="
}

#######################################################################################################################
# state checks
#######################################################################################################################

installedVersion() { # empty if not installed, also if removed but not purged (status config-files)
    dpkg-query -W -f '${db:Status-Status} ${Version}' "$PACKAGE_NAME" 2>/dev/null | awk '$1 == "installed" { print $2 }'
}
isHeld() { apt-mark showhold "$PACKAGE_NAME" 2>/dev/null | grep -qx "$PACKAGE_NAME"; }

declare -A SCRIPT_VERSION=()   # Debian version -> VERSION inserted into raspiBackup

assertInstalled() { # debianVersion [held|unheld]
    local expected="$1" hold="${2:-unheld}" actual scriptVersion
    local failedBefore="$FAILED" joined
    local -a ok=()
    actual="$(installedVersion)"
    noteInstalled "$actual"
    if [[ "$actual" == "$expected" ]]; then
        passQuiet "$PACKAGE_NAME $expected installed"
        ok+=("installed $expected")
    else
        fail "$PACKAGE_NAME $expected expected but ${actual:-nothing} installed"
        return
    fi

    if [[ "$hold" == held ]]; then
        isHeld && { passQuiet "$expected is held"; ok+=("held"); } || fail "$expected isn't held"
    else
        isHeld && fail "$expected is held" || { passQuiet "$expected isn't held"; ok+=("not held"); }
    fi

    scriptVersion="$(sed -n -E 's/^VERSION="([^"]*)".*/\1/p' "$RASPIBACKUP")"
    if [[ "$scriptVersion" == "${SCRIPT_VERSION[$expected]}" ]]; then
        passQuiet "raspiBackup reports version $scriptVersion"
        ok+=("raspiBackup reports $scriptVersion")
    else
        fail "raspiBackup reports version '$scriptVersion' instead of '${SCRIPT_VERSION[$expected]}'"
    fi

    if grep -qx "$CONFIG_MARKER" "$CONFIG" 2>/dev/null; then
        passQuiet "configuration kept ($CONFIG_MARKER)"
        ok+=("configuration kept")
    else
        fail "configuration changed, $CONFIG_MARKER missing in $CONFIG"
    fi

    # one line for all checks which passed
    if (( FAILED == failedBefore )); then
        joined="$(printf '%s, ' "${ok[@]}")"
        echo "    ok   ${joined%, }"
    fi
    return 0
}

assertRc() { # expectedRc description command...
    local expected="$1" description="$2" rc
    shift 2
    run "$@"
    rc=$?
    if (( rc == expected && rc != 0 )); then
        pass "$description (refused as expected, rc $rc)"
    elif (( rc == expected )); then
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

# functions of the installed raspiBackup which report new versions and deprecated versions after a backup
readonly NEWS_FUNCTIONS=(debianVersion isVersionInList isPackageInstalled isPackageHeld packageSuiteVersions highestVersion withoutDebianRevision
    withoutDeprecatedVersions updatePackageReminder reportPackageNews isVersionDeprecated runningVersion
    preReleaseKind isReportedPreRelease reportedPreReleases)

news() { # deprecated [skipDeprecated] - messages of the installed raspiBackup about versions, one per line
         # deprecated: DEPRECATED of raspiBackup.properties, skipDeprecated: SKIP_DEPRECATED of the configuration
         # Messages are printed as name of the message constant without MSG_ followed by their parameters.
    local script="$WORK/news.sh" f
    {
        echo 'logEntry() { :; }; logItem() { :; }; logExit() { :; }; getMessage() { :; }; exitError() { exit 2; }'
        grep -E '^MSG_[A-Z_]+=[0-9]+$' "$RASPIBACKUP" | grep -v '^MSG_LEVEL_'
        echo 'declare -A NAME_OF_MSG=(); for v in ${!MSG_@}; do NAME_OF_MSG[${!v}]="${v#MSG_}"; done'
        echo 'MSG_LEVEL_MINIMAL=0; MSG_LEVEL_DETAILED=1'
        echo 'writeToConsole() { local msg="$2"; shift 2; echo "${NAME_OF_MSG[$msg]:-$msg}${*:+ $*}"; }'
        for f in "${NEWS_FUNCTIONS[@]}"; do
            sed -n "/^function $f() /,/^}/p" "$RASPIBACKUP"
        done
        cat <<'EOF_NEWS'
PACKAGE_NAME=raspibackup PACKAGE_SUITE=stable PACKAGE_BETA_SUITE=beta
REGRESSION_TEST=1    # no refreshPackageIndex, the test updates the package index
UPDATE_REMINDER_MAX=3 PACKAGE_UPDATE_REMINDER_FILE=reminder LOG_FILE=/dev/null
VAR_LIB_DIRECTORY="$(mktemp -d)"
DEPRECATED_PROPERTY="$1" SKIP_DEPRECATED="$2"
VERSION="$(sed -n -E 's/^VERSION="([^"]*)".*/\1/p' "$3")"
reportPackageNews
RUNNING_VERSION="$(runningVersion)"
isVersionDeprecated "$RUNNING_VERSION" && writeToConsole $MSG_LEVEL_MINIMAL $MSG_SCRIPT_IS_DEPRECATED "$RUNNING_VERSION"
rm -rf "$VAR_LIB_DIRECTORY"
EOF_NEWS
    } > "$script"
    bash "$script" "$1" "${2:-}" "$RASPIBACKUP" 2>> "$LOG" | grep -v '^VISIT_VERSION_HISTORY_PAGE'
}

assertNews() { # description expected deprecated [skipDeprecated] - expected: messages of news() separated by ';', empty: none
    local description="$1" expected="$2" actual
    actual="$(news "${@:3}" | paste -sd ';')"
    log "news (DEPRECATED='$3' SKIP_DEPRECATED='${4:-}'): $actual"
    if [[ "$actual" == "$expected" ]]; then
        pass "$description${expected:+: $expected}"
    else
        fail "$description (DEPRECATED='$3'${4:+ SKIP_DEPRECATED='$4'}): '${actual}' instead of '${expected}'"
    fi
}

offers() { # what the update menu M3 of the installed raspiBackupConfig offers, - for not available:
            # "P1 <update> P2 <previous release> P3 <beta> P4 <revert beta to release>", same as options -U, -R, -b, -S
    (cd "$WORK" && bash -c 'source "$1" > /dev/null 2>&1 || exit 1
        LOG_FILE=/dev/null
        parsePackageVersions
        echo "P1 ${PACKAGE_OFFER_UPDATE:--} P2 ${PACKAGE_VERSION_PREVIOUS:--} P3 ${PACKAGE_OFFER_BETA:--} P4 ${PACKAGE_OFFER_REVERT_BETA:--}"' \
        _ "$RASPIBACKUPCONFIG" 2>> "$LOG")
}

assertOffers() { # description expected - expected: output of offers()
    local description="$1" expected="$2" actual
    actual="$(offers)"
    log "raspiBackupConfig update menu: $actual"
    if [[ "$actual" == "$expected" ]]; then
        pass "raspiBackupConfig offers $description: $expected"
    else
        fail "raspiBackupConfig offers '$actual' instead of '$expected' ($description)"
    fi
}

assertAvailable() { # description news offers - new versions reported by raspiBackup (see news()) and raspiBackupConfig (see offers())
    assertNews "raspiBackup reports $1" "$2" ""
    assertOffers "$1" "$3"
}

#######################################################################################################################
# actions
#######################################################################################################################

debianVersion() { # VERSION of raspiBackup -> Debian version, see build.sh
    sed -E -e 's/_/-/g' -e 's/-(alpha|beta|rc)/~\L\1/I' <<< "$1"
}

build() { # version [--no-repo] [--revision <n>] - builds the package with build.sh, adds it to the repository unless --no-repo
          # --revision: minor fix of the version (DEB_REVISION of build.conf), e.g. 0.9.6 --revision 1 -> 0.9.6-1
    local version="$1" revision="" debVersion
    shift
    local -a buildOptions=()
    while (( $# > 0 )); do
        case "$1" in
            --revision) revision="${2:?missing revision}"; shift 2 ;;
            *) buildOptions+=("$1"); shift ;;
        esac
    done
    debVersion="$(debianVersion "$version")${revision:+-$revision}"
    local where="suite stable"
    [[ "$debVersion" == *"~"* ]] && where="suite beta"
    [[ " ${buildOptions[*]} " == *" --no-repo "* ]] && where=".deb only, not in the repository"
    if [[ "$where" == suite* ]]; then
        step "maintainer: build and publish $debVersion in $where${revision:+ (minor fix $revision of $version)}"
    else
        step "maintainer: build $debVersion ($where)"
    fi

    { cat "$BUILD/build.conf.test"; echo "VERSION_RASPIBACKUP=\"$version\""; echo "DEB_REVISION=\"$revision\""; } > "$BUILD/build.conf"
    local -a options=("${buildOptions[@]}")
    (( LINTIAN )) || options+=(--no-check)
    (cd "$BUILD" && run ./build.sh "${options[@]}") || abort "build.sh failed for $version"

    local deb="$BUILD/deb/${PACKAGE_NAME}_${debVersion}.deb"
    [[ -f "$deb" && -f "$deb.sig" ]] || abort "build.sh didn't create $deb and $deb.sig"
    [[ "$(dpkg-deb -f "$deb" Version)" == "$debVersion" ]] || abort "$deb has version $(dpkg-deb -f "$deb" Version)"
    cp "$deb" "$deb.sig" "$DEBS/"
    BUILT+=("$(printf '%-22s %s' "$debVersion" "${where%%,*}")")
    SCRIPT_VERSION[$debVersion]="$version"
}

publish() { # version [--revision <n>] - build and add to the repository, like build.sh + publishRepo.sh
    build "$@"
    aptUpdate
}

aptUpdate() { # refresh only the raspiBackup repository
    [[ -f "$SOURCES" ]] || return 0     # not added yet by raspiBackupInstall.sh
    run apt-get update -o Dir::Etc::sourcelist="$SOURCES" -o Dir::Etc::sourceparts="$EMPTY_DIR" -o APT::Get::List-Cleanup=0 \
        || abort "apt-get update of the test repository failed"
}

aptUpgrade() { # what 'apt-get upgrade' does to raspibackup, other packages aren't touched
    step "user: apt-get upgrade"
    aptUpdate
    run apt-get -s upgrade
    if apt-get -s upgrade 2>/dev/null | grep -q "^Inst $PACKAGE_NAME "; then
        run apt-get install -y --only-upgrade "$PACKAGE_NAME" || fail "apt-get upgrade of $PACKAGE_NAME failed"
    fi
}

rbcPurpose() { # options - what raspiBackupConfig does with these options
    case " $* " in
        *" -U "*) echo "update to the latest version" ;;
        *" -R "*) echo "revert to the previous release and hold it" ;;
        *" -b "*) echo "install or update the latest beta" ;;
        *" -S "*) echo "revert the beta to the release" ;;
        *" -m "*) echo "merge the configuration" ;;
        *" -u "*) echo "uninstall" ;;
        *" -i "*) echo "install" ;;
    esac
}

rbc() { # options - raspiBackupConfig without terminal, so held packages aren't changed
    step "user: raspiBackupConfig $* ($(rbcPurpose "$@"), no terminal, questions are answered with no)"
    # -f: versions are published between the calls, so the package index has to be updated every time
    RASPIBACKUP_INSTALL_DEBUG=1 run "$RASPIBACKUPCONFIG" -f "$@" < /dev/null
}

rbcYes() { # options - raspiBackupConfig with a terminal answering yes
    step "user: raspiBackupConfig $* ($(rbcPurpose "$@"), answers yes)"
    log "\$ printf 'y\\n' | script -qec '$RASPIBACKUPCONFIG -f $*' /dev/null"
    printf 'y\n' | RASPIBACKUP_INSTALL_DEBUG=1 timeout 600 script -qec "$RASPIBACKUPCONFIG -f $*" /dev/null >> "$LOG" 2>&1
    local rc=$?
    log "rc=$rc"
    return $rc
}

installer() { # options - raspiBackupInstall.sh using the test repository and key
    local purpose="install the latest release"
    [[ "${1:-}" == --beta ]] && purpose="install the latest beta"
    [[ "${1:-}" == *.deb ]] && purpose="install the downloaded ${1##*/}"
    step "user: raspiBackupInstall.sh $* ($purpose)"
    (cd "$WORK" && REPO_URL="$TEST_REPO_URL" REPO_OWNER_GPG_FINGERPRINT="$GPG_FPR" run bash "$WORK/src/raspiBackupInstall.sh" -y "$@")
}

#######################################################################################################################
# setup
#######################################################################################################################

CURRENT_SECTION="setup"
section "Setup" "Clone the commit to test, create a temporary signing key and the build configuration in $WORK"
echo "    Log: $LOG"
echo ""
echo "    Every '---' line is an action of the maintainer or a user, the lines below it are the checks:"
echo "    'ok' check passed, 'FAIL' check failed. 'refused as expected' means the action had to be rejected."

step "clone $SOURCE_REF ($SOURCE_COMMIT)"
if [[ -n "$(git -C "$GIT_TOP" status --porcelain --untracked-files=no)" ]]; then
    echo "    Note: uncommitted changes in $GIT_TOP aren't tested"
fi
# only the commit to test, the whole history doesn't fit into a small work directory
run git init -q "$WORK/src" || abort "git init failed"
run git -C "$WORK/src" fetch -q --depth 1 "file://$GIT_TOP" "$SOURCE_COMMIT" || abort "git fetch $SOURCE_COMMIT failed"
run git -C "$WORK/src" checkout -q --detach FETCH_HEAD || abort "git checkout $SOURCE_COMMIT failed"

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
V_REL4="0.9.4"
V_REL5="0.9.5"
V_FIX5="0.9.5-m1"
V_BETA6="0.9.6-beta1";        D_BETA6="$(debianVersion "$V_BETA6")"
V_REL6="0.9.6"
D_MINOR6="$V_REL6-1"          # minor fix, built with --revision 1
D_MINOR6_2="$V_REL6-2"        # minor fix, built with --revision 2
V_REL7="0.9.7"
V_REL8="0.9.8"
V_FIX8="0.9.8-m1"
V_BETA9_1="0.9.9-beta1";      D_BETA9_1="$(debianVersion "$V_BETA9_1")"
V_BETA9_2="0.9.9-beta2";      D_BETA9_2="$(debianVersion "$V_BETA9_2")"
V_REL9="0.9.9"                # not published, deprecates its betas
V_LATEST="$V_FIX8"            # latest release in suite stable at the end, installed by the migration

#######################################################################################################################
# 1. release update and reversal
#######################################################################################################################

CURRENT_SECTION="release"
section "1. Release update and reversal" "A new release is installed with raspiBackupConfig and apt, reverted to the previous release, which is held, and updated again."

publish "$V_OLD"
installer && pass "installation from repository" || fail "installation from repository"
assertInSuite "$V_OLD" stable
sed -i -E "s/^${CONFIG_MARKER%%=*}=.*/$CONFIG_MARKER/" "$CONFIG"
assertInstalled "$V_OLD"
assertAvailable "nothing new" "" "P1 - P2 - P3 - P4 -"

publish "$V_REL"
assertAvailable "the new release" "NEW_VERSION_AVAILABLE $V_REL $V_OLD" "P1 $V_REL P2 - P3 - P4 -"
assertRc 0 "update to new release" rbc -U
assertInstalled "$V_REL"
assertAvailable "no newer version, the previous release" "" "P1 - P2 $V_OLD P3 - P4 -"

assertRc 0 "revert to previous release" rbc -R
assertInstalled "$V_OLD" held
assertAvailable "the release to a held version, it has to be installed with apt-get install" \
    "NEW_PACKAGE_VERSION_INSTALL $V_REL $V_OLD $V_REL" "P1 $V_REL P2 - P3 - P4 -"

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
section "2. Beta update and reversal" "A beta is installed only on request, updated to the next beta, reverted to the release and finally replaced by the next release."

publish "$V_BETA1"
assertInSuite "$D_BETA1" beta
assertAvailable "the beta to stable users" "BETAVERSION_AVAILABLE $D_BETA1" "P1 - P2 $V_OLD P3 $D_BETA1 P4 -"

aptUpgrade
assertInstalled "$V_REL"
assertRc 0 "update doesn't install a beta" rbc -U
assertInstalled "$V_REL"
assertRc 1 "release isn't reverted like a beta" rbc -S
assertInstalled "$V_REL"

assertRc 0 "install beta" rbc -b
assertInstalled "$D_BETA1"
assertAvailable "nothing new to the beta tester, the reversal to the release" "" "P1 - P2 - P3 - P4 $V_REL"
assertRc 1 "no newer beta" rbc -b
assertInstalled "$D_BETA1"
assertRc 0 "revert beta to release" rbc -S
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
section "3. Hotfix update and reversal" "A hotfix of the release is installed like a release and reverted to the release."

publish "$V_FIX1"
assertInSuite "$V_FIX1" stable
assertAvailable "the hotfix" "NEW_VERSION_AVAILABLE $V_FIX1 $V_REL2" "P1 $V_FIX1 P2 $V_REL P3 - P4 -"
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
section "4. Individual fix for one user" "A fix sent to one user as .deb (not in the repository) is installed, a .deb with a wrong signature is rejected, the fix is reverted and replaced by the next public version."

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
# 5. version to version updates and downgrades
#######################################################################################################################

CURRENT_SECTION="version to version"
section "5. Version to version updates and downgrades" "Updates skip several versions, downgrades step back over several versions, a beta is reverted to an older hotfix."

publish "$V_REL4"
publish "$V_REL5"
assertRc 0 "update skips release $V_REL4" rbc -U
assertInstalled "$V_REL5"

assertRc 0 "revert to previous release" rbc -R
assertInstalled "$V_REL4" held
assertRc 0 "revert of held release without terminal is refused" rbc -R
assertInstalled "$V_REL4" held
assertRc 0 "revert of held release confirmed" rbcYes -R
assertInstalled "$V_REL3" held
assertRc 0 "revert to previous hotfix confirmed" rbcYes -R
assertInstalled "$V_FIX2" held

step "downgrade over several versions with apt"
run apt-mark unhold "$PACKAGE_NAME"
run apt-get install -y --allow-downgrades "$PACKAGE_NAME=$V_OLD" && run apt-mark hold "$PACKAGE_NAME" \
    || fail "apt-get install --allow-downgrades $PACKAGE_NAME=$V_OLD"
assertInstalled "$V_OLD" held
assertRc 0 "update of held release over several versions confirmed" rbcYes -U
assertInstalled "$V_REL5"

step "downgrade with apt without hold"
run apt-get install -y --allow-downgrades "$PACKAGE_NAME=$V_REL2" || fail "apt-get install --allow-downgrades $PACKAGE_NAME=$V_REL2"
assertInstalled "$V_REL2"
aptUpgrade
assertInstalled "$V_REL5"

publish "$V_BETA6"
assertRc 0 "install beta" rbc -b
assertInstalled "$D_BETA6"
publish "$V_FIX5"
assertInSuite "$V_FIX5" stable
aptUpgrade
assertInstalled "$D_BETA6"
assertRc 0 "beta isn't replaced by an older hotfix" rbc -U
assertInstalled "$D_BETA6"
assertRc 0 "revert beta to hotfix" rbc -S
assertInstalled "$V_FIX5"

#######################################################################################################################
# 6. deprecated versions
#######################################################################################################################

# DEPRECATED of raspiBackup.properties is passed to the functions of the installed raspiBackup, see news()

CURRENT_SECTION="deprecated"
section "6. Deprecated versions" "raspiBackup reports new versions, betas and deprecated versions (DEPRECATED of raspiBackup.properties) after a backup. Minor fixes are installed but not reported."

publish "$V_REL6"
aptUpgrade
assertInstalled "$V_REL6"
assertNews "no news" "" ""
assertNews "deprecated version is reported" "SCRIPT_IS_DEPRECATED $V_REL6" "$V_REL6"
assertNews "SKIP_DEPRECATED suppresses the warning" "" "$V_REL6" "$V_REL6"

publish "$V_REL6" --revision 1
assertInSuite "$D_MINOR6" stable
assertNews "minor fix isn't reported" "" ""
assertNews "minor fix of a deprecated version is deprecated too" "SCRIPT_IS_DEPRECATED $V_REL6" "$V_REL6"
assertNews "deprecated version doesn't include a later version (${V_REL6}0)" "" "${V_REL6}0"
aptUpgrade
assertInstalled "$D_MINOR6"
assertNews "installed minor fix of a deprecated version is deprecated" "SCRIPT_IS_DEPRECATED $D_MINOR6" "$V_REL6"
assertNews "deprecated minor fix is detected" "SCRIPT_IS_DEPRECATED $D_MINOR6" "$D_MINOR6"

publish "$V_REL6" --revision 2
assertNews "minor fix of the installed minor fix isn't reported" "" ""
assertNews "minor fix is reported to users of a deprecated minor fix" \
    "NEW_VERSION_AVAILABLE $D_MINOR6_2 $D_MINOR6;SCRIPT_IS_DEPRECATED $D_MINOR6" "$D_MINOR6"

publish "$V_REL7"
publish "$V_REL8"
assertNews "latest release is reported" "NEW_VERSION_AVAILABLE $V_REL8 $D_MINOR6" ""
assertNews "deprecated latest release: newest release which isn't deprecated is reported with apt-get install" \
    "NEW_PACKAGE_VERSION_INSTALL $V_REL7 $D_MINOR6 $V_REL7" "$V_REL8"
assertNews "deprecated releases aren't reported (comma separated)" "" "$V_REL7,$V_REL8"
run apt-mark hold "$PACKAGE_NAME"
assertNews "held version: release is reported with apt-get install" "NEW_PACKAGE_VERSION_INSTALL $V_REL8 $D_MINOR6 $V_REL8" ""
run apt-mark unhold "$PACKAGE_NAME"

publish "$V_BETA9_1"
assertNews "beta is reported" "NEW_VERSION_AVAILABLE $V_REL8 $D_MINOR6;BETAVERSION_AVAILABLE $D_BETA9_1" ""
assertNews "betas of a deprecated release aren't reported" "NEW_VERSION_AVAILABLE $V_REL8 $D_MINOR6" "$V_REL9"
assertNews "deprecated beta isn't reported" "NEW_VERSION_AVAILABLE $V_REL8 $D_MINOR6" "$V_BETA9_1"

assertRc 0 "install beta" rbc -b
assertInstalled "$D_BETA9_1"
assertNews "no news for beta tester" "" ""
publish "$V_BETA9_2"
assertNews "newer beta is reported to beta tester" "NEW_VERSION_AVAILABLE $D_BETA9_2 $D_BETA9_1" ""
assertNews "deprecated newer beta isn't reported to beta tester" "" "$V_BETA9_2"
assertNews "deprecated release includes the installed and the newer beta" "SCRIPT_IS_DEPRECATED $D_BETA9_1" "$V_REL9"
assertNews "deprecated beta is reported (Debian version in DEPRECATED)" \
    "NEW_VERSION_AVAILABLE $D_BETA9_2 $D_BETA9_1;SCRIPT_IS_DEPRECATED $D_BETA9_1" "$D_BETA9_1"

assertRc 0 "revert beta to release" rbc -S
assertInstalled "$V_REL8"
assertNews "deprecated latest release" "BETAVERSION_AVAILABLE $D_BETA9_2;SCRIPT_IS_DEPRECATED $V_REL8" "$V_REL8"
publish "$V_FIX8"
assertNews "hotfix of deprecated release isn't reported" \
    "BETAVERSION_AVAILABLE $D_BETA9_2;SCRIPT_IS_DEPRECATED $V_REL8" "$V_REL8"
assertNews "hotfix is reported" "NEW_VERSION_AVAILABLE $V_FIX8 $V_REL8;BETAVERSION_AVAILABLE $D_BETA9_2" ""
aptUpgrade
assertInstalled "$V_LATEST"
assertNews "installed hotfix of deprecated release is deprecated" \
    "BETAVERSION_AVAILABLE $D_BETA9_2;SCRIPT_IS_DEPRECATED $V_FIX8" "$V_REL8"
assertNews "no news" "BETAVERSION_AVAILABLE $D_BETA9_2" ""

#######################################################################################################################
# uninstall
#######################################################################################################################

CURRENT_SECTION="uninstall"
section "Uninstall" "apt-get purge removes the package, its configuration and its state."

assertRc 0 "purge" apt-get purge -y "$PACKAGE_NAME"
noteInstalled "$(installedVersion)"
[[ -z "$(installedVersion)" ]] && pass "$PACKAGE_NAME removed" || fail "$PACKAGE_NAME still installed: $(installedVersion)"
[[ ! -e "$CONFIG" ]] && pass "$CONFIG removed" || fail "$CONFIG still exists"
[[ ! -e /var/lib/raspiBackup ]] && pass "/var/lib/raspiBackup removed" || fail "/var/lib/raspiBackup still exists"

#######################################################################################################################
# 7. migration of an installation without apt and its reversal
#######################################################################################################################

CURRENT_SECTION="migration"
section "7. Migration of an installation without apt and its reversal" "An installation made by raspiBackupInstallUI.sh is migrated to the package, keeping configuration, extensions and timer. revertMigration.sh restores it."

V_LEGACY="0.7.4"
readonly LEGACY_REF="$WORK/legacy"     # copy of the installation without apt to compare with
HAS_SYSTEMD=0
[[ -d /run/systemd/system ]] && HAS_SYSTEMD=1

legacyFiles() { # files of the installation without apt, the backup timer depends on systemd
    echo "$LEGACY_SCRIPT" "$LEGACY_INSTALLER" "$LEGACY_EXTENSION" "$CONFIG"
    if (( HAS_SYSTEMD )); then
        echo "${LEGACY_UNITS[@]}"
    else
        echo "$LEGACY_CRON"
    fi
}

createLegacy() { # version - installation like raspiBackupInstallUI.sh creates it
    local version="$1" file
    step "create installation $version without apt"
    LEGACY_CREATED=1
    mkdir -p "$(dirname "$LEGACY_SCRIPT")" "$(dirname "$CONFIG")"

    # the scripts aren't started, they only have to be identifiable
    printf '#!/bin/bash\nVERSION="%s"\n# raspiBackup installed without apt by the package test\necho "raspiBackup %s"\n' \
        "$version" "$version" > "$LEGACY_SCRIPT"
    printf '#!/bin/bash\nVERSION="0.5"\n# raspiBackupInstallUI installed without apt by the package test\n' > "$LEGACY_INSTALLER"
    printf '#!/bin/bash\n# extension of the user created by the package test\n' > "$LEGACY_EXTENSION"
    chmod 755 "$LEGACY_SCRIPT" "$LEGACY_INSTALLER" "$LEGACY_EXTENSION"
    ln -sfn raspiBackup.sh "${LEGACY_SCRIPT%.sh}"
    ln -sfn raspiBackupInstallUI.sh "${LEGACY_INSTALLER%.sh}"

    install -m 600 "$WORK/src/config/raspiBackup_en.conf" "$CONFIG"
    sed -i -E "s/^${CONFIG_MARKER%%=*}=.*/$CONFIG_MARKER/" "$CONFIG"

    if (( HAS_SYSTEMD )); then
        cp "$WORK/src/installation/raspiBackup.service" "$WORK/src/installation/raspiBackup.timer" /etc/systemd/system/
        run systemctl daemon-reload
        run systemctl enable raspiBackup.timer || fail "systemctl enable raspiBackup.timer"
    else
        echo "0 5 * * 0 root $LEGACY_SCRIPT" > "$LEGACY_CRON"
    fi

    rm -rf "$LEGACY_REF"
    mkdir -p "$LEGACY_REF"
    for file in $(legacyFiles); do
        cp -a --parents "$file" "$LEGACY_REF" || abort "copy of $file failed"
    done
}

assertTimer() { # enabled|disabled
    (( HAS_SYSTEMD )) || return 0
    if systemctl -q is-enabled raspiBackup.timer 2>/dev/null; then
        [[ "$1" == enabled ]] && pass "raspiBackup.timer is enabled" || fail "raspiBackup.timer is enabled"
    else
        [[ "$1" == disabled ]] && pass "raspiBackup.timer is disabled" || fail "raspiBackup.timer isn't enabled"
    fi
}

assertLink() { # link target
    [[ -L "$1" && "$(readlink "$1")" == "$2" ]] && pass "$1 links to $2" || fail "$1 doesn't link to $2: $(ls -l "$1" 2>&1)"
}

assertSaved() { # installation without apt saved by preinst
    local file
    [[ -x "$LEGACY_DIR/revertMigration.sh" ]] && pass "$LEGACY_DIR/revertMigration.sh created" \
        || fail "$LEGACY_DIR/revertMigration.sh missing"
    for file in $(legacyFiles); do
        cmp -s "$LEGACY_REF$file" "$LEGACY_DIR/files$file" && pass "$file saved" || fail "$file not saved in $LEGACY_DIR/files"
    done
    if (( HAS_SYSTEMD )); then
        [[ -f "$LEGACY_DIR/timer.enabled" ]] && pass "enabled timer noted" || fail "$LEGACY_DIR/timer.enabled missing"
    fi
}

assertMigrated() { # debianVersion - package installed, files of the installation without apt kept or saved
    assertInstalled "$1"
    assertLink "$LEGACY_SCRIPT" raspiBackup
    assertSaved
    cmp -s "$LEGACY_REF$LEGACY_EXTENSION" "$LEGACY_EXTENSION" && pass "extension kept" || fail "extension $LEGACY_EXTENSION changed or deleted"
    [[ -f "$SOURCES" && -f "$KEYRING" ]] && pass "apt repository configured" || fail "apt repository not configured"
    assertTimer enabled
}

assertReverted() { # version - package removed, installation without apt restored
    local version="$1" file actual
    noteInstalled "$(installedVersion)"
    [[ -z "$(installedVersion)" ]] && pass "$PACKAGE_NAME removed" || fail "$PACKAGE_NAME still installed: $(installedVersion)"
    dpkg-query -W -f '${Status}' "$PACKAGE_NAME" 2>/dev/null | grep -q "config-files" \
        && pass "$PACKAGE_NAME removed, not purged" || fail "$PACKAGE_NAME purged or still installed"
    [[ ! -e "$SOURCES" && ! -e "$KEYRING" ]] && pass "apt repository removed" || fail "$SOURCES or $KEYRING still exists"

    for file in $(legacyFiles); do
        if [[ ! -L "$file" ]] && cmp -s "$LEGACY_REF$file" "$file"; then
            pass "$file restored"
        else
            fail "$file not restored"
        fi
    done
    assertLink "${LEGACY_SCRIPT%.sh}" raspiBackup.sh
    assertLink "${LEGACY_INSTALLER%.sh}" raspiBackupInstallUI.sh
    [[ ! -e "$RASPIBACKUPCONFIG" ]] && pass "$RASPIBACKUPCONFIG removed" || fail "$RASPIBACKUPCONFIG still exists"
    [[ -f "$CONFIG.package" ]] && pass "configuration of the package saved as $CONFIG.package" || fail "$CONFIG.package missing"
    [[ -d "$LEGACY_DIR" ]] && pass "$LEGACY_DIR kept" || fail "$LEGACY_DIR deleted"

    actual="$("${LEGACY_SCRIPT%.sh}" 2>&1)"
    [[ "$actual" == "raspiBackup $version" ]] && pass "raspiBackup $version runs" || fail "raspiBackup prints '$actual' instead of 'raspiBackup $version'"
    assertTimer enabled
}

# sections 1 to 6 install the package without an installation without apt, nothing is saved
[[ ! -e "$LEGACY_DIR" ]] && pass "installation of the package saves nothing" || fail "$LEGACY_DIR created without an installation without apt"

createLegacy "$V_LEGACY"
installer && pass "migration with raspiBackupInstall.sh" || fail "migration with raspiBackupInstall.sh"
assertMigrated "$V_LATEST"

step "revertMigration.sh without answer"
run "$LEGACY_DIR/revertMigration.sh" < /dev/null
(( $? == 1 )) && pass "revert not confirmed is refused" || fail "revert not confirmed isn't refused"
assertInstalled "$V_LATEST"

step "revertMigration.sh confirmed (README section 2)"
log "\$ printf 'y\\n' | $LEGACY_DIR/revertMigration.sh"
printf 'y\n' | "$LEGACY_DIR/revertMigration.sh" >> "$LOG" 2>&1
rc=$?
log "rc=$rc"
(( rc == 0 )) && pass "migration reverted (rc $rc)" || fail "revertMigration.sh: rc $rc, expected 0"
assertReverted "$V_LEGACY"

step "migrate again after the reversal"
rm -f "$CONFIG.package"
installer && pass "second migration with raspiBackupInstall.sh" || fail "second migration with raspiBackupInstall.sh"
assertMigrated "$V_LATEST"

assertRc 0 "revertMigration.sh -y" "$LEGACY_DIR/revertMigration.sh" -y
assertReverted "$V_LEGACY"

assertRc 0 "migration once more" installer
assertMigrated "$V_LATEST"
assertRc 0 "purge after migration" apt-get purge -y "$PACKAGE_NAME"
noteInstalled "$(installedVersion)"
[[ -x "$LEGACY_DIR/revertMigration.sh" ]] && pass "$LEGACY_DIR kept by purge" || fail "$LEGACY_DIR deleted by purge"

#######################################################################################################################
# 8. configuration merge by apt-get upgrade
#######################################################################################################################

CURRENT_SECTION="config merge"
section "8. Configuration merge by apt-get upgrade" "A plain apt-get upgrade to a version with a newer config template adds new options and comments out deleted ones (postinst calls raspiBackupConfig -m). A downgrade doesn't change the configuration, purge deletes the saved copies."

V_CONF="0.9.10"                                   # its config templates have a newer config version
readonly NEW_OPTION="DEFAULT_PKGTEST_NEW_OPTION"  # added by the newer templates
readonly DELETED_OPTION="DEFAULT_KEEPBACKUPS_DDZ" # deleted by the newer templates

configVersion() { # file - VERSION_CONFIG of a configuration or template
    sed -n -E 's/^VERSION_CONFIG="([^"]*)".*/\1/p' "$1"
}

installer && pass "installation from repository" || fail "installation from repository"
sed -i -E "s/^${CONFIG_MARKER%%=*}=.*/$CONFIG_MARKER/" "$CONFIG"
assertInstalled "$V_LATEST"
OLD_CONFIG_VERSION="$(configVersion "$CONFIG")"
NEW_CONFIG_VERSION="${OLD_CONFIG_VERSION%.*}.$(( ${OLD_CONFIG_VERSION##*.} + 1 ))"
grep -q "^$DELETED_OPTION=" "$CONFIG" || abort "$DELETED_OPTION missing in $CONFIG, choose another option to delete"

step "config templates with config version $NEW_CONFIG_VERSION: $NEW_OPTION added, $DELETED_OPTION deleted"
for template in "$WORK/src/config/raspiBackup_en.conf" "$WORK/src/config/raspiBackup_de.conf"; do
    sed -i -E -e "s/^VERSION_CONFIG=.*/VERSION_CONFIG=\"$NEW_CONFIG_VERSION\"/" -e "/^$DELETED_OPTION=/d" "$template"
    printf '\n# option added by the package test\n%s="new"\n' "$NEW_OPTION" >> "$template"
done
# build.sh packages committed changes only
run git -C "$WORK/src" -c user.name="raspiBackup package test" -c user.email="test@example.invalid" \
    commit -q -am "Config version $NEW_CONFIG_VERSION" || abort "commit of the changed config templates failed"
publish "$V_CONF"

cp -a "$CONFIG" "$WORK/config.before"
aptUpgrade
assertInstalled "$V_CONF"
actual="$(configVersion "$CONFIG")"
[[ "$actual" == "$NEW_CONFIG_VERSION" ]] && pass "config version updated to $NEW_CONFIG_VERSION" \
    || fail "config version $actual instead of $NEW_CONFIG_VERSION"
grep -q "^$NEW_OPTION=\"new\"" "$CONFIG" && pass "new option $NEW_OPTION added" || fail "new option $NEW_OPTION not added"
if grep -q "^# $DELETED_OPTION=" "$CONFIG" && ! grep -q "^$DELETED_OPTION=" "$CONFIG"; then
    pass "deleted option $DELETED_OPTION commented out"
else
    fail "deleted option $DELETED_OPTION not commented out"
fi
cmp -s "$WORK/config.before" "$CONFIG.v$OLD_CONFIG_VERSION" \
    && pass "configuration before the merge saved as $CONFIG.v$OLD_CONFIG_VERSION" \
    || fail "configuration before the merge not saved as $CONFIG.v$OLD_CONFIG_VERSION"

cp -a "$CONFIG" "$WORK/config.merged"
assertRc 0 "merge again with raspiBackupConfig -m" rbc -m
cmp -s "$WORK/config.merged" "$CONFIG" && pass "configuration unchanged by a second merge" \
    || fail "configuration changed by a second merge"

step "downgrade with apt to $V_LATEST"
run apt-get install -y --allow-downgrades "$PACKAGE_NAME=$V_LATEST" \
    || fail "apt-get install --allow-downgrades $PACKAGE_NAME=$V_LATEST"
assertInstalled "$V_LATEST"
cmp -s "$WORK/config.merged" "$CONFIG" && pass "configuration unchanged by the downgrade" \
    || fail "configuration changed by the downgrade"

aptUpgrade
assertInstalled "$V_CONF"
cmp -s "$WORK/config.merged" "$CONFIG" && pass "configuration unchanged by an upgrade to the same config version" \
    || fail "configuration changed by an upgrade to the same config version"

assertRc 0 "purge" apt-get purge -y "$PACKAGE_NAME"
noteInstalled "$(installedVersion)"
if compgen -G "$CONFIG.v*" > /dev/null; then
    fail "purge didn't delete the configurations saved by the merge: $(echo "$CONFIG".v*)"
    rm -f "$CONFIG".v*
else
    pass "purge deleted the configurations saved by the merge"
fi

#######################################################################################################################
# 9. pre-release cycle: alpha, beta, rc and release
#######################################################################################################################

CURRENT_SECTION="pre-release cycle"
section "9. Pre-release cycle" "alpha1, alpha2, beta1, beta2, rc1, rc2 and the release are published one after the other. Stable users don't get pre-releases, a tester gets each of them and finally the release."

# all pre-releases go into suite beta, VERSION -> Debian version like build.sh: 0.9.11-alpha1 -> 0.9.11~alpha1
V_ALPHA11_1="0.9.11-alpha1";  D_ALPHA11_1="$(debianVersion "$V_ALPHA11_1")"
V_ALPHA11_2="0.9.11-alpha2";  D_ALPHA11_2="$(debianVersion "$V_ALPHA11_2")"
V_BETA11_1="0.9.11-beta1";    D_BETA11_1="$(debianVersion "$V_BETA11_1")"
V_BETA11_2="0.9.11-beta2";    D_BETA11_2="$(debianVersion "$V_BETA11_2")"
V_RC11_1="0.9.11-rc1";        D_RC11_1="$(debianVersion "$V_RC11_1")"
V_RC11_2="0.9.11-rc2";        D_RC11_2="$(debianVersion "$V_RC11_2")"
V_REL11="0.9.11"

step "version order"
order=("$V_CONF" "$D_ALPHA11_1" "$D_ALPHA11_2" "$D_BETA11_1" "$D_BETA11_2" "$D_RC11_1" "$D_RC11_2" "$V_REL11")
ordered=1
for (( i = 1; i < ${#order[@]}; i++ )); do
    dpkg --compare-versions "${order[i-1]}" lt "${order[i]}" || { ordered=0; fail "${order[i-1]} isn't lower than ${order[i]}"; }
done
(( ordered )) && pass "$(printf '%s < ' "${order[@]}" | sed 's/ < $//')"

installer && pass "installation from repository" || fail "installation from repository"
sed -i -E "s/^${CONFIG_MARKER%%=*}=.*/$CONFIG_MARKER/" "$CONFIG"
assertInstalled "$V_CONF"

# stable users don't get pre-releases, they are only reported
publish "$V_ALPHA11_1"
assertInSuite "$D_ALPHA11_1" beta
aptUpgrade
assertInstalled "$V_CONF"
assertRc 0 "update doesn't install an alpha" rbc -U
assertInstalled "$V_CONF"
assertNews "alpha isn't reported to stable users" "" ""
assertOffers "the alpha to stable users" "P1 - P2 $V_FIX8 P3 $D_ALPHA11_1 P4 -"

# a tester installs the alpha and gets every newer pre-release
assertRc 0 "install alpha" rbc -b
assertInstalled "$D_ALPHA11_1"
assertNews "no news for alpha tester" "" ""

publish "$V_ALPHA11_2"
assertInSuite "$D_ALPHA11_2" beta
assertNews "newer alpha is reported to alpha tester" "NEW_VERSION_AVAILABLE $D_ALPHA11_2 $D_ALPHA11_1" ""
assertOffers "the newer alpha to the alpha tester" "P1 $D_ALPHA11_2 P2 - P3 $D_ALPHA11_2 P4 $V_CONF"
aptUpgrade
assertInstalled "$D_ALPHA11_2"

publish "$V_BETA11_1"
assertInSuite "$D_BETA11_1" beta
assertNews "beta is reported to alpha tester" "NEW_VERSION_AVAILABLE $D_BETA11_1 $D_ALPHA11_2" ""
aptUpgrade
assertInstalled "$D_BETA11_1"

publish "$V_BETA11_2"
assertInSuite "$D_BETA11_2" beta
assertNews "newer beta is reported to beta tester" "NEW_VERSION_AVAILABLE $D_BETA11_2 $D_BETA11_1" ""
assertRc 0 "update beta to newer beta" rbc -U
assertInstalled "$D_BETA11_2"

publish "$V_RC11_1"
assertInSuite "$D_RC11_1" beta
assertNews "release candidate is reported to beta tester" "NEW_VERSION_AVAILABLE $D_RC11_1 $D_BETA11_2" ""
aptUpgrade
assertInstalled "$D_RC11_1"
assertOffers "the reversal of the release candidate to the release" "P1 - P2 - P3 - P4 $V_CONF"

# a release candidate is reverted like a beta, not like a release
assertRc 1 "release candidate isn't reverted like a release" rbc -R
assertInstalled "$D_RC11_1"
assertRc 0 "revert release candidate to release" rbc -S
assertInstalled "$V_CONF"
assertNews "release candidate isn't reported to stable users" "" ""
assertOffers "the release candidate to stable users" "P1 - P2 $V_FIX8 P3 $D_RC11_1 P4 -"
assertRc 0 "install release candidate again" rbc -b
assertInstalled "$D_RC11_1"

publish "$V_RC11_2"
assertInSuite "$D_RC11_2" beta
assertNews "newer release candidate is reported to rc tester" "NEW_VERSION_AVAILABLE $D_RC11_2 $D_RC11_1" ""
aptUpgrade
assertInstalled "$D_RC11_2"

# the release ends the cycle, the tester is back on stable
publish "$V_REL11"
assertInSuite "$V_REL11" stable
assertNews "release is reported to rc tester" "NEW_VERSION_AVAILABLE $V_REL11 $D_RC11_2" ""
assertOffers "the release to the tester" "P1 $V_REL11 P2 - P3 - P4 -"
aptUpgrade
assertInstalled "$V_REL11"
assertNews "no news after the release, older pre-releases aren't reported" "" ""
assertOffers "the previous release only after the release" "P1 - P2 $V_CONF P3 - P4 -"
assertRc 1 "no pre-release newer than the release" rbc -b
assertInstalled "$V_REL11"
assertRc 1 "release isn't reverted like a pre-release" rbc -S
assertInstalled "$V_REL11"

assertRc 0 "purge" apt-get purge -y "$PACKAGE_NAME"
noteInstalled "$(installedVersion)"

#######################################################################################################################
# result
#######################################################################################################################

# the summary report is written by cleanup, also when the test is aborted or interrupted
if (( FAILED )); then
    KEEP=1
    exit 1
fi
exit 0
