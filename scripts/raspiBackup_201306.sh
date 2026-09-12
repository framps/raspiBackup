#!/bin/bash
# vim: set expandtab tabstop=8 shiftwidth=8 autoindent smartindent
#
# Short script to create a backup of raspbian or raspbmc
#
# Invoke the script with -h to get a list of all possible arguments.
# Default parameters are defined in the script itself and can be customized.
#
# Script should be named raspiBackup.sh and copied into /usr/local/bin 
# to call it with cron every Sunday at 10 pm
#
# Samples in crontab:
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t xbmc -k 5 -o 'service xbmc stop' -a 'service xbmc start'
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t rsync -k 5 -o 'service xbmc stop' -a 'service xbmc start' -b / -e foor@bar.com
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t tar -k 5 -o 'service xbmc stop' -a 'service xbmc start'
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t dd -k 5 -e foor@bar.com
#
# !!! Check the created backup from time to time whether you can restore a system.
# !!! If you need the backup and it doesn't contain the data you expect that's not nice.
#
# See http://www.linux-tips-and-tricks.de/raspiBackup for latest code and additional information 
#
# 06/2013 - framp at linux-tips-and-tricks dot de
#
#######################################################################################################################
#
# Kleines Script um ein Backup eines raspbians oder raspbmc zu erstellen
#
# Mögliche Parameter werden beim Aufruf des Scripts mit -h angezeigt.
# Falls Parameter nicht beim Aufruf mitgegeben werden benutzt das Script
# Standardwerte, die im folgenden definiert und geändert werden können.
#
# Das Script sollte raspiBackup.sh heissen, in /usr/local/bin kopiert werden
# und am besten per cron regelmäßig aufgerufen werden. Z.B jeden Sonntag um 22 Uhr.
#
# Beispielzeile dafür in der crontab:
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t xbmc -k 5 -o 'service xbmc stop' -a 'service xbmc start'
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t rsync -k 5 -o 'service xbmc stop' -a 'service xbmc start' -b / -e foor@bar.com
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t tar -k 5 -o 'service xbmc stop' -a 'service xbmc start'
# 00 22  * * 0 /usr/local/bin/raspbiBackup.sh -p /backup -t dd -k 5 -e foor@bar.com
#
# !!! Das erstellte Backup sollte immer regelmäßig geprüft werden ob es funktioniert ein System zu restaurieren. 
# !!! Es ist sehr schlecht wenn man in dem Moment, wo man das Backup benötigt, feststellt, dass das Backup untauglich ist.
#
# Auf http://www.linux-tips-and-tricks.de/raspiBackup steht der aktuelle Code bereit sowie weitere Infoirmationen
#
# 06/2013 - framp at linux-tips-and-tricks dot de
#

VERSION="0.4.7"
MYSELF=${0##*/}
DATE=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname) 

if (( $UID != 0 )); then
	echo "??? Script must be run as root. Write 'sudo' in front of the command."
	exit 127
fi

LOG_FILE="/tmp/${MYSELF/.sh/}_${HOSTNAME}_lastRun.log"	# log for last run
LOG_FILE_VAR="/var/log/${MYSELF/.sh/}/$HOSTNAME.log"	# log file for all runs
[ ! -d /var/log/${MYSELF/.sh/} ] && mkdir -p /var/log/${MYSELF/.sh/}
rm -rf $LOG_FILE 2>&1 1>/dev/null

exec 1> >(tee -a $LOG_FILE >&1)
exec 2> >(tee -a $LOG_FILE >&2)

rc=""
LOG_NONE=0
LOG_INFO=1
LOG_DEBUG=2
declare -a LOG_PREFIX=("" "INFO" "DEBUG")

############# Begin default config section #############

# path to store the backupfile
DEFAULT_BACKUPPATH="/backup"
# how many backups to keep
DEFAULT_KEEPBACKUPS=3	
# type of backup: dd, tar or xbmc
DEFAULT_BACKUPTYPE="rsync"
# commands to stop services before backup separated by ;
DEFAULT_STOPSERVICES=""
# commands to start services after backup separated by ;
DEFAULT_STARTSERVICES=""
# email to send completion status
DEFAULT_EMAIL="" 
# directory to sync with rsync
DEFAULT_DIR_TO_BACKUP="/home/pi"
# log level
DEFAUL_LOG_LEVEL=$LOG_NONE

