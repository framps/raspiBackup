![](https://img.shields.io/github/release/framps/raspiBackup.svg?style=flat) ![](https://img.shields.io/github/last-commit/framps/raspiBackup.svg?style=flat)

# raspiBackup - Backup and restore your running Raspberries

* Create a full system backup unattended with no shutdown of the system or other manual intervention just by starting raspiBackup using cron. Important services can be stopped before starting the backup and are started again when the backup finished.
* Any device mountable on Linux can be used as backupspace (local USB disk, remote nfs drive, remote samba share, remote ssh server using sshfs, remote ftp server using curlftpfs, webdav drive using davfs, ...).
* Standard Linux backup tools dd, tar and rsync can be used to create the backup.
* An external rootpartition, Raspberry 3 USB boot images and NOOBS images are supported.
* Status eMail sent when backup finished
* UI installer configures all major options to get raspiBackup up and running in 5 minutes
* Much more features ... (See doc below)

## Documentation

* [Installation](https://www.linux-tips-and-tricks.de/en/quickstart-rbk)
* [Users guide](https://www.linux-tips-and-tricks.de/en/backup)
* [FAQ](https://www.linux-tips-and-tricks.de/en/faq)

## Installer
An installer [(Code)](https://github.com/framps/raspiBackup/blob/master/installation/raspiBackupInstallUI.sh) uses menus, checklists and radiolists similar to raspi-config and helps to install and configure major options of raspiBackup and in 5 minutes the first backup can be created.

![Screenshot1](https://github.com/framps/raspiBackup/blob/master/images/raspiBackupInstallUI-1.png)
![Screenshot2](https://github.com/framps/raspiBackup/blob/master/images/raspiBackupInstallUI-2.png)
![Screenshot3](https://github.com/framps/raspiBackup/blob/master/images/raspiBackupInstallUI-3.png)

## Usage

For the latest and actual list of options see [here](https://www.linux-tips-and-tricks.de/en/backup#parameters)

```
pi@raspberry: $ raspiBackup.sh
raspiBackup.sh 0.6.4, 2019-01-07/20:47:27 - 0530211

Usage: raspiBackup.sh [option]* {backupDirectory}

-General options-
-A append logfile to eMail (default: no)
-b {dd block size} (default: 1MB)
-D "{additional dd parameters}" (default: no)
-e {email address} (default: no)
-E "{additional email call parameters}" (default: no)
-g Display progress bar
-G {message language} (EN or DE) (default: EN)
-h display this help text
-l {log level} (Off | Debug) (default: Off)
-m {message level} (Minimal | Detailed) (default: Minimal)
-M {backup description}
-n notification if there is a newer scriptversion available for download (default: yes)
-s {email program to use} (mail,ssmtp,sendEmail,mailext) (default: mail)
--timestamps Prefix messages with timestampes (default: no)
-u "{excludeList}" List of directories to exclude from tar and rsync backup
-U current script version will be replaced by the actual version. Current version will be saved and can be restored with parameter -V
-v verbose output of backup tools (default: no)
-V restore a previous version
-z compress backup file with gzip (default: no)

-Backup options-
-a "{commands to execute after Backup}" (default: )
-B Save bootpartition in tar file (Default: 0)
-k {backupsToKeep} (default: 3)
-o "{commands to execute before Backup}" (default: no)
-P use dedicated partitionbackup mode (default: no)
-t {backupType} (dd|rsync|tar) (default: rsync)
-T "{List of partitions to save}" (Partition numbers, e.g. "1 2 3"). Only valid with parameter -P (default: *)

-Restore options-
-C Formating of the restorepartitions will check for badblocks (Standard: 0)
-d {restoreDevice} (default: no) (Example: /dev/sda)
-R {rootPartition} (default: restoreDevice) (Example: /dev/sdb1)
--noResizeRootFS or --resizeRootFS (Default: yes)
```

## Detailed information

 * [English](https://www.linux-tips-and-tricks.de/en/backup)
 * [German](https://www.linux-tips-and-tricks.de/de/raspibackup)

# Miscellaneous tools and utilities

* Wrapper script for raspiBackup to add any activities before and after backup [(Code)](https://github.com/framps/raspiBackup/blob/master/helper/raspiBackupWrapper.sh)

* Wrapper script which checks whether a nfsserver is online, mounts one exported directory and invokes raspiBackup. If the nfsserver is not online no backup is started. [(Code)](https://github.com/framps/raspiBackup/blob/master/helper/raspiBackupNfsWrapper.sh)

* Script which restores an existing tar or rsync backup created by raspiBackup into an image file and then shrinks the image with [pishrink](https://github.com/Drewsif/PiShrink). Result is the smallest possible dd image backup. When this image is restored via dd or windisk32imager it's expanding the root partition to the maximum possible size. [(Code)](https://github.com/framps/raspiBackup/blob/master/helper/raspiBackupRestore2Image.sh)

* Installation scripts [(Code)](https://github.com/framps/raspiBackup/tree/master/installation)
  * raspiBackup Installation
  * Extension sample installation

## Sample extensions [(Code)](https://github.com/framps/raspiBackup/tree/master/extensions)
* Sample eMail extension
* Sample pre/post extension which reports the memory usage before and after backup
* Sample pre/post extension which reports the CPU temperatur before and after backup
* Sample pre/post extension which reports the disk usage on the backup partition before and after backup and the absolute and relative change
* Sample pre/post extension which initiates different actions depending on the return code of raspiBackup
* Sample ready extension which copies /etc/fstab into the backup directory

## Start with Systemd

To start raspiBackup with Systemd see 
[here](https://github.com/framps/raspiBackup/tree/development/systemd/systemd_readme.md)

# REST API Server proof of concept

Allows to start a backup from a remote system or any web UI.
1. Download executable from RESTAPI directory
2. Create a file /usr/local/etc/raspiBackup.auth and define access credentials for the API. For every user create a line userid:password
3. Set file attributes for /usr/local/etc/raspiBackup.auth to 600
4. Start the RESTAPI with ```sudo raspiBackupRESTAPIListener```. Option -a can be used to define another listening port than :8080.
5. Use ```curl -u userid:password -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar", "keep": 3}' http://<raspiHost>:8080/v0.1/backup``` to kick off a backup.
