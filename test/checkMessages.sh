#!/bin/bash

#######################################################################################################################
#
# 	Check if there are unused or undefined messaged messages in raspiBackup
#
#######################################################################################################################
#
#    Copyright (c) 2022 framp at linux-tips-and-tricks dot de
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

error=0

echo "Searching for message constants not used..."

messagesFile=$(mktemp)
msgFile=$(mktemp)

messages=0
notUsed=0
notDefined=0

# collect all messageids
grep -E '^MSG_.*=[[:digit:]]+' ../raspiBackup.sh > $messagesFile
echo "" > $msgFile

while read line; do
   msg=$(cut -f 1 -d '=' <<< $line)
   echo $msg >> $msgFile
   ((messages++))
done < $messagesFile

echo "Messages defined: $messages "

# check if messageid is used
echo "Searching for messages not used..."
while read line; do
   cnt=$(grep -c "[^\[]\$$line" ../raspiBackup.sh)
   if [[ $cnt == 0 ]]; then
		if [[ $line != "MSG_UNDEFINED" ]];then
			echo "Not used: $line"
			((notUsed++))
			error=1
		fi
   fi
done < $msgFile

echo "Searching for messages not defined..."

grep -E 'writeToConsole.+MSG_.*' ../raspiBackup.sh | awk '{ print $3;}' | grep "MSG_" | sed 's/\$//' > $messagesFile

while read line; do
   cnt=$(grep -c "$line" $msgFile)
   if [[ $cnt == 0 ]]; then
   	echo "Not defined: $line"
	((notDefined++))
   	error=1
   fi
done < $messagesFile

rm $msgFile
rm $messagesFile

if (( $notUsed > 0)); then
	echo "Unused messageids: $notUsed"
fi
if (( $notDefined > 0)); then
	echo "Undefined messageids: $notDefined"
fi

exit $error
