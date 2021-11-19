This directory contains extensions provided by raspiBackup users. Feel free to create pull requests to add your code.

## raspiBackup_healthcheck

A pre script is used to signal to Healthcheck.io that raspiBackup is starting and a post script is sending a success or failure signal. Scripts are based upon other samples provided. They use a configuration file the user must provide (/usr/local/etc/healthcheck.conf) that will provide the Healthcheck.io url used for that check. This will allow script to be more flexible. Should raspiBackup be used with several configuration (some other backup solution often have different running profiles), scripts should be adapted to use something more flexible, such as an environment variable.
Maybe the code could already be adapted for this point...

Credits to [DesertRider](https://github.com/DesertRider/)
