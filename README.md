# OEAdmin.ps1

A single cross-platform PowerShell script to administer **OpenEdge (Progress)**
databases, NameServers, and (optionally) MS SQL DataServer brokers across any
number of servers, sites, environments, and OpenEdge versions.

It does **status / start / stop / restart / backup / restore / copy-backup**, can
launch the Progress client (interactive or batch), scans database `.lg` logs for
errors, checks broker ports, backs up your `conmgr`/`ubroker` properties before
state changes, and can email a log/alert. It also has an interactive `-Menu` so
operators don't have to memorize switches.

Nothing about your databases is hardcoded. The managed instances are discovered
at run time from each OpenEdge install's own property files
(`conmgr.properties` + `ubroker.properties`). You describe your **servers** once
in a small table at the top of the script; the rest follows.

> This is a **template**. Every server name, app name, site, path, and email
> value in it is a placeholder. Search the file for `CHANGE THIS` and edit the
> marked spots to match your environment.

---

## Requirements

- **PowerShell**: Windows PowerShell 5.1 **or** PowerShell 7+ (`pwsh`) on
  Linux/macOS/Windows.
- **OpenEdge**: a working install (`$DLC`) whose `bin` directory contains the
  admin tools (`dbman`, `nsman`, `mssman`) and, if you back up/restore,
  `probkup`/`prorest`. The script calls them with no extension on Linux and with
  `.bat` on Windows automatically — you don't change the command names.
- Run the script **on the database server** for normal (local) operation. The
  optional `-Remote` mode can target other servers from one box (see below).

---

## Quick start

1. Copy `OEAdmin.ps1` onto the server.
2. Open it and edit the spots marked `CHANGE THIS` (see the checklist below).
   The two you can't skip are the **`$Installs` table** and the
   **database-name parsers**.
3. Verify it parses:
   ```bash
   pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./OEAdmin.ps1),[ref]$null,[ref]$null)"
   ```
4. Do a safe read-only run:
   ```bash
   ./OEAdmin.ps1              # status of everything on this server (default)
   ./OEAdmin.ps1 -Menu        # interactive menu
   ./OEAdmin.ps1 -Backup -DryRun   # preview a backup, change nothing
   ```

On Linux you may need `chmod +x OEAdmin.ps1` and to invoke it as
`pwsh ./OEAdmin.ps1 ...`.

---

## The customization checklist

Everything below is marked `CHANGE THIS` in the script. In rough priority order:

1. **`$Installs` table** — the heart of the config. One row per OpenEdge install:
   app, tier (Production/Development), server hostname, OpenEdge version, DLC
   path, and AdminServer port. A single server can have several rows (e.g. two
   OpenEdge versions side by side).
2. **`-App` ValidateSet** — your application names (keep them in sync with
   `$Installs`).
3. **`$ValidSites` / `-Site`** — your site codes (or drop sites if you have none).
4. **`Parse-App1Database` / `Parse-App2Database`** — your database **naming
   convention**. This is how the script derives each database's environment and
   site from its name, so you don't list every database by hand. Edit the regex
   and the small maps here.
5. **Path defaults** — `$DlcBase`, `$App1BackupDir` / `$App2BackupBase`,
   `$App1SetupDir` / `$App2SetupDir`.
6. **`Get-BackupDevice`** — your backup file names/layout.
7. **`Get-App2EnvStem`** — the INI/PF filename stem per environment for a
   single-site app.
8. **`Resolve-ClientLaunch`** — the client executable per OpenEdge version
   (Windows `prowin`/`prowin32`, Linux `_progres`).
