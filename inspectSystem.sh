#!/bin/bash

#------------------------------------------------------------------------------------------------------------------
# This script collects information about the running system which will help future development of raspiBackup.
# The system will not be modified in any way. But some commands require root access and therefore this script has to be
# invoked with sudo.
# All collected information is written into file raspiBackup.info. Sensitive information may be exposed
# which should be masqueraded before sharing this file.
#------------------------------------------------------------------------------------------------------------------
# Dieses Script sammelt Informationen des laufenden Systems die bei der Weiterentwicklung von raspiBackup helfen.
# Änderungen werden auf dem System nicht vorgenommen. Manche Befehle benötigen root Rechte und deshalb muss
# das Script per sudo aufgerufen werden.
# Alle Informationen werden in eine Datei raspiBackup.info gesammelt. Sie koennen sensitive Informationen enthalten
# und sollten vor dem Verteilen maskiert werden.
#------------------------------------------------------------------------------------------------------------------

#######################################################################################################################
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for latest code and other details
#
#######################################################################################################################
#
#    Copyright (C) 2018 framp at linux-tips-and-tricks dot de
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

LANG_EXT=${LANG^^*}
LANG_SUFF=${LANG_EXT:0:2}
[[ $LANG_SUFF != "DE" ]]
de=$?

MYSELF="${0##*/}"
MYNAME=${MYSELF%.*}
LOGFILE="raspiBackup.info"

rm $LOGFILE &>/dev/null

function willExecute() {
	(( de )) && echo "Es wird '$1' ausgeführt ..." || echo "Executing '$1'..."
	echo "========================= $1" >> "$LOGFILE"
	eval "$1" &>>"$LOGFILE"
	echo &>>"$LOGFILE"
}

echo "$info"

if (( $UID != 0 )); then
	(( de )) && echo "Script muss als root aufgerufen werden. Benutze 'sudo $0'." || echo "Script has to be executed as root. Use 'sudo $0'."
	exit 42
fi

sed -n '/^# Start of list/,/^# End of list/p;/^# Liste Ende/q' $0

(( de )) && m="Datensammeln starten (j/n)?" || m="Start data collection (y/n)?"

read -p "$m" -t 60 -N 1 answer
if [[ ! $answer =~ [jJyY] ]]; then
	echo
	(( de )) && echo "Datensammeln abgebrochen." || echo "Data collection aborted."
	exit 0
fi

echo

# Start of list of commands which will be executed
willExecute "cat /etc/os*release"
willExecute "for f in /etc/*[-_]{release,version}; do echo - \$f -; cat \$f; echo; done"
willExecute "cat /etc/fstab"
willExecute "fdisk -l"
willExecute "blkid"
willExecute "lsblk -r -n -b"
willExecute "mount"
willExecute "find / -maxdepth 3 -type f -name cmdline.txt"
willExecute "findmnt / -o source -n"
willExecute "findmnt /boot -o source -n"
willExecute "find / -maxdepth 3 -type d -iname 'boot'"
# End of list of commands which will be executed

old_owner=$(stat -c %u:%g "$0")
chown $old_owner "$LOGFILE"

echo
(( de )) && echo "$LOGFILE wurde erstellt." || echo "$LOGFILE created."
