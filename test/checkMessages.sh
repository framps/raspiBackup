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

errors=0

echo "Searching for message constants not used..."

grep -E '^MSG_.*=[[:digit:]]+' ../raspiBackup.sh > messages.dat
echo "" > msg.dat

while read line; do
   msg=$(cut -f 1 -d '=' <<< $line)
   echo $msg >> msg.dat
done < messages.dat

while read line; do
   cnt=$(grep -c "[^\[]\$$line" ../raspiBackup.sh)
   if [[ $cnt == 0 ]]; then
		if [[ $line != "MSG_UNDEFINED" ]];then
			echo "Not used: $line"
			error=1
		fi
   fi
done < msg.dat

echo "Searching for messages not defined..."

grep -E 'writeToConsole.+MSG_.*' ../raspiBackup.sh | awk '{ print $3;}' | grep "MSG_" | sed 's/\$//' > messages.dat

while read line; do
   cnt=$(grep -c "$line" msg.dat)
   if [[ $cnt == 0 ]]; then
   	echo "Not defined: $line"
   	error=1
   fi
done < messages.dat

rm msg.dat
rm messages.dat

exit $error
