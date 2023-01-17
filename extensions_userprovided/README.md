This directory contains extensions provided by raspiBackup users. Feel free to create pull requests to add your code.

Any code is provided as is and there is no support given.

## raspiBackup_healthcheck

A pre script is used to signal to Healthcheck.io that raspiBackup is starting and a post script is sending a success or failure signal. Scripts are based upon other samples provided. They use a configuration file the user must provide (/usr/local/etc/healthcheck.conf) that will provide the Healthcheck.io url used for that check. This will allow script to be more flexible. Should raspiBackup be used with several configuration (some other backup solution often have different running profiles), scripts should be adapted to use something more flexible, such as an environment variable.
Maybe the code could already be adapted for this point...

Credits to [DesertRider](https://github.com/DesertRider/)

## raspiBackup_docker

A pre and post script that stops all running docker-container gracefully and starts them again after backup is finished.

Povided by [Springjunky](https://github.com/Springjunky)

## raspiBackupDiscordWrapper.sh

A wrapper script which should be an extension but because of some missing support for extensions in raspiBackup (will be available in nbext release) it's provided as a wrapper script.

raspiBackupDiscordWrapper supports to write raspiBackup success/failure notifications in Discord.
