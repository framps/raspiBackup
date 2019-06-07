#######################################################################################################################
#
# raspiBackup regression test
#
#######################################################################################################################
#
#    Copyright (C) 2013-2019 framp at linux-tips-and-tricks dot de
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

#!/bin/bash

set -e

NOTIFY_EMAIL="$(<email.conf)"

startTime=$(date +%Y-%M-%d/%H:%m:%S)
echo "Start: $startTime"
echo "Start: $startTime" | mailx -s "--- Backup regression started" "$NOTIFY_EMAIL"

./raspiBackupTest.sh
rc=$?

endTime=$(date +%Y-%M-%d/%H:%m:%S)

if [[ $rc != 0 ]]; then
	echo "??? Backup regression test failed"
	echo "End: $endTime" | mailx -s "??? Backup regression test failed" "$NOTIFY_EMAIL"
	exit 127
fi

echo "End: $endTime" | mailx -s "--- Backup regression finished" "$NOTIFY_EMAIL"

startTime=$(date +%Y-%M-%d/%H:%m:%S)
echo "Start: $startTime"
echo "Start: $startTime" | mailx -s "--- Restore regression started" "$NOTIFY_EMAIL"

./raspiRestoreTest.sh
rc=$?

endTime=$(date +%Y-%M-%d/%H:%m:%S)

echo "Start: $startTime - End: $endTime"

if [[ $rc != 0 ]]; then
	echo "??? Restore regression test failed"
	echo "End: $endTime" | mailx -s "??? Restore regression test failed" "$NOTIFY_EMAIL"
	exit 127
fi

echo "End: $endTime" | mailx -s "--- Restore regression finished" "$NOTIFY_EMAIL"

echo ":-) Raspibackup regression test finished successfully"
echo "" | mailx -s ":-) Raspibackup regression test finished sucessfully" $attach "$NOTIFY_EMAIL"

