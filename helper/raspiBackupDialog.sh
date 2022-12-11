#!/bin/bash

##########################################################################################################################################
#
# Auxiliary - script for easy, dialog guided creating or restoring of a backup with   "framps raspiBackup"
# Possible options
# --backup (simple dialog guided creation of a backup)
# --last (creation of a restore with selection of the target drive)
# --select (the backup to restore can be selected from a list of available backups)
# --delete (a backup can selected from a list of available backups to delete)
#   This Option is only reachable with the option -- delete
#
# Update 2022_07_26
# ______________________________________________________________________________________
# ______________________________________________________________________________________
# Dynamic mount added.
#
# Possible are mount via mount-unit or via fstab.
# Options
# --mountfs "Name of an existing mount-unit" e.g. "backup.mount".
# or
# --mountfs "fstab"
#
# For an automatic backup via cron, a --cron must be added to switch off the dialogue.
# The backup is then done with the settings from raspiBackup.conf.
#
# Examples for dynamic mount:
# sudo raspiBackupDialog.sh --mountfs "backup.mount"
# (The mount directory will be mounted with an existing mount-unit".
#
# sudo raspiBackupDialog.sh --mountfs "fstab"
# (The backup directory is mounted with an entry in fstab)
#
# Cron entry  (only when use dynamic mount) otherwise you must use "raspiBackup.sh"
# * * * * /usr/local/bin/raspiBackupDialog.sh --mountfs "backup.unit or fstab" --cron
# ______________________________________________________________________________________
# ______________________________________________________________________________________

# The options --select, --backup, --last and --delete can still be used with the exception of the cron call and must be placed last.
#
#
# Without option (The program asks whether a backup should be created or a backup should be restored.
# All options (with exception --delete) are asked in the program by dialog).
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
	echo -e "$yellow $Quest_more_than_2_partitions \n \n $normal"
	read input_partitions_more_then_2

	if [[ ${input_partitions_more_then_2,,} =~ [yj] ]]; then
		echo -e "$yellow $Quest_backup_more_than_2 \n \n $normal"
		read input_backup_more_then_2

		if [[ ${input_backup_more_then_2,,} =~ [yj] ]]; then
			echo -e " $yellow $Quest_additional_partitions \n \n $normal"
			read partitions
			echo ""
			backup_add_part_and_comment
		else
			ignore=--ignoreAdditionalPartitions
			backup_add_comment "$ignore"
		fi
	else
		backup_add_comment
	fi

		unmount
		exit 0
}

function backup_add_part_and_comment(){
	echo -e "$yellow $Quest_comment \n $normal"
	read Quest_comment

	if [[ ${Quest_comment,,} =~ [yj] ]]; then
		echo -e "$yellow $Quest_comment_text \n $normal"
		read Quest_comment_text
		
		echo -e "$Info_start \n"
		/usr/local/bin/raspiBackup.sh -M "$Quest_comment_text" -P -T "1 2 $partitions"
	else
		echo -e "$Info_start \n"
		/usr/local/bin/raspiBackup.sh -P -T "1 2 $partitions"
	fi
}

function backup_add_comment(){
	echo -e "$yellow $Quest_comment \n $normal"
	read Quest_comment

	if [[ ${Quest_comment,,} =~ [yj] ]]; then
		echo -e "$yellow $Quest_comment_text \n $normal"
		read Quest_comment_text
		echo -e "$Info_start \n"
		
		/usr/local/bin/raspiBackup.sh -M "$Quest_comment_text" "$1"
	else
		echo -e "$Info_start \n"
		/usr/local/bin/raspiBackup.sh "$1"
	fi
}

function execution(){
	lsblk                      #Output of lsblk to check the drive for restore
	echo -e "$yellow $Quest_select_drive \n $normal"
	read destination

	if [[ "$destination" =~ ^(sd[a-f]|mmcblk[0-2])$ ]]; then
		echo ""
	else
		echo -e "$red $destination $Warn_only_drive $normal"
		execution
	fi

 	if [[ -b /dev/$destination ]]; then
		echo -e "$green OK $normal \n"
	else
		echo -e "$red $destination $Warn_drive_not_present \n $normal"
		execution
	fi

	if grep -q /$destination /proc/mounts; then
		echo -e "$red $destination $Warn_drive_mounted \n $normal".
		exit 0
	fi

	echo -e "$green $Info_backup_drive \n $backup_path \n >>> $destination \n $normal"
	echo -e "$Info_start \n"
	/usr/local/bin/raspiBackup.sh -d /dev/$destination /$backup_path      #Call raspiBackup.sh
	exit 0
}

