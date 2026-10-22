# OEAdmin.ps1 — User Manual

A complete reference for the OEAdmin PowerShell administration script for
OpenEdge (Progress) databases.

- [1. What it is](#1-what-it-is)
- [2. Concepts and model](#2-concepts-and-model)
- [3. Installation](#3-installation)
- [4. Configuring for your environment](#4-configuring-for-your-environment)
- [5. Running the script](#5-running-the-script)
- [6. The interactive menu](#6-the-interactive-menu)
- [7. Actions in detail](#7-actions-in-detail)
- [8. Selectors in detail](#8-selectors-in-detail)
- [9. Checks and monitoring](#9-checks-and-monitoring)
- [10. Notifications and logging](#10-notifications-and-logging)
- [11. Remote operation](#11-remote-operation)
- [12. Cross-platform behavior](#12-cross-platform-behavior)
- [13. Full parameter reference](#13-full-parameter-reference)
- [14. Exit codes](#14-exit-codes)
- [15. Scheduling](#15-scheduling)
- [16. Troubleshooting](#16-troubleshooting)

---

## 1. What it is

OEAdmin.ps1 is one script that manages OpenEdge database brokers, NameServers,
and (optionally) MS SQL DataServer brokers. It runs on Windows PowerShell 5.1 and
on PowerShell 7+ (Linux, macOS, Windows).

It combines several jobs a DBA usually does with a handful of separate scripts:

- Check and change instance state (status / start / stop / restart).
- Online backups (`probkup`) of production databases.
- Restores (`prorest`) of production backups into dev/test/sandbox.
- Staging production backups onto the development server.
- Launching the Progress client, interactively or in batch.
- Scanning database `.lg` logs for errors since the last startup.
- Verifying AdminServer reachability and 4GL broker ports.
- Backing up `conmgr`/`ubroker` properties before any state change.
- Emailing a log and/or an alert, and writing a Windows EventLog entry.

The list of databases/brokers is **never hardcoded**. It is read at run time from
each install's property files.

---

## 2. Concepts and model

### 2.1 Installs (the topology table)

Everything starts from the `$Installs` table near the top of the script. Each row
is **one OpenEdge install** and carries:

| Field       | Meaning |
|-------------|---------|
| `App`       | Which application this install hosts (matches `-App`). |
| `Tier`      | `Production` or `Development` — gates backup/copy vs restore. |
| `Server`    | Hostname (matches `-Server`; compared to the local machine name). |
| `OEVersion` | OpenEdge version string (matches `-OEVersion`). |
| `DLC`       | The OpenEdge install directory for this install. |
| `Port`      | The AdminServer management port for this install. |
| `InstallDir` | The install **root** (e.g. `/opt/app1`). This is what appears in the master INI's `PROPATH`, so the `-Workspace` launch rewrites `InstallDir` → the chosen worktree's app folder. Per install, not global. |
| `SetupDir`  | Root of this install's `-Client`/`-Batch` INI/PF tree, always `<InstallDir>/setup` (INI under `<SetupDir>/ini/<server>/`, PF under `<SetupDir>/userPfs/<server>/`). Per install, not global, because the root can differ by machine **and** OE version. |
| `InstalledComponents` | Allowlist of shared components this install runs: any of `"NameServer"` / `"MSSQLBroker"` / `"OracleBroker"`, or `@()` for none. Gates which components `-Start`/`-Stop`/`-Restart` touch (see §7); databases ignore it. Per install/AdminServer. |
| `ExtraDatabases` | Allowlist of **exact** names of extra databases this install's AdminServer manages that are **not** application databases (so the name-parser skips them) but that you still want inventoried — e.g. a schema-holder DB. Each listed DB becomes a Database row with `Role="Extra"` and `Site`/`Env="All"`, tagged with this install's `App`. Case-insensitive match; `@()` (default) means none. Per install/AdminServer. |

A single server can appear in several rows (for example, two OpenEdge versions
installed side by side on different DLC paths and ports, each with its own
`SetupDir`, `InstalledComponents`, and `ExtraDatabases`).

### 2.2 Inventory (discovered, not listed)

At startup the script reads, for each install:

- `<DLC>/properties/conmgr.properties` → the databases the AdminServer manages,
  and each database's **4GL broker (client-connect) port**.
- `<DLC>/properties/ubroker.properties` → the **NameServer(s)**, the **MS SQL
  DataServer broker(s)**, and the **Oracle DataServer broker(s)**.

Each database name is passed through a **parser** to derive its role, environment,
and site. The result is a live inventory of "items", each being a Database, a
NameServer, an MSSQLBroker, or an OracleBroker. A component is inventoried only if
its type appears in that install's `InstalledComponents` allowlist. A managed
database whose name the parser does **not** recognize is normally skipped, unless
it is named in that install's `ExtraDatabases` allowlist — then it is inventoried
as a Database with `Role="Extra"` and `Site`/`Env="All"`.

### 2.3 Selectors and actions

- **Selectors** narrow the inventory: `-App`, `-Server`, `-Site`, `-Env`,
  `-OEVersion`, `-Component`.
- **Actions** say what to do to the selection: `-Status` (default), `-Start`,
  `-Stop`, `-Restart`, `-Backup`, `-Restore`, `-CopyBackup`, `-Client`,
  `-Batch`, and the interactive `-Menu`.

### 2.4 Tiers and the safety guard

The Production/Development tier on each install drives a safety model:

- `-Backup` and `-CopyBackup` run on **Production** installs only (the backups
  are local to the production server; `-CopyBackup` splits and pushes them to the
  dev server's share).
- `-Restore` runs on **Development** installs only.

This makes the unusual/dangerous cases (restoring over production, backing up a
dev copy) structurally impossible through this tool.

---

## 3. Installation

1. Copy `OEAdmin.ps1` onto the database server (or a management box for
   `-Remote`).
2. Ensure PowerShell is available:
   - Linux/macOS: install PowerShell 7 (`pwsh`).
   - Windows: Windows PowerShell 5.1 ships with the OS; PowerShell 7 also works.
3. Ensure the OpenEdge tools exist under each `<DLC>/bin` you list.
4. On Linux, optionally `chmod +x OEAdmin.ps1`.

Parse-check without running anything:

```bash
pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./OEAdmin.ps1),[ref]$null,[ref]$null); 'OK'"
```

If you hit an execution-policy block on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\OEAdmin.ps1 -Status
```

---

## 4. Configuring for your environment

Open the script and work through each `CHANGE THIS` marker. The order below is
the practical order to do them in.

### 4.1 `$Installs` table (required)

List your real servers. Example:

```powershell
$Installs=@(
    [PSCustomObject]@{ App="App1"; Tier="Production";  Server="dbserver1";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app1";      SetupDir="/opt/app1/setup";      InstalledComponents=@("NameServer");                           ExtraDatabases=@() }
    [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app1";      SetupDir="/opt/app1/setup";      InstalledComponents=@("NameServer","MSSQLBroker","OracleBroker"); ExtraDatabases=@("schemaholder1") }
    [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="10.2B"; DLC="/usr/dlc102b"; Port=20941; InstallDir="/opt/app1-102b"; SetupDir="/opt/app1-102b/setup"; InstalledComponents=@();                                       ExtraDatabases=@() }
    [PSCustomObject]@{ App="App2"; Tier="Production";  Server="dbserver2";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app2";      SetupDir="/opt/app2/setup";      InstalledComponents=@("NameServer");                           ExtraDatabases=@() }
    [PSCustomObject]@{ App="App2"; Tier="Development"; Server="dbserver2-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app2";      SetupDir="/opt/app2/setup";      InstalledComponents=@();                                       ExtraDatabases=@() }
)
```

### 4.2 `-App` ValidateSet (required)

Change `[ValidateSet("All","App1","App2")]` on the `$App` parameter to your app
names. Keep them identical to the `App=` values in `$Installs`.

### 4.3 Sites (`$ValidSites`, `-Site`) (as needed)

If you use sites, set `$ValidSites` (e.g. `@("S1","S2")`) and update the `-Site`
comment. If you have no sites at all, keep everything on `Site="All"` (as App2
does) and you can ignore site switches.

### 4.4 Database-name parsers (required — this is the important one)

The parsers turn a raw database name into `{ Role; Env; Site }`. This is how the
script knows an environment/site without you listing every database. Two examples
ship:

```powershell
# App1: ("app1db"|"app1aux") + env + site   e.g. app1dbprods1
function Parse-App1Database {
    param($DBName)
    if ($DBName -match '^(?i)(app1db|app1aux)(prod|dev|test|sbox)(s1|s2)$') { ... }
}

# App2: "<envprefix>-<role>"                 e.g. prod-main
function Parse-App2Database {
    param($DBName)
    if ($DBName -match '^(?i)(prod|prodcopy|dv|ts|sb)-(main|aux|report)$') { ... }
}
```

Edit the regex and the small maps to match how **your** databases are named. A
name that doesn't match returns `$null` and is silently ignored — that's how
QA/scratch/template databases get skipped automatically. Add a case in
`Parse-Database` for each app you have.

### 4.5 Paths (as needed)

- `$DlcBase` — default OpenEdge home (`/usr/dlc` on Linux, e.g.
  `C:/Progress/OpenEdge` on Windows).
- `$App1BackupDir` / `$App2BackupBase` — where backups live (the `-CopyBackup`
  source, local to the production server).
- **Client INI/PF setup tree** — this is the per-install `SetupDir` column in
  `$Installs` (section 2.1), always `<InstallDir>/setup`, not a global. Set each
  row's `InstallDir` (install root) and `SetupDir` to their
  machine + version's setup root.

### 4.5b CopyBackup settings (as needed)

- `$CopyDestServer` — the dev server `-CopyBackup` pushes to.
- `$BackupShareName` — the **named share** on that dev server (destination is
  `\\<CopyDestServer>\<BackupShareName>\...`, deliberately **not** the admin
  `drive$` share).
- `$SplitThresholdBytes` (default `1GB`) — a `.bk` larger than this is split.
- `$SplitSliceBytes` (default `1GB`) — slice size.
- `$CopyMaxRetries` / `$CopyRetryDelay` (defaults `5` / `15s`) — per-file copy
  retry/backoff.
- `$AsyncCopy` / `$AsyncQueueDepth` (default depth `3`) — pipeline split+copy and
  cap how many slices sit on local disk at once.
- The destination-root build in `Invoke-CopyBackup` uses the Windows
  `\\server\share` UNC form; on Linux change it to your mount/ssh scheme.

### 4.6 Backup file layout (`Get-BackupDevice`) (as needed)

Maps an (app, role, site) to a backup file path. Adjust to your naming.

### 4.7 Client executables (`Resolve-ClientLaunch`) (as needed)

Maps each OpenEdge version to its client exe. Ships as Windows
`prowin.exe`/`prowin32.exe` and Linux `_progres`. Adjust if you run clients
differently.

### 4.8 SMTP / email (as needed)

Set `$SmtpServer`, `$SmtpPort`, `$EmailFrom`, `$EmailTo`, and add `-SmtpUseSsl`
if your relay needs TLS.

### 4.9 `-Remote` path mapping (`Convert-ToRemotePath`) (only if using -Remote)

Ships with the Windows UNC admin-share convention. For Linux cross-server work,
change it to map a local path to your NFS mount / ssh target / etc.

### 4.10 Launch tools (`$Tools`) (as needed)

The `$Tools` map defines the named programs a `-Client`/`-Batch` session can run
(`-Tool <name>`). Each row:

```powershell
$Tools=@(
    [PSCustomObject]@{ Name="Run";        Pgm="sh/startup.p"; Extra=""; App=""; Startup=$true }
    [PSCustomObject]@{ Name="Editor";     Pgm="_edit.p";      Extra=""; App=""; Startup=$false }
    # ... add your own; App="" = any app, Startup=$true = the app's -Run default
)
```

Add rows for your own tools — no code change needed. `-Tool` wins over the fixed
`-Run`/`-Editor`/... aliases, and an app-specific entry wins over a shared one of
the same name.

### 4.11 Git working copies (`$GitReposRoot`, `$GitRepoApps`) (only if using -Workspace / -Git)

- `$GitReposRoot` — where your bare-clone + per-branch-worktree repos live. The
  default is **machine-aware** (edit the resolver to taste); override with the
  `-GitReposRoot` param. Leave the worktree features unused by simply never
  passing `-Workspace` / `-Git`.
- `$GitRepoApps` — maps a repo name to an app (`@{App1Repo="App1"; App2Repo="App2"}`).
  Only mapped repos are discovered.
- `$GitProjects` — maps a repo name to a clone URL, used only by
  `-NewWorkspace -BootstrapClone` to create a missing bare repo. Keys match
  `$GitRepoApps`.
- The layout assumption (`<GitReposRoot>/<Repo>/.bare` + one worktree per branch)
  lives in `Get-WorkingCopies` / the `AppPath` probe — adjust them if your git
  layout differs (see §7.10). `-NewWorkspace` and `-UpdateRepos` detect a missing
  `.bare` and handle it safely rather than cloning blindly (see §7.10).

---

## 5. Running the script

Default action is **Status**, so a bare run is read-only and safe:

```bash
./OEAdmin.ps1
```

General form:

```bash
./OEAdmin.ps1 [selectors] [action] [options]
```

Preview any action safely with `-DryRun`, which prints the exact commands that
would run and changes nothing:

```bash
./OEAdmin.ps1 -Restart -App App1 -Site S1 -Env Prod -DryRun
```

---

## 6. The interactive menu

`-Menu` is a drill-down front end for operators who don't want to remember
switches:

```bash
./OEAdmin.ps1 -Menu
```

It asks, in turn: **what to do** (the action), then only the parameters that
action needs (app, site, environment, etc.). Options that don't exist on this
machine are shown in **red** and can't be selected (unless you use `-Remote`).
Pressing Enter takes the first valid default. Before anything runs it prints the
**equivalent command line** and asks for a `y/n` confirmation — a good way to
learn the switches.

The action list includes **Git** (§7.10). Its flow first splits into **Daily
workflow** (pick a working copy, then status / diff / log / stash / commit /
push), **Maintenance** (UpdateRepos, or NewWorkspace — which prompts app, base
branch, optional new branch, and warns before bootstrapping if this machine isn't
on the bare+worktree layout), and **Cheat sheet** (prints the git help). The
**Client** flow additionally offers a working-copy picker and a "pull before
launching?" prompt when worktrees are found for the chosen app (§7.11), and a
launch-tool picker built from the `$Tools` map scoped to that app.

---

## 7. Actions in detail

Exactly one action runs per invocation (Status is the default if you specify
none). The menu enforces this too.

### 7.1 `-Status` (default)

Queries each selected instance and reports RUNNING / NOT RUNNING / UNKNOWN. With
`-RestartOnError`, anything found down is restarted.

### 7.2 `-Start`

Starts the selection. Each target is status-checked first; anything already
running is **skipped** (no "already running" error). Waits `SleepAfterStart`
seconds, then re-queries.

### 7.3 `-Stop`

Stops the selection. Anything already stopped is **skipped**.

### 7.4 `-Restart`

Stop, then start. Waits `-RestartDelay` seconds (default 10) between the two so
lingering processes finish exiting before the start.

**Whole-server gating for `-Start`/`-Stop`/`-Restart`.** NameServer, MSSQLBroker,
and OracleBroker are shared, server-wide resources, so these three actions touch
them **only when the selection covers every database that install manages** (within
the `-App` filter). If `-Site`/`-Env` (or `-App`) narrow the selection to a subset
of an install's databases, that install's components are **left running** and only
the selected databases are started/stopped (a skipped component is logged in gray).
So `-Stop -Server <box>` with no site/env stops the databases **and** the shared
components; `-Stop -Server <box> -Env Prod` stops only the Prod databases. This is
separate from the `InstalledComponents` allowlist, which decides whether a component
exists to be acted on at all.

### 7.5 `-Backup` (Production servers only)

Runs `probkup online <db> <device>` for each selected **Production** database in
the **Prod** environment. Non-production targets are refused by design. The backup
file path comes from `Get-BackupDevice`.

### 7.6 `-Restore` (Development servers only)

Runs `prorest` of the production backup into a selected **Dev/Test/SBox**
database, as stop → prorest → start. **`-Site` is required for a multi-site app**
(e.g. App1) so a restore can't silently fan out across sites. Single-source apps
(App2) don't need `-Site`.

If the whole `.bk` isn't staged but a `split/<basename>/` folder of slices is
(left by `-CopyBackup` for a large backup), `-Restore` **reassembles** the `.bk`
first (progress meter, manifest-checked), then deletes the slices and proceeds.

A short **settle delay** (`$SettleDelay`, default 5 s) is inserted after `prodel`
and after `prorest` so back-to-back operations on the same database don't race
the OS releasing file handles ("database in use").

### 7.7 `-CopyBackup` (Production servers only)

**Runs on the production server** and **pushes** production backups to the dev
server's **named share** (`\\<Dest>\<BackupShareName>\...`, not the admin
`drive$` share), scoped by `-App`. The source is a plain **local** path.

The destination dev server comes from **`-Dest <server>`**; if omitted it
defaults per app from `$CopyDestDefaults` (an explicit `-Dest` always wins). In
the `-Menu`, CopyBackup offers a picker of that app's Development servers with the
app default pre-selected (for `-App All`, each app uses its own default).

- A `.bk` larger than `$SplitThresholdBytes` (default 1 GB) is binary-**split**
  into `$SplitSliceBytes` slices (progress meter) under a local
  `split/<basename>/` folder, with a small `.split.manifest` (original name,
  size, slice size, part count).
- Each slice is copied to the dev share with **retry/backoff**
  (`$CopyMaxRetries` / `$CopyRetryDelay`), and the **local slice is deleted as
  soon as it lands**, so production scratch stays small.
- Files at/under the threshold copy whole (same retry logic).
- The dev side reassembles the slices at restore time (see 7.6).

**`-AsyncCopy`** pipelines the split and the copy: a background runspace copies
slice *N* over the network while the main thread carves slice *N+1* from disk.
A bounded queue (`$AsyncQueueDepth`, default 3) caps how many finished slices sit
on local disk at once (~depth × slice size). Opt-in; the synchronous
split-then-copy path runs when it's off. (Uses a runspace + `BlockingCollection`,
so it works on both Windows PowerShell 5.1 and 7.)

### 7.8 `-Client`

Launches the Progress GUI client for one environment. Command line:

```
<exe> -ininame <ini> -pf <pf> [ -p <StartupProgram> ]
```

Rules:
- **Multi-site app (App1):** requires `-Site` and a single `-Env`. INI/PF share
  the `<App><Env><Site>` stem (e.g. `app1DevS2.ini` + `app1DevS2.pf`).
- **Single-site app (App2):** no site; requires a single dev-side `-Env`. INI/PF
  stem is the env word (see `Get-App2EnvStem`). Prod is refused (dev-side tool).

Add `-Run` to append `-p <StartupProgram>`. Override files with `-Ini` / `-Pf`
(a bare filename is looked up in the standard setup subdir; a full path is used
as-is). Add secondary PFs with `-AddPfs "a.pf,b.pf"`. The exe is chosen by the
target's OpenEdge version.

**Launch tools (`$Tools` map + `-Tool`).** Instead of (or alongside) `-Run`, you
can name any entry in the `$Tools` configuration map with `-Tool <name>`. Each
entry has a `Name`, the `Pgm` it runs (its `-p`), optional `Extra` args, an
optional `App` scope (blank = any app), and a `Startup` flag (the app's default
"run" tool). The template ships Run/Editor/AppBuilder/Desktop/Dict/Admin; add
your own by editing `$Tools`, no code change. `-Tool` takes precedence over the
fixed `-Run`/`-Editor`/... switches (which remain as convenience aliases), and an
app-specific entry wins over a shared one of the same name. The `-Menu` Client
flow offers a picker built from `$Tools` scoped to the chosen app.

**Launch from a git working copy (`-Workspace`).** By default `-Client` launches
the **installed** code. Pass `-Workspace <token>` to launch from a git **working
copy** (worktree) instead — see §7.10 for how working copies are discovered and
how the per-workspace INI is built (the PROPATH is rewritten to the worktree; the
PF is left untouched). Add `-UpdateRepos` to fast-forward that working copy
before launching. The `-Menu` Client flow offers a working-copy picker (and a
"pull before launching?" prompt) whenever worktrees are found for the app.

### 7.9 `-Batch`

Same resolution as `-Client` but runs a program non-interactively:

```
<exe> -ininame <ini> -pf <pf> -p <program> -b
```

`-Pgm <program>.p` is **required**. The session runs blocking; stdout goes to
`<script dir>/<program>.out` and stderr to `<program>.err`. A non-zero exit sets
the error flag.

### 7.10 `-Git` (local repo/worktree maintenance)

`-Git` is an extensible action group for git work. It has two **maintenance**
sub-actions that operate across worktrees (`-UpdateRepos`, `-NewWorkspace`) and a
set of **day-in-the-life** helpers that operate in one working copy
(`-GitStatus`/`-GitDiff`/`-GitLog`/`-GitStash`/`-GitStashPop`/`-GitStashList`/
`-GitCommit`/`-GitPush`), plus `-GitHelp` (a printed cheat sheet).

```bash
./OEAdmin.ps1 -Git -UpdateRepos          # every mapped repo
./OEAdmin.ps1 -Git -UpdateRepos -App App1   # only that app's mapped repos
```

**`-UpdateRepos`** fast-forwards every worktree of each mapped repo: for each repo
under `$GitReposRoot`, it `fetch`es the bare clone, then runs
`git merge --ff-only origin/<branch>` in each worktree. Fast-forward-only means it
never creates merge commits or clobbers local work — a worktree with diverged or
uncommitted changes is simply skipped with a warning. Honors `-DryRun` (prints the
git commands, runs nothing). Optional `-App` scopes it to that app's repos (via
`$GitRepoApps`); `-App All` covers every mapped repo.

`-UpdateRepos` is also usable **with** `-Client`/`-Batch` (alongside
`-Workspace`) to refresh just the chosen working copy before launching.

**`-NewWorkspace`** creates a new git **working copy** (worktree) for one app's
repo, based on an existing branch and optionally a new branch cut from it. Rather
than a fresh full clone, it `git worktree add`s a new folder off the repo's
existing `.bare`; the folder is named after the branch (slashes → hyphens), so it
is immediately selectable as a `-Workspace`.

```bash
# New worktree on an existing branch
./OEAdmin.ps1 -Git -NewWorkspace -App App1 -BaseBranch main

# New feature branch cut off main, as its own worktree, then launch it
./OEAdmin.ps1 -Git -NewWorkspace -App App1 -BaseBranch main -NewBranch my-fix
./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Dev -Workspace my-fix
```

- `-App <name>` — **required** (a specific app/repo, not `All`).
- `-BaseBranch <b>` — existing branch to base on (menu: picked from a list; CLI:
  required).
- `-NewBranch <b>` — optional; a **new** branch of that name is cut off
  `-BaseBranch` and checked out, else `-BaseBranch` is used as-is. Names are
  validated (no `\ / : * ? " < > |`).
- `-BootstrapClone` — opt-in; see the safety note below.

It `-DryRun`-previews, and refuses up front if the target worktree folder already
exists.

**Expected git layout (CHANGE THIS for your setup).** The working-copy features
assume a **bare clone + per-branch worktree** layout: each repo lives at
`<GitReposRoot>/<Repo>/.bare`, with one worktree folder per branch beside it. If
your repos are plain clones or laid out differently, adjust `Get-WorkingCopies`
and the `AppPath` probe. `$GitRepoApps` maps a repo name to an app
(`@{App1Repo="App1"; App2Repo="App2"}`); only mapped repos are considered.

**Safety for mixed setups (important if other developers run this).** Because
these sub-actions assume the bare+worktree layout, OEAdmin guards against misuse
on a machine that uses a conventional single clone:

- **No `.bare` detected → it does not silently clone.** `-NewWorkspace` checks for
  the bare repo (`git rev-parse --is-bare-repository`). If missing, it explains the
  layout assumption and **stops without making a change**. To create a *fresh,
  separate* bare clone there, pass **`-BootstrapClone`** (CLI) or answer **yes** at
  the menu prompt — the clone comes from `$GitProjects`. Otherwise use your normal
  `git clone` if you're not on the bare+worktree layout.
- **Branch already checked out → friendly refusal.** Git allows a branch in only
  one worktree. Before `worktree add`, OEAdmin checks the repo's `worktree list`;
  if your chosen branch is already checked out elsewhere it refuses with a clear
  message (instead of git's raw `fatal: '…' is already checked out`) and suggests
  another branch or launching the existing worktree with `-Workspace`.
- **`-UpdateRepos`** simply finds no `.bare` on a non-standard machine and skips
  that repo with a warning — harmless, but it won't do anything useful there.

**Day-in-the-life git helpers.** The remaining `-Git` sub-actions wrap everyday
git for people who aren't fully comfortable on the command line. They don't
replace git — they package the common calls with friendly output (and, for the
write ones, confirmations). Each runs in **one working copy**, resolved in order:
`-Workspace <token>` → `-RepoPath <dir>` → the current directory if it's inside a
git work tree.

- **Read-only (safe, run even under `-DryRun`):**
  - `-GitStatus` — `git status -sb` + how far ahead/behind upstream + the commits
    waiting on the server (`git log HEAD..origin/<branch>`).
  - `-GitDiff` — your uncommitted changes; `-DiffVs <ref>` diffs against a ref
    (e.g. `origin/main` = "what did I change vs production").
  - `-GitLog` — pretty history (`git log --oneline --graph --decorate`).
  - `-GitStashList` — `git stash list`.
- **Stash save/restore:** `-GitStash` (`git stash push`) and `-GitStashPop`
  (`git stash pop`).
- **Guarded writes** (show what will happen, confirm unless `-Yes`, honor
  `-DryRun`, never `--force`):
  - `-GitCommit -Message "..."` — stage + commit. `-Message` is **required**;
    `-AddAll` stages everything first, else only already-staged changes. Shows
    status + the staged diff and confirms.
  - `-GitPush` — pushes the current branch; the first push auto-adds
    `-u origin <branch>` to set tracking.
- **`-GitHelp`** prints a cheat sheet of the common flow (mapped to both the
  OEAdmin sub-actions and raw git) **plus** the exact commands for what OEAdmin
  deliberately does **not** automate — `rebase` onto main, resolving conflict
  markers, `push --force-with-lease`, and plain `git switch`. Those rewrite
  history or need human judgement, so they're shown, not run.

```bash
./OEAdmin.ps1 -Git -GitStatus -Workspace my-feature
./OEAdmin.ps1 -Git -GitDiff   -Workspace my-feature -DiffVs origin/main
./OEAdmin.ps1 -Git -GitCommit -Workspace my-feature -AddAll -Message "Add validation"
./OEAdmin.ps1 -Git -GitPush   -Workspace my-feature
./OEAdmin.ps1 -Git -GitHelp
```

Run any of these from inside a working copy and you can drop `-Workspace` — it
falls back to the current directory.

### 7.11 Working copies and the per-workspace INI

When `-Workspace <token>` is given (to `-Client`/`-Batch`), the script:

1. Discovers the app's working copies with `Get-WorkingCopies` (enumerates
   `git worktree list` for each mapped repo) and matches the one whose **token**
   equals `<token>`. A token is the branch name made filename-safe (slashes →
   hyphens); it's what the menu picker shows.
2. Resolves the per-workspace INI: `<App><Env><Site>-<token>.ini` in the same
   `ini/<server>/` folder as the default INI. If that file already exists it is
   used as-is. If it doesn't, the script **copies the default INI** and rewrites
   the `PROPATH=` line, replacing the install root (the `InstallDir`) with the
   worktree's app path, leaving Progress/UNC segments alone. **The PF is never
   touched** — database connections don't change with the worktree.
3. Launches the client with its working directory set to the worktree's app path.

With `-DryRun`, the default INI is used (no file is copied or rewritten).

---

## 8. Selectors in detail

| Selector      | Values | Effect |
|---------------|--------|--------|
| `-App`        | `All` / your app names | Limit to one application. |
| `-Server`     | a hostname / `All`     | Limit to one server (defaults to this machine). |
| `-Site`       | `All` / your site codes | Limit to one site (databases only). |
| `-Env`        | `All` / `Prod` / `Dev` / `Test` / `SBox` | Limit to one environment. |
| `-OEVersion`  | `Matrix` / a version    | `Matrix` uses each instance's own version; a value limits to that version. |
| `-Component`  | `All` / `Database` / `NameServer` / `MSSQLBroker` / `OracleBroker` | Limit to one component type. |

NameServer, MSSQLBroker, and OracleBroker items are server-wide (site/env =
`All`). When you restrict by site or env, a server-wide component is kept only if
the same server+version still has a selected database, so it doesn't tag along
unexpectedly.

---

## 9. Checks and monitoring

Run automatically (each can be toggled):

- **`CheckAdminServer`** — confirms each AdminServer (DLC+port, or server+port
  under `-Remote`) is reachable before issuing commands. Unreachable targets are
  skipped.
- **`CheckPort`** — probes each selected database's **4GL broker** port (the port
  clients actually connect to, read from the servergroup in `conmgr.properties`).
  A numeric port is TCP-probed; a named service is resolved via the OS services
  file first.
- **`CheckLogErrors`** — scans each database `.lg` log, but only the portion at or
  after the **most recent startup marker**, so old history doesn't raise a false
  positive. Patterns are in `$LogErrorPatterns`; startup markers in
  `$LogStartupMarkers`.

`-RestartOnError` will restart an instance that fails status or shows a log error.

---

## 10. Notifications and logging

- **Log file** (`$LogFile`, default beside the script). Reset each run by default;
  written in ASCII to avoid BOM garbage. If the log is locked at startup, the run
  logs to a timestamped fallback file instead of crashing.
- **Email on error** (`$EmailOnError`) sends a short alert; **`-LogFileEmail`**
  (or any error) attaches the full log. Needs `$SmtpServer` + `$EmailTo`.
- **Windows EventLog** (`$EventLogger`) writes an Application-log entry on error.
  No-op on Linux.

---

## 11. Remote operation

`-Remote` lets one box act on all servers at once:

- Inventory is read from **every** install's property files over the network
  instead of only the local machine's (unreachable/denied paths are skipped
  silently).
- Every runtime path is rewritten to that server's remote form via
  `Convert-ToRemotePath`.
- `dbman`/`nsman`/`mssman` and the reachability/port probes target
  `-host <server>` instead of localhost.

As shipped, `Convert-ToRemotePath` uses the Windows UNC admin-share convention
(`\\server\drive$\path`). On Linux there is no universal equivalent, so edit that
function to match how you reach each server (NFS/autofs mount, ssh, etc.). Local
(non-Remote) operation never calls it.

With `-Remote` and no `-Server`, the script targets **all** servers.

---

## 12. Cross-platform behavior

- **Paths.** A `Join-PathX` helper builds forward-slash paths that work on both
  OSes. Defaults are Linux (`/usr/dlc`); set Windows paths in the param block if
  needed.
- **Tool extension.** `Get-OEToolPath` appends `.bat` on Windows and nothing on
  Linux, so `dbman` vs `dbman.bat` is automatic.
- **Client exe.** `Resolve-ClientLaunch` picks `prowin`/`prowin32` on Windows and
  `_progres` on Linux (adjust as needed).
- **Copy tool.** `-CopyBackup` uses `Copy-Item` (with split/retry), pushing to a
  `\\server\share` UNC path by default; change the destination-root build in
  `Invoke-CopyBackup` for a Linux mount/ssh scheme.
- **Services file.** `/etc/services` on Linux, `%windir%\System32\drivers\etc\services`
  on Windows.
- **EventLog.** Windows only; silently skipped elsewhere.

---

## 13. Full parameter reference

Logging: `-LogFile`, `-LockFile`, `-EventLogger`, `-EventSource`, `-LogFileWrite`,
`-LogFileReset`, `-LogFileEmail`.

Selectors: `-App`, `-Server`, `-Site`, `-Env`, `-OEVersion`, `-Component`.

Checks: `-CheckRunning`, `-CheckPort`, `-CheckLogErrors`, `-LogErrorPatterns`,
`-LogStartupMarkers`, `-CheckAdminServer`, `-RestartOnError`.

Settings backup: `-SettingsBackup`, `-ForceBackup`.

Actions: `-Menu`, `-Status`, `-Start`, `-Stop`, `-Restart`, `-Backup`,
`-Restore`, `-CopyBackup`, `-Client`, `-Run`, `-Batch`, `-Pgm`,
`-StartupProgram`, `-Git`.

Client tools & workspaces: `-Tool` (named entry from the `$Tools` map),
`-Workspace` (launch from a git working copy), `-Run`/`-Editor`/`-AppBuilder`/
`-Desktop`/`-Dict`/`-Admin` (aliases for `$Tools` entries).

Git (maintenance): `-Git` (action group), `-UpdateRepos` (fast-forward worktrees;
also usable with `-Client`/`-Batch` + `-Workspace`), `-NewWorkspace` (add a
worktree for a branch) with `-BaseBranch` / `-NewBranch` / `-BootstrapClone`,
`-GitReposRoot` (bare-clone/worktree root; machine-aware default), `-GitRepoApps`
(repo→app map), `-GitProjects` (repo→clone-URL map, for `-BootstrapClone`).

Git (day-in-the-life, scoped via `-Workspace` / `-RepoPath` / current dir):
`-GitStatus`, `-GitDiff` (`-DiffVs <ref>`), `-GitLog`, `-GitStash`,
`-GitStashPop`, `-GitStashList`, `-GitCommit` (`-Message`, `-AddAll`), `-GitPush`,
`-GitHelp`; `-Yes` skips the commit/push confirmation.

CopyBackup: `-Dest` (override; per-app default via `$CopyDestDefaults`),
`-BackupShareName`, `-SplitThresholdBytes`, `-SplitSliceBytes`, `-CopyMaxRetries`,
`-CopyRetryDelay`, `-AsyncCopy`, `-AsyncQueueDepth`.

Paths: `-DlcBase`, `-App1BackupDir`, `-App2BackupBase`, `-Ini`, `-Pf`, `-AddPfs`.
(The client setup-tree root is the per-install `SetupDir` in `$Installs`, not a
global parameter.)

Email: `-EmailOnError`, `-SmtpServer`, `-SmtpPort`, `-SmtpUseSsl`, `-EmailFrom`,
`-EmailTo`.

Misc: `-DryRun`, `-Remote`, `-User`, `-RestartDelay`, `-Installs`.

Every parameter has a default and can be overridden on the command line or edited
in the `param()` block.

---

## 14. Exit codes

| Code | Meaning |
|------|---------|
| `0`    | Success. |
| `2001` | A general error occurred (`OnError`). |
| `2002` | A database log error was found (`OnLogError`). |
| `2003` | A broker port was not listening (`OnPortError`). |

---

## 15. Scheduling

**Linux (cron)** — nightly production backup at 01:00:

```cron
0 1 * * *  /usr/bin/pwsh /opt/oeadmin/OEAdmin.ps1 -Backup >> /var/log/oeadmin-cron.log 2>&1
```

**Windows (Task Scheduler)** — status check every hour:

```
Program:   pwsh.exe
Arguments: -NoProfile -File "C:\OEAdmin\OEAdmin.ps1" -Status
```

Alert on non-zero exit codes to catch failures.

---

## 16. Troubleshooting

**"No matching instances for the given selectors."**
The filters excluded everything, or no install for this server has property
files. Run a bare `./OEAdmin.ps1` to see what's discovered, and check `-Server`
matches the local hostname / an `$Installs` row.

**"WARNING: no property files for … skipping"**
An install listed for *this* server has no readable
`conmgr.properties`/`ubroker.properties` at its `PropertiesDir`. Check the DLC
path and permissions.

**A database isn't showing up.**
Its name probably doesn't match your parser regex. Confirm the name in
`conmgr.properties` and adjust `Parse-App1Database`/`Parse-App2Database`.

**Broker port shows UNKNOWN or NAMED SERVICE (unresolved).**
The 4GL port in `conmgr.properties` is a service name not present in the OS
services file. Add it to services, or use a numeric port.

**AdminServer NOT REACHABLE.**
The AdminServer isn't running or the port is wrong. Start it (`proadsv -start`)
or fix the `Port` in `$Installs`.

**`-Restore` for App1 refuses to run.**
`-Site` is required for multi-site restores. Add `-Site S1` or `-Site S2`.

**`-CopyBackup` refuses to run.**
It must run **on a Production server** for the selected `-App` (the source
backups are a local path there). Run it on the production box, not dev or a
management station.

**`-CopyBackup` can't write to the dev share.**
The destination is `\\<CopyDestServer>\<BackupShareName>\...` — confirm that
named share exists on the dev server and points at its backup directory, and that
you have write access. It is deliberately not the admin `drive$` share.

**Client won't launch / INI or PF not found.**
Check the setup-tree layout (`ini/<server>/`, `userPfs/<server>/`) and the stem
(App1 `<App><Env><Site>`, App2 env word), or pass `-Ini`/`-Pf` explicitly.

**Log shows garbled characters (Windows PowerShell 5.1).**
The script writes ASCII specifically to avoid this; make sure nothing else is
appending to the log with `>>`.
