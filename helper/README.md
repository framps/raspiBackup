## Collection of some sample scripts useful for raspiBackup users

__Note:__ Most of the scripts are provided by framps as is and are not included in any raspiBackup release and thus are not maintained. Enhancements and other helper scripts are welcome in a PR. raspiBackupDialog was provided by [franjo-G](https://github.com/franjo-G) and will be maintained by him. 

1. r2i-raspi - Sample code which retrieves the latest backup created with raspiBackup and uses raspiBackupRestore2Image to create an image from a tar or rsync backup

2. raspiBackupNfsWrapper - Wrapper for raspiBackup which dynamically mounts and umounts a nfs backup drive

3. raspiBackupRestore2Image - Script which builds a dd image from a tar or rsync backup in the backup directory or restores a rsync or tar backup on a device like a SD card or SSD which then can be used as a cold backup.

4. raspiImageMail - Send an email using the functions from raspiBackup, based of version 0.6.4

5. stopStartAllServicesWrapper - Script wish either stops or starts all existing services.

6. raspiBackupDialog.sh - Makes backup and restore of backups much more convenient. (Old name: raspiBackupRestoreHelper.sh) 

   Help script to create a backup or restore a backup created with raspiBackup in a simple, dialog-driven way.
   It can simply be started without any options. Then first a query appears whether a backup should be created or a restore should be performed. In case of a restore it is asked if the last backup should be restored. (y/N) At (N) a corresponding backup can be selected from a list. Then the target medium is selected and raspiBackup does the rest.

   Possible options --last , --select and --backup

        Option --last -> the last backup will be selected automatically and the target medium is requested without
                         further inquiry
        Option --select -> the desired backup can be selected from a list
        Option --backup -> some options are asked like more than two default partitions, comment in backup name....    
    - See [this flowchart](./images/raspiBackopRestoreHelper_simple_flow-chart.pdf) for details

   Upgrade 2022-07-22

    Because of the -M function, with which a comment can be appended to the name of the backup directory (but these backups are not included in the backup strategy), I added an option --delete, with which a version can be selected from a list and deleted.
    Before the final confirmation of the deletion process, the name of the directory to be deleted is displayed for checking purposes.
    After the deletion process, the contents of the backup directory are displayed again via ls-la for checking purposes.

    !! This dialogue can only be called up (as protection against accidental wrong entries) by using the --delete option.

    I have also made a few optical changes and removed the completely superfluous dash lines.

7. raspiBackupMsg2JSON.sh - Parses the raspiBackup message file and generates a JSON doc which represents the messages

8. raspiBackupAndClone.sh - Creates a backup and then restores the backup to a device

9. raspiBackupAndJSON.sh - Creates a backup and generates a JSON message file

