# raspiBackup Debian package and apt repository

raspiBackup is distributed as Debian package `raspibackup` in a signed apt repository
hosted on GitHub Pages:

```
https://framps.github.io/raspiBackup        <- branch gh-pages, created by publishRepo.sh
```

Contents of this file:

1. [Publish a new release](#1-publish-a-new-release) (maintainer)
2. [Install and update](#2-install-and-update) (users)
3. [Beta versions](#3-beta-versions) (maintainer and users)
4. [Revert to a previous release](#4-revert-to-a-previous-release) (users and maintainer)
5. [How the package is verified](#5-how-the-package-is-verified)
6. [Test the package](#6-test-the-package) (maintainer)
7. [Files in this directory](#7-files-in-this-directory)

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
| `REPO_BETA_SUITE` | `beta`, has to match `REPO_BETA_SUITE` in `raspiBackupInstall.sh`  |
| `VERSION_RASPIBACKUP` | version inserted into `raspiBackup` and used for the package, empty = `VERSION` of `raspiBackup.sh` |
| `VERSION_RASPIBACKUPCONFIG` | version inserted into `raspiBackupConfig`, empty = `VERSION` of `raspiBackupConfig.sh` |
| `DEB_REVISION` | Debian revision appended to the package version for a minor fix, e.g. `1` -> `0.7.5-1`, empty = none |

GitHub Pages is already enabled (repository settings -> Pages -> Deploy from a branch ->
`gh-pages`, `/ (root)`). Nothing else has to be done on GitHub.

### Every release

```
# 1. Set a new, higher version in raspiBackup.sh, e.g. VERSION="0.7.5"
#    (or VERSION_RASPIBACKUP="0.7.5" in build.conf)
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
- `VERSION_RASPIBACKUP` and `VERSION_RASPIBACKUPCONFIG` in `build.conf` override `VERSION` of
  `raspiBackup.sh` and `raspiBackupConfig.sh`. They are inserted into the packaged scripts,
  the committed sources stay unchanged.
- raspiBackup detects new releases, hotfixes and betas in the repository itself (once a day
  `apt-get update` of the raspiBackup repository only) and reports them after the backup.
  Users of a release get new releases and betas reported, no alphas and release candidates.
  Users of a pre-release get a new release reported first. If there is none, newer betas and
  release candidates, users of an alpha also newer alphas. A pre-release is only reported if it's
  the newest one. The update menu of `raspiBackupConfig` (and `-b`) offers all of them.
  `raspiBackup.properties` isn't needed for that. Its `DEPRECATED` (versions separated by blanks or
  commas, e.g. `DEPRECATED="0.7.5 0.7.6-beta1"`) is still used: these versions are never reported
  as update or beta, and users running one of them get a warning. A version includes all versions
  derived from it: `0.7.5` deprecates `0.7.5~1`, `0.7.5-rc1`, `0.7.5-beta1`, `0.7.5-1`, `0.7.5-m1`,
  `0.7.5-m1~u972.1`, ..., but not `0.7.50`. If `apt upgrade` would install a
  deprecated version, raspiBackup tells the user the `apt-get install raspibackup=<version>` command
  for the newest version which isn't deprecated.
- All published versions stay in the repository (unless removed with `--remove`, see section 4),
  so users can always go back.
  `publishRepo.sh` copies packages published earlier but missing locally back into `repo/`,
  so you can publish from any system.
- Neither `build/deb/` nor `build/repo/` are committed to `master`. The packages exist on
  `gh-pages` only.

### Installations without apt

Installations with `raspiBackupInstallUI.sh` or `install.sh` don't know the apt repository. They
read `published/` on `master`: `raspiBackup.properties` for new versions, `raspiBackup.sh` for
`raspiBackup.sh -U` and `raspiBackupInstallUI.sh` for the update of the installer. To bring them
to the package (see [Migrate an installation without apt](#migrate-an-installation-without-apt)),
publish the current code there once after the first package release, and with every release
which should be announced to them:

```
# 1. Use versions higher than those of the installations without apt (0.7.4 and installer 0.5):
#    VERSION in raspiBackup.sh and raspiBackupConfig.sh, VERSION and VERSION_INSTALLER
#    in properties/raspiBackup.properties. Commit and push them.

# 2. Publish raspiBackup.sh, raspiBackupConfig.sh (also as raspiBackupInstallUI.sh),
#    the config templates and raspiBackup.properties into published/ and commit them on master
./publish.sh master
```

Then

- `raspiBackup.sh` reports the new version and `raspiBackup.sh -U` installs the current
  `raspiBackup.sh`. Without the package it reports after every backup how to migrate (RBK0367W)
  and `-U` shows the same instead of updating.
- `raspiBackupInstallUI.sh` offers the update of the installer. The updated installer is
  `raspiBackupConfig` and offers the migration at its start and in the update menu.
- `install.sh` starts `raspiBackupConfig`, which offers the migration as well.

### Beta versions

Betas are built and published like a release but with a version like `0.7.5-beta1`,
see [section 3](#3-beta-versions).

### Version numbers

| Purpose                           | `VERSION`         | Debian version     | Where                                   |
|-----------------------------------|-------------------|--------------------|-----------------------------------------|
| beta, release candidate           | `0.7.6-beta1`     | `0.7.6~beta1`      | suite `beta`, installed only on request |
| release                           | `0.7.5`           | `0.7.5`            | suite `stable`                          |
| minor fix, not reported          | `0.7.5`           | `0.7.5-1`          | suite `stable`, `DEB_REVISION="1"`      |
| hotfix for all users              | `0.7.5-m1`        | `0.7.5-m1`         | suite `stable`                          |
| temporary fix for one user only   | -                 | `0.7.5-m1~u972.1`  | not in the repository, see below        |

They sort in this order, so every version is replaced by the next public one:

```
0.7.5 < 0.7.5-1 < 0.7.5-2 < 0.7.5-m1~u972.1 < 0.7.5-m1~u972.2 < 0.7.5-m1 < 0.7.6~beta1 < 0.7.6
```

- A minor fix (small code fix, packaging, maintainer scripts, ...) keeps `VERSION` of raspiBackup
  and sets `DEB_REVISION` in `build.conf`: `"1"` for the first rebuild, `"2"` for the next one,
  and so on. Empty it again for the next release. New installations get the fix, existing
  installations get it with `apt upgrade`, but raspiBackup doesn't tell users of the same version
  about it (`0.7.5` -> `0.7.5-1`). Users of an older version are told about the latest one
  (`0.7.4` -> `0.7.5-1`). To have a minor fix reported to users of an earlier minor fix, add that
  one to `DEPRECATED` in `raspiBackup.properties`: `0.7.5-1` reports `0.7.5-2` to users of `0.7.5-1`.
  Users of `0.7.5` can't be told about a minor fix, because `DEPRECATED="0.7.5"` deprecates the
  minor fixes as well. Publish a hotfix (`0.7.5-m1`) instead.

- Use `~` only for versions which have to sort **before** the version in front of it:
  pre-releases (`~alpha`, `~beta`, `~rc`) and fixes for one user.
  A `~` sorts before everything, even before the end of the version.
- Behind the `~` the text is compared alphabetically. That's why `alpha < beta < rc` works,
  but `0.7.6~m972` would sort between `0.7.6~beta1` and `0.7.6~rc1`. Use only `alpha`, `beta`
  and `rc` for pre-releases.
- `buildRepo.sh` puts every version containing `~` into the suite `beta`.
- Never use `~` for a fix of a published release: `0.7.5~1` sorts before `0.7.5`, so users of
  `0.7.5` never get it (only as a downgrade), and it lands in suite `beta`. A fix of `0.7.5` is
  `0.7.5-1` (not reported) or `0.7.5-m1` (reported).
- Rule of thumb: should the version replace something already published? Then no `~`.
  Should it be replaced by something not published yet? Then `~`.

| You want                              | Version            | Reported to users of `0.7.5` | Installed by                                      |
|---------------------------------------|--------------------|------------------------------|---------------------------------------------------|
| fix of `0.7.5`, silent                | `0.7.5-1`          | no                           | `apt upgrade`, `raspiBackupConfig -U`, new installation |
| fix of `0.7.5` for everybody, announced | `0.7.5-m1`       | yes                          | `apt upgrade`, `raspiBackupConfig -U`, new installation |
| next release                          | `0.7.6`            | yes                          | `apt upgrade`, `raspiBackupConfig -U`, new installation |
| test version before `0.7.6`           | `0.7.6~beta1`      | as beta available            | `raspiBackupConfig -b`, `apt-get install -t beta`, `raspiBackupInstall.sh --beta` |
| fix for one user                      | `0.7.5-m1~u972.1`  | no                           | the user installs the `.deb` file                 |

### Fix for one user only

Every package in the repository reaches all users of its suite. So a fix for one user isn't
added to the repository. The user gets the `.deb` file instead.

Name it as pre-release of the next public hotfix plus `u<issue>.<n>`, e.g. `0.7.5-m1~u972.1`
if `0.7.5` is the current release. Then it

- upgrades the installed release `0.7.5`,
- is replaced by `0.7.5-m1~u972.2` if the first fix wasn't sufficient,
- is replaced automatically by the next public hotfix `0.7.5-m1` or release `0.7.6` on the
  next `apt-get upgrade`, because the user's system still uses the repository.

Don't use `0.7.5+u972`: it sorts after the hotfix `0.7.5-m1`, so the user would never get it.

```
# Build without adding it to build/repo. The argument is the Debian version.
cd build
./build.sh --no-repo 0.7.5-m1~u972.1
# -> deb/raspibackup_0.7.5-m1~u972.1.deb and .sig, send both to the user

# The user installs it with
sudo apt install ./raspibackup_0.7.5-m1~u972.1.deb

# and returns to the release before the next version is published with
sudo apt install raspibackup=0.7.5
```

The argument of `build.sh` sets only the version of the package. To show it in the
messages of raspiBackup too, set `VERSION_RASPIBACKUP="0.7.5-m1~u972.1"` in `build.conf`
for this build and remove it afterwards.

Useful commands:

```
./build.sh --help                       # options: --no-check (no lintian), --no-repo
./buildRepo.sh                          # re-create and re-sign the repository index only
git fetch origin gh-pages && git ls-tree -r --name-only FETCH_HEAD pool   # published versions
```

---

## 2. Install and update

```
curl -fsSL https://framps.github.io/raspiBackup/raspiBackupInstall.sh | bash
```

The script adds the repository and installs `raspibackup`. It isn't stored and isn't part of the package,
its log is written to `/tmp/raspiBackupInstall.XXXXXX.log`. Options are passed with `bash -s -- <options>`. Then configure raspiBackup
(backup path, backup type, timer, ...) with

```
sudo raspiBackupConfig
```

`raspiBackupConfig` detects the package installation. It offers the configuration.
Users not familiar with apt can update and uninstall raspiBackup
with `sudo raspiBackupConfig -U` and `sudo raspiBackupConfig -u` (asks before, `-y` answers yes). `-i` isn't available,
the package is already installed. Every action of `raspiBackupConfig` and the apt commands
with the same result are listed in
[What raspiBackupConfig does, and the same with apt](#what-raspibackupconfig-does-and-the-same-with-apt).

The menu `M3 Update components` of `raspiBackupConfig` runs `apt-get update` and offers
the apt commands described below:

| Option | apt command | Available if |
|--------|-------------|--------------|
| `P1` Update current release | `apt-get install raspibackup=<candidate>` | apt's candidate is newer: the latest release, or for an installed beta the latest beta or the release which follows it |
| `P2` Revert to previous release | `apt-get install --allow-downgrades raspibackup=<previous>` and `apt-mark hold` | a release is installed and an older one exists |
| `P3` Install or update beta | `apt-get install raspibackup=<latest beta>` | a newer beta exists |
| `P4` Revert from beta to current release | `apt-get install --allow-downgrades raspibackup=<latest stable>` | a beta is installed |

Every option removes a hold first. Afterwards `raspiBackupConfig` restarts with the installed version.

Without the menu:

- `sudo raspiBackupConfig -U` updates the installed release, or an installed beta to the latest
  beta or the release which follows it, like `P1`.
- `sudo raspiBackupConfig -R` reverts to the previous release and holds it, like `P2`.
- `sudo raspiBackupConfig -b` installs or updates the latest beta, like `P3`.
- `sudo raspiBackupConfig -S` reverts a beta to the current release, like `P4`.

If the installed version is held, the options and the menu ask the same question before they
change it. Without a terminal (e.g. cron) the options answer no. If the menu shows an item as
not available, the option ends with an error (`-U` reports that the latest version is installed).

The menu and the options update the package index with `apt-get update` at most once a day,
or when the apt repository was changed. Add `-f` to update it anyway, e.g. right after a new
version was published: `sudo raspiBackupConfig -f -U`.

Updates afterwards:

```
sudo apt-get update && sudo apt-get upgrade
```

To test beta versions see [section 3](#3-beta-versions).

### Migrate an installation without apt

raspiBackup installed with `raspiBackupInstallUI.sh` or `install.sh` doesn't get updates any more.
Any of these commands replaces it by the package:

```
curl -fsSL https://framps.github.io/raspiBackup/raspiBackupInstall.sh | bash   # reports the installation found and migrates it

sudo raspiBackupInstallUI.sh                # update the installer in the update menu, then accept the migration
sudo raspiBackupInstallUI.sh -U             # updates the installer, call it a second time to migrate
```

The migration adds the repository and installs the package. dpkg replaces `raspiBackup.sh` and
`raspiBackupInstallUI.sh` in `/usr/local/bin` by links to `raspiBackup` and `raspiBackupConfig`
because they aren't owned by any package. Kept are

- the configuration `/usr/local/etc/raspiBackup.conf`, new options are added (saved as `raspiBackup.conf~` before)
- the extensions `/usr/local/bin/raspiBackup_*.sh`
- the systemd units in `/etc/systemd/system` or `/etc/cron.d/raspiBackup`, they still call
  `/usr/local/bin/raspiBackup.sh`
- the versions saved by former updates, `/usr/local/bin/raspiBackup.<version>.sh`.
  They aren't needed any more and can be deleted.

#### Revert the migration

Before dpkg unpacks the package, `preinst` saves the former installation in
`/var/backups/raspiBackup-legacy/files` (`raspiBackup.sh`, `raspiBackupInstallUI.sh`, extensions,
configuration, systemd units or cron file, whether the timer was enabled) together with
`revertMigration.sh`. The directory isn't deleted by `apt-get purge`. A later migration replaces it.

```
sudo /var/backups/raspiBackup-legacy/revertMigration.sh        # asks before it starts, -y doesn't ask
```

It needs neither the package nor network access and

1. removes the package with `apt-get remove` (not purge) and its apt repository
2. restores `raspiBackup.sh`, `raspiBackupInstallUI.sh` and their links `raspiBackup` and `raspiBackupInstallUI`
3. restores the extensions and the configuration; the configuration of the package is kept as `raspiBackup.conf.package`
4. restores the systemd units or the cron file and enables the timer again if it was enabled

raspiBackup then runs as before the migration. It still reports the migration after the backup,
because `published/` announces the package.

Uninstall:

```
sudo apt-get remove raspibackup        # keeps the configuration, deletes the timer
sudo apt-get purge raspibackup         # also deletes configuration and its saved copies, state and logs
sudo rm /etc/apt/sources.list.d/raspibackup.sources /usr/share/keyrings/raspibackup-archive-keyring.gpg
```

`sudo raspiBackupConfig -u` deletes more files, see
[Uninstall](#uninstall-raspibackupconfig--u-or-menu-uninstall) below.

### Files installed

| File | |
|------|-|
| `/usr/local/bin/raspiBackup`, `raspiBackup.sh` | raspiBackup, `raspiBackup.sh` is a link for former installations |
| `/usr/local/bin/raspiBackupConfig` | configuration |
| `/usr/local/bin/raspiBackupInstallUI`, `raspiBackupInstallUI.sh` | links to `raspiBackupConfig`, the former installer |
| `/usr/local/etc/raspiBackup.conf` | configuration, created on first installation from a template |
| `/usr/local/share/raspibackup/` | configuration templates |
| `/usr/local/share/raspibackup/extensions/` | sample extensions and their README |
| `/usr/local/lib/systemd/system/raspiBackup.{service,timer}` | default systemd units |
| `/etc/systemd/system/raspiBackup.{service,timer}` | units configured by `raspiBackupConfig`, take precedence |

The configuration isn't managed by dpkg (no conffile), so dpkg never replaces it and there are
no questions about it during `apt-get upgrade`. A configuration of a former installation with the
curl script is used as it is. Before every installation the configuration is saved as `raspiBackup.conf~`.

After every installation, update or version change, also a plain `apt-get upgrade`, `postinst`
calls `raspiBackupConfig -m`. It adds new options of the template
`/usr/local/share/raspibackup/raspiBackup_{en,de}.conf` to the configuration and comments out options
which no longer exist, but only if the template has a newer config version than the configuration.
Existing values aren't changed. The configuration before the merge is saved as
`raspiBackup.conf.v<config version>`, `apt-get purge` deletes these copies like the configuration
because they may contain passwords. A downgrade doesn't change it. If the merge fails, the package
is installed anyway and `raspiBackupConfig` offers the merge when it's started.

### What raspiBackupConfig does, and the same with apt

`raspiBackupConfig` only runs apt and a few file operations. Everything can be done manually
with the same result. Commands need root, e.g. `sudo -i`.

#### Add the repository (`-i`, menu install, migration)

Same as `raspiBackupInstall.sh`. `raspiBackupConfig` accepts the key only if it has the fingerprint
`23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24`, is valid, and keeps only this key in the keyring.

```
curl -fsSL -o /tmp/raspibackup-archive-keyring.gpg https://framps.github.io/raspiBackup/raspibackup-archive-keyring.gpg
gpg --show-keys /tmp/raspibackup-archive-keyring.gpg        # check: 23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24
install -m 644 /tmp/raspibackup-archive-keyring.gpg /usr/share/keyrings/raspibackup-archive-keyring.gpg
cat > /etc/apt/sources.list.d/raspibackup.sources <<EOF
Types: deb
URIs: https://framps.github.io/raspiBackup
Suites: stable beta
Components: main
Signed-By: /usr/share/keyrings/raspibackup-archive-keyring.gpg
EOF
```

An existing repository isn't changed. Only if `Suites:` misses `beta`, `raspiBackupConfig` adds it
before every `apt-get update` (installations made before the beta suite existed).

#### Install (`-i`, menu install)

```
apt-get update
apt-get install raspibackup
```

`postinst` creates `/usr/local/etc/raspiBackup.conf` from the German template if `LANG` starts with `de`,
otherwise from the English one. `raspiBackupConfig` uses the language selected in its menu instead.
To change the language of a new configuration manually:

```
install -m 600 /usr/local/share/raspibackup/raspiBackup_de.conf /usr/local/etc/raspiBackup.conf   # replaces the configuration!
```

`raspiBackupConfig` also writes the selected settings into the configuration and creates a disabled timer:
`/etc/systemd/system/raspiBackup.{service,timer}`, or `/etc/cron.d/raspiBackup` without systemd.
Without `raspiBackupConfig` the default units of the package (Sundays at 05:00) are used:

```
systemctl enable --now raspiBackup.timer
systemctl edit raspiBackup.timer          # other time: [Timer] OnCalendar= and OnCalendar=<new time>
```

#### Migrate an installation without apt (`-i`, `-U`, menu install)

Add the repository and install the package, see above. `postinst` merges the new options into
the existing configuration. Configuration, extensions and timers are kept, see
[Migrate an installation without apt](#migrate-an-installation-without-apt).

#### Update (`-U`, menu `P1`)

```
apt-mark unhold raspibackup               # only if held, raspiBackupConfig asks before
apt-get update
apt-get install --only-upgrade raspibackup   # or: apt-get upgrade
```

The menu `P1` installs `raspibackup=<candidate>` instead, which is the same version.
`postinst` merges the configuration. `raspiBackupConfig` runs `apt-get update` at most once a day
(time in `/var/lib/raspiBackup/packageIndexUpdated`), `-f` forces it.

#### Other versions (`-R`, `-b`, `-S`, menu `P2`-`P4`)

See the table above and [section 3](#3-beta-versions) and [section 4](#4-revert-to-a-previous-release).
Every option removes a hold first (`apt-mark unhold raspibackup`), `-R` and `P2` set it again
(`apt-mark hold raspibackup`).

#### Sample extensions

`raspiBackupConfig` doesn't install them. Link the ones needed and enable them in the configuration:

```
ln -s /usr/local/share/raspibackup/extensions/raspiBackup_{mem,temp,disk}_{pre,post}.sh /usr/local/bin/
# /usr/local/etc/raspiBackup.conf: DEFAULT_EXTENSIONS="mem temp disk"
```

`apt-get remove` and `purge` delete these links.

#### Uninstall (`raspiBackupConfig -u` or menu uninstall)

`apt-get purge` deletes the package, the timers in `/etc/systemd/system` and `/etc/cron.d`, the links
to the sample extensions, `/usr/local/etc/raspiBackup.conf`, `raspiBackup.conf~` and `raspiBackup.conf.v*`,
`/var/lib/raspiBackup` and `/var/log/raspiBackup`. `raspiBackupConfig -u` and the menu uninstall
additionally delete the files below. Before they start, they list the ones which exist, except the
configuration, and ask. Without a terminal `-u` answers no and deletes nothing, `-y` answers yes,
e.g. in scripts:

```
apt-get purge raspibackup
rm -f /etc/apt/sources.list.d/raspibackup.sources /usr/share/keyrings/raspibackup-archive-keyring.gpg
# in addition by raspiBackupConfig -u:
rm -f /usr/local/bin/raspiBackup_*.sh     # all extensions, also your own ones!
rm -f /usr/local/etc/raspiBackup*         # e.g. raspiBackup.conf.package, .iservices, .eservices
rm -f /usr/local/bin/raspiBackup*.*       # versions saved by former updates, e.g. raspiBackup.0.7.3.sh
rm -f /tmp/raspiBackup*
```

Neither deletes `/var/backups/raspiBackup-legacy`, the backup of a migrated installation.

---

## 3. Beta versions

### How it works

The repository has two suites. Both share the packages in `pool/`:

| Suite    | Contains                                    | Installed by apt                          |
|----------|---------------------------------------------|-------------------------------------------|
| `stable` | releases and hotfixes, e.g. `0.7.4`, `0.7.4-m972` | always, the default                 |
| `beta`   | all versions containing `~`, e.g. `0.7.5~beta1`, `0.7.5~rc1` | only on request          |

`buildRepo.sh` sorts the packages into the suites by their version. The `Release` file of
`beta` is marked `NotAutomatic: yes` and `ButAutomaticUpgrades: yes`. So apt

- never installs a beta by itself, not even with `apt-get upgrade`,
- installs a beta only with `apt-get install -t beta raspibackup`,
- keeps an installed beta updated to newer betas and finally to the release.

`build.sh` converts the suffixes `-alpha`, `-beta` and `-rc` of `VERSION` in `raspiBackup.sh`
to `~alpha`, `~beta` and `~rc`, e.g. `0.7.5-beta1` to `0.7.5~beta1`. A `~` sorts before
everything, even before the end of the version:

```
0.7.4 < 0.7.4-m972 < 0.7.5~beta1 < 0.7.5~beta2 < 0.7.5~rc1 < 0.7.5 < 0.7.5-m1
```

Without `~` a beta `0.7.5-beta1` would be newer than the release `0.7.5` and the release
would never be installed on systems running the beta.

### Publish a beta (maintainer)

```
# 1. Set the beta version in raspiBackup.sh and commit it. Only committed changes are packaged!
#    VERSION="0.7.5-beta1"
git commit -am "Beta 0.7.5-beta1"
git push

# 2. Build, sign and add the package to the local repository. It goes into the suite beta.
cd build
./build.sh

# 3. Publish the repository on GitHub Pages
./publishRepo.sh

# 4. Check after one or two minutes that the beta is online
curl -fsS https://framps.github.io/raspiBackup/dists/beta/main/binary-armhf/Packages | grep ^Version
```

Next steps:

| Step                         | `VERSION` in raspiBackup.sh | Result for beta testers on their next `apt-get upgrade` |
|------------------------------|-----------------------------|---------------------------------------------------------|
| fix bugs in the beta         | `0.7.5-beta2`, `0.7.5-beta3`, ... | get the new beta                                  |
| release candidate (optional) | `0.7.5-rc1`                 | get the release candidate                               |
| final release, see section 1 | `0.7.5`                     | get the release and are back on `stable`                |

Notes:

- **Every beta build needs a new, higher version** (`beta1`, `beta2`, ...). A rebuild with
  the same version won't reach beta testers.
- Nothing has to be removed from `beta` after the release. Old betas stay in the repository
  but are never installed again, because the release is newer.
- To give up a beta, publish the release or a new beta which contains the good code.
  Beta testers can also revert themselves, see below.

### Install a beta (users)

New installation:

```
curl -fsSL https://framps.github.io/raspiBackup/raspiBackupInstall.sh | bash -s -- --beta
```

Existing installation:

```
sudo apt-get update
sudo apt-get install -t beta raspibackup
```

If there is no beta in the repository, apt installs the current release instead.

Installations made before the beta suite existed have only `Suites: stable` in
`/etc/apt/sources.list.d/raspibackup.sources`. Change it to `Suites: stable beta`
or run `raspiBackupInstall.sh` again. Otherwise apt doesn't know any beta.

Check which version is installed and which ones are available:

```
apt-cache policy raspibackup
```

### Upgrade a beta (users)

```
sudo apt-get update && sudo apt-get upgrade
```

A beta tester gets every new beta and finally the release, e.g.
`0.7.5~beta1 -> 0.7.5~beta2 -> 0.7.5`. After the release apt stays on `stable` again.
To test the next beta install it again with `apt-get install -t beta raspibackup`.

### Revert a beta to the current release (users)

```
sudo apt-get update
sudo apt-get install raspibackup/stable
```

apt asks to confirm the downgrade. Afterwards `apt-get upgrade` doesn't install betas any
more until a beta is installed again with `-t beta`.

The configuration `/usr/local/etc/raspiBackup.conf` isn't reverted. If the beta updated
it (`raspiBackupConfig` merges new options), the newer configuration is used by the release:
new options are ignored and deleted options get their built-in default. Only a changed
value of an option deleted by the beta is lost, the release uses its default then.
The configuration before the last installation is saved as `raspiBackup.conf~`.

---

## 4. Revert to a previous release

### Available versions

Every published version stays in the repository until it is removed with
`./publishRepo.sh --remove <version>`, so any older release can be installed again.
Stable versions are listed in the suite `stable`, beta versions in the suite `beta`.

```
# on a system with the repository (after sudo apt-get update)
apt list -a raspibackup                 # all versions, the installed one is marked
apt-cache madison raspibackup           # one line per version and suite

# without apt, directly from the published indices
curl -s https://framps.github.io/raspiBackup/dists/stable/main/binary-amd64/Packages | grep ^Version
curl -s https://framps.github.io/raspiBackup/dists/beta/main/binary-amd64/Packages   | grep ^Version

# maintainer: versions published on gh-pages with their suite and the ones in repo/ not yet published
./publishRepo.sh --list
git log --format='%cd %b' FETCH_HEAD    # afterwards: "Versions:" and "Removed:" of each publish
```

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

raspiBackup doesn't update itself or its configuration any more. The options `-U`, `-S`, `-V`
and `--updateConfig` only print a message pointing to `raspiBackupConfig`, which updates, downgrades
and reverts the package with apt and merges the configuration.

### Maintainer

Users with the faulty version only get rid of it with a new, **higher** version:

- fix the bug and publish it as hotfix, e.g. `0.7.5-m1` (see section 1), or
- if the fix takes longer, build the code of the last good version with a higher version
  number, e.g. the code of `0.7.4` as `0.7.5-m1`, and publish it. Users get the good code
  back with their next `apt-get upgrade`.

Deleting the faulty package from the repository doesn't help those users: apt never downgrades
installed packages by itself. It only stops new installations and upgrades to that version:

```
./publishRepo.sh --remove 0.7.5             # or --remove 0.7.5-beta1, can be repeated
```

The packages are removed and the indices re-signed in the same commit on `gh-pages`, so the
published index never lists a missing package. Deleting a package only in `build/repo/` doesn't
work, `publishRepo.sh` restores it from `gh-pages`.

---

## 5. How the package is verified

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

### Verify it yourself (experienced users)

All checks compare against the fingerprint `23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24`.
Take it from at least two places, e.g. this page and the website, and don't continue if they differ.
Don't trust the green *Verified* badge on GitHub: it is shown for any key added to the
GitHub account and for commits made in the web interface (signed by GitHub's key).

1. Get the key by its fingerprint from keys.openpgp.org, independent of GitHub:

   ```
   gpg --keyserver hkps://keys.openpgp.org --recv-keys 23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24
   ```

2. Verify the installation script. It's published with a signed commit on the branch `gh-pages`.
   The commit has to be signed (`G` or `U`) with the fingerprint above and the downloaded
   script has to be identical to the one in the commit:

   ```
   git clone -q --depth 1 --branch gh-pages https://github.com/framps/raspiBackup.git rbk-pages
   git -C rbk-pages log -1 --format='%G? %GF'
   # U 23A2E977F377FC31CE44DC9C4B9E02DBACA4DD24
   curl -fsSLO https://framps.github.io/raspiBackup/raspiBackupInstall.sh
   cmp raspiBackupInstall.sh rbk-pages/raspiBackupInstall.sh && echo identical
   ```

   `U` means good signature from a key you haven't certified yourself, that's fine.
   `N` (no signature) or `B` (bad signature) or any other fingerprint: don't run the script.

3. Verify the repository index. apt does this on every `apt update`, manually:

   ```
   curl -fsSLO https://framps.github.io/raspiBackup/dists/stable/InRelease
   gpg --verify InRelease
   # Good signature from "framps ..."  Primary key fingerprint: 23A2 E977 F377 FC31 ...
   ```

4. Verify the package. Its SHA256 has to be listed in `Packages`, whose SHA256 is listed in
   the signed `InRelease`:

   ```
   arch=$(dpkg --print-architecture)
   curl -fsSLO https://framps.github.io/raspiBackup/dists/stable/main/binary-$arch/Packages
   sed -n '/^SHA256:/,/^[A-Z]/p' InRelease | grep "main/binary-$arch/Packages$"
   sha256sum Packages                     # has to be the same SHA256 as the line above

   apt-get download raspibackup
   deb=$(ls raspibackup_*.deb)
   awk -v RS= -v f="/$deb" 'index($0, f "\n")' Packages | grep '^SHA256:'
   sha256sum "$deb"                       # has to be the same SHA256 as the line above
   ```

   `apt-get download` needs the repository added already. Without it download the `.deb`
   listed under `Filename:` in `Packages` from `https://framps.github.io/raspiBackup/`.
   For a beta use `beta` instead of `stable`.

---

## 6. Test the package

`build/test/testPackageUpdates.sh` checks the whole life cycle of the package with real apt:
it builds test versions, publishes them in a local signed repository (`file://`, temporary GPG
key) and installs, updates, reverts and uninstalls them with apt, `raspiBackupInstall.sh` and
`raspiBackupConfig`. What each section checks is listed by `./testPackageUpdates.sh -h`.

### Requirements

- **A test system only**, e.g. a spare Raspberry or a VM. The test installs, downgrades and purges
  the package `raspibackup` and its dependencies. It refuses to start if `raspibackup` or its
  repository is installed (`--force` removes them first) or if an installation without apt exists.
- root (`sudo`), git, gnupg, apt-utils, gettext-base, bsdutils and curl (lintian for `-l`).
  The system repositories have to be reachable for the dependencies.
- **Don't use apt in parallel.** apt allows only one run at a time. If something is installed or
  updated during the test (also by `unattended-upgrades`), the next apt command of the test fails
  and the check looks like an error of `raspiBackupConfig` (e.g. `RBI0004E`).
- Only committed changes are tested, the test fetches the commit to test from the local git
  repository. Push them and pull them on the test system first.
- It takes about 30 minutes on a CM4. The work directory needs only a few MB in `/var/tmp`
  (`-w` selects another directory, `/tmp` is a small tmpfs on Debian 13).

### Run it

```
cd ~/github.com/framps/raspiBackup
git pull
cd build/test
sudo ./testPackageUpdates.sh                 # -k keeps package, repository and work directory, -x stops at the first failure
```

The test doesn't need a terminal. To run it without keeping a terminal or SSH session open,
start it in the background and follow its output, e.g. from another login:

```
sudo sh -c 'nohup ./testPackageUpdates.sh > /var/tmp/packageTest.out 2>&1 < /dev/null &'
tail -f /var/tmp/packageTest.out                       # Ctrl-C ends tail only, not the test
grep '^=== \[' /var/tmp/packageTest.out | tail -1      # current section, e.g. [5/11]
grep FAIL /var/tmp/packageTest.out                     # failures so far
pgrep -af testPackageUpdates.sh                        # still running?
```

Interrupting the test (Ctrl-C, a closed SSH session) leaves an incomplete run. Start it in the
background as above if the session might be closed. Check afterwards with `dpkg -l raspibackup` and
`ls /etc/apt/sources.list.d/raspibackup.sources` whether package and repository are left, the
next run refuses to start otherwise (`--force` removes them).

### Output, report and log

- `=== [n/11] ...` starts a section and tells what it checks.
- `--- ...` is an action of the maintainer or a user.
- `$ ...` below it are the exact commands executed. They can be copied and repeated manually.
- `ok ...` and `FAIL ...` are the checks. `refused as expected` means the action had to be rejected.

At the end a summary report is displayed: result, passed and failed checks per section, packages
built, the order of the installed versions and the failures. Afterwards the system is cleaned up:
the package is purged and the test repository removed. Kept are

| File | Contents |
|------|----------|
| `/var/tmp/raspiBackupPkgTest.XXXXXX.report` | summary report |
| `/var/tmp/raspiBackupPkgTest.XXXXXX.log` | complete log: every command with its output and exit code (`rc=`), every check |
| `/var/tmp/raspiBackupPkgTest.XXXXXX/` | work directory with `test.log`, packages and repository, only with `-k` or after a failure |

If a check failed, the work directory, the package and the repository are kept to analyse the
failure. The end of the report tells how to remove them. In the log the output of the command
which failed is right above the `FAIL` line, `grep -B1 '^rc=[1-9]' <log>` lists all failed commands.
`/var/tmp` isn't cleared on reboot, delete old reports and logs with
`sudo rm /var/tmp/raspiBackupPkgTest.*.{report,log}`.

### Run it on GitHub

Without a test system the test can run on a GitHub arm64 runner (Ubuntu). It needs the GitHub CLI
`gh` authenticated with `gh auth login`:

```
cd build/test
./testPackageUpdatesOnGitHub.sh              # tests the pushed HEAD, waits and displays the report
```

It pushes a temporary branch `test-packageTest` with the workflow `packageTest.yml`, waits for the
result and deletes the branch. Report and log are downloaded to `build/test/packageTest-results/<run id>/`.
`-n` only starts the test. Only committed and pushed changes are tested.

---

## 7. Files in this directory

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
├── testPackageUpdates.sh # tests updates and reversals (release, beta, hotfix, individual fix, migration without apt) on a test system
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
│   │   ├── preinst     # before installation: save installation without apt, revertMigration.sh              |     |
│   │   ├── postinst    # after installation: create config from template if missing, else merge it         |     |
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
