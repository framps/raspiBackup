#!/bin/bash

##########################################################################################################################################

#Auxiliary script for easy restore of a backup created with raspiBackup on Raspberry Pi OS.
# Possibe Options:
# --load     (automatic selection of the last backup)
# --select   (any backup can be selected from a list)
# Without Options   (This is the same process as with options except that at startup it asks whether the last backup should be restored.)

##########################################################################################################################################
#
#    Copyright (c) 2022 franjo-G at git@fgreufe.de
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
###########################################################################################################################################



if (( $UID != 0 )); then
    echo "Error: Script has to be called as root or with sudo" 
    exit
fi

    normal='\033[0;39m'                #Font colors for output
    red='\033[1;31m'
    yellow='\033[1;33m'
    green='\033[1;32m'

    hostname="$(hostname)"           #Determine hostname

    FILE="/usr/local/etc/raspiBackup.conf"    #Determining the DEFAULT_BACKUPPATH from raspiBackup.conf
        source $FILE
    backupdir=$DEFAULT_BACKUPPATH

    backup_path="$(find $backupdir/$hostname/$hostname* -maxdepth 0 | sort -r | head -1)"  #Determine last backup

function execution(){

    lsblk                      #Output of lsblk to check the drive for restore
    echo ""
    echo -e "$yellow Please enter the destination drive. e.g. mmcblk0,sda,sdb,sdc.... $normal"
    read destination

if [[ -e /dev/$destination ]]; then

    echo "OK"

else
    echo""
    echo -e "$red Drive not present $normal"
	execution
fi

if grep -q /$destination /proc/mounts; then
    echo -e "$red -------------------------------------------------------------------------------------------------"
    echo ""
    echo " At least one partition on the target drive is mounted. Please unmount first".
    echo ""
    echo -e " ------------------------------------------------------------------------------------------------- $normal"
  exit 0

fi

    echo -e "$green ----------------------------------------------------------------------------------------------"
    echo ""
    echo " The backup to restore $backup_path Drive to restore /dev/$destination"
    echo ""
    echo -e " ------------------------------------------------------------------------------------------------- $no>rmal"

    /usr/local/bin/raspiBackup.sh -d /dev/$destination /$backup_path      #Call raspiBackup.sh
  exit 0
}

function execution_select(){

  declare -a backup_folder
        backup_folder=( $(find $backupdir/$hostname/$hostname* -maxdepth 0 -type d))

for i in "${!backup_folder[@]}"

    do

        v=$(( $i + 1 ))

        echo "${backup_folder[$i]}  -> $v"
    done

        echo ""
        echo -e "$yellow Please enter the number at the end of the desired backup. $normal"
        echo ""

	read v

        number="$v"
        min=1
        max="${#backup_folder[@]}"

        i=$(( $v - 1 ))
        backup_path=${backup_folder[$i]}

    test_digit "$number" "$min" "$max" "$backup_path"


if [[ -d "$backup_path" ]]; then

        execution

       echo -e "$red Oops The directory does not exist.g? $normal"
       echo ""
       execution_select
fi

}

function test_digit(){


    if [[ "$1" =~ ^[0-9]+$ ]]; then            # regex: a number has to have

        if (( $1 < $2 || $1 > $3 )); then
            echo -e "$red Invalid number $1 for range $2 - $3 $normal"
	    echo ""
	    execution_select

        else
            echo -e "$green $1 The Backup $4 will be restored $normal"
	    echo""

        fi

else
    echo -e "$red $1 is no number $normal"
    echo""
	execution_select
fi

}

if [[ $1 == "--last" ]]; then
    execution
  exit 0

    elif [[ $1 == "--select" ]]; then
    execution_select
    exit 0

else
    echo ""
    echo -e "$yellow Should the last backup be restored? y/N $normal"
    read answer
fi

if [[ ${answer,,} = "y" ]]; then
    execution
  exit 0

else
    execution_select
fi


