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
| `Tier`      | `Production` or `Development` — gates backup vs restore. |
| `Server`    | Hostname (matches `-Server`; compared to the local machine name). |
| `OEVersion` | OpenEdge version string (matches `-OEVersion`). |
| `DLC`       | The OpenEdge install directory for this install. |
| `Port`      | The AdminServer management port for this install. |

A single server can appear in several rows (for example, two OpenEdge versions
installed side by side on different DLC paths and ports).

### 2.2 Inventory (discovered, not listed)

At startup the script reads, for each install:

- `<DLC>/properties/conmgr.properties` → the databases the AdminServer manages,
  and each database's **4GL broker (client-connect) port**.
- `<DLC>/properties/ubroker.properties` → the **NameServer(s)** and the
  **MS SQL DataServer broker(s)**.

Each database name is passed through a **parser** to derive its role, environment,
and site. The result is a live inventory of "items", each being a Database, a
NameServer, or an MSSQLBroker.

### 2.3 Selectors and actions

- **Selectors** narrow the inventory: `-App`, `-Server`, `-Site`, `-Env`,
  `-OEVersion`, `-Component`.
- **Actions** say what to do to the selection: `-Status` (default), `-Start`,
  `-Stop`, `-Restart`, `-Backup`, `-Restore`, `-CopyBackup`, `-Client`,
  `-Batch`, and the interactive `-Menu`.

### 2.4 Tiers and the safety guard

The Production/Development tier on each install drives a safety model:

- `-Backup` runs on **Production** installs only.
- `-Restore` and `-CopyBackup` run on **Development** installs only.

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
    [PSCustomObject]@{ App="App1"; Tier="Production";  Server="dbserver1";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
    [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
    [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="10.2B"; DLC="/usr/dlc102b"; Port=20941 }
    [PSCustomObject]@{ App="App2"; Tier="Production";  Server="dbserver2";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
    [PSCustomObject]@{ App="App2"; Tier="Development"; Server="dbserver2-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
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
- `$App1BackupDir` / `$App2BackupBase` — where backups live.
- `$App1SetupDir` / `$App2SetupDir` — the INI/PF setup trees for the client.

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

### 7.5 `-Backup` (Production servers only)

Runs `probkup online <db> <device>` for each selected **Production** database in
the **Prod** environment. Non-production targets are refused by design. The backup
file path comes from `Get-BackupDevice`.

### 7.6 `-Restore` (Development servers only)

Runs `prorest` of the production backup into a selected **Dev/Test/SBox**
database, as stop → prorest → start. **`-Site` is required for a multi-site app**
(e.g. App1) so a restore can't silently fan out across sites. Single-source apps
(App2) don't need `-Site`.

### 7.7 `-CopyBackup` (Development servers only)

Copies production backup files onto the development server, scoped by `-App`. On
Windows it uses `robocopy`; on Linux it uses `rsync` (adjust in
`Invoke-CopyBackup` if you prefer another method).

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

### 7.9 `-Batch`

Same resolution as `-Client` but runs a program non-interactively:

```
<exe> -ininame <ini> -pf <pf> -p <program> -b
```

`-Pgm <program>.p` is **required**. The session runs blocking; stdout goes to
`<script dir>/<program>.out` and stderr to `<program>.err`. A non-zero exit sets
the error flag.

---

## 8. Selectors in detail

| Selector      | Values | Effect |
|---------------|--------|--------|
| `-App`        | `All` / your app names | Limit to one application. |
| `-Server`     | a hostname / `All`     | Limit to one server (defaults to this machine). |
| `-Site`       | `All` / your site codes | Limit to one site (databases only). |
| `-Env`        | `All` / `Prod` / `Dev` / `Test` / `SBox` | Limit to one environment. |
| `-OEVersion`  | `Matrix` / a version    | `Matrix` uses each instance's own version; a value limits to that version. |
| `-Component`  | `All` / `Database` / `NameServer` / `MSSQLBroker` | Limit to one component type. |

NameServer and MSSQLBroker items are server-wide (site/env = `All`). When you
restrict by site or env, a server-wide component is kept only if the same
server+version still has a selected database, so it doesn't tag along
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
- **Copy tool.** `robocopy` on Windows, `rsync` on Linux.
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
`-StartupProgram`.

Paths: `-DlcBase`, `-App1BackupDir`, `-App2BackupBase`, `-App1SetupDir`,
`-App2SetupDir`, `-Ini`, `-Pf`, `-AddPfs`.

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

**Client won't launch / INI or PF not found.**
Check the setup-tree layout (`ini/<server>/`, `userPfs/<server>/`) and the stem
(App1 `<App><Env><Site>`, App2 env word), or pass `-Ini`/`-Pf` explicitly.

**Log shows garbled characters (Windows PowerShell 5.1).**
The script writes ASCII specifically to avoid this; make sure nothing else is
appending to the log with `>>`.
