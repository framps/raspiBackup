# NOTE

The deb package creation is still under development

Directories:

```
                                                                              set in       set in        in
                                                                              common.sh    build.conf    build.sh
├── build.conf          # configuration for package build
├── build.log           # build log
├── build-debug.log     # build debug log
├── build.sh            # build script, calls buildRepo.sh at the end
├── buildRepo.sh        # adds packages to the signed apt repository in repo/
├── publishRepo.sh      # publishes repo/ and raspiBackupInstall.sh on GitHub Pages (branch gh-pages)
├── common.sh           # common definitions for build and install
├── compareVersions.sh  # to test version up- and downgrade recognition
│
├── deb                 # built deb packages (not committed)                  $DEB_TGT                           <--.
│   │                                                                                                               |
│   ├── raspibackup_0.7.4-m-972.deb                                                                                 |
│   └── raspibackup_0.7.4-m-972.deb.sig                                                                             |
│                                                                                                                   |
├── gpg.conf            # gpg key id used to sign the packages                                                      |
├── install.log         # installation log                                                                          |
├── install.sh          # install packages                                                                          |
│                                                                                                                   |
├── package                                                                   $PACKAGE                              |
│   │                                                                                                               |
│   ├── DEBIAN          # DEBIAN package source                                                             --.     |
│   │   ├── conffiles   # definition of config files                                                          |     |
│   │   ├── control     # package control file                                                                v     |
│   │   ├── copyright                                                                                         |     |
│   │   ├── postinst    # script executed after package installation                                          |     |
│   │   └── postrm      # script executed after apt remove  (not existing yet)                                |     ^
│   │                                                                                                         |     |
│   └── src             # deb package build directory                         $TGT                         <--´   --´
│       ├── DEBIAN
│       │    └── ...
│       └── usr
│           └── local
│               ├── bin                                                                    $DIR_BIN        <--.
│               ├── etc                                                                    $DIR_ETC        <--|
│               ├── lib                                                                    $DIR_LIB        <--|
│               └── share                                                                  $DIR_SHARE      <--|
│                                                                                                             |
├── raspiBackupInstall.sh   # public installation script, adds the apt repository and installs from it        |
├── repo                    # signed apt repository, not committed, see publishRepo.sh   $REPO                  |
│   ├── dists/stable/{InRelease,Release,Release.gpg,main/binary-*/Packages*}                                    |
│   ├── pool/main/r/raspibackup/raspibackup_<version>_all.deb                                                   |
│   └── raspibackup-archive-keyring.{gpg,asc}   # public signing key                                            |
└── README.md               # the file you are reading just now                                               |
                                                                                                              ^
                                                                                                              |
/tmp/raspiBackup_gitsrc4deb.XXXXXX                                                                         $GITSRC
```

## Signed apt repository

`build.sh` adds every built package to the apt repository in `repo/` via `buildRepo.sh`
(`buildRepo.sh` without arguments just re-indexes and re-signs it). Older versions stay
in the pool, so a downgrade is possible with `apt-get install raspibackup=<version>`.
Release a new version with a new version number, otherwise installed systems won't update.

`publishRepo.sh` publishes `repo/` and `raspiBackupInstall.sh` on the branch `gh-pages`,
served by GitHub Pages as `https://framps.github.io/raspiBackup` (the default `REPO_URL`
in `raspiBackupInstall.sh`). Packages already published but missing in the local `repo/`
are copied back first, so no published version gets lost. `--no-push` only creates the commit.

GitHub Pages has to be enabled once:
Repository settings -> Pages -> Deploy from a branch -> `gh-pages`, `/ (root)`

Release workflow: `./build.sh` then `./publishRepo.sh`

### Chain of trust

```
fingerprint built into raspiBackupInstall.sh  (REPO_OWNER_GPG_FINGERPRINT)
  └─ accepts only that key from repo/raspibackup-archive-keyring.gpg
     -> /usr/share/keyrings/raspibackup-archive-keyring.gpg
     -> /etc/apt/sources.list.d/raspibackup.sources  (Signed-By: that keyring only)
        └─ apt verifies the signature of dists/stable/InRelease
           └─ SHA256 of Packages
              └─ SHA256 of raspibackup_<version>_all.deb
```

Hence a modified package, index or key on GitHub is rejected by apt, on the first
installation and on every later `apt-get upgrade`. The only thing users have to trust
is the fingerprint in the installation script, so publish it on the website too.

### Installation by the user

```
curl -fsSLO https://framps.github.io/raspiBackup/raspiBackupInstall.sh
bash raspiBackupInstall.sh
```

Updates: `sudo apt-get update && sudo apt-get upgrade`

`raspiBackupInstall.sh <file.deb>` installs a downloaded package without the repository.
It verifies `<file.deb>.sig` against the same built-in fingerprint.

