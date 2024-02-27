#!/bin/bash

#######################################################################################################################
#
# 	Sample script to convert raspiBackup messages into JSON format
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#	NOTE: This is sample code and is provided as is with no support.
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

set -eou pipefail

OUTPUT="$1"

[[ -e $OUTPUT ]] && rm $OUTPUT &>>/dev/null

echo "[" >> $OUTPUT
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
		echo "," >> $OUTPUT
	else
		echo >> $OUTPUT
	fi
	first=0
             
	echo -n $final >> $OUTPUT

done < messages

echo "]" >> $OUTPUT
