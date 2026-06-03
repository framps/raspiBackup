#!/bin/bash
#######################################################################################################################
#
#    Build raspiBackup Debian package
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

usage() {
	cat <<"EOF_USAGE"
Usage:

	build.sh [options]

That simple call builds a Debian package from raspiBackup.
Finally it runs `lintian` to check the package for compliance.
That is a reduced check to fit this package not being a "real" Debian package.

Options:

    --no-check     don't check anything with `lintian`
    -h | --help    display this short help

In file 'build.conf' you can configure some aspects of the build process.

EOF_USAGE
}


# shellcheck disable=1091
source ./common.sh

if [[ ! -f ./build.conf ]] ; then
	echo "Error: Configuration file 'build.conf' not found."
	echo "Creating one for you now. Please check/edit it and try again..."

	cat <<EOF_CONF > ./build.conf
# BRANCH_TO_DEB
# The branch used to build the Debian package from.
# If empty then the curent branch is used.
# Note: Always only the commited changes are taken into account!
# BRANCH_TO_DEB="master"
# BRANCH_TO_DEB="m_972"
BRANCH_TO_DEB=""

# Note: Some of the following variables need to be exported
#       because they are used in/with envsubst.

# Debian wants to have all-lowercase package names
export PACKAGE_NAME="raspibackup"

# absolute pathes for the files in the package
# will be used relatively and absolutely
export DIR_BIN="/usr/local/bin"
export DIR_ETC="/usr/local/etc"
export DIR_LIB="/usr/local/lib"
export DIR_SHARE="/usr/local/share"

# LINTIAN_CHECK
#   - "full"    : all checks
#   - "reduced" : intentionally suppress some checks (default here)
#   - ""        : no checks at all
LINTIAN_CHECK=reduced

# LINTIAN_OPTIONS
#   - "--info" : display more details on failed checks
LINTIAN_OPTIONS="--verbose --info --color always --fail-on error"

# VERBOSITY
#   - normal
#   - debug
VERBOSITY=normal

# GPG_KEYID
# The GPG key ID used for signing the built package. Required!
GPG_KEYID=
EOF_CONF

	exit 1
fi


source ./build.conf

[[ -v LINTIAN_CHECK ]] || LINTIAN_CHECK=reduced
[[ -v LINTIAN_OPTIONS ]] || LINTIAN_OPTIONS="--verbose --info --color always"

VERBOSITY="${VERBOSITY:-debug}"

if [[ -z "$GPG_KEYID" ]] ; then
	echo ""
	echo "Error: The package can't be signed due to missing GPG_KEYID!"
	echo "       Please set GPG_KEYID in 'build.conf' to the ID to be used"
	echo "       for signing the built package."
	echo ""
	exit 1
fi


## For the transition of older gpg.conf to build.conf:
#
# if [[ -f gpg.conf ]] ; then
# 	# fill GPG_KEYID with existing local key
# 	# shellcheck disable=1091
# 	source ./gpg.conf
# 	cat ./gpg.conf >> build.conf
# 	mv gpg.conf gpg.conf.bak
# 	echo "Note: Moved the GPG_KEYID from 'gpg.conf' into 'build.conf'!"
# fi


if (( $# > 0 )); then
	case "$1" in
	    -h|--help) usage
		       exit
		       ;;
	    --no-check) LINTIAN_CHECK=""
			shift
			;;
	esac
fi

LOG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")").log
readonly LOG_FILE
DEBUG_FILE=$(cut -d'.' -f1 <<< "$(basename "$0")")-debug.log
readonly DEBUG_FILE

exec 1> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE")
exec 2> >(stdbuf -i0 -o0 -e0 tee -ia "$LOG_FILE" >&2)

rm -f "$LOG_FILE" || true
rm -f "$DEBUG_FILE" || true

trap 'err $?' ERR


GITSRC=$(mktemp --tmpdir -d raspiBackup_gitsrc4deb.XXXXXX)
# shellcheck disable=2034
readonly GITSRC

