# Start raspiBackup with Systemd

_Make sure that the commands are executed as root_

## Preparation

Copy `raspiBackup.service` and `raspiBackup.timer` to `/etc/systemd/systemd/system/`

Check the rights and adjust them if necessary

    chown root:root /etc/systemd/systemd/system/raspiBackup.service /etc/systemd/systemd/system/raspiBackup.timer
    chmod 644 /etc/systemd/systemd/system/raspiBackup.service /etc/systemd/systemd/system/raspiBackup.timer

## Customizing

If the installation path is different, it must be corrected in the `raspiBackup.service`.

The execution start is defined in raspiBackup.timer. Currently the backup is 
started every Sunday at 05.00 o'clock (as in the manual).
For further customization options see [here](https://www.freedesktop.org/software/systemd/man/systemd.timer.html#)

If you changes the files, execute: `systemctl daemon-reload`


## Enable

Check if raspiBackup is executed with the service unit

    systemctl start raspiBackup.service
    
if successful

    systemctl start raspiBackup.timer
    systemctl enable raspiBackup.timer
    
## Other

Delete /etc/cron.d/raspiBackup or remove any entry in /etc/crontab to start raspiBackup to disable any other 
automatic start of raspiBackup. Keep in mind you cannot change the backup time any more with the raspiBackup installer.