############# End default config section #############

function deployMyself() { # invocationparms

#    HOSTS="raspberrypi raspxbmc raspifix"
    HOSTS="raspberrypi"

    for host in $HOSTS; do
        echo "*** Copying script to $host"
        scp -p $MYSELF root@$host:/usr/local/bin > /dev/null
    done
    exit 0
}

function log() { # level message
	if [[ $1 -gt $LOG_NONE && $1 -le $LOG_LEVEL ]]; then
		echo "${LOG_PREFIX[$1]}: $2"
	fi
}

function cleanup() {
	local error=0
	trap - SIGINT SIGTERM EXIT
	log $LOG_INFO "Cleanup: $rc"
	if [[ -z "$rc" || $rc -ne 0 ]]; then
		echo "??? Error occured with rc $rc"
		error=1
	fi
		
	if (( $error )); then
		log $LOG_DEBUG "Removing incomplete backup $BACKUPPATH/$BACKUPFILE"
		rm -fr $BACKUPPATH/$BACKUPFILE 1>/dev/null 2>&1	# remove incomplete backupfile if it exists
		echo "??? Backup failed. See logfile $LOG_FILE for details"
		[ -n "$EMAIL" ] && echo "$MYSELF $passedOpts ($VERSION)" | mail -s "$HOSTNAME: $MYSELF $FAILED. RC:$rc" -a $LOG_FILE $EMAIL	
		logger -t $MYSELF "Backup failed with rc $rc"
	else
		echo "--- Backup finished successfully"
		[ -n "$EMAIL" ] && echo "$MYSELF $passedOpts ($VERSION)" | mail -s "$HOSTNAME: $MYSELF completed. RC:$rc" -a $LOG_FILE $EMAIL	
		logger -t $MYSELF "Backup finished"
	fi

	if (( $KEEPLOG )); then
		log $LOG_DEBUG "Copy logfile $LOG_FILE to $LOG_FILE_VAR"
		cat $LOG_FILE >> $LOG_FILE_VAR	# save logfile in /var/log
		rm $LOG_FILE
	fi

	if (( ! $error )) ; then
		log $LOG_DEBUG "Cleaning up log files"
		echo "--- Cleaning up log files"
		rm -f ${LOG_FILE_BASE}* 1>/dev/null 2>&1		# remove log files in /tmp
	fi
}

function bootPartitionBackup() {
		if  [[ ! -e $BACKUPPATH/../$BACKUPFILE_NODATE.img ]]; then
			log $LOG_INFO "Creating backup of boot partition on  $BACKUPPATH/../$BACKUPFILE_NODATE.img ..."
			dd if=/dev/mmcblk0p1 of=$BACKUPPATH/../$BACKUPFILE_NODATE.img bs=1M
		else
			log $LOG_INFO "Found existing backup of boot partition $BACKUPPATH/../$BACKUPFILE_NODATE.img ..."
		fi
		if  [[ ! -e $BACKUPPATH/../$BACKUPFILE_NODATE.sfdisk ]]; then
			log $LOG_INFO "Creating backup of partition layout on  $BACKUPPATH/../$BACKUPFILE_NODATE.sfdisk ..."
			sfdisk -d > $BACKUPPATH/../$BACKUPFILE_NODATE.sfdisk
		else
			log $LOG_INFO "Found existing backup of partition layout $BACKUPPATH/../$BACKUPFILE_NODATE.sfdisk ..."
		fi
}		

function ddBackup() {
	dd if=/dev/mmcblk0 of=$BACKUPPATH/$BACKUPFILE.img bs=1MB
}

function tarBackup() {
	local verbose
	verbose=""
	(( $VERBOSE )) && verbose="v" 
	bootPartitionBackup
	tar -cpzi$verbose --one-file-system -f $BACKUPPATH/$BACKUPFILE.tgz \
				--exclude=$BACKUPPATH \
				--exclude=/proc \
				--exclude=/lost+found \
				--exclude=/sys \
				--exclude=/mnt \
				--exclude=/media \
				--exclude=/dev \
				--exclude=/tmp \
				--warning=no-xdev \
				$DIR_TO_BACKUP
}