CURRENT_BRANCH=$(git branch --show-current)

BRANCH_TO_DEB="${BRANCH_TO_DEB:-${CURRENT_BRANCH}}"
show "Using branch '$BRANCH_TO_DEB' as source for the build"

if [[ "$CURRENT_BRANCH" == "$BRANCH_TO_DEB" ]] ; then
    git worktree add --detach "$GITSRC"
else
    git worktree add "$GITSRC" "$BRANCH_TO_DEB"
fi

export VERSION
# extract version number from raspiBackup script
version="$(grep "^VERSION=" "$GITSRC/raspiBackup.sh" 2>/dev/null) | cut -f 2 -d "=" )"
REGEX='.*="([^"]*)"'
if [[ $version =~ $REGEX ]]; then
	VERSION=${BASH_REMATCH[1]}
fi

# allow to pass another version number for upgrade/downgrade tests
if (( $# > 0 )); then
	VERSION="$1"
fi

# underscores are not allowed in Debian version numbers
# change m_972 to m-972
VERSION="$(sed -E 's/_/-/g' <<< "$VERSION")"
VERSION_FILES="_$(sed -E 's/_/./g' <<< "$VERSION")"

show "Building deb package '${PACKAGE_NAME}' for raspiBackup $VERSION"

rm -rf "$TGT"
rm -rf "$DEB_TGT"
mkdir -p "$DEB_TGT"

# copy source files
install -m755 -D -t "$TGT/$DIR_BIN" "$GITSRC/raspiBackup.sh" "$GITSRC/installation/raspiBackupInstallUI.sh"

# and get rid of .sh extension
pushd "$TGT/$DIR_BIN" > /dev/null
mv raspiBackup.sh raspiBackup
mv raspiBackupInstallUI.sh raspiBackupInstallUI
popd > /dev/null

# copy config files - Note: They may contain credentials - therefore change to 600 during installation
install -m644 -D -t "$TGT/$DIR_ETC/${PACKAGE_NAME}" "$GITSRC/config/raspiBackup_de.conf" "$GITSRC/config/raspiBackup_en.conf"
# make the english version the default
mv "$TGT/$DIR_ETC/${PACKAGE_NAME}/raspiBackup_en.conf" "$TGT/$DIR_ETC/${PACKAGE_NAME}/raspiBackup.conf"

# copy systemd files
install -m644 -D -t "$TGT/$DIR_LIB/systemd/system" "$GITSRC/installation/raspiBackup.service" "$GITSRC/installation/raspiBackup.timer"

# copy extension files
for file in "$GITSRC"/extensions/raspiBackup_*; do
	install -m755 -D -t "$TGT/$DIR_SHARE/${PACKAGE_NAME}" "$file"
done

# get current commit sha and date into code
pushd "$GITSRC" > /dev/null
last_date=$(git log --pretty=format:"%ai" -1)
sha1=$(git log --pretty=format:"%h" -1)
popd > /dev/null

# the gitsrc worktree is no longer needed here
git worktree remove "$GITSRC"

# Insert commit date and sha1 into the scripts
sed -i -e "s/\\\$Date\\\$/\\\$Date: $last_date\\\$/g" -e "s/\\\$Sha1\\\$/\\\$Sha1: $sha1\\\$/g" "$TGT/$DIR_BIN"/raspiBackup* "$TGT/$DIR_SHARE/${PACKAGE_NAME}"/*

# copy doc files (copyright in this case)
install -m644 -D -t "$TGT/$DIR_SHARE/doc/${PACKAGE_NAME}" "$PACKAGE/DEBIAN/copyright"
# The above locations isn't accepted by lintian, the one below is okay:
#   install -m644 -D -t "$TGT/usr/share/doc/${PACKAGE_NAME}" "$PACKAGE/DEBIAN/copyright"
# But perhaps we should keep the first location and just silence lintian a bit... See below.

mkdir -p "$TGT/DEBIAN"
# create DEBIAN package files and insert version number in control file
envsubst < "$PACKAGE/DEBIAN/control"   > "$TGT/DEBIAN/control"
envsubst < "$PACKAGE/DEBIAN/conffiles" > "$TGT/DEBIAN/conffiles"
envsubst < "$PACKAGE/DEBIAN/postinst"  > "$TGT/DEBIAN/postinst"
chmod 644 "$TGT/DEBIAN/conffiles" "$TGT/DEBIAN/control"
chmod 755 "$TGT/DEBIAN/postinst"

rc=0

show "Build (and sign) package"
LC_ALL=C dpkg-deb --root-owner-group --build "$TGT" "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

if [[ "$VERBOSITY" != debug ]] ; then
	exec 3> "$DEBUG_FILE"
	exec 4>&1
	exec 5>&2
	exec 1>&3 2>&1
fi

show "Resulting DEBIAN package files ..."

for f in "$TGT"/DEBIAN/* ; do
	echo ""
	show "... $f"
	cat "$f"
done

show "Resulting systemd files ..."

for f in "$TGT/$DIR_LIB"/systemd/system/* ; do
	echo ""
	show "... $(realpath --relative-to . "$f")"
	cat "$f"
done

show "${PACKAGE_NAME} $VERSION package information"
dpkg-deb -I "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"

show "Show files which will be installed"
dpkg-deb -c "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb"


show "Sign package"

gpg --verbose --yes --detach-sign -u "$GPG_KEYID" "$DEB_TGT/${PACKAGE_NAME}${VERSION_FILES}.deb" || exit $?


if [[ "$VERBOSITY" != debug ]] ; then
	if [[ -f "$DEBUG_FILE" ]] ; then
		cat "$DEBUG_FILE" >> "$LOG_FILE"
		rm "$DEBUG_FILE"
	fi
	exec 3>&-
	exec 1>&4-
	exec 2>&5-
fi


# create links
pushd "$DEB_TGT" > /dev/null
ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb" "${PACKAGE_NAME}.deb"
if [[ -n "$GPG_KEYID" ]] ; then
	ln -sf "${PACKAGE_NAME}${VERSION_FILES}.deb.sig" "${PACKAGE_NAME}.deb.sig"
fi
popd > /dev/null


if [[ -n "$LINTIAN_CHECK" ]] ; then
	show "Check package with lintian "

	if ! command -v lintian > /dev/null ; then
		echo "Error: Can't check package because 'lintian' isn't installed!"
		exit 1
	fi

	# Note: The default behaviour for lintian exiting with rc=2 is:
	#         `--fail-on error`
	#       Since this packet isn't a real Debian one there are some
	#       "accepted" errors. We simply **could** ignore all of the
	#       failing checks by using option '--fail-on pedantic'.
	#       But the cleaner way is:
	#       Only suppress the unwanted checks via --suppress_tags.
	case "$LINTIAN_CHECK" in
		full) # Sometimes we might want to do a full check
		      echo "Note: Reports all errors, even the accepted/known ones!"
		      echo ""
		      SUPPRESS_TAGS=""
		      ;;

		*) # "reduced" checks is the default
		   SUPPRESS_TAGS="--suppress-tags file-in-unusual-dir"
		   SUPPRESS_TAGS="$SUPPRESS_TAGS,dir-in-usr-local,file-in-usr-local"
		   SUPPRESS_TAGS="$SUPPRESS_TAGS,file-in-usr-marked-as-conffile,non-etc-file-marked-as-conffile"
		   SUPPRESS_TAGS="$SUPPRESS_TAGS,no-changelog"
		   SUPPRESS_TAGS="$SUPPRESS_TAGS,no-copyright-file"
		   ;;
	esac

	# shellcheck disable=2086  # Double quote to prevent globbing and word splitting
	lintian $LINTIAN_OPTIONS $SUPPRESS_TAGS "$DEB_TGT/${PACKAGE_NAME}.deb" || exit $?
fi


show "The final package in $DEB_TGT"
ls -l "$DEB_TGT"