9. **SMTP block** — `$SmtpServer`, `$SmtpPort`, `$EmailFrom`, `$EmailTo`.
10. **`Convert-ToRemotePath`** — only if you use `-Remote` (how to reach another
    server's paths).
11. **`$StartupProgram`** — the `-Run` startup program, if you use one.

The example ships with **two applications** so you can see a multi-app,
multi-tier, multi-version layout:

- **App1** — two databases (`app1db` + `app1aux`) per environment, on
  `dbserver1` (prod) and `dbserver1-dev` (dev, running two OpenEdge versions),
  across sites `S1`/`S2`. DB naming: `app1db|app1aux` + env + site
  (e.g. `app1dbprods1`).
- **App2** — a single database set on `dbserver2` (prod) / `dbserver2-dev` (dev),
  no sites. DB naming: `<envprefix>-<role>` (e.g. `prod-main`).

If you have only one app, delete the App2 rows from `$Installs` and the App2
parser — the rest of the script adapts.

---

## How it works (in one paragraph)

At startup the script reads each install's `conmgr.properties` (the databases and
their 4GL broker ports) and `ubroker.properties` (the NameServer and MS SQL
broker), runs each database name through the parser to learn its env/site, and
builds a live inventory. Your **selector** switches (`-App`, `-Server`, `-Site`,
`-Env`, `-OEVersion`, `-Component`) filter that inventory; your **action**
switches say what to do. Commands go through the AdminServer via `dbman` /
`nsman` / `mssman`.

---

## Common commands

```bash
# Status (default) of everything on this server
./OEAdmin.ps1

# Interactive menu — no switches to remember
./OEAdmin.ps1 -Menu

# Restart only site-S1 Production databases on dbserver1
./OEAdmin.ps1 -Server dbserver1 -Site S1 -Env Prod -Restart

# Online backup of this server's Production databases (probkup)
./OEAdmin.ps1 -Backup

# Preview anything without making changes
./OEAdmin.ps1 -Backup -DryRun

# Copy production backups onto the dev server (App1)
./OEAdmin.ps1 -CopyBackup -App App1

# Restore the site-S2 production backup into the Test databases
./OEAdmin.ps1 -Restore -App App1 -Site S2 -Env Test

# Launch the App1 client for site-S1 Test (and run the startup program)
./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test -Run

# Run a program in batch
./OEAdmin.ps1 -Batch -App App1 -Site S1 -Env Test -Pgm sh/startup.p

# See all servers from one box (needs Convert-ToRemotePath set up)
./OEAdmin.ps1 -Remote
```

---

## Safety model

- **Tier guard.** Every install is tagged Production or Development.
  `-Backup` runs on Production servers only; `-Restore` and `-CopyBackup` run on
  Development servers only. This structurally prevents an accidental prod restore
  or dev backup.
- **Required `-Site` for multi-site restores.** When an app has multiple sites
  whose prod backups stage onto one dev server, `-Restore` refuses to run without
  an explicit `-Site`, so a restore can't silently hit both sites.
- **Already-running / already-stopped are skipped**, not errored.
- **`-DryRun`** prints the exact commands that would run and changes nothing.
- **Settings backup.** Before a start/stop/restart, `conmgr.properties` and
  `ubroker.properties` are copied to `.bak`.

---

## Cross-platform notes

- Defaults use **Linux** paths (`/usr/dlc`, forward slashes) since most OpenEdge
  sites run on Linux. On Windows, set your paths (e.g. `C:/Progress/OpenEdge`)
  and it runs unchanged.
- OpenEdge tools have **no extension on Linux** (`dbman`) and are **`.bat` on
  Windows** — handled automatically.
- **`-Remote`** ships using the Windows UNC admin-share convention. For
  cross-server use on Linux, edit `Convert-ToRemotePath` to map a local path to
  however you reach that server (NFS/autofs mount, ssh, etc.). Local operation
  needs no change.
- The **EventLog** integration is Windows-only and is a no-op on Linux.

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0`    | Success |
| `2001` | A general error occurred (`OnError`) |
| `2002` | A database log error was found (`OnLogError`) |
| `2003` | A broker port was not listening (`OnPortError`) |

Useful for schedulers (cron / Task Scheduler) that alert on non-zero exit.

---

See **`OEAdmin-User-Manual.md`** for the full parameter-by-parameter reference.

## License

Provided as a template under the Apache License 2.0. Update the author/company
in the script header before publishing.