function xbmcBackup() {
	local verbose
	verbose=""
	(( $VERBOSE )) && verbose="v" 
	bootPartitionBackup
	tar -cpz$verbose --one-file-system -f $BACKUPPATH/$BACKUPFILE.tgz \
				--exclude=$BACKUPPATH \
				--warning=no-xdev \
				/home/pi/.xbmc
}

function rsyncBackup() {
	local rc verbose
	verbose=""
	(( $VERBOSE )) && verbose="v" 
	bootPartitionBackup
	lastBackupDir=$(ls -At $BACKUPPATH | head -n 1)
	log $LOG_DEBUG "LastBackupDir: $lastBackupDir"
	if  [ -z "$lastBackupDir" ]; then
		LINK_DEST=""
	else
		LINK_DEST="--link-dest=$BACKUPPATH/$lastBackupDir"
	fi
	log $LOG_DEBUG "LinkDest: $LINK_DEST"
	log $LOG_DEBUG "Starting rsync"
	rsync --exclude="$BACKUPPATH" \
		  --exclude="/proc/*" \
		  --exclude="/sys/*" \
		  --exclude="/dev/*" \
		  --exclude="/boot/*" \
		  --exclude="/tmp/*" \
		  --exclude="/run/*" \
		  --exclude="/mnt/*" \
		  $LINK_DEST \
		  --numeric-ids \
		  -aHAXx$verbose \
		  $DIR_TO_BACKUP $BACKUPPATH/$BACKUPFILE
	rc=$?
	if [ $rc -eq 23 ]; then		# some files changed during backup
		log $LOG_DEBUG "Some files changed during backup"
		return 0
	else
		return $rc
	fi
	
}

function backup() {
	local verbose
	logger -t $MYSELF "Starting backup..."
   	[ -n "$EMAIL" ] && echo "$MYSELF $VERSION $passedOpts" | mail -s "$MYSELF $VERSION started on $HOSTNAME" $EMAIL
	[ -n "$STOPSERVICES" ] && ( echo "--- Stopping services ..."; $STOPSERVICES )

	BACKUPPATH=$BACKUPPATH/$HOSTNAME
	if [[ ! -d $BACKUPPATH ]]; then
		mkdir -p $BACKUPPATH		
	fi

	log $LOG_INFO "Starting backup with $BACKUPTYPE..."	
	
	if [[ -z "$RC" ]]; then
		case "$BACKUPTYPE" in
	
			"dd") ddBackup
				;;
		
			"tar") tarBackup
				;;
			
			"xbmc") xbmcBackup
				;;
			
			"rsync") rsyncBackup
				;;
		 
			*) echo "??? Invalid backuptype $BACKUPTYPE"
				exit 127;;			
		esac
		rc=$?
	else
		rc=$RC
	fi

	log $LOG_INFO "Backup created with return code: $rc"
	verbose=""
	(( $VERBOSE )) && verbose="v" 
	if [[ -z "$RC" && $rc -eq 0 ]]; then	
		log $LOG_DEBUG "Deleting oldest directory"
		pushd $BACKUPPATH 1>/dev/null; ls -a | head -n -$KEEPBACKUPS | xargs rm -rf$verbose 2>/dev/null ; popd > /dev/null
	fi
	[ -n "$STARTSERVICES" ] && ( echo "--- Starting services..."; $STARTSERVICES )
	log $LOG_INFO "Backup finished"
}

function usage() {
    echo "$MYSELF $VERSION"
    echo "usage: $MYSELF parms"
    echo "-p backupPath (default: $DEFAULT_BACKUPPATH)"
    [ -z "$DEFAULT_EMAIL" ] && DEFAULT_EMAIL="no email" 
    echo "-e email address (default: $DEFAULT_EMAIL)"
    echo "-t backupType {dd|tar|xbmc|rsync} (default: $DEFAULT_BACKUPTYPE)"
    echo "-k backupsToKeep (default: $DEFAULT_KEEPBACKUPS)"
    echo "-o servicesStopCommand(s)"
    echo "-a servicesStartCommand(s)"
    echo "-b directory to backup (default: $DEFAULT_DIR_TO_BACKUP)"
    echo "-l Log level (0, 1 and 2) <=> none, info, debug"
    echo "-v : verbose output of backup tools" 
    echo "-h : display this help text"
}       

