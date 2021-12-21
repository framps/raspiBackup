#!/bin/bash
#
#######################################################################################################################
#
# Send an email using the functions from raspiBackup, based of version 0.6.4
# Written by kmbach 2017
#
# Using: raspiImageMail.sh <msgTitle> <msg> [<attach>]
#        The condition is that mail is configured in raspiBackup.conf and works in raspiBackup.
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup and https://github.com/framps/raspiBackup to get more
# details about raspiBackup
#
#	NOTE: This is sample code how to extend functionality of raspiBackup and is provided as is with no support.
#
#######################################################################################################################
#
#    Copyright (C) 2017 kmbach
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
#
# raspiImageMail.sh for raspiBackupRestore2Image.sh
# =================================================
# raspiImageMail.sh extends raspiBackupRestore2Image.sh and sends an
# eMail of it's execution result. The required function to send eMails is
# used from raspiBackup together with the eMail configuration done in
# raspiBackup.conf. Finally the console messages of raspiBackupRestore2Image.sh
# will be sent in an eMail.
#
# Base:
# raspiBackup.sh VERSION="0.6.4"
#
# Prerequisites:
# -  raspiImageMail.sh, raspiBackup.sh, raspiBackupRestore2Image.sh and pishrink.sh
#    have to be in the same directory which defaults to /usr/local/bin
# -  raspiImageMail.sh has to be executable (chmod +x raspiImageMail.sh)
# -  /usr/local/etc/raspiBackup.conf has to be configured so raspiBackup.sh
#    is able to send an eMail
#
# If any prerequisites are not fulfilled raspiBackupRestore2Image.sh will not fail.
# You just will not get an eMail.
#
#######################################################################################################################
#
# raspiImageMail.sh für raspiBackupRestore2Image.sh
# =================================================
# raspiImageMail.sh erweitert raspiBackupRestore2Image.sh um Funktionalitäten
# zum Versenden von Ergebnis- eMails. Dafür importiert raspiImageMail.sh die für das
# Versenden von eMail benötigten Funkionen aus raspiBackup.sh sowie die
# eMail- Einstellungen aus raspiBackup.conf. Die Konsolenmeldungen aus
# raspiBackupRestore2Image.sh werden in einer eMail verschickt.
#
# Basis:
# raspiBackup.sh VERSION="0.6.4"
#
# Voraussetzungen:
# -  raspiImageMail.sh muss sich, zusammen mit den Programmen
#    raspiBackup.sh, raspiBackupRestore2Image.sh und pishrink.sh,
#    im gleichen Verzeichnis befinden. Das ist standardmäßig /usr/local/bin
# -  raspiImageMail.sh muss ausführbar sein (chmod +x raspiImageMail.sh)
# -  in der /usr/local/etc/raspiBackup.conf sollte eMail konfiguriert
#    und aus raspiBackup.sh heraus funktionsfähig sein
#
# Befindet sich die Datei raspiImageMail.sh nicht im raspiBackup- Verzeichnis, ist nicht
# ausführbar oder ist die eMail- Funktion in raspiBackup nicht eingerichtet bzw.
# funktioniert nicht, führt dies zu keinem Fehlverhalten von raspiBackupRestore2Image.
# Es wird nur einfach keine email generiert. Funktioniert es widererwartend nicht sollten
# nochmals die Punkte unter 'Voraussetzungen' geprüft werden!

MYSELF=${0##*/}

VERSION="0.2.0"

if [[ ! $(which raspiBackup.sh) ]]; then
	echo "raspiBackup.sh not found"
	exit 1
fi

function usage() {
	echo "Syntax: $MYSELF <msgTitle> <msg> [<attach>]"
}

# query invocation parms
if [[ $# < 2 ]]; then
	echo "??? Missing Mail parameter"
	usage
	exit 1
fi


MSG_TITLE="$1"
MSG="$2"
APPEND="${3:-""}"

# include raspiBackup.sh
. raspiBackup.sh --include

# defaults for use functions from raspiBackup.sh
MYNAME="raspiBackup"
MSG_FILE=/dev/null
LOG_FILE="$MYNAME.log"

# include raspiBackup.conf
readConfigParameters

# set parameters from raspiBackup.conf
EMAIL=$DEFAULT_EMAIL
EMAIL_PROGRAM=$DEFAULT_MAIL_PROGRAM
EMAIL_PARMS=$DEFAULT_EMAIL_PARMS

# other defines
NL=$'\n'

# check if email includes attachment
if [[ $APPEND != "" ]]; then
    if [[ -f $APPEND ]]; then
        APPEND_LOG=1
	    LOG_FILE="$APPEND"
    else
        MSG="$MSG$NL$NL$APPEND not exist."
    fi
fi

# mail parameters are defined in .conf
if [[ -n $EMAIL ]]; then
    sendEMail "$MSG" "$MSG_TITLE" 
    RC=$?
else
    RC=1
fi

exit $RC
