# raspiBackup

## Backup and restore your raspberry

For detailed documentation and download of the latest version of raspiBackup and it's installation script [see here in English](https://www.linux-tips-and-tricks.de/en/backup) and [here in German](https://www.linux-tips-and-tricks.de/de/raspiBackup)

For the list of all fixes and enhancemants of raspiBackup [see here in English](https://www.linux-tips-and-tricks.de/en/versionhistory) and [here in German](https://www.linux-tips-and-tricks.de/de/versionshistorie)

## Miscellaneous tools and utilities for raspiBackup

* Wrapper script for raspiBackup to add any activities before and after backup [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupWrapper.sh)

* Wrapper script which checks whether a nfsserver is online, mounts one exported directory and invokes raspiBackup. If the nfsserver is not online no backup is started. [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupNfsWrapper.sh)

* Script which restores an existing tar or rsync backup created by raspiBackup into an image file and then shrinks the image with [pishrink](https://github.com/Drewsif/PiShrink). Result is the smallest possible dd image backup. When this image is restored via dd or windisk32imager it's expanding the root partition to the maximum possible size. [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupRestore2Image.sh)

* Installation scripts [(Code)](https://github.com/framps/raspiBackup/tree/master/installation)
  * raspiBackup Installation
  * Extension sample installation

## Sample extensions [(Code)](https://github.com/framps/raspiBackup/tree/master/extensions)
* Sample eMail extension
* Sample extension which reports the memory usage before and after backup
* Sample extension which reports the CPU temperatur before and after backup
* Sample extension which reports the disk usage on the backup partition before and after backup and the absolute and relative change
* Sample extension which initiates different actions depending on the return code of raspiBackup

## REST API Server proof of concept

Allows to start a backup from a remote system or any web UI.
1. Download executable from RESTAPI directory
2. Create a file /usr/local/etc/raspiBackup.auth and define access credentials for the API. For every user create a line userid:password
3. Set file attributes for /usr/local/etc/raspiBackup.auth to 600
4. Start the RESTAPI with ```sudo raspiBackupRESTAPIListener```
5. Use ```curl -u userid:password -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar", "keep": 3}' http://<raspiHost>:8080/v0.1/backup``` to kick off a backup.

## New features and bug fixes

Any PRs are welcome.
1. Missing feature - raspiBackup has a lot of features already but if you miss some functionality just create an issue or a PR. I suggest to create an issue first in order to discuss the missing feature before start coding.
2. Bugfixes - Nobody is perfect. Either create an issue or just create a PR
