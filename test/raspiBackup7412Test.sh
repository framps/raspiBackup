#!/bin/bash
#######################################################################################################################
#
# 	Test script to test raspiBackup smarte recycle strategy
#	1) Keep last d daily backups
#	2) Keep last w weekly backups
#	3) Keep last m monthly backups
#	4) Keep last y yearly backups
#
#######################################################################################################################
#
#    Copyright (c) 2019, 2023 framp at linux-tips-and-tricks dot de
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

#set -euf -o pipefail

MYSELF=${0##*/}
MYNAME=${MYSELF%.*}
VERSION="0.2"

if (( $UID != 0 )); then
	echo "Call me as root"
	exit 1
fi

if ! which faketime 1>/dev/null; then
	echo "??? faketime program not found"
	exit 1
fi

# main program

SCRIPT_DIR=$( cd $( dirname ${BASH_SOURCE[0]}); pwd | xargs readlink -f)
DIR="7412backups"
LOG_FILE="$MYNAME.log"

DEBUG=0
PER_BUCKET=1
DAILY=$PER_BUCKET
WEEKLY=$PER_BUCKET
MONTHLY=$PER_BUCKET
YEARLY=$PER_BUCKET
MASS=1
TYPE=1
ADD_HOST=0		# flag to create old named backups

HOSTNAME=$(hostname)

source ../raspiBackup.sh

function createSpecificBackups() { # stringlist_of_dates of form yyyymmdd{-hhmmss] type dont_delete_flag

	if (( $# <= 2 )); then
		echo "Cleaning backups..."
		rm -rf $DIR
		mkdir $DIR # create directory to get faked backup directories
	fi

	local type=${2:-rsync}

	echo "Creating specific backups of type $type in dir $DIR"

	(( $DEBUG )) && echo "Creating -> $@"
	local d
	local tc="-154245"
	local h
	for d in $1; do
		(( ${#d} <= 8 )) && t="$tc" || t=""
		local h="${HOSTNAME}/${HOSTNAME_OSR}-${type}-backup-"$d$t
		mkdir -p $DIR/$h
		if (( $ADD_HOST )); then									# flag to create old directorynames also
			local h="${HOSTNAME}/${HOSTNAME}-${type}-backup-"$d$t
			mkdir -p $DIR/$h
		fi
		h="${HOSTNAME}/${HOSTNAME_OSR}-${type}-backup-"${d}-100000_before_before
		mkdir -p $DIR/$h
		h="${HOSTNAME}/${HOSTNAME_OSR}-${type}-backup-"${d}-200000_after_after
		mkdir -p $DIR/$h
	done

	(( $DEBUG )) && ls -1 "$DIR/${HOSTNAME}"

}

function createMassBackups() { # startdate count #per_day type dont_delete_flag

	if (( $# < 5 )); then
		echo "Cleaning backups..."
		rm -rf $DIR
		mkdir $DIR # create directory to get faked backup directories
	fi

	# create daily backups
	local c=$2

	# use current date if date was empty, otherwise date has to be in format yyyy-mm-dd
	local now=$(date +"%Y-%m-%d")
	local today=${1:-$now}
	local type=${4:-rsync}

	echo "Creating $c fake backups of type $type in dir $DIR starting $today"
	local TICKS=100
	local i

	for i in $(seq 0 $c); do

		local F_D=$(($3-1))
		for y in $(seq 0 $F_D); do
			if (( $3 > 1 )); then # create random times if #per > 1
				local F_HR=$(shuf -i 0-24 -n 1)
				local F_MI=$(shuf -i 0-59 -n 1)
				local F_SI=$(shuf -i 0-59 -n 1)
			else
				local F_HR=15
				local F_MI=42
				local F_SI=45
			fi
			printf -v F_HR "%02d" $F_HR
			printf -v F_MI "%02d" $F_MI
			printf -v F_SI "%02d" $F_SI
			local h="${HOSTNAME}/${HOSTNAME_OSR}-${type}-backup-"$(date -d "$today -$i days" +%Y%m%d-)
			local n="$h$F_HR$F_MI$F_SI"
			if (( c-- % $TICKS == 0 )); then
				(( $DEBUG )) && echo "Next $TICKS ... $n ..."
			fi
			mkdir -p $DIR/$n
			n="${h}100000_before_before"
			mkdir -p $DIR/$n
			n="${h}200000_after_after"
			mkdir -p $DIR/$n
		done
	done

	(( $DEBUG )) && ls -1 "$DIR/${HOSTNAME}"

}

function testOldDirNames() { # lineNo type number_of_backups
	local l="$1"
	local type="$2"
	local n="$3"

	echo "Testing for type $type old names $3"

	local f=$(ls $DIR/${HOSTNAME}/${HOSTNAME}-* | grep $type | grep -v "_" | wc -l)

	if (( f != n )); then
		echo "??? Test in line $l: Expected #$n old backups but found $f backups"
		(( $DEBUG )) && ls -1 "$DIR/${HOSTNAME}"
		exit 1
	fi

}

function testSpecificBackups() { # lineNo stringlist_of_dates type numberOfstaticBackups

	local l="$1"
	local dtes="$2"
	local type="$3"
	local static

	if [[ "$3" =~ [0-9]+ ]]; then
		type="rsync"
		static="$3"
	else
		type="$3"
		static="$4"
	fi

	echo "Testing for type $type and static $((2*$static)) ..."

	local f=$(ls $DIR/${HOSTNAME}/${HOSTNAME_OSR}* | grep $type | grep -v "_" | wc -l)
	local n=$(wc -w <<< "$dtes")

	if (( f != $n )); then
		echo "??? Test in line $l: Expected #$n $dtes but found $f backups of type $type"
		(( $DEBUG )) && ls -1 "$DIR/${HOSTNAME}"
		exit 1
	fi

	local f=$(ls $DIR/${HOSTNAME}/${HOSTNAME_OSR}* | grep $type | grep "_" | wc -l)

	if (( f != $(($static*2)) )); then
		echo "??? Test in line $l: Expected #$(($static*2)) statics but found $f statics of type $type"
		(( $DEBUG )) && ls -1 "$DIR/${HOSTNAME}"
		exit 1
	fi

	local d
	for d in $dtes; do
		if [[ -z $(find $DIR/${HOSTNAME}/${HOSTNAME_OSR}* -type d -name "*${type}-backup-${d}*") ]] ; then
			echo "??? Test in line $l: Expected date $d of type $type in $dtes not found"
			ls -1 "$DIR/${HOSTNAME}"
			exit 1
		fi
	done
}

# For including the OS release into the name of the backup directory
os_release=$(getOSRelease)
# Note: Sanitize the os_release to be usable as (part of) directory name.
# But don't allow or use "-" or "_" as replacement character!
# Both characters are already used as dividers/markers later on!
# The "~" seems to be okay. Even safer would be "", a.k.a. nothing.
HOSTNAME_OSR="${HOSTNAME}@${os_release//[ \/\\\:\.\-_]/\~}"


# tests to execute for all timeframes
# 1) check limit on option is used for timeframe
# 2) check if backup of this week/month/year is included
# 3) check if latest or most current backup is used if there exist more backups in the timeframe
# 4) check if gaps in timeframe are considered
# 5) check if change a higher timeframe change is reflected (i.e. days collected when week changes, weeks collect when month changes, months collected when year changes)

raspiOpts="--smartRecycle --smartRecycleDryrun- -t rsync -F -x -c -Z -m 1 -l 1 -L 3 -o : -a : 7412backups"

###
### Daily
###

if (( $DAILY )); then


	ADD_HOST=1
	l=$LINENO
	echo "$l === DAILY (1) + (5)"
	d="20191116 20191117 20191118 20191119"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "3 0 0 0"  $raspiOpts >> $LOG_FILE
	testSpecificBackups $l "20191117 20191118 20191119" $(wc -w <<< "$d")
	testOldDirNames $l rsync 4
	ADD_HOST=0

	l=$LINENO
	echo "$l === DAILY (2)"
	d="20191116 20191117 20191119"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "3 0 0 0" $raspiOpts >> $LOG_FILE
	testSpecificBackups $l "20191119 20191117" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === DAILY (3) + (4)"
	d="20191117-130000 20191117-230010 20191118-130000 20191118-140005 20191119-120000 20191119-120001"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "3 0 0 0" $raspiOpts >> $LOG_FILE
	testSpecificBackups $l "20191117-230010 20191118-140005 20191119-120001" $(wc -w <<< "$d")
fi

###
### Weekly
###

if (( $WEEKLY )); then

	ADD_HOST=1
	l=$LINENO
	echo "$l === WEEKLY (1)"
	d="20191118 20191112 20190601"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 2 0 0" $raspiOpts >> $LOG_FILE
	testSpecificBackups $l "20191118 20191112" $(wc -w <<< "$d")
	testOldDirNames $l rsync 3
	ADD_HOST=0

	l=$LINENO
	echo "$l === WEEKLY (1)"
	d="20191118 20191112 20190601"
	createSpecificBackups "$d"
	faketime "2019-11-18" ../raspiBackup.sh --smartRecycleOptions "0 2 0 0"  $raspiOpts >> $LOG_FILE
	testSpecificBackups $l "20191118 20191112" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY (2)"
	d="20191118 20191112 20190601"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 4 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191112" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY (2)"
	d="20191118 20191112 20190601"
	createSpecificBackups "$d"
	faketime "2019-11-18" ../raspiBackup.sh --smartRecycleOptions "0 4 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191112" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY (3)"
	d="20191119 20191118 20191117 20191116 20191115 20191114 20191113 20191112 20191111 20191110"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 4 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191111 20191110" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY (3)"
	d="20191118 20191117 20191116 20191115 20191114 20191113 20191112 20191111 20191110"
	createSpecificBackups "$d"
	faketime "2019-11-18" ../raspiBackup.sh --smartRecycleOptions "0 4 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191111 20191110" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY (4) + (5)"
	d="20191118 20191112 20191030"
	createSpecificBackups "$d"
	faketime "2019-11-18" ../raspiBackup.sh --smartRecycleOptions "0 4 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191112 20191030" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY (4) + (5)"
	d="20191118 20191112 20191030"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 4 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191112 20191030" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY - different weekdays considered"
	d="20191119 20191115 20191107 20191101 20191026"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 5 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191119 20191115 20191107 20191101 20191026" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY - different weekdays considered"
	d="20191118 20191115 20191107 20191101 20191026"
	createSpecificBackups "$d"
	faketime "2019-11-18" ../raspiBackup.sh --smartRecycleOptions "0 5 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191115 20191107 20191101 20191026" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY - different multiple weekdays considered with most current weekday"
	d="20191118 20191115 20191112 20191111 20191105 20191103 20191030 20191029 20191024 20191021 20191018 20191015 20191012 20191010 20190929 20190925"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 10 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191111 20191105 20191029 20191021 20191015 20191010 20190925" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === WEEKLY - different multiple weekdays considered with most current weekday"
	d="20191118 20191115 20191112 20191111 20191105 20191103 20191030 20191029 20191024 20191021 20191018 20191015 20191012 20191010 20190929 20190925"
	createSpecificBackups "$d"
	faketime "2019-11-18" ../raspiBackup.sh --smartRecycleOptions "0 10 0 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191118 20191111 20191105 20191029 20191021 20191015 20191010 20190925" $(wc -w <<< "$d")
fi

###
### Monthly
###

if (( $MONTHLY )); then

	ADD_HOST=1
	l=$LINENO
	echo "$l === MONTHLY (1)"
	d="20191108 20191003 20190903 20190810"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 0 1 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191108" $(wc -w <<< "$d")
	testOldDirNames $l rsync 4
	ADD_HOST=0

	l=$LINENO
	echo "$l === MONTHLY (2)"
	d="20191103 20191003 20190903 20190810"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 0 12 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191103 20191103 20190903 20190810" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === MONTHLY (3)"
	d="20191108 20191103 20191003 20191020 20190903 20190910 20190810 20190830"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 0 12 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191103 20191003 20190903 20190810" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === MONTHLY (4)"
	d="20191111 20190903 20190708 20190503"
	createSpecificBackups "$d"
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "0 0 5 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191111 20190903 20190708" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === MONTHLY (5)"
	d="20190111 20181203 20181108 20181003"
	createSpecificBackups "$d"
	faketime "2019-01-19" ../raspiBackup.sh --smartRecycleOptions "0 0 5 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20190111 20181203 20181108 20181003" $(wc -w <<< "$d")
fi

###
### Yearly
###

if (( $YEARLY )); then

	ADD_HOST=1
	l=$LINENO
	echo "$l === YEARLY (1)"
	d="20190111 20181203 20171108 20161003"
	createSpecificBackups "$d"
	faketime "2019-01-19" ../raspiBackup.sh --smartRecycleOptions "0 0 1 0" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20190111" $(wc -w <<< "$d")
	testOldDirNames $l rsync 4
	ADD_HOST=0

	l=$LINENO
	echo "$l === YEARLY (2)"
	d="20190111 20181203 20171108 20161003"
	createSpecificBackups "$d"
	faketime "2019-01-19" ../raspiBackup.sh --smartRecycleOptions "0 0 0 3" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20190111 20181203 20171108" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === YEARLY (3)"
	d="20190111 20181108 20181003"
	createSpecificBackups "$d"
	faketime "2019-01-19" ../raspiBackup.sh --smartRecycleOptions "0 0 0 3" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20190111 20181003" $(wc -w <<< "$d")

	l=$LINENO
	echo "$l === YEARLY (4)"
	d="20190111 20181003 20161203"
	createSpecificBackups "$d"
	faketime "2019-01-19" ../raspiBackup.sh --smartRecycleOptions "0 0 0 5" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20190111 20181003 20161203" $(wc -w <<< "$d")
fi

#
# MASS
#

if (( $MASS )); then

	DEBUG=0

	cnt=$((365*2))

	l=$LINENO
	echo "$l === MASS Default"
	createMassBackups "2019-11-17" $cnt 1
	faketime "2019-11-17" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191117 20191116 20191115 20191114 20191113 20191112 20191111 \
	20191104 20191101 20191028 20191021 \
	20191001 20190901 20190801 20190701 20190601 20190501 20190401 20190301 20190201 20190101 \
	20181201
	" $((cnt+1))

	l=$LINENO
	echo "$l === MASS Default var"
	createMassBackups "2019-11-19" $((365*2)) 1
	faketime "2019-11-19" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191119 20191118 20191117 20191116 20191115 20191114 20191113 \
	20191111 20191104 20191101 20191028 \
	20191001 20190901 20190801 20190701 20190601 20190501 20190401 20190301 20190201 20190101 \
	20181201
	" $((cnt+1))

	l=$LINENO
	echo "$l === MASS next day on default"
	d="20191120"
	createSpecificBackups "$d" "" 1 # add day -> one last daily deleted
	faketime "2019-11-20" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191120 20191119 20191118 20191117 20191116 20191115 20191114 \
	20191111 20191104 20191101 20191028 \
	20191001 20190901 20190801 20190701 20190601 20190501 20190401 20190301 20190201 20190101 \
	20181201
	" $((cnt+2))

	l=$LINENO
	echo "$l === MASS addtl week on default"
	createMassBackups "2019-11-27" $((7)) 1 "" 1
	faketime "2019-11-27" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191127 20191126 20191125 20191124 20191123 20191122 20191121 \
	20191118 20191111 20191104 20191101 \
	20191001 20190901 20190801 20190701 20190601 20190501 20190401 20190301 20190201 20190101 \
	20181201
	" $((cnt+2+7))

	l=$LINENO
	echo "$l === MASS addtl month on default"
	createMassBackups "2019-12-04" $((30)) 1 "" 1
	faketime "2019-12-04" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20191204 20191203 20191202 20191201 20191130 20191129 20191128 \
	20191125 20191118 20191111 20191101 \
	20191001 20190901 20190801 20190701 20190601 20190501 20190401 20190301 20190201 20190101 \
	" $((cnt+2+7+7))

	l=$LINENO
	echo "$l === MASS addtl month on default"
	createMassBackups "2020-01-01" $((30)) 1 "" 1
	faketime "2020-01-01" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts  >> $LOG_FILE
	testSpecificBackups $l "20200101 20191231 20191230 20191229 20191228 20191227 20191226 \
	20191223 20191216 20191209 20191201 \
	20191101 20191001 20190901 20190801 20190701 20190601 20190501 20190401 20190301 20190201 \
	" $((cnt+2+7+35))

fi

if (( $TYPE )); then

# now test whether backup type is considered in strategy

	l=$LINENO
	echo "$l === TYPE rsync and dd at same time"
	createMassBackups "2020-01-01" $((30)) 1 "rsync"
	createMassBackups "2020-01-01" $((30)) 1 "dd" 1
	faketime "2020-01-01" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts -t "rsync"  >> $LOG_FILE
	faketime "2020-01-01" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts -t "dd" >> $LOG_FILE

	testSpecificBackups $l "20200101 20191231 20191230 20191229 20191228 20191227 20191226 \
	20191223 20191216 20191209 20191202 \
	" "rsync" 31

	testSpecificBackups $l "20200101 20191231 20191230 20191229 20191228 20191227 20191226 \
	20191223 20191216 20191209 20191202 \
	" "dd" 31

	l=$LINENO
	echo "$l === TYPE rsync and dd at different time"
	createMassBackups "2019-12-04" $((30)) 1 "rsync" 1
	createMassBackups "2020-01-01" $((30)) 1 "dd" 1
	faketime "2019-12-04" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts -t "rsync" >> $LOG_FILE
	faketime "2020-01-01" ../raspiBackup.sh --smartRecycleOptions "7 4 12 1" $raspiOpts -t "dd" >> $LOG_FILE

	testSpecificBackups $l "20191204 20191203 20191202 20191201 20191130 20191129 20191128 \
	20191125 20191118 20191111 20191104 \
	" "rsync" 59

	testSpecificBackups $l "20200101 20191231 20191230 20191229 20191228 20191227 20191226 \
	20191223 20191216 20191209 20191202 \
	" "dd" 31
fi

exit 0