function execution_select(){
	declare -a backup_folder
	backup_folder=( $(find $backupdir/$dir/$dir* -maxdepth 0 -type d))

	for i in "${!backup_folder[@]}"; do
		v=$(( $i + 1 ))
		echo "${backup_folder[$i]}  -> $v"
	done

	echo -e "\n\n$yellow $Quest_number_of_backup \n $normal"
	read v

	number="$v"
	min=1
	max="${#backup_folder[@]}"

	i=$(( $v - 1 ))
	backup_path=${backup_folder[$i]}

	test_digit "$number" "$min" "$max" "$backup_path"

	if [[ $del != "y" ]]; then
		echo -e "$green $Info_restore \n $backup_path $normal"
	else
		echo -e "$red $Info_delete \n $backup_path\n\n"
		echo -e " $Quest_sure $normal\n\n"
		read input_sure

		if [[ ${input_sure,,} =~ [yj] ]]; then
			echo -e "$yellow $backup_path \n $Info_Confirmation \n\n"
			echo -e "$green $Info_update $normal"
			rm -R $backup_path
			echo ""
			ls -la $backupdir/$hostname
			echo ""
			exit 0
		else
			exit 0
		fi
	fi

	if [[ -d "$backup_path" ]]; then
		execution
		echo -e "$red $Warn_drive_not_present \n $normal"
		execution_select
	fi
}

function test_digit(){
	if [[ "$1" =~ ^[0-9]+$ ]]; then            # regex: a number has to have

		if (( $1 < $2 || $1 > $3 )); then
			echo -e "$red $1 $Warn_invalid_number $2 > $3 \n $normal"
			execution_select
		fi
	else
		echo -e "$red $1 $Warn_no_number \n $normal"
		execution_select
	fi
}

function backupdir_test(){
	mountpoint="/bin/mountpoint"
	$mountpoint -q "$1"
	[[ $? == 0 ]]
}

function mount(){
	backupdir_test "$backupdir"

	if [[ $unitname == *".mount" ]]; then

		if backupdir_test "$backupdir"; then
			echo -e "$green $Info_already_mounted $normal \n"
		else
			systemctl start $unitname
			backupdir_test "$backupdir"

			if backupdir_test "$backupdir"; then
				echo -e "$green $Info_is_mounted $normal \n"
				mounted=ok
			else
				echo -e "$red $Info_not_mounted $normal \n"
				exit 0
			fi
		fi
	fi

	if [[ $unitname == "fstab" ]]; then

		if backupdir_test "$backupdir"; then
		echo -e "$green $Info_already_mounted $normal \n"
		else
			/usr/bin/mount -a
			backupdir_test "$backupdir"

			if backupdir_test "$backupdir"; then
				echo -e "$green $Info_is_mounted $normal \n"
				mounted=ok
			else
				echo -e "$red $Info_not_mounted $normal \n"
				exit 0
			fi
		fi
	fi
}

function unmount(){
	if [[ $mounted == ok ]]; then
	/usr/bin/umount $backupdir
	fi
}

function sel_dir(){
    ls -1 $backupdir
    echo ""
    echo -e "$yellow $Quest_sel_dir \n $normal"
    read dir
	backup_path="$(find $backupdir/$dir/$dir* -maxdepth 0 | sort -r | head -1)"
}

