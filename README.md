# raspiBackup

1. Backup and restore your raspberry with raspiBackup.

For detailed documentation and download of the latest version of raspiBackup and it's installation script [see here in English](https://www.linux-tips-and-tricks.de/en/backup) and [here in German](https://www.linux-tips-and-tricks.de/de/raspiBackup)

2. Miscellaneous tools and utilities for raspiBackup.

  * Wrapper script for raspiBackup to add any activities before and after backup [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupWrapper.sh)

	* Wrapper scipt which checks whether a nfsserver is online, mounts one exported directory and invokes raspiBackup. If the nfsserver is not online no backup is started. [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupNfsWrapper.sh)

  * Installation scripts [(Code)](https://github.com/framps/raspiBackup/tree/master/installation)
	  * raspiBackup Installation
	  * Extension sample installation

3. Sample extensions for raspiBackup [(Code)](https://github.com/framps/raspiBackup/tree/master/extensions)
	* Sample eMail extension
	* Sample extension which reports the memory usage before and after backup
	* Sample extension which reports the CPU temperatur before and after backup
	* Sample extension which initiates different actions depending on the return code of raspiBackup

4. REST API Server proof of concept for raspiBackup
	Allows to start a backup from a remote system or any web UI.
	1. Download executable from RESTAPI directory
	2. Create a file /usr/local/etc/raspiBackup.auth and define access credentials for the API. For every user create a line userid:password
	3. Set file attributes for /usr/local/etc/raspiBackup.auth to 600
	4. Start the RESTAPI with ```sudo raspiBackupRESTAPIListener```
	4. Use ```curl -u userid:password -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar", "keep": 3}' http://<raspiHost>:8080/v0.1/backup``` to kick off a backup.
