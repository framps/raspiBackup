#!/bin/bash
#
# upgrade replaces unmodified config
# a modified config  there will be a prompt
# whether to keep current config or to replace with new
#
# Possible to keep old and later on call raspiBackup with option --updateConfig which will add
# new config options if there are any new
#
# In order to revert and config should be backed up in preinst script (append version number
# raspiBackup.conf -> raspiBackup_0_7_2.sh or raspiBackup_0_7_2_1.sh
# If a revert is required the old files are still available.
