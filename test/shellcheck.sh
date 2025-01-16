#/bin/bash

if (( $# == 0 )); then
	shellcheck -S warning --color=never --shell=bash ../raspiBackup.sh | tee shellcheck.log
else	
	shellcheck -S warning --color=never --shell=bash ../installation/raspiBackupInstallUI.sh | tee shellcheck.log
fi	
