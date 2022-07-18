#!/bin/bash

##########################################################################################################################################
#
# Auxiliary - script for easy, dialog guided creating or restoring of a backup with   "framps raspiBackup"
# Possible options
# --backup (simple dialog guided creation of a backup)
# --last (creation of a restore with selection of the target drive)
# --select (the backup to restore can be selected from a list of available backups)
#
# Without option (The program asks whether a backup should be created or a backup should be restored.
# All options are asked in the program by dialog).
#
# Selectable languages "German" and "English"
#
# Requirement  Installing of "framps raspiBackup"
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

function backup(){
		echo ""
		lsblk
		echo ""
		echo -e "$yellow ------------------------------------------------------------------ \n"
		echo -e " $Quest_more_than_2_partitions \n"
		echo -e " ------------------------------------------------------------------$normal \n"
		read input_partitions_more_then_2

	if [[ ${input_partitions_more_then_2,,} =~ [yj] ]]; then
		echo -e "$yellow -----------------------------------------------------------------0- \n"
		echo -e " $Quest_backup_more_than_2 \n"
		echo -e " -------------------------------------------------------------------$normal \n"
		read input_backup_more_then_2

		if [[ ${input_backup_more_then_2,,} =~ [yj] ]]; then
			echo -e "$yellow ----------------------------------------------------------------- \n"
			echo -e " $yellow $Quest_additional_partitions \n"
			echo -e " -----------------------------------------------------------------$normal \n"
			read partitions
			echo ""
			backup_add_part_and_comment

		else
			ignore=ignoreAdditionalPartitions
			backup_add_comment "$ignore"

			fi

	else
		backup_add_comment

	fi
		exit 0
}

function backup_add_part_and_comment(){
		echo -e "$yellow ----------------------------------------------------------------------- \n"
		echo -e " $Quest_comment \n"
		echo -e " -----------------------------------------------------------------------$normal \n"
		read Quest_comment

	if [[ ${Quest_comment,,} =~ [yj] ]]; then
		echo -e "$yellow ----------------------------------------------------------------------- \n"
		echo -e " $Quest_comment_text \n"
		echo -e " -----------------------------------------------------------------------$normal \n"
		read Quest_comment_text
		/usr/local/bin/raspiBackup.sh -M "$Quest_comment_text" -P -T "1 2 $partitions"
	else
		/usr/local/bin/raspiBackup.sh -P -T "1 2 $partitions"
	fi
}

function backup_add_comment(){
		echo -e "$yellow ----------------------------------------------------------------------- \n"
		echo -e " $Quest_comment \n"
		echo -e " -----------------------------------------------------------------------$normal \n"
		read Quest_comment

	if [[ ${Quest_comment,,} =~ [yj] ]]; then
		echo -e "$yellow ----------------------------------------------------------------------- \n"
		echo -e " $Quest_comment_text \n"
		echo -e " -----------------------------------------------------------------------$normal \n"
		read Quest_comment_text
		/usr/local/bin/raspiBackup.sh -M "$Quest_comment_text" --"$1"
	else
		/usr/local/bin/raspiBackup.sh --"$1"
	fi
}

function execution(){

		lsblk                      #Output of lsblk to check the drive for restore
		echo -e "$yellow ---------------------------------------------------------- \n"
		echo -e " $Quest_select_drive \n"
		echo -e " ----------------------------------------------------------$normal \n"
		read destination

	if [[ "$destination" =~ ^(sd[a-f]|mmcblk[0-2])$ ]]; then
		echo ""

	else
		echo -e "$red -----------------------------------------------------------\n"
		echo -e "$destination $Warn_only_drive"
		echo -e " ----------------------------------------------------------$normal \n"
		execution
	fi
	
 	if [[ -b /dev/$destination ]]; then
		echo "OK"
	else
		echo -e "$red --------------------------------------------------------- \n"
		echo -e " $destination $Warn_drive_not_present \n"
		echo -e " ---------------------------------------------------------$normal \n"
		execution
	fi

	if grep -q /$destination /proc/mounts; then
		echo -e "$red ------------------------------------------------------------------------ \n"
		echo -e " $destination $Warn_drive_mounted \n".
		echo -e " -------------------------------------------------------------------------- $normal"
		exit 0
	fi
    
		echo -e "$green --------------------------------------------------------------------------------------------------------------------- \n"
		echo -e " $Info_backup_drive $backup_path >>> $destination \n"
		echo -e " -------------------------------------------------------------------------------------------------------------------- $normal \n"

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

	echo -e " $yellow ------------------------------------------------------------------ \n"
	echo -e " $Quest_number_of_backup \n"
	echo -e " -------------------------------------------------------------------$normal \n"

	read v

	number="$v"
	min=1
	max="${#backup_folder[@]}"

	i=$(( $v - 1 ))
	backup_path=${backup_folder[$i]}

	test_digit "$number" "$min" "$max" "$backup_path"

	if [[ -d "$backup_path" ]]; then
		execution
		echo -e "$red -------------------------------------------------------------- \n"
		echo -e " $Warn_drive_not_present \n"
		echo -e " ------------------------------------------------------------- $normal \n"
		execution_select
		fi
}

