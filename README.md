# raspiBackup

Miscellaneous tools and utilities for [raspiBackup EN](https://www.linux-tips-and-tricks.de/en/backup).

German native speakers should visit [raspiBackup DE](https://www.linux-tips-and-tricks.de/de/raspiBackup) 

1. Wrapper script for raspiBackup to add any activities before and after backup [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupWrapper.sh)
2. Wrapper scipt which checks whether a nfsserver is online, mounts one exported directory and invokes raspiBackup. If the nfsserver is not online no backup is started. [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupNfsWrapper.sh)
2. Installation scripts [(Code)](https://github.com/framps/raspiBackup/tree/master/installation)
	1. raspiBackup Installation
	2. Extension sample installation
3. Sample extensions for raspiBackup [(Code)](https://github.com/framps/raspiBackup/tree/master/extensions)
	1. Sample eMail extension
	2. Sample extension which reports the memory usage before and after backup
	3. Sample extension which reports the CPU temperatur before and after backup
	4. Sample extension which initiates different actions depending on the return code of raspiBackup

4. REST API Server for raspiBackup written in go 
	Allows to start a backup from a remote system or any web UI.
	1. Download executable from RESTAPI directory
	2. Create a file /usr/local/etc/raspiBackup.auth and define access credentials for the API. For every user create a line userid:password
	3. Set file attributes for /usr/local/etc/raspiBackup.auth to 600
	4. Start the RESTAPI with ```sudo raspiBackupRESTAPIListener``` 
	4. Use ```curl -u userid:password -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar", "keep": 3}' http://<raspiHost>:8080/v0.1/backup``` to kick off a backup.
	
	