function language(){
	echo -e "\n \n$yellow Please choose your preferred language"
	echo -e " Bitte waehle deine bevorzugte Sprache \n \n"
	echo -e " German  = 1"
	echo -e " English = 2 \n \n $normal"
	read lang

	if (( $lang == 1 )); then
		Quest_last_backup="Soll das letzte Backup restored werden? j/N"
		Quest_select_drive="Bitte waehle das Ziellaufwerk z.B. mmcblk0,sda,sdb,sdc...."
		Warn_drive_not_present="Das Ziellaufwerk existiert nicht"
		Warn_drive_mounted="Mindestens eine Partition ist gemountet. Bitte erst aushaengen."
		Info_backup_drive="Folgendes Backup wird restored "
		Quest_number_of_backup="Bitte gebe die hinter dem gewuenschten Backup stehende Zahl ein. "
		Warn_no_dir="Oops Das Verzeichnis existiert nicht."
		Warn_invalid_number="Die eingegebene Zahl ist ungueltig. Nur Zahlen im Bereich von "
		Info_restore="Das folgende Backup wird zurueckgespielt "
		Warn_no_number="Das ist keine Zahl "
		Warn_false_number="Falsche Eingabe Bitte nur 1 oder 2 eingeben "
		Quest_backup_or_restore="Soll ein Backup erstellt oder ein bestehendes Backup restored werden?"
		Quest_more_than_2_partitions="Befinden sich auf dem Systemlaufwerk mehr als die 2 Standard-Partitionen /boot und /root ?   j/N"
		Quest_backup_more_than_2="Sollen mehr als die 2 Standardpartitionen gesichert werden?   j/N"
		Quest_additional_partitions="Bitte die Partitionsnummer(n) eingeben, die zusaetzlich \n  zu den Standardpartitionen gesichert werde sollen. \n Nur die zusätzlichen. Die Standardpartitionen werden automatisch berücksichtigt \n Falls mehrere, dann getrennt durch Leerzeichen.  \n  Beispiel:  3 4 5 "
		Warn_only_drive="Bitte ein gueltiges Laufwerk eingeben"
		Quest_comment="Soll ein Kommentar am Ende des Backup-Verzeichnisses eingefügt werden? \n Dieses Backup wird dann nicht in die backup-Strategie übernommen und nicht automatisch recycled. \n j/N \n"
		Quest_comment_text="Bitte gebe den Kommentar ein \n"
		Info_delete="Das folgende Backup wird gelöscht"
		Quest_sure="Bist du wirklich sicher?   j/N"
		Info_update="Das Backup wird jetzt endgültig gelöscht \n Das kann eine Weile dauern \n Im Anschluss wird dir das aktualisierte Backupverzeichnis noch einmal angezeigt \n \n"
		Info_already_mounted="Das Backupverzeichnis ist bereits gemountet. Es wird im Anschluss nicht ausgehängt."
		Info_is_mounted="Das Backupverzeichnis wurde gemountet. Es wird im Anschluss ausgehängt"
		Info_not_mounted="Das Backupverzeichnis konnte nicht gemountet werden"
		Info_start="raspiBackup wird jetzt gestartet"
		Warn_not_mounted="Das Backupverzeichnis ist nicht gemountet"
		Quest_sel_dir="Bitte gebe den Namen des Backupverzeichnisses ein"
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
		Quest_backup_or_restore="Should a backup be created or an existing backup restored?"
		Quest_more_than_2_partitions="Are there more than the 2 standard partitions on the system drive?   y/N"
		Quest_backup_more_than_2="Should more than the 2 standard partitions be backed up   y/N?"
		Quest_additional_partitions="Enter the partition number(s) to be backed up in addition to the standard partitions. \n Only the additional ones. The standard partitions are automatically taken. \n If more than one, separate them with spaces.  \n Example: 3 4 5 "
		Warn_only_drive="Please only enter a valid Drive"
		Quest_comment="Should a comment be inserted at the end of the backup directory? \n This backup will not be included in the backup strategy and will not be recycled automatically. \n y/N \n"
		Quest_comment_text="Please enter the comment \n"
		Info_delete="The following Backup will be deletet"
		Quest_sure="Are you realy sure   y/N?"
		Info_update="The backup is now finally deleted. \n This may take a while, \n Afterwards, the updated backup directory is displayed again. \n \n"
		Info_already_mounted="The backup directory is already mounted. It will not be unmounted afterwards"
		Info_is_mounted="The backup directory was mounted. It will be unmounted afterwards"
		Info_not_mounted="The backup directory could not be mounted"
		Info_start="raspiBackup will be started now"
		Warn_not_mounted="The Backup directory is not mounted"
		Quest_sel_dir="Please enter the name of the backup-Directory"
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

	source $FILE
	backupdir=$DEFAULT_BACKUPPATH

	if [[ $3 == "--cron" ]]; then
		/usr/local/bin/raspiBackup.sh
		unmount
		exit 0		
	else
		language
	fi
	
	if [[ $1 == "--mountfs" ]]; then

		if [[ $2 == *".mount"* ]] || [[ $2 == "fstab" ]]; then
			unitname=$2
			mount
		else
			echo "Angabe erforderlich wie das Laufwerk gemountet wird. (mount-unit oder fstab)"
		exit
		fi
	fi
		
	if cat /proc/mounts | grep $backupdir > /dev/null; then
        	echo " "
    else
        echo -e "$red $Warn_not_mounted $normal"
        exit
    fi	


	if [[ $1 == "--last" ]] || [[ $3 == "--last" ]]; then
		sel_dir
		execution
		unmount
		exit 0

	elif [[ $1 == "--select" ]] || [[ $3 == "--select" ]]; then
		sel_dir
		execution_select
		unmount
		exit 0

	elif [[ $1 == "--backup" ]] || [[ $3 == "--backup" ]]; then
		backup
		unmount
		exit 0

	elif [[ $1 == "--delete" ]] || [[ $3 == "--delete" ]]; then
		del=y
		execution_select
		unmount
		exit 0
	fi

	echo -e "$yellow $Quest_backup_or_restore \n"
	echo -e " backup    1"
	echo -e " restore   2 \n $normal"

	read backup_or_restore

	if (( $backup_or_restore  == 1 )); then
		backup
	
	elif (($backup_or_restore == 2 )); then
		sel_dir
		echo -e "$yellow $Quest_last_backup \n $normal"
		read answer
	else
		echo -e "$red $Warn_false_number \n $normal"
	fi

	if [[ ${answer,,} =~ [yj] ]]; then
		execution
		unmount
		exit 0
	else
		execution_select

	fi