function test_digit(){

	if [[ "$1" =~ ^[0-9]+$ ]]; then            # regex: a number has to have

		if (( $1 < $2 || $1 > $3 )); then
			echo -e "$red ------------------------------------------------------\n"
			echo -e " $$1 $Warn_invalid_number $2 > $3 \n"
			echo -e " -----------------------------------------------------$normal \n"
			execution_select
		else
			echo -e "$green --------------------------------------------------------------------------------------- \n"
			echo -e " $Info_restore $backup_path \n"
			echo -e " ---------------------------------------------------------------------------------------$normal \n"
		fi

	else
		echo -e "$red --------------------------------------------------------------\n"
		echo -e " $1 $Warn_no_number \n"
		echo -e " -------------------------------------------------------------$normal \n"
		execution_select
	fi
}

function language(){

		echo -e "$yellow ------------------------------------------------------------ \n"
		echo -e " Please choose your preferred language"
		echo -e " Bitte waehle deine bevorzugte Sprache \n"
		echo -e " German  = 1"
		echo -e " English = 2 \n"
		echo -e " ------------------------------------------------------------$normal \n"
		read lang

	if (( $lang == 1 )); then
		Quest_last_backup="Soll das letzte Backup restored werden? j/N"
		Quest_select_drive="Bitte waehle das Ziellaufwerk z.B. mmcblk0,sda,sdb,sdc...."
		Warn_drive_not_present="Das Ziellaufwerk existiert nicht"
		Warn_drive_mounted="Mindestens eine Partition ist gemountet. Bitte erst aushaengen."
		Info_backup_drive="Folgendes Backup wird restored "
		Quest_number_of_backup="Bitte gebe die hinter dem gewuenschten Backups stehende Zahl ein. "
		Warn_no_dir="Oops Das Verzeichnis existier nicht."
		Warn_invalid_number="Die eingegebene Zahl ist ungueltig. Nur Zahlen im Bereich von "
		Info_restore="Das folgende Backup wird zurueckgespielt "
		Warn_no_number="Das ist keine Zahl "
		Warn_false_number="Falsche Eingabe Bitte nur 1 oder 2 eingeben "
		Quest_backup_or_restore="Soll ein Backup oder ein restore erstellt werden?"
		Quest_more_than_2_partitions="Befinden sich auf dem Systemlaufwerk mehr als die 2 Standard-Partitionen?   j/N"
		Quest_backup_more_than_2="Sollen mehr als die 2 Standardpartitionen gesichert werden?   j/N"
		Quest_additional_partitions="Bitte die Partitionsnummer(n) eingeben, die zusaetzlich \n  zu den Standardpartitionen gesichert werde sollen. \n  Falls mehrere, dann getrennt durch Leerzeichen.  \n  Beispiel:  3 4 5 "
		Warn_only_drive="Bitte ein gueltiges Laufwerk eingeben"
		Quest_comment="Soll ein Kommentar am Ende des Backup-Verzeichnisses eingefügt werden? \n Dieses Backup wird dann nicht automatisch recycled. \n j/N \n"
		Quest_comment_text="Bitte gebe den Kommentar ein \n"

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
		Quest_backup_or_restore="Should a backup or a restore be created?"
		Quest_more_than_2_partitions="Are there more than the 2 standard partitions on the system drive?   y/N"
		Quest_backup_more_than_2="Should more than the 2 standard partitions be backed up   y/N?"
		Quest_additional_partitions="Please enter the partition number(s) that should be backed up \n  in addition to the default partitions. \n  If more than one, separate them with spaces. \n  Example:   3 4 5 "
		Warn_only_drive="Please only enter a valid Drive"
		Quest_comment="Should a comment be inserted at the end of the backup directory? \n This backup will then not be recycled automatically. \n y/N \n"
		Quest_comment_text="Please enter the comment \n"
	else
		echo -e "$red False input. Please enter only 1 or 2"
		echo -e " Falsche Eingabe. Bitte nur 1 oder 2 eingeben $normal"
		language
  
	fi
}

if (( $UID != 0 )); then
	echo ""
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

elif [[ $1 == "--backup" ]]; then
	backup
	exit 0
fi

	echo -e "$yellow ------------------------------------------------------------ \n"
	echo -e " $Quest_backup_or_restore \n"
	echo -e " backup    1"
	echo -e " restore   2 \n"
	echo -e " ------------------------------------------------------------$normal \n"
	
	read backup_or_restore

if (( $backup_or_restore  == 1 )); then
	backup
    
elif (($backup_or_restore == 2 )); then
	echo -e "$yellow ------------------------------------------------------------ \n"
	echo -e " $Quest_last_backup \n"
	echo -e "-------------------------------------------------------------$normal \n"
	read answer
    
else
	echo -e "$red --------------------------------------------------------------- \n"
	echo -e " $Warn_false_number \n"
	echo -e " ------------------------------------------------------------$normal \n"
fi

if [[ ${answer,,} =~ [yj] ]]; then
	execution
exit 0
    
else
	execution_select
fi
