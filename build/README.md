# raspiBackup Debian package and apt repository

raspiBackup is distributed as Debian package `raspibackup` in a signed apt repository
hosted on GitHub Pages:

```
https://framps.github.io/raspiBackup        <- branch gh-pages, created by publishRepo.sh
```

Contents of this file:

1. [Publish a new release](#1-publish-a-new-release) (maintainer)
2. [Install and update](#2-install-and-update) (users)
3. [Revert to a previous release](#3-revert-to-a-previous-release) (users and maintainer)
4. [How the package is verified](#4-how-the-package-is-verified)
5. [Files in this directory](#5-files-in-this-directory)

---

## 1. Publish a new release

### One time preparation

```
# tools used by the build
sudo apt-get install git gnupg dpkg-dev apt-utils lintian gettext-base

# check the GPG key used for signing is available (secret key required)
gpg --list-secret-keys 23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24
```

`build.conf` isn't committed. `./build.sh` creates a template if it's missing.
Check these settings:

| Setting         | Meaning                                                              |
|-----------------|----------------------------------------------------------------------|
| `BRANCH_TO_DEB` | branch the package is built from, empty = current branch             |
| `GPG_KEYID`     | full fingerprint of the signing key                                  |
| `REPO_SUITE`    | `stable`, has to match `REPO_SUITE` in `raspiBackupInstall.sh`       |

GitHub Pages is already enabled (repository settings -> Pages -> Deploy from a branch ->
`gh-pages`, `/ (root)`). Nothing else has to be done on GitHub.

### Every release

```
# 1. Set a new, higher version in raspiBackup.sh, e.g. VERSION="0.7.5"
#    and commit and push it. Only committed changes are packaged!
git commit -am "Release 0.7.5"
git push

# 2. Build, sign and add the package to the local repository build/repo
cd build
./build.sh

# 3. Publish the repository on GitHub Pages (branch gh-pages)
./publishRepo.sh              # or first: ./publishRepo.sh --no-push to review the commit

# 4. Check after one or two minutes that the new version is online
curl -fsS https://framps.github.io/raspiBackup/dists/stable/main/binary-armhf/Packages | grep ^Version

# 5. Optional: tag the release
git tag v0.7.5 && git push origin v0.7.5
```

`gpg` asks for the passphrase of the signing key during steps 2 and 3.

Notes:

- **Always use a new, higher version number.** apt only installs a package with a higher
  version than the installed one. A rebuild with the same version won't reach users.
- Version numbers are compared by `dpkg --compare-versions`, see `compareVersions.sh`:
  `0.7.5~beta1 < 0.7.5~rc1 < 0.7.5 < 0.7.5-m1 < 0.7.6`.
  An underscore in `VERSION` (e.g. `0.7.4-m_972`) is converted to `-` (`0.7.4-m-972`).
- All published versions stay in the repository, so users can always go back.
  `publishRepo.sh` copies packages published earlier but missing locally back into `repo/`,
  so you can publish from any system.
- Neither `build/deb/` nor `build/repo/` are committed to `master`. The packages exist on
  `gh-pages` only.

Useful commands:

```
./build.sh --help                       # options: --no-check (no lintian), --no-repo
./buildRepo.sh                          # re-create and re-sign the repository index only
git fetch origin gh-pages && git ls-tree -r --name-only FETCH_HEAD pool   # published versions
```

---

## 2. Install and update

```
curl -fsSLO https://framps.github.io/raspiBackup/raspiBackupInstall.sh
bash raspiBackupInstall.sh
```

The script adds the repository and installs `raspibackup`. Then configure raspiBackup
(backup path, backup type, timer, extensions, ...) with

```
sudo raspiBackupInstallUI
```

`raspiBackupInstallUI` detects the package installation. It offers the configuration
and the sample extensions only. Installing, updating and uninstalling raspiBackup is done
with apt, the options `-i`, `-U` and `-u` aren't available.

Updates afterwards:

```
sudo apt-get update && sudo apt-get upgrade
```

Uninstall:

```
sudo apt-get remove raspibackup        # keeps the configuration
sudo apt-get purge raspibackup         # also deletes configuration
sudo rm /etc/apt/sources.list.d/raspibackup.sources /usr/share/keyrings/raspibackup-archive-keyring.gpg
```

### Files installed

| File | |
|------|-|
| `/usr/local/bin/raspiBackup`, `raspiBackup.sh` | raspiBackup, `raspiBackup.sh` is a link for former installations |
| `/usr/local/bin/raspiBackupInstallUI` | configuration |
| `/usr/local/etc/raspiBackup.conf` | configuration, created on first installation from a template |
| `/usr/local/share/raspibackup/` | configuration templates |
| `/usr/local/share/raspibackup/extensions/` | sample extensions and their README |
| `/usr/local/lib/systemd/system/raspiBackup.{service,timer}` | default systemd units |
| `/etc/systemd/system/raspiBackup.{service,timer}` | units configured by `raspiBackupInstallUI`, take precedence |

The configuration isn't managed by dpkg (no conffile). Installation, update and downgrade
never change it, so there are no questions about it during `apt-get upgrade`.
A configuration of a former installation with the curl script is used as it is.
Before every installation the configuration is saved as `raspiBackup.conf~`.
New configuration options are added with `sudo raspiBackup --updateConfig`.

---

## 3. Revert to a previous release

### Users

```
# 1. List the available versions
apt list -a raspibackup

# 2. Install the previous version, e.g. 0.7.4
sudo apt-get install --allow-downgrades raspibackup=0.7.4

# 3. Keep apt from upgrading again to the faulty version
sudo apt-mark hold raspibackup
```

As soon as a fixed version is available:

```
sudo apt-mark unhold raspibackup
sudo apt-get update && sudo apt-get upgrade
```

The configuration `/usr/local/etc/raspiBackup.conf` isn't changed by a downgrade.
Before every installation the previous configuration is saved as `raspiBackup.conf~` in
the same directory.

**Don't use `raspiBackup -U` or `raspiBackup -V` with the package.**
raspiBackup still contains its own update (`-U`) and revert (`-V`) code from the time it was
installed with the curl script:

- `-U` downloads `raspiBackup.sh` from the website and replaces the script without signature
  verification. That bypasses apt, and the next `apt-get upgrade` replaces it again.
- `-V` looks for saved copies `raspiBackup.<version>.sh` next to the script. The package
  installs `/usr/local/bin/raspiBackup` without `.sh` and doesn't create such copies,
  so there is nothing to revert to.

Use apt as described above instead. TODO: raspiBackup should detect a package installation
(`dpkg -S "$0"`) and point to apt for `-U` and `-V`.

### Maintainer

Users with the faulty version only get rid of it with a new, **higher** version:

- fix the bug and publish it as hotfix, e.g. `0.7.5-m1` (see section 1), or
- if the fix takes longer, build the code of the last good version with a higher version
  number, e.g. the code of `0.7.4` as `0.7.5-m1`, and publish it. Users get the good code
  back with their next `apt-get upgrade`.

Deleting the faulty package from the repository doesn't help: apt never downgrades
installed packages by itself. Also `publishRepo.sh` doesn't support removing packages yet,
it restores packages deleted only locally.

---

## 4. How the package is verified

```
fingerprint built into raspiBackupInstall.sh  (REPO_OWNER_GPG_FINGERPRINT)
  └─ accepts only that key from repo/raspibackup-archive-keyring.gpg
     -> /usr/share/keyrings/raspibackup-archive-keyring.gpg
     -> /etc/apt/sources.list.d/raspibackup.sources  (Signed-By: that keyring only)
        └─ apt verifies the signature of dists/stable/InRelease
           └─ SHA256 of Packages
              └─ SHA256 of raspibackup_<version>_all.deb
```

A modified package, index or key on GitHub is rejected by apt, on the first installation
and on every later `apt-get upgrade`. The only thing users have to trust is the fingerprint
in the installation script, so publish it on the website too:

```
23A2 E977 F377 FC31 CE44  DC9C 4B9E 02DB ACA4 DD24
```

`raspiBackupInstall.sh <file.deb>` installs a downloaded package without the repository.
It verifies `<file.deb>.sig` against the same built-in fingerprint.

---

## 5. Files in this directory

```
                                                                              set in       set in        in
                                                                              common.sh    build.conf    build.sh
├── build.conf          # configuration for package build (not committed)
├── build.log           # build log
├── build-debug.log     # build debug log
├── build.sh            # build script, calls buildRepo.sh at the end
├── buildRepo.sh        # adds packages to the signed apt repository in repo/
├── publishRepo.sh      # publishes repo/ and raspiBackupInstall.sh on GitHub Pages (branch gh-pages)
├── common.sh           # common definitions for build and install
├── compareVersions.sh  # to test version up- and downgrade recognition
│
├── deb                 # built deb packages (not committed)                  $DEB_TGT                           <--.
│   ├── raspibackup_<version>.deb                                                                                   |
│   ├── raspibackup_<version>.deb.sig                                                                               |
│   └── VERSION                                                                                                     |
│                                                                                                                   |
├── install.log         # installation log                                                                          |
├── install.sh          # install the locally built package (development)                                           |
│                                                                                                                   |
├── package                                                                   $PACKAGE                              |
│   │                                                                                                               |
│   ├── DEBIAN          # DEBIAN package source                                                             --.     |
│   │   ├── control     # package control file                                                                v     |
│   │   ├── copyright                                                                                         |     |
│   │   ├── postinst    # after installation: create config from template if missing                          |     |
│   │   ├── prerm       # before apt remove: disable backup timer                                             |     |
│   │   └── postrm      # after apt remove/purge: remove extension links, timers, on purge config            |     ^
│   │                                                                                                         |     |
│   └── src             # deb package build directory (not committed)         $TGT                         <--´   --´
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
├── repo                    # signed apt repository (not committed), published by publishRepo.sh  $REPO         |
│   ├── dists/stable/{InRelease,Release,Release.gpg,main/binary-*/Packages*}                                    |
│   ├── pool/main/r/raspibackup/raspibackup_<version>_all.deb                                                   |
│   └── raspibackup-archive-keyring.{gpg,asc}   # public signing key                                            |
├── downgrade.sh, upgrade.sh, uninstall.sh      # notes and helpers for development                             |
└── README.md               # the file you are reading just now                                               |
                                                                                                              ^
                                                                                                              |
/tmp/raspiBackup_gitsrc4deb.XXXXXX                                                                         $GITSRC
```
