#!/bin/bash
#
# Unittest of reportPackageNews: updates and betas reported from the apt repository, deprecated versions ignored.
# apt-cache, apt-mark and dpkg-query are replaced by stubs, so neither root nor a repository is needed.
#

source ../../../raspiBackup.sh

REGRESSION_TEST=1	# don't refresh the package index
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
VAR_LIB_DIRECTORY="$TMP/varlib"
LOG_FILE="$TMP/log"

error=0

# --- stubs

INSTALLED=""		# installed version
HELD=0
STABLE=""			# versions in suite stable
BETA=""				# versions in suite beta
CANDIDATE=""		# version 'apt upgrade' installs
MESSAGES=()			# messages written: <msgnumber> <args>

dpkg-query() { echo -n "$INSTALLED"; }
apt-mark() { (( HELD )) && echo "$PACKAGE_NAME"; }
apt-cache() {
	local v
	case "$1" in
		madison)
			for v in $STABLE; do echo " $PACKAGE_NAME | $v | https://example.invalid/raspiBackup stable/main all Packages"; done
			for v in $BETA; do echo " $PACKAGE_NAME | $v | https://example.invalid/raspiBackup beta/main all Packages"; done
			;;
		policy)
			echo "$PACKAGE_NAME:"
			echo "  Installed: $INSTALLED"
			echo "  Candidate: ${CANDIDATE:-$INSTALLED}"
			;;
	esac
}
writeToConsole() { shift; [[ "$1" == "$MSG_VISIT_VERSION_HISTORY_PAGE" ]] || MESSAGES+=("$*"); }

# --- helpers

check() { # description expectedMessages... - runs reportPackageNews with a fresh reminder
	local description="$1" expected actual
	shift
	rm -rf "$VAR_LIB_DIRECTORY"
	MESSAGES=()
	reportPackageNews
	expected="$(printf '%s|' "$@")"
	actual="$(printf '%s|' "${MESSAGES[@]}")"
	if [[ "$expected" != "$actual" ]]; then
		echo "Error: $description"
		echo "       expected: $expected"
		echo "       actual:   $actual"
		error=1
	fi
}

U=$MSG_NEW_VERSION_AVAILABLE
I=$MSG_NEW_PACKAGE_VERSION_INSTALL
B=$MSG_BETAVERSION_AVAILABLE

# --- releases and hotfixes

INSTALLED="0.7.5"; HELD=0; STABLE="0.7.4 0.7.5"; BETA=""; CANDIDATE="0.7.5"; DEPRECATED_PROPERTY=""
check "latest release installed"

STABLE="0.7.4 0.7.5 0.7.5-m1"; CANDIDATE="0.7.5-m1"
check "hotfix" "$U 0.7.5-m1 0.7.5"

STABLE="0.7.4 0.7.5 0.7.5-m1 0.7.6"; CANDIDATE="0.7.6"
check "release" "$U 0.7.6 0.7.5"

DEPRECATED_PROPERTY="0.7.6"
check "deprecated release isn't reported, apt upgrade would install it" "$I 0.7.5-m1 0.7.5 0.7.5-m1"

DEPRECATED_PROPERTY="0.7.5-m1, 0.7.6"
check "all newer versions deprecated"

DEPRECATED_PROPERTY=""; INSTALLED="0.7.4"; HELD=1; STABLE="0.7.4 0.7.5"; CANDIDATE="0.7.5"
check "held release" "$I 0.7.5 0.7.4 0.7.5"
HELD=0

# --- individual fix

INSTALLED="0.7.5-m1~u972.1"; STABLE="0.7.5"; BETA="0.7.6~beta1"; CANDIDATE="0.7.5-m1~u972.1"
check "individual fix newer than repository, beta announced" "$B 0.7.6~beta1"

STABLE="0.7.5 0.7.5-m1"; BETA=""; CANDIDATE="0.7.5-m1"
check "individual fix replaced by hotfix" "$U 0.7.5-m1 0.7.5-m1~u972.1"

# --- betas

INSTALLED="0.7.5"; STABLE="0.7.5"; BETA="0.7.6~beta1"; CANDIDATE="0.7.5"
check "beta announced" "$B 0.7.6~beta1"

DEPRECATED_PROPERTY="0.7.6-beta1"
check "deprecated beta (VERSION notation) isn't announced"
DEPRECATED_PROPERTY=""

STABLE="0.7.5 0.7.6"; BETA="0.7.6~beta1"; CANDIDATE="0.7.6"
check "beta older than release isn't announced" "$U 0.7.6 0.7.5"

INSTALLED="0.7.6~beta1"; STABLE="0.7.5"; BETA="0.7.6~beta1 0.7.6~beta2"; CANDIDATE="0.7.6~beta2"
check "beta tester gets newer beta" "$U 0.7.6~beta2 0.7.6~beta1"

DEPRECATED_PROPERTY="0.7.6~beta2"
check "beta tester: deprecated beta ignored"
DEPRECATED_PROPERTY=""

INSTALLED="0.7.6~beta2"; STABLE="0.7.5 0.7.6"; CANDIDATE="0.7.6"
check "beta tester gets release" "$U 0.7.6 0.7.6~beta2"

# --- reminder: reported UPDATE_REMINDER_MAX times per version

INSTALLED="0.7.5"; STABLE="0.7.5 0.7.6"; BETA=""; CANDIDATE="0.7.6"
rm -rf "$VAR_LIB_DIRECTORY"
count=0
for (( i=0; i < UPDATE_REMINDER_MAX + 2; i++ )); do
	MESSAGES=()
	reportPackageNews
	(( ${#MESSAGES[@]} )) && (( count++ ))
done
if (( count != UPDATE_REMINDER_MAX )); then
	echo "Error: update reported $count times instead of $UPDATE_REMINDER_MAX"
	error=1
fi
STABLE="0.7.5 0.7.6 0.7.7"; CANDIDATE="0.7.7"; MESSAGES=()
reportPackageNews
if [[ "${MESSAGES[*]}" != "$U 0.7.7 0.7.5" ]]; then
	echo "Error: new version doesn't reset the reminder: ${MESSAGES[*]}"
	error=1
fi

# --- isVersionDeprecated with lists and both notations

DEPRECATED_PROPERTY="0.7.4, 0.7.5-beta1 0.7.5-m1"; SKIP_DEPRECATED=""
for v in 0.7.4 0.7.5-beta1 0.7.5~beta1 0.7.5-m1; do
	isVersionDeprecated "$v" || { echo "Error: $v not deprecated"; error=1; }
done
for v in 0.7.5 0.7.5-m2 0.7.4.1; do
	isVersionDeprecated "$v" && { echo "Error: $v deprecated"; error=1; }
done
SKIP_DEPRECATED="0.7.4"
isVersionDeprecated "0.7.4" && { echo "Error: SKIP_DEPRECATED ignored"; error=1; }

(( error )) || echo "reportPackageNews o.k."
exit $error
