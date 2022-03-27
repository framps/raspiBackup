#!/bin/bash

##########################################################################################################################################
#
# Auxiliary script for easy restore of a backup created with raspiBackup on Raspberry Pi OS.
# Possibe Options:
# --load     (automatic selection of the last backup)
# --select   (any backup can be selected from a list)
# Without Options   (This is the same process as with options except that at startup it asks whether the last backup should be restored.)
#
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

normal='\033[0;39m'                #Font colors for output
red='\033[1;31m'
yellow='\033[1;33m'
green='\033[1;32m'

hostname="$(hostname)"           #Determine hostname

FILE="/usr/local/etc/raspiBackup.conf"    #Determining the DEFAULT_BACKUPPATH from raspiBackup.conf

function execution(){

    lsblk                      #Output of lsblk to check the drive for restore
    echo ""
    echo -e "$yellow $Quest_select_drive $normal"
    read destination

    if [[ -e /dev/$destination ]]; then
        echo "OK"
    else
        echo""
        echo -e "$red $destination Warn_drive_not_present $normal"
        execution
    fi

    if grep -q /$destination /proc/mounts; then
        echo -e "$red -------------------------------------------------------------------------------------------------"
        echo ""
        echo " $red $destination $Warn_drive_mounted $normal".
        echo ""
        echo -e " ------------------------------------------------------------------------------------------------- $normal"
      exit 0

    fi

    echo -e "$green ----------------------------------------------------------------------------------------------"
    echo ""
    echo "$Info_backup_drive $backup_path >>> $destination"
    echo ""
    echo -e " ------------------------------------------------------------------------------------------------- $normal"

    /usr/local/bin/raspiBackup.sh -d /dev/$destination /$backup_path      #Call raspiBackup.sh
    exit 0
}

function execution_select(){

    declare -a backup_folder
    backup_folder=( $(find $backupdir/$hostname/$hostname* -maxdepth 0 -type d))

    for i in "${!backup_folder[@]}"; do

        v=$(( $i + 1 ))
        echo "${backup_folder[$i]}  -> $v"
    done

    echo ""
    echo -e "$yellow $Quest_number_of_backup $normal"
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
        echo -e "$red $Warn_drive_not_present $normal"
        echo ""
        execution_select
    fi

}

function test_digit(){

    if [[ "$1" =~ ^[0-9]+$ ]]; then            # regex: a number has to have

        if (( $1 < $2 || $1 > $3 )); then
            echo -e "$red $1 $Warn_invalid_number $2 > $3 $normal"
            echo ""
            execution_select
        else
            echo -e "$green $Info_restore $backup_path $normal"
            echo""
        fi

    else
        echo -e "$red $1 $Warn_no_number $normal"
        echo""
        execution_select
    fi

}

function language(){

        echo ""
        echo -e "$yellow Please choose your preferred language"
        echo -e " Bitte waehle deine bevorzugte Sprache"
        echo ""
        echo -e " German  = 1"
        echo -e " English = 2 $normal"

        read lang

    if (( $lang == 1 )); then
	Quest_last_backup="Soll das letzte Backup restored werden? y/N"
	Quest_select_drive="Bitte waehle das Ziellaufwerk z.B. mmcblk0,sda,sdb,sdc...."
	Warn_drive_not_present="Das Ziellaufwerk existiert nicht"
	Warn_drive_mounted="Mindestens eine Partition ist gemountet. Bitte erst aushaengen."
	Info_backup_drive="Folgendes Backup wird restored "
	Quest_number_of_backup="Bitte gebe die hinter dem gewuenschten Backups stehende Zahl ein. "
	Warn_no_dir="Oops Das Verzeichnis existier nicht."
	Warn_invalid_number="Die eingegebene Zahl ist ungueltig. Nur Zahelen im Bereich von "
	Info_restore="Das folgende Backup wird zurueckgespielt "
	Warn_no_number="Das ist keine Zahl "
	Warn_false_number="Falsche Eingabe Bitte nur 1 oder 2 eingeben "

    elif (( $lang == 2 )); then
	Quest_last_backup="Should the last backup be restored? y/N "
	Quest_select_drive="Please enter the destination drive. e.g. mmcblk0,sda,sdb,sdc.... "
	Warn_drive_not_present="Drive is not present "
	Warn_drive_mounted="At least one partition on the target drive is mounted. Please unmount first ".
	Info_backup_drive="$The backup to restore $backup_path Drive to restore "
	Quest_number_of_backup="$Please enter the number at the end of the desired backup. "
	Warn_no_dir="Oops The directory does not exist "
	Warn_invalid_number="Invalid number Please enter only numbers in range "
	Info_restore="The following Backup will be restored "
	Warn_no_number="That is no number "
	Warn_false_number="Please enter 1 or 2 "

    else
	echo -e "$red False input. Please enter only 1 or 2"
	echo -e " Falsche Eingabe. Bitte nur 1 oder 2 eingeben $normal"
	language
    fi
}

if (( $UID != 0 )); then
    echo -e "$red Script has to be called as root or with sudo $normal"
    echo -e "$red Das Script muss als root oder mit sudo aufgerufen werden $normal"
	exit
fi

	language

source $FILE
backupdir=$DEFAULT_BACKUPPATH

backup_path="$(find $backupdir/$hostname/$hostname* -maxdepth 0 | sort -r | head -1)"  #Determine last backup

if [[ $1 == "--last" ]]; then
    execution
    exit 0

elif [[ $1 == "--select" ]]; then
    execution_select
    exit 0

else
    echo ""
    echo -e "$yellow $Quest_last_backup $normal"
    read answer
fi

if [[ ${answer,,} = "y" ]]; then
    execution
    exit 0

else
    execution_select
fi
