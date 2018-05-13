#!/bin/bash
#r2i-raspi.sh

#####################################################################################################################################
#
# Sample code which retrieves the latest backup created with raspiBackup and uses raspiBackupRestore2Image to create an image
# from a tar or rsync backup
#
# Visit http://www.linux-tips-and-tricks.de/raspiBackup for more details about raspiBackup
#
# made available by Peter, a user of raspiBackup on 5/12/18
# See history in German on https://www.linux-tips-and-tricks.de/de/hilfsprogramme#comment-2670
#
# Header and english translations added by framp
#
#####################################################################################################################################

#NFS-Share mounten
#Mount NFS share
mount -t nfs -o soft,vers=3 192.168.192.5:/c/backup /backup

#schreibt die Verzeichnis-Struktur in die Datei folders.txt
#write directory structure in file folder.txt
ls /backup/raspi > folders.txt

#erzeugt aus den Name des neuesten Verzeichnisses die Variable $$bckpfad
#Achtung: wenn im "backup root Ordner" Dateien vorhanden sind oder neuere Ordner die nichts mit dem Backup zu tun haben
#werden diese ausgelesen und als Variable gesetzt!
#retrieves the name of the backup directory in $bckpfad
#Attention: if there are files in backup root folder this retrieval algorithm will not work!
bckpfad="$(head -n 100 folders.txt | tail -n 1)"

#loescht die temporaere Datei folders.txt
#delete temporary file folder.txt
rm folders.txt

#startet r2i mit dem entsprechenden Pfad
#start r2i with the latest backup path
raspiBackupRestore2Image.sh /backup/raspi/$bckpfad

#Bennent die erstellte "r21"-Datei um damit diese unter Windows als Image-Datei auf eine SD-Karte geschrieben werde kann
#rename created r2i so it can be used on windows to write it on SD card
mv /backup/raspi/$bckpfad/raspi-backup.dd /backup/raspi/$bckpfad/raspi-full-image.img


#todo's (Ausbau fuer everyone):
#- Alle Variablen am Anfang des Scripts definieren, wie z.B. bei raspiBackupNfsWraper.sh
#- nur die Ordner in die Datei folders.txt schreiben und evt. sortiert (ls -D (?), ls -c (?) )
#- pruefen ob die Datei "raspi-full-image.img" bereits exisitert, dann abbrechen.
#- pruefen ob ueberhaupt eine Backup-Datei (*.dd) exisitiert, sonst abbrechen

#todos
#- Define all variables atthe beginning of script
#- just collect the directories only in folders.txt
#- check if raspi-full-image.img exists already and terminate
#- check whether a backup file (*.dd) exists and terminate
