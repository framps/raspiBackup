# raspiBackup

Miscellaneous tools and utilities for [raspiBackup](https://www.linux-tips-and-tricks.de/en/backup) 

1. Wrapper script for raspiBackup to add any activities before and after backup [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupWrapper.sh)
2. Installation script [(Code)](https://github.com/framps/raspiBackup/tree/master/installation)
  1. raspiBackupInstall [(Code)](https://github.com/framps/raspiBackup/blob/master/installation/raspiBackupInstall.sh)
  2. Sample extensions [(Code)](https://github.com/framps/raspiBackup/blob/master/installation/raspiBackupSampleExtensionsInstall.sh)
3. Sample extensions for raspiBackup [(Code)](https://github.com/framps/raspiBackup/tree/master/extensions)
	1. Sample eMail extension
	2. Sample extension which reports the memory usage before and after backup
	3. Sample extension which reports the CPU temperatur before and after backup
	4. Sample extension which initiates different actions depending on the return code of raspiBackup

4. REST API Server Prototype for raspiBackup written in go [(Code)](https://github.com/framps/raspiBackup/blob/master/RESTAPIServer.go)
	1. Install go (Use following [instructions](http://www.admfactory.com/how-to-install-golang-on-raspberry-pi/))
	2. Create go subdirectory ```mkdir /home/pi/go```
	3. Configure go ```export GOPATH=/home/pi/go; export PATH=$GOPATH/bin:$PATH```
	4. Execute ```go get github.com/framps/raspiBackup```
	5. Start REST API server ```raspiBackup```
	6. Invoke raspiBackup via REST with curl
	
		```curl -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar"}' http://<raspiHost>:8080/v0.1/backup```

[Details about raspiBackup (English)](https://www.linux-tips-and-tricks.de/en/backup)

[Details über raspiBackup (German)](https://www.linux-tips-and-tricks.de/de/raspiBackup)
