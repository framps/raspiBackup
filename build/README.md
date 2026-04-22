# NOTE

The deb package creation is still under development

Directories:

```
├── build.log			# build log
├── build.sh			# build script
├── common.sh			# common definitions for build and install
├── compareVersions.sh	# script used to test version up- and downgrade recognition
├── deb					# directory which receives the built deb packages
├── gitsrc				# clone of raspiBackup repository used to populate package directory
├── gpg.conf			# gpg key id used to sign the packages
├── install.log			# installation log
├── install.sh			# install packages
├── package
│   ├── DEBIAN			# DEBIAN package source
│   │   ├── conffiles	# definition of config files
│   │   ├── control		# package control file
│   │   ├── postinst	# script executed after package installation 
│   │   └── postrm		# script executed after apt remove
│   └── src				# deb package build directory
│       ├── DEBIAN
│       ├── etc
│       └── usr
├── raspiBackupInstall.sh	# draft public installation script, uses the deb and gpg key from github 
└── README.md

```
