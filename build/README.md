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
| `GPG_KEY_UID`   | regex, only matching user IDs of the key are published (e.g. `GITHUB-KEY`), empty = all |
| `REPO_SUITE`    | `stable`, has to match `REPO_SUITE` in `raspiBackupInstall.sh`       |
| `REPO_BETA_SUITE` | `beta`, has to match `REPO_BETA_SUITE` in `raspiBackupInstall.sh`  |
| `VERSION_RASPIBACKUP` | version inserted into `raspiBackup` and used for the package, empty = `VERSION` of `raspiBackup.sh` |
| `VERSION_RASPIBACKUPCONFIG` | version inserted into `raspiBackupConfig`, empty = `VERSION` of `raspiBackupConfig.sh` |
| `DEB_REVISION` | Debian revision appended to the package version for a minor fix, e.g. `1` -> `0.7.5-1`, empty = none |
| `FIXES` | fix branches in the package, e.g. `m_972 m_965`, empty = branches `m_<issue>` merged since the last tag, see [Tags and GitHub releases](#tags-and-github-releases) |
| `GITHUB_RELEASES` | `1` = `publishRepo.sh` creates public GitHub releases, empty = git tags only. **Set it only when the apt repository is in production** |
| `DEPRECATED` | published versions with a severe bug, e.g. `0.7.5 0.7.6~beta1`, see [Deprecate a version](#deprecate-a-version) |

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
./build.sh --dry-run          # optional: check version, suite and fix branches first
./build.sh

# 3. Publish the repository on GitHub Pages (branch gh-pages). Also tags the published
#    version (v0.7.5) and, if GITHUB_RELEASES="1", creates its GitHub release
./publishRepo.sh --dry-run    # optional: check what is published, tagged and released first
./publishRepo.sh

# 4. Check after one or two minutes that the new version is online
curl -fsS https://framps.github.io/raspiBackup/dists/stable/main/binary-armhf/Packages | grep -E '^(Version|Fixes):'
```

`gpg` asks for the passphrase of the signing key during steps 2 and 3.

#### Check before building and publishing

Both scripts have a `--dry-run` which changes nothing. It doesn't sign (no passphrase), doesn't
touch `build/deb/` and `build/repo/` and doesn't commit, push or tag. Only `build.log` is rewritten.

| Command | Shows | Warns if |
|---------|-------|----------|
| `./build.sh --dry-run [--no-repo] [<version>]`, `./build.sh --dry-run --fix <try>` | branch and commit, package version, versions of raspiBackup and raspiBackupConfig, fix branches (`Fixes`), last tag, target suite or for `--fix` the fix directory | the version is a build of a fix branch (`-m_972`) which would go into a suite, the version is already in `build/repo/`, or it's lower than the highest version of its suite in `build/repo/` (apt wouldn't install it as update) |
| `./publishRepo.sh --dry-run [--remove <version>] [--remove-fix <branch>]` | versions which would be published, marked `(new)`, removed versions, fixes for testers per branch, removed fixes, tags which would be created on which commit, GitHub releases with their notes, and whether they would be created (`GITHUB_RELEASES`) | a version can't be tagged (fix branch build, commit not available) |

`./publishRepo.sh --no-push` is no dry run: it signs and updates `build/repo/` and creates the
commit locally, only pushing, tagging and the GitHub releases are skipped.

`build.sh --dry-run` only knows the versions in the local `build/repo/`. The published ones are
shown by `./publishRepo.sh --dry-run` or `--list`.

A fix branch build like `0.8.1-m-972` is dangerous in suite `stable`: apt reads it as release
`0.8.1-m` plus revision `972`, so it sorts above every hotfix `0.8.1-m1`, `0.8.1-m2`, ... Users who
installed it never get a hotfix of `0.8.1`. So `build.sh` and `buildRepo.sh` refuse to add it to a
suite. Build a fix for the tester with `--fix <try>`, see [Fix of a branch for one tester](#fix-of-a-branch-for-one-tester).

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
  Deprecated versions are marked in the repository as well, see
  [Deprecate a version](#deprecate-a-version). A package installation doesn't download
  `raspiBackup.properties` any more, only installations without apt still read it.
- All published versions stay in the repository (unless removed with `--remove`, see section 4),
  so users can always go back.
  `publishRepo.sh` copies packages published earlier but missing locally back into `repo/`,
  so you can publish from any system.
- Neither `build/deb/` nor `build/repo/` are committed to `master`. The packages exist on
  `gh-pages` only.

### Tags and GitHub releases

Which fix branch went into which version is recorded automatically, nothing has to be
documented by hand. The branch number is the issue number: `m_972` fixes issue #972.

**In the package.** `build.sh` writes two own fields into the package:

| Field | Content |
|-------|---------|
| `Fixes` | fix branches in the package, e.g. `m_972 m_965`. `build.sh` takes the branches `m_<issue>` merged since the last tag (`Merge branch 'm_972'`, `Merge pull request #.. from ../m_972`). Set `FIXES` in `build.conf` if that's wrong or incomplete, e.g. for a squash merge |
| `Git-Commit` | commit the package was built from, `publishRepo.sh` tags it |

They are also listed in the Debian changelog (`apt changelog raspibackup`). Every version in the
repository shows them, on GitHub (`dists/stable/main/binary-armhf/Packages` on branch `gh-pages`)
and on every system with the repository:

```
apt-cache show raspibackup | grep -E '^(Version|Fixes):'
```

**Git tags.** After the push `publishRepo.sh` creates a signed tag `v<version>` on the commit of
every published package which has no tag yet and pushes it. A tag can't contain `~`, so the
tags look like the former ones: `v0.7.5`, `v0.7.5-1`, `v0.7.5-m1`, `v0.7.6-beta1`. Packages built
before `build.sh` recorded the commit aren't tagged. On GitHub every commit page lists the tags
containing it, and two tags can be compared (`compare/v0.7.5...v0.7.5-m1`).

**GitHub releases.** With `GITHUB_RELEASES="1"` in `build.conf`, `publishRepo.sh` also creates a
GitHub release for every new tag:

| Version | Release |
|---------|---------|
| release `0.7.5`, hotfix `0.7.5-m1` | release with the fixed issues, e.g. `- #972 (branch m_972)` |
| beta `0.7.6~beta1` | pre-release |
| minor fix `0.7.5-1` | none, only the tag: minor fixes aren't announced |
| fix of a branch for one tester `0.7.5-m1+m972.1` | none and no tag: it's in no suite and never announced |
| build of a fix branch `0.7.5-m-972` (`VERSION="0.7.5-m_972"` without `--fix`) | none and no tag. `build.sh` and `buildRepo.sh` refuse to add it to a suite |

> **Warning: GitHub releases are public.** They are shown to everybody on
> https://github.com/framps/raspiBackup/releases, the page raspiBackup refers to in its update
> messages and where the releases of the installations without apt are announced. Set
> `GITHUB_RELEASES="1"` only when the apt repository is in production. Before that, leave it empty:
> `publishRepo.sh` creates the tags only and says that no releases were created.
> With `GITHUB_RELEASES="1"`, `publishRepo.sh` shows the same warning together with the releases
> it would create and asks before creating them.

Creating the releases requires the GitHub CLI: `sudo apt-get install gh` and `gh auth login`.
If you answer no, or `gh` is missing, the tags exist anyway and a later `publishRepo.sh` doesn't
create the releases again. Create them by hand:

```
gh release create v0.7.5-m1 --verify-tag --title "raspiBackup 0.7.5-m1" --notes "Fixes: #972 (branch m_972)"
gh release create v0.7.6-beta1 --verify-tag --prerelease --title "raspiBackup 0.7.6~beta1" --notes "..."
```

### Deprecate a version

A published version with a severe bug is marked as deprecated in the signed package index.
apt itself has no such mark: the usual way is to publish a fixed version, which `apt upgrade`
installs and raspiBackup reports. The mark in addition reaches the users who don't update or keep
a version (`-R`, `apt-mark hold`), and keeps the version from being offered again.

```
# 1. List the version in build.conf, versions separated by blanks or commas
DEPRECATED="0.7.5"

# 2. Check and publish, publishRepo.sh recreates and signs the package index (buildRepo.sh).
#    No package has to be built.
./publishRepo.sh --dry-run      # lists the versions with 'deprecated'
./publishRepo.sh
```

- `buildRepo.sh` adds the field `Deprecated: yes` to these versions in the package index
  (`apt-cache show raspibackup=0.7.5`). The packages stay in the pool: apt has to know a version,
  so its users get the warning.
- An entry includes all versions derived from it: `0.7.5` deprecates `0.7.5-1`, `0.7.5-m1`,
  `0.7.5~beta1`, `0.7.5~rc1`, ..., but not `0.7.50`. Debian versions and `VERSION` of raspiBackup
  (`0.7.6-beta1`) are both accepted. `buildRepo.sh` warns about an entry which matches no version.
- raspiBackup warns users of a deprecated version at the start of every run (RBK0135W, three times)
  and sends the eMail even with `MAIL_ON_ERROR_ONLY`. Telegram, Pushover and Slack get 💀 in their
  notification if they are configured to send messages. It never reports a deprecated version as
  update or beta. `SKIP_DEPRECATED` in the configuration
  of raspiBackup suppresses the warning for a version.
- raspiBackup also tells users of a deprecated version how to get rid of it. If there is a newer
  version which isn't deprecated, it reports it with `raspiBackupConfig -U` (menu `M3`, `P1`) after
  every run, not only three times like other updates. Otherwise it offers to revert (RBK0368I) to
  the version `raspiBackupConfig` installs: the previous release with `-R` (menu `P2`), for a
  beta the release with `-S` (menu `P4`). Without such a version there is only the warning.
- `raspiBackupConfig` never offers a deprecated version (menu `P1`-`P4`, `-U`, `-R`, `-b`, `-S`).
  If `apt upgrade` would install a deprecated version, `-U` installs the newest one which isn't
  deprecated. raspiBackup tells the user to update with `raspiBackupConfig -U` or menu `M3` (`P1`).
  A plain `apt upgrade` still installs it, so publish a fixed version soon.
- raspiBackup reads the mark from the local package index, which `apt-daily` and raspiBackup
  itself (once a day) update. A changed mark reaches the users within a day.
- Fixes of a branch for one tester (`-F`) aren't in the package index and are never deprecated.
- Installations without apt still read `DEPRECATED` of `raspiBackup.properties` on `master`.

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
| fix of a branch for one tester    | `0.7.5-m_972`     | `0.7.5-m1+m972.1`  | in no suite, `repo/fixes/m_972`, see [below](#fix-of-a-branch-for-one-tester) |

They sort in this order, so every version is replaced by the next public one:

```
0.7.5 < 0.7.5-1 < 0.7.5-2 < 0.7.5-m1 < 0.7.5-m1+m972.1 < 0.7.5-m1+m972.2 < 0.7.5-m2 < 0.7.6~beta1 < 0.7.6
```

- A minor fix (small code fix, packaging, maintainer scripts, ...) keeps `VERSION` of raspiBackup
  and sets `DEB_REVISION` in `build.conf`: `"1"` for the first rebuild, `"2"` for the next one,
  and so on. Empty it again for the next release. New installations get the fix, existing
  installations get it with `apt upgrade`, but raspiBackup doesn't tell users of the same version
  about it (`0.7.5` -> `0.7.5-1`). Users of an older version are told about the latest one
  (`0.7.4` -> `0.7.5-1`). To have a minor fix reported to users of an earlier minor fix, add that
  one to `DEPRECATED` in `build.conf`: `0.7.5-1` reports `0.7.5-2` to users of `0.7.5-1`.
  Users of `0.7.5` can't be told about a minor fix, because `DEPRECATED="0.7.5"` deprecates the
  minor fixes as well. Publish a hotfix (`0.7.5-m1`) instead.

- Use `~` only for versions which have to sort **before** the version in front of it:
  pre-releases (`~alpha`, `~beta`, `~rc`).
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
| fix of a branch, tested by one user   | `0.7.5-m1+m972.1`  | no, never offered to others  | the tester with `raspiBackupConfig -F m_972`      |

### Fix of a branch for one tester

A fix is developed on a fix branch `m_<issue>`, e.g. `m_972` for issue #972, with
`VERSION="0.7.5-m_972"` in `raspiBackup.sh`. Before it's merged, the user who reported the issue
tests it. Nobody else gets it or is told about it until it's released.

Every package in a suite reaches all users of that suite. So the fix isn't added to a suite, but
published next to the repository in `fixes/m_972/` on `gh-pages`. apt never sees it, raspiBackup
never reports it. Only who knows the branch can install it, and only signed with the key of the
repository. `build.sh` and `buildRepo.sh` refuse to add a build of a fix branch to a suite.

**Version.** `build.sh --fix <try>` takes the newest published release as base and appends
`+m<issue>.<try>`, with `-0` if the base has no Debian revision:

| Newest release | Try 1             | Try 2             |
|----------------|-------------------|-------------------|
| `0.7.5`        | `0.7.5-0+m972.1`  | `0.7.5-0+m972.2`  |
| `0.7.5-1`      | `0.7.5-1+m972.1`  | `0.7.5-1+m972.2`  |
| `0.7.5-m1`     | `0.7.5-m1+m972.1` | `0.7.5-m1+m972.2` |

Every try is above its base and the previous try, and below **every** later public version:
a minor fix, any hotfix (`0.7.5-m2`, `0.7.5-m10`), a beta or the next release. So it doesn't
matter in which order fixes of different branches are released. Without the `-0`,
`0.7.5+m972.1` would sort above the hotfix `0.7.5-m1`.

**Maintainer**

```
# 1. On the fix branch: VERSION="0.7.5-m_972" in raspiBackup.sh, the fix committed
git switch m_972
cd build
./build.sh --dry-run --fix 1      # shows the version of the fix
./build.sh --fix 1                # -> repo/fixes/m_972/raspibackup_0.7.5-m1+m972.1_all.deb and .sig
./publishRepo.sh                  # publishes fixes/m_972 on gh-pages, no tag, no release

# 2. Tell the tester: sudo raspiBackupConfig -F m_972

# 3. The fix isn't sufficient: next try, every try needs a new, higher number
./build.sh --fix 2 && ./publishRepo.sh

# 4. The fix works: merge it and release it as hotfix or with the next release
git switch master && git merge m_972        # VERSION="0.7.5-m2" or "0.7.6"
./build.sh && ./publishRepo.sh              # Fixes: m_972, tagged, GitHub release if enabled

# 5. Tell the tester: sudo raspiBackupConfig -U
#    After the tester updated, remove the fix
./publishRepo.sh --remove-fix m_972
```

`./publishRepo.sh --list` and `--dry-run` show the published fixes per branch. `build.sh --fix`
warns if the branch is based on an older release than the newest one: the fix replaces the newest
release for the tester, so merge or rebase the branch first.

**Tester**

| Step | Command |
|------|---------|
| install the fix, also every newer try | `sudo raspiBackupConfig -F m_972` |
| fix doesn't work: back to the release | `sudo raspiBackupConfig -R` |
| fix is released: install the release with the fix | `sudo raspiBackupConfig -U` |

`-F` downloads the newest try, checks its signature against the key apt trusts for the
repository, installs it and holds the package. Nothing replaces it then: neither
`apt-get upgrade`, nor a hotfix of another branch, nor a beta. raspiBackup still reports new
releases after the backup, also the release with the fix, and refers to `raspiBackupConfig -U`.
`-U` installs the newest release then and releases the hold. It never installs a beta, although
apt's candidate can be a beta: a package installed from a file has the same apt priority as
the beta suite. `-R` installs the release the fix is based on and holds it, `-F` installs the fix
again. Like before with the fixed `raspiBackup.sh`: if the tester updates with `-U` to an
unrelated hotfix before the fix is released, the fix is gone. Tell the tester which version
contains the fix.

Useful commands:

```
./build.sh --help                       # options: --dry-run, --fix <try>, --no-check (no lintian), --no-repo
./publishRepo.sh --help                 # options: --dry-run, --list, --no-push, --remove <version>, --remove-fix <branch>
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

The menu and the options update the package index of the raspiBackup repository on every call,
so a new version is offered right after it was published (GitHub Pages may deliver the old index
for a few minutes). The other repositories are only updated for an installation. `-f` is ignored.

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
curl script is used as it is. `apt-get purge` also deletes a `raspiBackup.conf~` left by former installations.

After every installation, update or version change, also a plain `apt-get upgrade`, `postinst`
calls `raspiBackupConfig -m`. It adds new options of the template
`/usr/local/share/raspibackup/raspiBackup_{en,de}.conf` to the configuration and comments out options
which no longer exist, but only if the template has a newer config version than the configuration.
Existing values aren't changed. The configuration before the merge is saved as
`raspiBackup.conf.v<config version>`, `apt-get purge` deletes these copies like the configuration
because they may contain passwords. A downgrade doesn't change it. If the merge fails, the package
is installed anyway and `raspiBackupConfig` offers the merge when it's started.

### Files raspiBackup writes

Besides the backups, raspiBackup keeps information in these files.

#### State between runs: `/var/lib/raspiBackup/`

Created when it's needed first, deleted by `apt-get purge` and `raspiBackupConfig -u`.

| File | Content | Used for |
|------|---------|----------|
| `restore.reminder` | `<yyyymm> <count>`: month the reminder period started, number of reminders so far | reminder to test a restore every `RESTORE_REMINDER_INTERVAL` months (default 6), `RESTORE_REMINDER_REPEAT` times (default 3). Only if `RESTORE_REMINDER_INTERVAL` > 0 |
| `report.counter` | number of reminders left | reminder about backups with the names used before release 0.7, `OLD_REMINDER_REPEAT` times (default 5) |
| `package.reminder` | `<version> <count>`: last reported update, number of reports | an update is reported at most 3 times, every time while the installed version is deprecated. A newer version restarts the count. Package only |
| `package.index` | only its time stamp | `apt-get update` of the raspiBackup repository at most once a day. Package only |

#### Configuration

| File | Written by |
|------|------------|
| `/usr/local/etc/raspiBackup.conf` | `postinst` from the template, `raspiBackupConfig` (menu, `-m` merge) |
| `/usr/local/etc/raspiBackup.conf.v<config version>` | `raspiBackupConfig -m`, copy before a merge |
| `~/.raspiBackup.conf`, `./.raspiBackup.conf`, option `-f <file>` | the user. Read after the one in `/usr/local/etc` and override its options. `~` is the home of the user who called `sudo` |

raspiBackup itself only reads the configuration.

#### Log and messages of a run

raspiBackup writes the log (`.log`) and the messages (`.msg`) to `/tmp` while it runs and copies
them at the end to the log target (`DEFAULT_LOG_OUTPUT`, option `-L`). A restore uses `.logr` and `.msgr`.

| Log target | Files |
|------------|-------|
| `Backup` (default) | `<backup directory>/raspiBackup.log`, `raspiBackup.msg` |
| `Varlog` | `/var/log/raspiBackup/<hostname>.log`, `.msg`, appended. Deleted by `apt-get purge` |
| `Current` | `~/raspiBackup.log`, `~/raspiBackup.msg` of the calling user. Also used if the backup failed with target `Backup`, the backup directory was deleted or `-F` (fake) is used |
| `-L <file>` | `<file>.log`, `<file>.msg` |

#### In the backup directory

Every backup contains, besides the data, the partition layout needed for a restore:
`<hostname>-backup.sfdisk` and `.mbr`, for tar and rsync backups also the boot partition as
`.img` (dd) or `.tmg` (tar). Partition oriented backups have `.blkid`, `.parted` and `.fdisk` in
addition. In rsync backups unchanged files are hard links to the ones of the previous backup.

#### Until the next reboot: `/tmp`

| File | Content |
|------|---------|
| `/tmp/raspiBackup.vars` | after every run as root: `BACKUP_TARGETDIR`, `BACKUP_TARGETFILE`, `MSG_FILE` and `LOG_FILE` of the last run, e.g. for own scripts |
| `/tmp/raspiBackup.properties` | properties file downloaded from `master`. Installations without apt only, the package gets new and deprecated versions from the repository |
| `/tmp/raspiBackup.log`, `.msg`, `.logf`, `/tmp/<pid>.sfdisk`, `/tmp/raspiBackup_mnt*` | log, messages, mount points and partition table while raspiBackup runs, removed or moved at the end |

#### Written by raspiBackupConfig and the package

| File | Content |
|------|---------|
| `/etc/apt/sources.list.d/raspibackup.sources`, `/usr/share/keyrings/raspibackup-archive-keyring.gpg` | the apt repository and its key, `raspiBackupInstall.sh` and `raspiBackupConfig` (install, migration). Deleted by `raspiBackupConfig -u` |
| `/etc/systemd/system/raspiBackup.{service,timer}`, `/etc/cron.d/raspiBackup` | the backup timer configured with `raspiBackupConfig` |
| `/var/backups/raspiBackup-legacy/` | the installation without apt, saved by `preinst` during the migration, with `revertMigration.sh` |

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
`postinst` merges the configuration. `raspiBackupConfig` runs `apt-get update` of the raspiBackup
repository only (`-o Dir::Etc::sourcelist=/etc/apt/sources.list.d/raspibackup.sources`) once per call,
for an installation of all repositories.

#### Other versions (`-R`, `-b`, `-S`, menu `P2`-`P4`)

See the table above and [section 3](#3-beta-versions) and [section 4](#4-revert-to-a-previous-release).
Every option removes a hold first (`apt-mark unhold raspibackup`), `-R` and `P2` set it again
(`apt-mark hold raspibackup`).

#### Fix of a branch (`-F m_972`)

See [Fix of a branch for one tester](#fix-of-a-branch-for-one-tester). The repository URL is the
one in `/etc/apt/sources.list.d/raspibackup.sources`.

```
url=https://framps.github.io/raspiBackup/fixes/m_972
fix="$(curl -fsSL "$url/latest")"                 # file name of the newest try
curl -fsSLO "$url/$fix" && curl -fsSLO "$url/$fix.sig"
gpgv --keyring /usr/share/keyrings/raspibackup-archive-keyring.gpg "$fix.sig" "$fix"
sudo apt-mark unhold raspibackup
sudo apt-get install -y --allow-downgrades "./$fix"
sudo apt-mark hold raspibackup
```

With a fix installed, `-U` and `P1` install the newest release (`apt-get install raspibackup=<version>`),
not the candidate of apt, which can be a beta.

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

### Test by hand with a test repository

New versions, betas, deprecations and fixes can be tried on a real system before they are published,
e.g. how `raspiBackupConfig` offers them and what raspiBackup reports after the backup. The test
repository is built like the real one, signed with `GPG_KEYID`, and served from the build machine.
`raspiBackupConfig`, `raspiBackup` and apt take the repository URL from
`/etc/apt/sources.list.d/raspibackup.sources` (also for fixes with `-F`), so only that URL is changed
on the test system. Two scripts in `build/test` do all steps:

- `testRepo.sh` on the build machine builds the test versions in a separate build directory
  (a git worktree, default `~/raspiBackup-testRepo`) and serves its repository. **Don't build test
  versions in `build/`**: `publishRepo.sh` publishes everything in `build/repo`.
- `useTestRepo.sh` on the test system switches between the test repository and the real one.
  `testRepo.sh serve` offers it for download with the URL of the test repository.

On the build machine (`buildhost` stands for its IP address, which `serve` uses and prints):

```
cd build/test
./testRepo.sh init m_972                  # once: test build directory for branch m_972, build.conf from build/build.conf
./testRepo.sh build 0.9.1                 # build the latest commit of m_972 as 0.9.1 into the test repository
./testRepo.sh build 0.9.2-beta1           # more versions, a beta goes into the suite beta
./testRepo.sh deprecate "0.9.1"           # deprecate versions, "" removes the marks
./testRepo.sh build --fix 1               # fix for one tester, VERSION of raspiBackup.sh, e.g. 0.9.2-m_972
./testRepo.sh list                        # versions and fixes in the test repository
./testRepo.sh serve                       # serve it on http://buildhost:8000 until Ctrl-C, prints the commands below
```

`serve` uses the IP address of the interface of the default route, a host name often can't be
resolved on the test system. `serve 8080 192.168.0.10` uses another port and address. Only committed changes are built, `build` uses the latest commit
of the branch. The repository can be served while new versions are built in another terminal.

On the test system:

```
curl -fsSL http://buildhost:8000/useTestRepo.sh | sudo bash -s -- on        # use the test repository
sudo raspiBackupConfig                                                        # offers the test versions
sudo raspiBackupConfig -F m_972                                               # fix of a branch
sudo raspiBackup ...                                                          # reports news after the backup

curl -fsSL http://buildhost:8000/useTestRepo.sh | sudo bash -s -- refresh   # after a new build or deprecation
curl -fsSL http://buildhost:8000/useTestRepo.sh | sudo bash -s -- status    # repository used and versions
curl -fsSL http://buildhost:8000/useTestRepo.sh | sudo bash -s -- off       # back to the real repository
```

- `on` replaces the URL in `raspibackup.sources`, apt then knows only the test versions. `on`, `refresh`
  and `off` fail if the repository can't be read. Without the
  repository (new system) it calls `raspiBackupInstall.sh` with `REPO_URL` of the test repository,
  which adds it and installs raspiBackup from it.
- `on` and `refresh` update the package index of the repository and remove
  `/var/lib/raspiBackup/package.index`, so the next backup of raspiBackup updates the index too and
  reports the news at once. raspiBackupConfig 0.8 and older update the index only once a day, call
  them with `-f`.
- `off` switches back to `https://framps.github.io/raspiBackup`. A test version newer than the latest
  published release is replaced by that release and its hold is removed.

Finally remove the test build directory on the build machine with `./testRepo.sh remove`.

What the scripts do by hand: `git worktree add --detach`, `BRANCH_TO_DEB` and `VERSION_RASPIBACKUP` in
its `build.conf`, `./build.sh` there and `python3 -m http.server 8000 --directory repo`. On the test
system `sed -i 's|^URIs:.*|URIs: http://buildhost:8000|' /etc/apt/sources.list.d/raspibackup.sources`
and `sudo apt-get update`.

To sign test versions with a throwaway key instead of `GPG_KEYID`, create it in a separate `GNUPGHOME`
like `testPackageUpdates.sh` does and set it as `GPG_KEYID` in the `build.conf` of the test build
directory. The test system then needs that key: `REPO_URL=http://buildhost:8000
REPO_OWNER_GPG_FINGERPRINT=<its fingerprint> bash raspiBackupInstall.sh`. Call it without both variables
to get the real key and repository back.

This replaces the test of new versions with `URLTARGET` and a test `raspiBackup.properties`, which
only installations without apt still read.

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
├── publishRepo.sh      # publishes repo/ and raspiBackupInstall.sh on GitHub Pages (branch gh-pages), tags versions
├── common.sh           # common definitions for build and install
├── compareVersions.sh  # to test version up- and downgrade recognition
├── testPackageUpdates.sh # tests updates and reversals (release, beta, hotfix, fix of a branch for a tester, migration without apt) on a test system
├── test/testRepo.sh    # builds test versions into a test repository and serves it, see "Test by hand with a test repository"
├── test/useTestRepo.sh # on the test system: switches between the test repository and the real one
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
