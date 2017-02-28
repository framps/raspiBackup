# raspiBackup

Miscellaneous tools and utilities for [raspiBackup EN](https://www.linux-tips-and-tricks.de/en/backup).

German native speakers should visit [raspiBackup DE](https://www.linux-tips-and-tricks.de/de/raspiBackup) 

1. Wrapper script for raspiBackup to add any activities before and after backup [(Code)](https://github.com/framps/raspiBackup/blob/master/raspiBackupWrapper.sh)
2. Installation scripts [(Code)](https://github.com/framps/raspiBackup/tree/master/installation)
	1. raspiBackup Installation
	2. Extension sample installation
3. Sample extensions for raspiBackup [(Code)](https://github.com/framps/raspiBackup/tree/master/extensions)
	1. Sample eMail extension
	2. Sample extension which reports the memory usage before and after backup
	3. Sample extension which reports the CPU temperatur before and after backup
	4. Sample extension which initiates different actions depending on the return code of raspiBackup

4. REST API Server Prototype for raspiBackup written in go [(Code)](https://github.com/framps/raspiBackup/blob/master/RESTAPIServer.go)
	1. Install go (Use following [instructions](http://www.admfactory.com/how-to-install-golang-on-raspberry-pi/))
	2. Create go directory ```mkdir /home/pi/go```
	3. Configure go ```export GOPATH=/home/pi/go; export PATH=$GOPATH/bin:$PATH```
	4. Execute ```go get github.com/framps/raspiBackup```
	5. Start REST API server ```raspiBackup```
	6. Invoke raspiBackup via REST with curl
	
		```curl -H "Content-Type: application/json" -X POST -d '{"target":"/backup","type":"tar"}' http://<raspiHost>:8080/v0.1/backup```