function doit() {
	
	if [[ "${BACKUPPATH:0:1}" != "/" ]]; then
		echo "??? BACKUPPATH $BACKUPPATH has to be absolute"
		exit 127
	fi

	if [[ ! -d $BACKUPPATH ]]; then
		echo "??? BACKUPPATH $BACKUPPATH does not exist"
		usage
		exit 127
	fi

	if [[ $BACKUPTYPE != "xbmc" ]]; then

		if [[ "${DIR_TO_BACKUP:0:1}" != "/" ]]; then
			echo "??? DIR_TO_BACKUP $DIR_TO_BACKUP has to be absolute"
			exit 127
		fi

		if [[ ! -d $DIR_TO_BACKUP ]]; then
			echo "??? DIR_TO_BACKUP $DIR_TO_BACKUP does not exist"
			usage
			exit 127
		fi
	else
		if [[ ! -d /home/pi/.xbmc ]]; then
			echo "??? /home/pi/.xbmc does not exist"			
			exit 127
		fi
	fi

	regex="^[0-9]+$"
	if [[ ! $KEEPBACKUPS =~ $regex || $KEEPBACKUPS -lt 1 || $KEEPBACKUPS -gt 52 ]]; then
		echo "??? KEEPBACKUPS $KEEPBACKUPS is invalid"
		usage
		exit 127
	fi

	regex="^(dd|tar|xbmc|rsync)$"
	if [[ ! $BACKUPTYPE =~ $regex ]]; then
		echo "??? BACKUPTYPE $BACKUPTYPE is invalid."
		usage
		exit 127
	fi

	if [[ $BACKUPTYPE == "rsync" ]]; then
		if [[ ! $(which rsync) ]]; then
			echo "??? rsync not installed"
			exit 127
		fi
		if ! df -hT $DIR_TO_BACKUP | grep -viE "Filesystem" | awk '{print $2}' | egrep "ext[34]" > /dev/null; then
			echo "??? Filesystem of rsync directory $DIR_TO_BACKUP has to be either ext3 or ext4"
			exit 127
		fi
	fi

	BACKUPFILE_NODATE="$HOSTNAME-$BACKUPTYPE-backup"
	BACKUPFILE="$HOSTNAME-$BACKUPTYPE-backup-$DATE"

	echo "--- $HOSTNAME: $MYSELF $VERSION starting at $(date) ..."
	trap cleanup SIGINT SIGTERM EXIT
	time backup
	echo "--- $HOSTNAME: $MYSELF $VERSION finished at $(date) ..."

}

passedOpts="$@"

BACKUPPATH=$DEFAULT_BACKUPPATH
KEEPBACKUPS=$DEFAULT_KEEPBACKUPS
BACKUPTYPE=$DEFAULT_BACKUPTYPE
STOPSERVICES=$DEFAULT_STOPSERVICES
STARTSERVICES=$DEFAULT_STARTSERVICES
EMAIL=$DEFAULT_EMAIL
KEEPLOG=0
VERBOSE=0
RC=""
DIR_TO_BACKUP=$DEFAULT_DIR_TO_BACKUP
LOG_LEVEL=$DEFAUL_LOG_LEVEL
DEPLOY=0

log $LOG_DEBUG "Options: $passedOpts"

while getopts ":o:a:r:e:p:t:k:hvl:b:d" opt; do
   case $opt in
		o) 	STOPSERVICES=$OPTARG
			;;
		a) 	STARTSERVICES=$OPTARG
			;;
		e)	EMAIL=$OPTARG
			;;
		b) 	DIR_TO_BACKUP=$OPTARG
			;;
		p) 	BACKUPPATH=$OPTARG
			;;
		d)	DEPLOY=1
			;;
		t) 	BACKUPTYPE=$OPTARG
			;;
		k) 	KEEPBACKUPS=$OPTARG
			;;
		r) 	RC=$OPTARG
			;;
		l) 	LOG_LEVEL=$OPTARG
			;;
		v)	VERBOSE=1
			;;
		\?)	echo "??? Unknown option \"-$OPTARG\"." >&2
			usage
			exit 127
			;;
		:) 	echo "??? Option \"-$OPTARG\" requires an argument."
			usage
			exit 127
			;;
		h)  usage; 
			rc=0
			exit 0
			;;

    esac
done
shift $((OPTIND-1))

if (( $DEPLOY )); then
    deployMyself "$args"
else
	doit
fi	
