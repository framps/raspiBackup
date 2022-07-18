## Collection of some sample scripts useful for raspiBackup users

__Note:__ The scripts are provided as is by framps and raspiBackup users and are not included in any raspiBackup release and thus are not maintained. Enhancements and other helper scripts are welcome in a PR.

1. r2i-raspi - Sample code which retrieves the latest backup created with raspiBackup and uses raspiBackupRestore2Image to create an image from a tar or rsync backup

2. raspiBackupNfsWrapper - Wrapper for raspiBackup which dynamically mounts and umounts a nfs backup drive

3. raspiBackupRestore2Image - Script which builds a dd image from a tar or rsync backup created with raspiBackup

4. raspiImageMail - Send an email using the functions from raspiBackup, based of version 0.6.4

5. stopStartAllServicesWrapper - Script wish either stops or starts all existing services.

6. raspiBackupRestoreHelper.sh - Makes restore of backups much more convenient.

  - Auxiliary script to restore a backup created by raspiBackup in a simple dialog-guided way.
  - It can simply be started without options. Then a prompt appears whether the last backup should be restored. (y/N) For (N) an appropriate backup can be selected from a list. Then select the target medium and raspiBackup does the rest.
  - Possible options --last or --select
    - Option --last -> the last backup is automatically selected without any prompt
    - Option --select -> the desired backup can be selected from a list
  + See [this flowchart](./images/raspiBackopRestoreHelper_simple_flow-chart.pdf) for details
