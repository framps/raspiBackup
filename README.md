# raspiBackup - Backup and restore your Raspberry

## Features

* Unattended backup of a running Raspberry Pi (Pi backups itself)
* Other similar SoCs are supported (Banana Pi, Ondroid, Beagle Board, Cubieboard, ...)
* Support of Raspberry3 running without SD card (booted from USB)
* Partitionoriented backupmode backups a variable number of partitions of the SD card and thus can save NOOBs images and images with more than 2 partitions
* Backup and restore is independent of the operating system (Linux, Windows or Mac) used to access the Raspberry Pi
* Windows or Mac user just use the Raspberry to restore their backup
* Windows user can restore dd backups with win32diskimager
* Linux user can use their Linux system or the Raspberry to restore the backup
* Plugins allow to extend the script capabilities with custom code
* Various backup targets, for example
 * External USB stick
 * External USB disk
 * Synology drives
 * cifs/samba mounted network drive
 * nfs mounted network drive
 * sshfs mounted network drive
 * webdav network drive
 * Mounted ftp server
 * In general every device which can be mounted on Linux
* Simple restore of the backup
* An external root filesystem on disk or USB stick will be saved with in the normal backup mode if tar or rsync backup is used
* Can be used to clone Raspberry Pi
* Simple installation. A configuration wizzard helps to configure the most important parameters.
* Messages in English and German
* Lots of invocation parameters to customize the backup process
* dd, tar and rsync backup possible (-t option). rsync requires an ext3/ext4 partition for hardlinks
* dd and tar can be zipped to reduce the backup size (-z option)
* dd backup can be enabled to save only the space used by the partitions. That way a 32GB SD card with a 8GB partition will only need 8GB for backup
* Boot partition backups are saved with hardlinks to save backup space if enabled with an option
* Different backup types can be mixed per system (e.g. day backup uses rsync, weekly backup uses dd)
* Automatic stop and start of running services before and after the backup (-a and -o option)
* Sample script helps to easily add additional activities to be executed before and after the backup. E.g. mount and unmount of the backup device
* Number of backups to keep is configurable (-k option)
* If the target SD card is smaller or larger than the original SD card the second root partition will be adjusted accordingly
* eMail is sent to report the backup result (-e option)
* rsync uses hardlinks to reduce the backup size
* Supported eMail programs: mailx/mail, sendEmail and ssmtp (-s option)
* Unsupported eMail clients can be used via the eMailPlugin
* Automatic notification if there is a newer version of raspiBackup available (-n option)
* Simple update of raspiBackup to the latest version (-U option)
* Simple restore of a previous version of raspiBackup (-V option)
* Arbitrary directories and files can be excluded from the backup (-u option)
* Multiple Raspberries can save their backup at the same place

## More detailed information

* Quickstart, FAQ, detailed description of options, version history and more
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
3. Pull requests for new features and bug fixes are welcome
