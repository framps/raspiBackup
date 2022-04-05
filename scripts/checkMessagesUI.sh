#!/bin/bash

#######################################################################################################################
#
# 	Check if there are unused or undefined messaged messages in raspiBackupInstallUI
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

echo "Searching for message constants not used..."

grep -E '^.*=\$\(\(SCNT\+\+\)\)' ../installation/raspiBackupInstallUI.sh > messages.dat
echo "" > msg.dat

while read line; do
	if [[ "$line" =~ (.*)=\$\(\(SCNT\+\+\)\) ]]; then
		name=${BASH_REMATCH[1]}
	fi
    echo $name >> msg.dat
done < messages.dat

while read line; do
   cnt=$(grep -c "[^\[]\$$line" ../installation/raspiBackupInstallUI.sh)
   if [[ $cnt == 0 ]]; then
   	echo "$line: $cnt"
   fi
done < msg.dat | uniq

rm msg.dat
rm messages.dat
