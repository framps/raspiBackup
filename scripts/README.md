## Collection of some useful tools for raspiBackup 

1. checkUUIDsInImage - Check whether UUIDs used in a dd backup match with the BLKIDs used in the image

2. inspectSystem - Collect various system information
 
3. raspiBackupOnlineVersions - List current versions and commit shas of raspiBackup files which are available online for download

4. supportsACLs - check if filesystem used by a directory supports ACLs

5. supportsFileAttributes - check if a filesystem used by a directory supports Linux fileattributes

6. raspiBackupFromGitInvocation.sh - Download and invoke raspiBackup from a git branch. This script helps to easily call a test, hotfix or fix release of raspiBackup directly from github. First option has to be the branch name and all following options can be the normal raspiBackup options.
