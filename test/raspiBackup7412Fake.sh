#!/bin/bash

#######################################################################################################################
#
# 	Test script to test raspiBackup7424.sh in order to implement the following backup strategy:
#	1) Keep last 7 daily backups
#	2) Keep last 4 weekly backups
#	3) Keep last 12 monthly backups
#	4) Keep last 5 yearly backups
#
#	Backup deletion strategy borrowed from 'Automating backups on a Raspberry Pi NAS'
#	(https://opensource.com/article/18/8/automate-backups-raspberry-pi) and adapted for raspiBackup
#
# 	Visit http://www.linux-tips-and-tricks.de/raspiBackup for details about raspiBackup
#
#######################################################################################################################
#
#   Copyright # (C) 2019 - framp at linux-tips-and-tricks dot de
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

set -euf -o pipefail

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.1"

set +u;GIT_DATE="$Date: 2019-05-03 15:05:59 +0200$"; set -u
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE)
set +u;GIT_COMMIT="$Sha1: 1fbe96b$";set -u
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION, $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

# number of backups to keep
DAILY=7
WEEKLY=4
MONTHLY=12
YEARLY=5

# add pathes if not already set (usually not set in crontab)

if [[ -e /bin/grep ]]; then
   PATHES="/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin"
   for p in $PATHES; do
      if ! /bin/grep -E -q "[^:]$p[:$]" <<< $PATH; then
         [[ -z $PATH ]] && export PATH=$p || export PATH="$p:$PATH"
      fi
   done
fi

function readVars() {
	if [[ -f /tmp/raspiBackup.vars ]]; then
		source /tmp/raspiBackup.vars						# retrieve some variables from raspiBackup for further processing
# now following variables are available for further backup processing
# BACKUP_TARGETDIR refers to the backupdirectory just created
# BACKUP_TARGETFILE refers to the dd backup file just created
	else
		echo "/tmp/raspiBackup.vars not found"
		exit 42
	fi
}

function listYearlyBackups() {
	if (( $YEARLY > 0 )); then
		for i in $(seq 0 $(( $YEARLY-1)) ); do
			f_d=$(ls | egrep "\-backup\-$(date +%Y -d "${i} year ago")[0-9]{2}[0-9]{2}" | sort -u | head -n 1 | cut -d'-' -f 4) # grab datefield (cut) for the first day for each year
			ls | egrep "\-backup\-$f_d" | sort -ur | head -n 1 # and use the last made backup (includig time sort !) from that day
		done
	fi
}

function listMonthlyBackups() {
	if (( $MONTHLY > 0 )); then
		for i in $(seq 0 $(($MONTHLY-1)) ); do
			# ... error in date ... see http://bashworkz.com/linux-date-problem-1-month-ago-date-bug/
			# ls ${BACKUPDIR} | egrep "\-backup\-$(date +%Y%m -d "${i} month ago")[0-9]{2}" | sort -u | head -n 1
			d=$(date -d "$(date +%Y%m15) -${i} month" +%Y%m)
			f_d=$(ls ${BACKUPDIR} | egrep "\-backup\-$d[0-9]{2}" | sort -u | head -n 1 | cut -d'-' -f 4) # grab datefield (cut) for the first day for each month
			ls | egrep "\-backup\-$f_d" | sort -ur | head -n 1 # and use the last made backup (includig time sort !) from that day
		done
	fi
}

function listWeeklyBackups() {
	if (( $WEEKLY > 0 )); then
		for i in $(seq 0 $(( $WEEKLY-1)) ); do
			f_d=$(ls ${BACKUPDIR} | grep "\-backup\-$(date +%Y%m%d -d "last monday -${i} weeks")" | sort -u | head -n 1 | cut -d'-' -f 4) # grab datefield (cut) for the first day for each week
			ls | egrep "\-backup\-$f_d" | sort -ur | head -n 1 # and use the last made backup (includig time sort !) from that day
		done
	fi
}

function listDailyBackups() {
	if (( $DAILY > 0 )); then
		for i in $(seq 0 $(( $DAILY-1)) ); do
			ls ${BACKUPDIR} | grep "\-backup\-$(date +%Y%m%d -d "-${i} day")" | sort -ur | head -n 1 # use latest Backup that was made each day
		done
	fi
}

function getAllBackups() {
        listYearlyBackups
        listMonthlyBackups
        listWeeklyBackups
        listDailyBackups
}

function listUniqueBackups() {
        getAllBackups | sort -u
}

function listBackupsToDelete() {
        ls ${BACKUPDIR} | grep -v -e "$(echo -n $(listUniqueBackups) | sed "s/ /\\\|/g")"
}

# main program

### NOTE ### This is test code for raspiBackup7412.sh !!!

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)
DIR="fakebackups"

rm -rf $DIR
mkdir $DIR	# create directory to get faked backup directories
# create daily fake backups for the last 6 years
c=$((365 * 6))

# create just daily backup directories as raspiBackup will do
today=$(date +"%Y-%m-%d")
echo "Creating fake backups in dir $DIR"
TICKS=100
t=$TICKS
for i in $(seq 0 $c); do
	F_D=$(shuf -i 1-5 -n 1)
	for y in $(seq 0 $F_D); do		# added rnd loop to make 1-5 backups each day - warning LOG/CONSOLE SPAM ! call test with echo to file
		F_HR=$(shuf -i 0-24 -n 1)
		F_MI=$(shuf -i 0-59 -n 1)
		F_SI=$(shuf -i 0-59 -n 1)
		printf -v F_HR "%02d" $F_HR
		printf -v F_MI "%02d" $F_MI
		printf -v F_SI "%02d" $F_SI
        h="raspberry-rsync-backup-"$(date -d "$today -$i days" +%Y%m%d-)
        n="$h$F_HR$F_MI$F_SI"
		mkdir -p $DIR/$n
		if (( --t == 0 )); then
			echo "Next $TICKS ... $n ..."
			t=$TICKS
		fi
	done
done


#raspiBackup.sh -k \\-1     	 						# ===> keep all backups (option -k \\-1), configure all other options in /usr/local/etc/raspiBackup.conf. Don't forget -a and -o options
rc=0

if (( $rc == 0 )); then
	echo "Backup succeeded :-)"						# do whatever has to be done in case of success
	#readVars
	BACKUPDIR="$SCRIPT_DIR/$DIR"
	cd ${BACKUPDIR}
	#echo "--- Existing backups ---"
	#ls -1
	echo "Execute backup strategy"
	listBackupsToDelete | while read file_to_delete; do
		rm -rf ${file_to_delete}
	done
	echo "--- Existing backups when backup strategy was applied ---"
	ls -1
else
	echo "Backup failed with rc $rc :-("			# do whatever has to be done in case of backup failure
	exit $rc
fi
