#!/bin/bash
#
# rollback from 0.7.2.1 to 0.7.2
sudo apt-mark hold raspibackup

# download old package
#
apt download raspibackup=0.7.2

# old config usually kept
