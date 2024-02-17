#!/bin/bash

set -eou pipefail

OUTPUT="json"

echo "" > $OUTPUT

started=0

while read sep id message; do
	msg="$id $message"
	tpl="$(egrep "^MSG_EN.+$id" ../raspiBackup.sh | cut -f 2 -d = | sed 's/^"//; s/"$//')"

	#echo $msg

	msga=( $msg )
	tpla=( $tpl )

	id="$(sed 's/:$//' <<< $id)"
	echo "{" >> $OUTPUT
	echo "\"id\" : \"$id\" ," >> $OUTPUT
	echo -n "\"text\" : \"$message\"" >> $OUTPUT

	if (( started )); then
		echo -n ", " >> $OUTPUT
	fi

	parms=0
	startedParms=0

	for (( i=1; i< ${#tpla[@]}; i++ )); do
		m="${msga[$i]}"
		t="${tpla[$i]}"
		if [[ $m != $t ]]; then
			if (( startedParms )); then
				echo " , " >> $OUTPUT
			fi
			if (( ! parms )); then
				parms=1
				echo "\"parms\" : [" >> $OUTPUT
				echo -n "     \"$m\"" >> $OUTPUT
			else
				echo -n "     \"$m\"" >> $OUTPUT
			fi
			startedParms=1
		fi
	done
	if (( parms )); then
		if (( startedParms )); then
			echo >> $OUTPUT
		fi
		echo "     ]" >> $OUTPUT
	fi
	echo "}" >> $OUTPUT
done < messages

cat $OUTPUT
