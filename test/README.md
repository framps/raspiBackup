# Regressiontest scripts

The following scripts are used to execute regressiontests every time before a new release of raspiBackup is published. The regressiontest tests the basic backup and restore function for all backup modes and backup types on an SD only environment and and USB only environment to make sure the backup created with the new release can still be restored successfully and will boot up.
Mixed environment with /boot od SD card an /root on USB is not tested. In addition the smart recycle strategy is tested.  

See also [this page](https://www.linux-tips-and-tricks.de/en/raspibackupcategorye/510-raspibackup-regressiontests-executed/) which tests are executed on the restored backup to verify it's working correctly.

The qemu setup is based on the descriptions on [this German page](https://crycode.de/raspberry-pi-4-emulieren-mit-qemu/) and customized for raspiBackup special requirements .
Previously the setup was done according [this page](https://www.linux-tips-and-tricks.de/en/raspberrye/310-how-to-emulate-raspberry-pi-on-kvm-2/).

## Prerequ

1. Existing RaspberryPiOS image
2. QEMU installed 
3. QEMU image startup script

## Scripts

1. raspiBackupRegression.sh - Main script which executes regressiontests for all backup types and backup modes
2. raspiBackupTest.sh - Executes a specific backup regressiontest
3. raspiRestoreTest.sh - Executes a restore test for an existing backup
4. testRaspiBackup.sh - Executed on the qemu image to create a backup
