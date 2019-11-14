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
Für weitere Anpassungsmöglichkeiten siehe [hier](https://www.freedesktop.org/software/systemd/man/systemd.timer.html#)

If you changes the files, execute: `systemctl daemon-reload`


## Enable

Check if raspiBackup manuell run with the Service Unit

    systemctl start raspiBackup.service
    
if successful

    systemctl start raspiBackup.timer
    systemctl enable raspiBackup.timer
    
## Other

Remember to disable any other automatic executions you may have set up (e.g. /etc/cron.d/raspiBackup).