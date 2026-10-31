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
6. [Files in this directory](#6-files-in-this-directory)

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
- All published versions stay in the repository, so users can always go back.
  `publishRepo.sh` copies packages published earlier but missing locally back into `repo/`,
  so you can publish from any system.
- Neither `build/deb/` nor `build/repo/` are committed to `master`. The packages exist on
  `gh-pages` only.

### Beta versions

Betas are built and published like a release but with a version like `0.7.5-beta1`,
see [section 3](#3-beta-versions).

### Version numbers

| Purpose                           | `VERSION`         | Debian version     | Where                                   |
|-----------------------------------|-------------------|--------------------|-----------------------------------------|
| beta, release candidate           | `0.7.6-beta1`     | `0.7.6~beta1`      | suite `beta`, installed only on request |
| release                           | `0.7.5`           | `0.7.5`            | suite `stable`                          |
| hotfix for all users              | `0.7.5-m1`        | `0.7.5-m1`         | suite `stable`                          |
| temporary fix for one user only   | -                 | `0.7.5-m1~u972.1`  | not in the repository, see below        |

They sort in this order, so every version is replaced by the next public one:

```
0.7.5 < 0.7.5-m1~u972.1 < 0.7.5-m1~u972.2 < 0.7.5-m1 < 0.7.6~beta1 < 0.7.6
```

- Use `~` only for versions which have to sort **before** the version in front of it:
  pre-releases (`~alpha`, `~beta`, `~rc`) and fixes for one user.
  A `~` sorts before everything, even before the end of the version.
- Behind the `~` the text is compared alphabetically. That's why `alpha < beta < rc` works,
  but `0.7.6~m972` would sort between `0.7.6~beta1` and `0.7.6~rc1`. Use only `alpha`, `beta`
  and `rc` for pre-releases.
- `buildRepo.sh` puts every version containing `~` into the suite `beta`.

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
curl -fsSLO https://framps.github.io/raspiBackup/raspiBackupInstall.sh
bash raspiBackupInstall.sh
```

The script adds the repository and installs `raspibackup`. Then configure raspiBackup
(backup path, backup type, timer, extensions, ...) with

```
sudo raspiBackupConfig
```

`raspiBackupConfig` detects the package installation. It offers the configuration
and the sample extensions. Users not familiar with apt can update and uninstall raspiBackup
with `sudo raspiBackupConfig -U` and `sudo raspiBackupConfig -u`. `-i` isn't available,
the package is already installed.

The menu `M3 Update components` of `raspiBackupConfig` runs `apt-get update` and offers
the apt commands described below:

| Option | apt command | Available if |
|--------|-------------|--------------|
| `P1` Update current release | `apt-get install raspibackup=<latest stable>` | a newer release exists |
| `P2` Revert to previous release | `apt-get install --allow-downgrades raspibackup=<previous>` and `apt-mark hold` | a release is installed and an older one exists |
| `P3` Install available beta | `apt-get install raspibackup=<latest beta>` | a newer beta exists |
| `P4` Revert from beta to current release | `apt-get install --allow-downgrades raspibackup=<latest stable>` | a beta is installed |

Every option removes a hold first. Afterwards `raspiBackupConfig` restarts with the installed version.

Updates afterwards:

```
sudo apt-get update && sudo apt-get upgrade
```

To test beta versions see [section 3](#3-beta-versions).

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
| `/usr/local/bin/raspiBackupConfig` | configuration |
| `/usr/local/etc/raspiBackup.conf` | configuration, created on first installation from a template |
| `/usr/local/share/raspibackup/` | configuration templates |
| `/usr/local/share/raspibackup/extensions/` | sample extensions and their README |
| `/usr/local/lib/systemd/system/raspiBackup.{service,timer}` | default systemd units |
| `/etc/systemd/system/raspiBackup.{service,timer}` | units configured by `raspiBackupConfig`, take precedence |

The configuration isn't managed by dpkg (no conffile). Installation, update and downgrade
never change it, so there are no questions about it during `apt-get upgrade`.
A configuration of a former installation with the curl script is used as it is.
Before every installation the configuration is saved as `raspiBackup.conf~`.
After an installation, update or version change `raspiBackupConfig` (menu and `-U`) adds new options
of the template `/usr/local/share/raspibackup/raspiBackup_{en,de}.conf` to the configuration and
comments out options which no longer exist. Existing values aren't changed. The configuration
before the merge is saved as `raspiBackup.conf.v<config version>`. A downgrade doesn't change it.

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
curl -fsSLO https://framps.github.io/raspiBackup/raspiBackupInstall.sh
bash raspiBackupInstall.sh --beta
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

Deleting the faulty package from the repository doesn't help: apt never downgrades
installed packages by itself. Also `publishRepo.sh` doesn't support removing packages yet,
it restores packages deleted only locally.

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

## 6. Files in this directory

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
