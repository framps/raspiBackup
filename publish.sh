#!/bin/bash
#######################################################################################################################
#
#    Publish raspiBackup
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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH_DIR="$REPO_DIR/published"

FILES=(
    "raspiBackup.sh"
    "installation/raspiBackupInstallUI.sh"
    "installation/install.sh"
    "config/raspiBackup_de.conf"
    "config/raspiBackup_en.conf"
    "config/raspiBackup_sample_notify.conf"
    "properties/raspiBackup.properties"
)

# Current repository HEAD
sha="$(git rev-parse --short HEAD)"
date="$(git log -1 --format='%ci' HEAD)"

for file in "${FILES[@]}"; do

	# remove path
	tgtFile=${file##*/}  

    destination="$PUBLISH_DIR/$tgtFile"

    sed \
        -e "s/\\\$Sha1\\\$/$sha/g" \
        -e "s/\\\$Date\\\$/$date/g" \
        "$file" > "$destination"

    echo "Published: $file"
done

file=$PUBLISH_DIR/raspiBackupSampleExtensions.tgz
tar --owner=root --group =root -cvzf $file  extensions/*
echo "Published: $file"
