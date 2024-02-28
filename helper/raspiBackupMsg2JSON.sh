#!/bin/bash
#
#######################################################################################################################
#
#  Sample script to convert raspiBackup messages into JSON format
#
#  Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#  NOTE: This is sample code and is provided as is with no support.
#
#######################################################################################################################
#
#   Copyright (c) 2024 framp at linux-tips-and-tricks dot de
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################
#
# --- RBK0009I: @HOSTNAME@: raspiBackup.sh V0.6.9.1 - 2024-01-02 (2e7040a) started at Fri 16 Feb 18:30:03 CET 2024.
# --- RBK0031I: Checking whether a new version of raspiBackup.sh is available.
# --- RBK0151I: Using backuppath /backup with partition type fuse.
# --- RBK0085I: Backup of type ddz started. Please be patient.
# --- RBK0078I: Backup time: 03:25:26.
# --- RBK0033I: Please wait until cleanup has finished.
# --- RBK0159I: 10 backups kept for ddz backup type. Please be patient.
# --- RBK0017I: Backup finished successfully.
# --- RBK0010I: @HOSTNAME@: raspiBackup.sh V0.6.9.1 - 2024-01-02 (2e7040a) stopped at Fri 16 Feb 21:55:50 CET 2024 with rc 0.
#
# will create
#[
#  {
#    "id": "RBK0009I",
#    "text": "@HOSTNAME@: raspiBackup.sh V0.6.9.1 - 2024-01-02 (2e7040a) started at Fri 16 Feb 18:30:03 CET 2024.",
#    "parms": [
#      "@HOSTNAME@:",
#      "raspiBackup.sh",
#      "V0.6.9.1",
#      "2024-01-02",
#      "(2e7040a)",
#      "Fri"
#    ]
#  },
#  {
#    "id": "RBK0031I",
#    "text": "Checking whether a new version of raspiBackup.sh is available.",
#    "parms": [
#      "raspiBackup.sh"
#    ]
#  },
#  {
#    "id": "RBK0151I",
#    "text": "Using backuppath /backup with partition type fuse.",
#    "parms": [
#      "/backup",
#      "fuse."
#    ]
#  },
#  {
#    "id": "RBK0085I",
#    "text": "Backup of type ddz started. Please be patient.",
#    "parms": [
#      "ddz"
#    ]
#  },
#  {
#    "id": "RBK0078I",
#    "text": "Backup time: 03:25:26.",
#    "parms": [
#      "03:25:26."
#    ]
#  },
#  {
#    "id": "RBK0033I",
#    "text": "Please wait until cleanup has finished.",
#    "parms": []
#  },
#  {
#    "id": "RBK0159I",
#    "text": "10 backups kept for ddz backup type. Please be patient.",
#    "parms": [
#      "10",
#      "ddz"
#    ]
#  },
#  {
#    "id": "RBK0017I",
#    "text": "Backup finished successfully.",
#    "parms": []
#  },
#  {
#    "id": "RBK0010I",
#    "text": "@HOSTNAME@: raspiBackup.sh V0.6.9.1 - 2024-01-02 (2e7040a) stopped at Fri 16 Feb 21:55:50 CET 2024 with rc 0.",
#    "parms": [
#      "@HOSTNAME@:",
#      "raspiBackup.sh",
#      "V0.6.9.1",
#      "2024-01-02",
#      "(2e7040a)",
#      "Fri",
#      "16",
#      "Feb",
#      "21:55:50"
#    ]
#  }
#]
#

set -eou pipefail

SOURCE="$1"
DESTINATION="$2"

[[ ! -e $SOURCE ]] && { echo "$SOURCE does not exist"; exit 1; }

if ! which jq &>/dev/null; then
   echo "??? Missing jq"
   exit 1
fi

TEMP_OUTPUT=$(mktemp)

echo "[" >> $TEMP_OUTPUT
first=1

rbkSource="$(which raspiBackup.sh)"

while read sep id message; do

   msg="$id $message"
   tpl="$(egrep "^MSG_EN.+$id" "$rbkSource" | cut -f 2 -d = | sed 's/^"//; s/"$//')"

   msga=( $msg )
   tpla=( $tpl )

   ID="$(sed 's/:$//' <<< $id)"
   TEXT="$message"
   PARMS=()

   for (( i=1; i< ${#tpla[@]}; i++ )); do
      m="${msga[$i]}"
      t="${tpla[$i]}"
      if [[ $m != $t ]]; then
         PARMS+=("$m")
      fi
   done

   final=$(jq -n --arg id "$ID" \
              --arg text "$TEXT" \
              --argjson parms "$(jq -nc ' $ARGS.positional ' --args ${PARMS[@]})" \
              '$ARGS.named' )

   if (( ! $first )); then
      echo "," >> $TEMP_OUTPUT
   fi
   first=0

   echo -n $final >> $TEMP_OUTPUT

done < "$SOURCE"

echo >> $TEMP_OUTPUT
echo "]" >> $TEMP_OUTPUT

[[ -e "$DESTINATION" ]] && rm "$DESTINATION" &>>/dev/null

jq "." "$TEMP_OUTPUT"  > "$DESTINATION"
rm "$TEMP_OUTPUT" &>>/dev/null



