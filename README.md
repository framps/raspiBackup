# raspiBackup - Backup and restore your running Raspberry

raspiBackup helps to create backups of a running Raspberry with no shutdown or manual intervention by using cron. Important services will be stopped just before starting the backup and are started again when the backup finished.

Any device which can be mounted on Linux can be used as backupspace (USB disk, USB stick, nfs, samba, sshfs, ...). Standard Linux backup tools dd, tar and rsync using hardlinks are used to create the backup.

An external rootpartition, Raspberry 3 USB boot images and NOOBS images are supported.

## Usage

```
pi@raspberry: $ raspiBackup.sh

raspiBackup.sh 0.6.3.1-, 2018-02-21/19:17:52 - 7f9d77a
usage: raspiBackup.sh [option]* {backupDirectory | backupFile}

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
-L {log location} (Syslog: /var/log/syslog | Varlog: /var/log/raspiBackup/<hostname>.log | Backup: <backupPath> | Current: ~/raspiBackup.log) (default: Varlog)
-m {message level} (Minimal | Detailed) (default: Minimal)
-M {backup description}
-n notification if there is a newer scriptversion available for download (default: yes)
-s {email program to use} (mail,ssmtp,sendEmail,mailext) (default: mail)
-u "{excludeList}" List of directories to exclude from tar and rsync backup
-U current script version will be replaced by the actual version. Current version will be saved and can be restored with parameter -V
-v verbose output of backup tools (default: no)
-V restore a previous version
-X extended attributes and ACLs are handled by tar (default: no)
-z compress backup file with gzip (default: no)

-Backup options-
-a "{commands to execute after Backup}" (default: )
-B Save bootpartition in tar file (Default: 0)
-k {backupsToKeep} (default: 3)
-o "{commands to execute before Backup}" (default: no)
-P use dedicated partitionbackup mode (default: no)
-t {backupType} (dd|rsync|tar) (default: dd)
-T "{List of partitions to save}" (Partition numbers, e.g. "1 2 3"). Only valid with parameter -P (default: *)

-Restore options-
-C Formating of the restorepartitions will check for badblocks (Standard: 0)
-d {restoreDevice} (default: no) (Example: /dev/sda)
-R {rootPartition} (default: restoreDevice) (Example: /dev/sdb1)
--noResizeRootFS or --resizeRootFS (Default: yes)
```

## Detailed information
* Installer, quickstart, FAQ, detailed description of all options, version history and more
 * [English](https://www.linux-tips-and-tricks.de/en/backup)
 * [German](https://www.linux-tips-and-tricks.de/de/raspiBackup)

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

# REST API Server proof of concept

Allows to start a backup from a remote system or any web UI.
1. Download executable from RESTAPI directory
2. Create a file /usr/local/etc/raspiBackup.auth and define access credentials for the API. For every user create a line userid:password
3. Set file attributes for /usr/local/etc/raspiBackup.auth to 600
4. Start the RESTAPI with ```sudo raspiBackupRESTAPIListener```. Option -a can be used to define another listening port than :8080.
5. Use ```curl -u userid:password -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar", "keep": 3}' http://<raspiHost>:8080/v0.1/backup``` to kick off a backup.

## New features and bug fixes

1. Missing feature - raspiBackup has a lot of features already but if you miss some functionality just create an issue or a PR. I suggest to create an issue first in order to discuss the missing feature before start coding.
2. Bugfixes - Nobody is perfect. Either create an issue or just create a PR
