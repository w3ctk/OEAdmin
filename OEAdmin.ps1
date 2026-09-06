<#PSScriptInfo

.VERSION 1.0.0

.AUTHOR

Your Name Here            # CHANGE THIS: script author / maintainer.

.COMPANYNAME

Your Company Here         # CHANGE THIS: your organization name.

.COPYRIGHT

Copyright 2026 Your Name Here

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

.RELEASENOTES

1.0.0 - Generic, shareable edition of OEAdmin.  A cross-platform PowerShell
        administration tool for OpenEdge databases, NameServers, and (optionally)
        MS SQL DataServer brokers, driven by each install's live property files.

        THIS IS A TEMPLATE.  All server names, application names, sites,
        environments, paths, and email settings below are PLACEHOLDERS.  Search
        the file for "CHANGE THIS" and edit the marked spots to match your
        environment.  The two most important spots are:
          1. The $Installs table (server topology) - see "INSTALL TABLE".
          2. The path defaults ($DlcBase, backup dirs, setup dirs) and the
             database NAMING CONVENTION parsers (Parse-App1Database /
             Parse-App2Database) - see "PROPERTY-FILE READERS".

#>

<#

.DESCRIPTION

OEAdmin.ps1 - a cross-platform PowerShell administration script for OpenEdge
databases.

Manages OpenEdge database brokers (via the "dbman" command through the
AdminServer), the NameServer (nsman), and optionally the MS SQL DataServer
broker (mssman), across any number of servers, sites, environments, and
OpenEdge versions.

The set of managed instances is NOT hardcoded.  It is read at run time from each
OpenEdge install's property files:
    <DLC>/properties/conmgr.properties  -> the databases the AdminServer manages
    <DLC>/properties/ubroker.properties -> the NameServer and MS SQL broker

Command-line SELECTOR parameters (-App, -Server, -Site, -Env, -OEVersion,
-Component) filter that inventory down to the instances you want, and ACTION
parameters say what to do with them.  Every setting has a sensible default and
can be overridden on the command line.

------------------------------------------------------------------------------
CROSS-PLATFORM NOTES (read this first if you are new to the script)
------------------------------------------------------------------------------
* Most OpenEdge sites run on Linux, so the DEFAULTS in this template use Linux
  paths (e.g. /usr/dlc) and forward slashes.  The script also runs on Windows
  (Windows PowerShell 5.1 or PowerShell 7+); set the paths in the param block to
  your Windows locations (e.g. C:\Progress\OpenEdge) and it works unchanged.
* OpenEdge command-line utilities have NO file extension on Linux (dbman, nsman,
  mssman, probkup, prorest) but are .bat wrappers on Windows (dbman.bat, ...).
  The helper Get-OEToolPath adds ".bat" only when running on Windows, so you do
  not edit any command names yourself.
* Path building uses a small Join-PathX helper (forward-slash friendly) instead
  of hardcoded separators, so a path works on either OS.

------------------------------------------------------------------------------
EXAMPLE ENVIRONMENT MODELLED BELOW (all placeholders - CHANGE THIS)
------------------------------------------------------------------------------
Two example applications are modelled so you can see how a multi-app, multi-tier,
multi-version site is described.  Replace them with your own:

  App1  - two databases per environment (app1db + app1aux), running on:
            dbserver1      (Production)
            dbserver1-dev  (Development; runs TWO OpenEdge versions side by side)
          Sites S1 and S2; environments Prod / Dev / Test / SBox.
          Database naming convention: "app1db" | "app1aux" + <env> + <site>
            e.g. app1dbprods1, app1auxdevs2   (see Parse-App1Database).

  App2  - a single set of databases on:
            dbserver2      (Production)
            dbserver2-dev  (Development)
          No site distinction; environments Prod / Dev / Test / SBox.
          Database naming convention: "<envprefix>-<role>"
            e.g. prod-main, dev-main   (see Parse-App2Database).

If you have only ONE application, delete the App2 rows from $Installs and the
App2 parser; the rest of the script adapts automatically.

ACTIONS:
    -Menu        Interactive drill-down: pick an action and its parameters from
                 numbered menus, review the equivalent command line, and run it
                 after a y/n confirm.  No need to know the switches.
    -Status      Report status (default action).
    -Start       Start the selected instances.  Each target is status-checked
                 first; anything already running is skipped (no dbman -start, so
                 no "already running" error).
    -Stop        Stop the selected instances.  Anything already stopped is
                 skipped (no error).
    -Restart     Stop then start the selected instances.  Waits -RestartDelay
                 seconds (default 10) between the stop and the start so lingering
                 processes finish exiting (avoids a too-quick-start failure).
    -Backup      probkup online of the selected Prod databases.
                 PRODUCTION servers only (tier guard).
    -CopyBackup  copy production backups onto the development server.  Scoped by
                 -App.  DEVELOPMENT servers only (tier guard).
    -Restore     prorest a staged production backup into the -Env Dev/Test/SBox
                 target (stop -> prorest -> start).  DEVELOPMENT servers only.
                 -Site is REQUIRED when an app has multiple sites (see below).
    -Client      Launch the Progress GUI client (prowin/prowin32) for one
                 environment.  See per-app rules under the -Client parameter.
    -Batch       Same as -Client but runs a program in batch: the command line
                 ends with "-p <program> -b".  -Pgm <program>.p is REQUIRED.

Backup / restore safety model:
    A server Tier (Production vs Development) is attached to every install.
    -Backup refuses to run on anything but a Production server; -Restore and
    -CopyBackup refuse to run on anything but a Development server.  This
    structurally prevents the atypical prod-restore / dev-backup cases.

    When an app has more than one site whose production backups all stage onto a
    single dev server, -Restore REQUIRES an explicit -Site so a restore cannot
    silently fan out across both sites.  An app with a single production source
    does not need -Site for restore.

Usage examples (all switches shown; App/Site/Env names are placeholders):
    # Interactive menu (no switches to remember)
    ./OEAdmin.ps1 -Menu

    # Status of everything on the current server (default action)
    ./OEAdmin.ps1

    # Restart only site-S1 Production databases on dbserver1
    ./OEAdmin.ps1 -Server dbserver1 -Site S1 -Env Prod -Restart

    # Stop the site-S2 Dev databases of a given OpenEdge version
    ./OEAdmin.ps1 -Site S2 -Env Dev -OEVersion 12.8 -Stop

    # Back up the Production databases on a prod server (probkup online)
    ./OEAdmin.ps1 -Backup

    # Preview (no changes made)
    ./OEAdmin.ps1 -Backup -DryRun

    # Copy production backups onto the dev server (App1 only)
    ./OEAdmin.ps1 -CopyBackup -App App1

    # Restore the site-S2 production backup into the Test databases
    ./OEAdmin.ps1 -Restore -App App1 -Site S2 -Env Test

    # Launch the App1 client for site-S1 Test
    ./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test

    # ...and run a startup program on launch
    ./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test -Run

    # Launch with an explicit ini/pf pair (bare filename is taken from the
    # standard setup subdir; a full path is accepted verbatim)
    ./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test -Ini app1TestS1.ini -Pf app1TestS1.pf

    # Add secondary PF(s) (Progress accepts multiple -pf); comma-separated list
    ./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test -AddPfs "extra.pf,more.pf"

    # Run a program in batch (out/err -> <script dir>/startup.out/.err)
    ./OEAdmin.ps1 -Batch -App App1 -Site S1 -Env Test -Pgm sh/startup.p

    # Status of ALL servers from one box, over the network (files + -host <server>)
    ./OEAdmin.ps1 -Remote

Naming conventions (parsed from the database name - CHANGE THIS to match yours):
    App1 database  = ("app1db" | "app1aux") + Env + Site  (e.g. app1dbprods1)
    Site : S1, S2      Env : Prod, Dev, Test, SBox
    App2 database  = <env-prefix>-<role>                  (e.g. prod-main)
    Env prefixes   : prod->Prod, prodcopy->ProdCopy, dv->Dev, ts->Test, sb->SBox

#>

## ============================================================================
## Script PARAMETERS
## Everything here has a default and can be overridden on the command line.
## The spots you MUST review for your own environment are marked "CHANGE THIS".
## ============================================================================
param (

    ##### ---- LOGGING ---------------------------------------------------------

    # Location of log file that contains all messages and errors.
    $LogFile="$PSScriptRoot/OEAdmin.log",

    # Location of the lock file created whenever this script is running.
    $LockFile="$PSScriptRoot/OEAdmin.lck",

    # Log to the Windows Application EventLog (Windows only; ignored on Linux).
    $EventLogger=$true,

    # Event Source Name to use in the Windows EventLog.
    $EventSource="OEAdmin",

    # Write all messages/errors to the log file as well as the screen.
    $LogFileWrite=$true,

    # Clear out the log file each time the script is run.
    $LogFileReset=$true,

    # Email the log file after the script finishes running.
    [switch]$LogFileEmail,

    ##### ---- SELECTORS (which inventory rows to act on) ----------------------

    # Application to target.  "All" (default) covers whatever app the selected
    # server hosts.  CHANGE THIS ValidateSet to your own app names (and keep them
    # in sync with the $Installs table and the parsers below).
    [ValidateSet("All","App1","App2")]
    $App="All",

    # Database server to target.  Defaults to this machine's hostname.
    # Valid values are any Server in the $Installs table, or "All".
    $Server=$env:COMPUTERNAME,

    # Site to target.  CHANGE THIS to your site codes (or set to "All" only if
    # you have no site distinction).  Example uses S1, S2, or "All".
    $Site="All",

    # Environment to target.  Valid: Prod, Dev, Test, SBox, or "All".
    $Env="All",

    # OpenEdge version filter.
    #   "Matrix" = use each instance's own version from the inventory (default)
    #   an explicit version (e.g. "12.8") = only act on instances of that version
    # CHANGE THIS ValidateSet to the OpenEdge versions you actually run.
    [ValidateSet("Matrix","10.2B","11.7","12.2","12.8","9.1E")]
    $OEVersion="Matrix",

    # Component type to target.
    # Valid: Database, NameServer, MSSQLBroker, or "All".
    $Component="All",

    ##### ---- CHECKS TO PERFORM ----------------------------------------------

    # Check the broker/process is running.
    $CheckRunning=$true,

    # Check each selected database's 4GL broker (client-connect) port is listening.
    $CheckPort=$true,

    # Scan the OpenEdge database .lg log for common error strings.
    $CheckLogErrors=$true,

    # Error strings to look for in each database .lg log (case-insensitive,
    # treated as regex).  CHANGE THIS: tune against your real logs.
    $LogErrorPatterns=@(
        "SYSTEM ERROR",
        "Fatal error",
        "died",
        "terminated abnormally",
        "SANITY CHECK",
        "broker .* no longer available",
        "\(509\)",
        "\(1183\)"
    ),

    # Startup markers used to find where the database last came up.  Only log
    # lines at/after the most recent match are scanned for errors, so old
    # history (e.g. a shutdown weeks ago) does not trigger a false positive.
    $LogStartupMarkers=@(
        "Multi-user session begin",
        "BROKER\s+0: Started",
        "Database connections have been enabled",
        "\(333\)",
        "\(4234\)"
    ),

    # Confirm the AdminServer itself is reachable before issuing commands.
    $CheckAdminServer=$true,

    # Restart an instance automatically if a check above fails.
    [switch]$RestartOnError,

    ##### ---- SETTINGS BACKUP -------------------------------------------------

    # Backup conmgr.properties / ubroker.properties before a state-changing action.
    $SettingsBackup=$true,

    # Force the backup even when a .bak already exists.
    [switch]$ForceBackup,

    ##### ---- ACTIONS TO PERFORM ---------------------------------------------

    # Interactive drill-down menu.  Overrides the default -Status.
    [switch]$Menu,

    # Report status of the selected instances (default action).
    $Status=$true,

    # Start the selected instances.
    [switch]$Start,

    # Stop the selected instances.
    [switch]$Stop,

    # Restart (stop then start) the selected instances.
    [switch]$Restart,

    # Backup the selected Prod databases (probkup online). PRODUCTION SERVERS ONLY.
    [switch]$Backup,

    # Restore the production backup into the selected Dev/Test/SBox databases
    # (prorest). DEVELOPMENT SERVERS ONLY. Choose the target with -Env, and for a
    # multi-site app the required -Site picks which production backup to restore.
    [switch]$Restore,

    # Copy production backup files to the development server. DEVELOPMENT SERVERS ONLY.
    [switch]$CopyBackup,

    # Launch the Progress GUI client (prowin/prowin32) for one environment.
    #   Multi-site app: requires -Site and a single -Env; INI/PF share the
    #        <App><Env><Site> stem (e.g. app1DevS2.ini + app1DevS2.pf).
    #   Single-site app: no site; requires a single -Env; INI/PF stem is the env
    #        word (see Get-App2EnvStem).  Prod/ProdCopy are refused (dev-side tool).
    # The exe is chosen by the target's OpenEdge version (see Resolve-ClientLaunch).
    # Command line (all options space-separated):
    #   <exe> -ininame <ini> -pf <pf> [ -p <startup program> ]
    [switch]$Client,

    # When set with -Client, append "-p <StartupProgram>" (see $StartupProgram)
    # so the session runs a startup program on launch.
    [switch]$Run,

    # -Batch: run the Progress client in BATCH (non-interactive) mode.  Same rules
    # as -Client but the command line ends with "-p <program> -b", and the session
    # runs blocking with its output captured to files (see -Pgm).
    [switch]$Batch,

    # The program -Batch runs (the "-p" value), e.g. -Pgm sh/startup.p.  Required
    # for -Batch.  Standard output goes to <script dir>/<program>.out and standard
    # error to <program>.err (program base name, path/extension stripped).
    $Pgm="",

    # The startup program appended by -Run (and the menu's "run startup?" prompt).
    # CHANGE THIS to your own startup .p if you use one.
    $StartupProgram="sh/startup.p",

    ##### ---- PATH DEFAULTS  (CHANGE THIS for your environment) ---------------
    #
    # DLC base.  Most Linux OpenEdge installs live under /usr/dlc.  If you run
    # several OpenEdge versions, each install points at its own DLC in the
    # $Installs table below; this value is only a convenient default you can
    # reference.  On Windows set your install path, e.g. "C:/Progress/OpenEdge".
    $DlcBase="/usr/dlc",

    ##### ---- BACKUP LOCATIONS  (CHANGE THIS) ---------------------------------
    # App1 backups: <App1BackupDir>/<Role><Prod><Site>.bk  (e.g. app1dbProdS1.bk)
    $App1BackupDir="/opt/app1/backups",
    # App2 backups: <App2BackupBase>/<subdir>/<file>.bk
    $App2BackupBase="/opt/app2/backups",

    ##### ---- CLIENT (-Client) SETUP LOCATIONS  (CHANGE THIS) -----------------
    # Setup trees hold the INI + PF files, laid out as:
    #   <SetupDir>/ini/<server>/<stem>.ini
    #   <SetupDir>/userPfs/<server>/<stem>.pf
    # For App1 the stem is <App><Env><Site> (e.g. app1TestS1); for App2 it is the
    # env word (see Get-App2EnvStem).
    $App1SetupDir="/opt/app1/setup",
    $App2SetupDir="/opt/app2/setup",

    # Optional explicit overrides for -Client / -Batch.  Pass just the FILENAME
    # (e.g. "app1TestS1.ini"); it is assumed to live in the standard setup
    # subdirectory for the target's app/server.  A value containing a path
    # separator is used verbatim instead (must exist).
    $Ini="",
    $Pf="",

    # Optional SECONDARY PF file(s) for -Client / -Batch.  Progress accepts
    # multiple "-pf <file>" options; each entry here is appended as its own extra
    # "-pf" after the primary PF.  Accepts a comma-separated list
    # (e.g. -AddPfs "extra.pf,more.pf").  Same filename-or-path rule as -Pf.
    [string[]]$AddPfs=@(),

    ##### ---- MISC ------------------------------------------------------------

    # Email on error notifications.
    $EmailOnError=$true,

    ##### ---- EMAIL / SMTP  (CHANGE THIS - all placeholders) ------------------
    # Point these at your own mail relay.  The example assumes an internal relay
    # with no auth and no SSL on port 25; adjust as needed.
    $SmtpServer="smtp.example.com",         # CHANGE THIS
    $SmtpPort=25,                            # CHANGE THIS if not 25
    [switch]$SmtpUseSsl,                     # add -SmtpUseSsl if your relay needs it
    # From defaults to "<hostname>@example.com"; To must be set to receive alerts.
    $EmailFrom="$($env:COMPUTERNAME)@example.com",   # CHANGE THIS domain
    $EmailTo="admin@example.com",                     # CHANGE THIS recipient

    # Show the exact dbman/nsman/mssman commands that WOULD run, without
    # executing them.  Useful for testing off-box and for a safe preview.
    [switch]$DryRun,

    # Act on ANY server from one box (default off = local only).  With -Remote:
    #   * inventory is read from EVERY install's property files over the network
    #     share instead of only the local machine's, so one run can see all
    #     servers.  File failures (missing / no permission / unreachable) are
    #     ignored silently.
    #   * every path used at runtime is rewritten to that server's network form
    #     (see Convert-ToRemotePath - CHANGE THIS to match your share layout).
    #   * dbman/nsman/mssman and the reachability/broker-port probes target
    #     "-host <server>" instead of localhost.
    # Without -Remote the script behaves exactly as before (localhost only).
    #
    # NOTE: -Remote as shipped uses the Windows UNC admin-share convention
    # (\\server\drive$\path).  On Linux there is no single universal equivalent,
    # so if you want cross-server operation on Linux, edit Convert-ToRemotePath
    # to map a local path to however you reach that server (NFS mount, autofs,
    # ssh, etc.).  Local (non-Remote) operation needs no such change.
    [switch]$Remote,

    # Optional AdminServer user.  When set, "-user <User>" is added to every
    # dbman/nsman/mssman command.  Leave blank to omit (default).
    $User="",

    # Seconds to wait between the -stop and -start halves of a -Restart, so
    # lingering processes from the stopped instance finish exiting before the
    # start.  Default 10; set 0 to disable.
    [int]$RestartDelay=10,

    ##### ---- INSTALL TABLE  (CHANGE THIS - the heart of the config) ----------
    # The ONE place server topology is defined.  Each row is one OpenEdge install:
    #   App       - which application this install hosts (matches -App / ValidateSet)
    #   Tier      - "Production" or "Development" (gates Backup vs Restore/CopyBackup)
    #   Server    - the hostname (matches -Server; compared to $env:COMPUTERNAME)
    #   OEVersion - the OpenEdge version string (matches -OEVersion)
    #   DLC       - the OpenEdge install directory for THIS install
    #   Port      - the AdminServer management port for THIS install
    #
    # A single server can host MULTIPLE installs (e.g. two OpenEdge versions side
    # by side on different DLCs and ports) - just add a row for each.
    #
    # The databases/NameServers/brokers themselves are NOT listed here; they are
    # discovered from each install's property files at run time.
    $Installs=@(
        # ---- App1: prod on dbserver1, dev on dbserver1-dev (two OE versions) ----
        [PSCustomObject]@{ App="App1"; Tier="Production";  Server="dbserver1";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
        [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
        [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="10.2B"; DLC="/usr/dlc102b"; Port=20941 }
        # ---- App2: prod on dbserver2, dev on dbserver2-dev ----------------------
        [PSCustomObject]@{ App="App2"; Tier="Production";  Server="dbserver2";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
        [PSCustomObject]@{ App="App2"; Tier="Development"; Server="dbserver2-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931 }
    )
)

## ============================================================================
## VARIOUS SETTINGS
## ============================================================================

# Seconds to wait after start/stop before re-checking.
$SleepAfterStart = 15
$SleepAfterStop  = 5

# Error state flags.
$OnError    = $false
$OnLogError = $false
$OnPortError= $false

# True when running on Windows (works in both Windows PowerShell 5.1 and pwsh 7).
# On PowerShell 7+ the automatic $IsWindows exists; on 5.1 it does not, so we
# fall back to the OS env var.  Used to decide tool extension (.bat) and EventLog.
$IsWindowsHost = if ($null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) { $IsWindows } else { ($env:OS -eq 'Windows_NT') }

# Recognized environments and sites.  CHANGE THIS to your own site codes.
# Anything outside these sets is treated as QA/template/unknown and ignored.
$ValidEnvs  = @("Prod","Dev","Test","SBox")
$ValidSites = @("S1","S2")

# ---------------------------------------------------------------------------
# Path helpers (cross-platform).
# ---------------------------------------------------------------------------

# Join path parts with a forward slash, trimming stray separators.  Used instead
# of Join-Path so results are consistent on Linux and Windows and a Windows drive
# path (C:/...) is never misread as a PSDrive when the script is edited off-box.
function Join-PathX {
    param([Parameter(ValueFromRemainingArguments=$true)] $Parts)
    $clean = foreach ($p in $Parts) {
        if ($null -eq $p) { continue }
        ([string]$p).Trim() -replace '[\\/]+$',''   # drop trailing slashes
    }
    return ($clean -join '/')
}

# Return the full path of an OpenEdge command-line tool for an install.  On
# Windows the tools are .bat wrappers; on Linux they have no extension.  So
# Get-OEToolPath <DLC> "dbman" -> "<DLC>/bin/dbman.bat" on Windows,
#                              -> "<DLC>/bin/dbman"     on Linux.
function Get-OEToolPath {
    param($DLC, $Tool)
    $ext = if ($IsWindowsHost) { ".bat" } else { "" }
    return (Join-PathX $DLC "bin" ("$Tool$ext"))
}

# Convert a local path to the form used to reach it on another server under
# -Remote.  The shipped implementation uses the WINDOWS UNC admin share
# (\\server\drive$\path), e.g. ("dbserver1","G:/backups") -> \\dbserver1\G$\backups.
#
# CHANGE THIS for Linux/remote operation: map a local path to however you reach
# that server (an NFS/autofs mount point, an ssh target, etc.).  A path that is
# not a "<drive>:/..." local path is returned unchanged.  Local (non-Remote)
# operation never calls this, so you only need it if you use -Remote.
function Convert-ToRemotePath {
    param($Server, $LocalPath)
    if ($LocalPath -match '^([A-Za-z]):[\\/](.*)$') {
        return "\\$Server\$($Matches[1])`$\$($Matches[2])"
    }
    return $LocalPath
}

## ============================================================================
## INSTALL TABLE POST-PROCESSING
## ============================================================================
# $Installs is defined as a parameter (see param block).  Give each install its
# properties directory if the caller did not supply one.  PropertiesDir defaults
# to "<DLC>/properties" but can be set explicitly (e.g. off-box testing).
foreach ($i in $Installs) {
    if (-not $i.PSObject.Properties['PropertiesDir']) {
        $propsLocal = Join-PathX $i.DLC "properties"
        $propsPath  = if ($Remote -eq $true) { Convert-ToRemotePath -Server $i.Server -LocalPath $propsLocal } else { $propsLocal }
        $i | Add-Member -NotePropertyName PropertiesDir -NotePropertyValue $propsPath
    }
}

## ============================================================================
## PROPERTY-FILE READERS
## ============================================================================

# Return the databases the AdminServer manages, from conmgr.properties, as
# objects of { Name; DatabaseName } where DatabaseName is the full db path
# (its ".lg" log lives alongside it as "<DatabaseName>.lg").
function Get-ManagedDatabases {
    param([parameter(Mandatory=$true)] $PropertiesDir)
    $file = Join-PathX $PropertiesDir "conmgr.properties"
    if (-not (Test-Path -Path $file -PathType Leaf)) { return @() }
    $dbs = New-Object System.Collections.Generic.List[object]
    $cur = $null
    switch -regex -file $file {
        '^\[database\.(.+)\]\s*$' {
            if ($cur) { $dbs.Add($cur) }
            $cur = [PSCustomObject]@{ Name=$matches[1]; DatabaseName=$null }
        }
        '^\s*databasename\s*=\s*(.+?)\s*$' {
            if ($cur) { $cur.DatabaseName = $matches[1] }
        }
        '^\[(?!database\.)' {          # left the [database.*] region
            if ($cur) { $dbs.Add($cur); $cur = $null }
        }
    }
    if ($cur) { $dbs.Add($cur) }
    return $dbs
}

# Return names of sections of a given type from ubroker.properties.
# e.g. -Prefix 'NameServer'   matches [NameServer.NS1]         -> NS1
#      -Prefix 'UBroker.MS'   matches [UBroker.MS.mssbroker1]  -> mssbroker1
function Get-BrokerNames {
    param(
        [parameter(Mandatory=$true)] $PropertiesDir,
        [parameter(Mandatory=$true)] $Prefix
    )
    $file = Join-PathX $PropertiesDir "ubroker.properties"
    if (-not (Test-Path -Path $file -PathType Leaf)) { return @() }
    $escaped = [Regex]::Escape($Prefix)
    Select-String -Path $file -Pattern "^\[$escaped\.([^\.\]]+)\]$" |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
}

# Return a hashtable of { <database-name> = <4GL broker port> } from
# conmgr.properties.  The client-connect port an ABL/4GL client actually talks to
# lives on the database's 4GL server group, NOT on the [database.*] or
# [configuration.*] section:
#     [servergroup.<db>.<config>.<name>]
#         configuration=<db>.<config>
#         port=41100          <- the listening port
#         type=4gl            <- 4GL group (vs type=sql, a separate SQL port)
# We want the group carrying the 4GL listener.  That group's TYPE is either "4gl"
# (a dedicated 4GL group) or "both" (a combined 4GL+SQL group); a "sql"-only group
# is skipped.  The group NAME varies by OE version and site convention, so we key
# off type, not the section name.  When a db has BOTH a dedicated 4gl group and a
# combined "both" group, prefer the dedicated 4gl one.
# The value may be numeric (e.g. 41100) or a service NAME that resolves via the
# OS services file - we return whatever is there; the caller decides whether it
# can do a numeric TCP probe.  The database is matched to its group via the
# group's configuration= line (<db>.<config>) - we take the <db> part before the
# first dot so it lines up with [database.<db>].
function Get-BrokerPorts {
    param([parameter(Mandatory=$true)] $PropertiesDir)
    $file = Join-PathX $PropertiesDir "conmgr.properties"
    $ports = @{}   # db -> port      (best pick so far)
    $isS4gl = @{}  # db -> $true if the recorded port came from a dedicated 4gl group
    if (-not (Test-Path -Path $file -PathType Leaf)) { return $ports }
    $curDb = $null; $curPort = $null; $curType = $null
    # flush the current [servergroup.*] block into the map if it carries 4GL.
    $flush = {
        if ($curDb -and $curPort -and ($curType -eq "4gl" -or $curType -eq "both")) {
            $dedicated = ($curType -eq "4gl")
            if (-not $ports.ContainsKey($curDb) -or ($dedicated -and -not $isS4gl[$curDb])) {
                $ports[$curDb]  = $curPort
                $isS4gl[$curDb] = $dedicated
            }
        }
    }
    switch -regex -file $file {
        '^\[servergroup\.(.+)\]\s*$' {
            & $flush
            $curDb = $null; $curPort = $null; $curType = $null
        }
        '^\s*configuration\s*=\s*(.+?)\s*$' {
            $curDb = ($matches[1] -split '\.')[0].ToLower()
        }
        '^\s*port\s*=\s*(.+?)\s*$' {
            $curPort = $matches[1]
        }
        '^\s*type\s*=\s*(.+?)\s*$' {
            $curType = $matches[1].ToLower()
        }
        '^\[(?!servergroup\.)' {   # left the [servergroup.*] region entirely
            & $flush
            $curDb = $null; $curPort = $null; $curType = $null
        }
    }
    & $flush   # last section in the file
    return $ports
}

## ============================================================================
## DATABASE-NAME PARSERS  (CHANGE THIS to match YOUR naming conventions)
## ----------------------------------------------------------------------------
## These turn a raw database name (as it appears in conmgr.properties) into its
## Role / Env / Site.  This is how the script knows a db's environment and site
## WITHOUT you listing every database by hand.  If your databases are named
## differently, edit the regex and the maps here - this is the single place the
## naming convention lives.  A name that does not match returns $null and is
## silently ignored (so QA/scratch/template dbs are skipped automatically).
## ============================================================================

# App1: names are ("app1db" | "app1aux") + <env> + <site>, e.g. "app1dbprods1".
# Role is which of the two databases; Env/Site come from the suffixes.
function Parse-App1Database {
    param([parameter(Mandatory=$true)] $DBName)
    if ($DBName -match '^(?i)(app1db|app1aux)(prod|dev|test|sbox)(s1|s2)$') {
        $role = if ($Matches[1].ToLower() -eq "app1db") { "App1Db" } else { "App1Aux" }
        $env  = (Get-Culture).TextInfo.ToTitleCase($Matches[2].ToLower())  # Prod/Dev/Test/Sbox
        if ($env -eq "Sbox") { $env = "SBox" }
        return [PSCustomObject]@{
            Role = $role
            Env  = $env
            Site = $Matches[3].ToUpper()
        }
    }
    return $null
}

# App2: names are "<envprefix>-<role>", e.g. "prod-main" / "dev-main".  No site,
# so Site is "All".  CHANGE THIS role set + env-prefix map to match yours.
function Parse-App2Database {
    param([parameter(Mandatory=$true)] $DBName)
    if ($DBName -match '^(?i)(prod|prodcopy|dv|ts|sb)-(main|aux|report)$') {
        $envMap = @{ prod="Prod"; prodcopy="ProdCopy"; dv="Dev"; ts="Test"; sb="SBox" }
        return [PSCustomObject]@{
            Role = (Get-Culture).TextInfo.ToTitleCase($Matches[2].ToLower())  # Main/Aux/Report
            Env  = $envMap[$Matches[1].ToLower()]
            Site = "All"
        }
    }
    return $null
}

# Dispatch database-name parsing to the right app parser.  Add a case here for
# each app in your $Installs table.
function Parse-Database {
    param($App, $DBName)
    switch ($App) {
        "App1" { return Parse-App1Database -DBName $DBName }
        "App2" { return Parse-App2Database -DBName $DBName }
    }
    return $null
}

## ============================================================================
## BUILD INVENTORY  (databases + NameServer + MS SQL broker, from live config)
## ============================================================================
function Build-Inventory {
    $items = New-Object System.Collections.Generic.List[object]

    foreach ($install in $Installs) {

        # Locally (default), property files are read from THIS machine's filesystem
        # (every command runs against -host localhost), so only installs hosted on
        # this server can be inventoried; an install for another server legitimately
        # has no local files and is skipped silently, and we warn (red) only when an
        # install that IS for this server is missing its files.  With -Remote the
        # files are pulled from EVERY server, so a missing/unreachable/denied path is
        # expected for some servers and is skipped silently (no warning).
        $conmgrFile  = Join-PathX $install.PropertiesDir "conmgr.properties"
        $ubrokerFile = Join-PathX $install.PropertiesDir "ubroker.properties"
        if (-not (Test-Path -Path $conmgrFile -PathType Leaf) -and
            -not (Test-Path -Path $ubrokerFile -PathType Leaf)) {
            if ($Remote -ne $true -and $install.Server -eq $env:COMPUTERNAME) {
                Write-Message ("  WARNING: no property files for {0} {1} at {2} - skipping" -f `
                    $install.Server, $install.OEVersion, $install.PropertiesDir) -Fore Red
            }
            continue
        }

        # Under -Remote, DLC (exe location) and each db path resolve on the install's
        # own server; locally they stay as the plain path.
        $itemDLC = if ($Remote -eq $true) { Convert-ToRemotePath -Server $install.Server -LocalPath $install.DLC } else { $install.DLC }

        # ---- Databases (dbman) ----
        # Broker (4GL client-connect) ports, keyed by lowercase db name.
        $brokerPorts = Get-BrokerPorts -PropertiesDir $install.PropertiesDir
        foreach ($db in (Get-ManagedDatabases -PropertiesDir $install.PropertiesDir)) {
            $parsed = Parse-Database -App $install.App -DBName $db.Name
            if ($null -eq $parsed) { continue }   # skip anything outside the app's managed set
            # NB: use $dbLogFile, NOT $logFile.  PowerShell variable names are
            # case-insensitive, so a local "$logFile" is the SAME variable as the
            # global "$LogFile" (the script's own log path).  A distinct name avoids
            # accidentally redirecting Write-Message into a database .lg file.
            $dbPath    = if ($Remote -eq $true -and $db.DatabaseName) { Convert-ToRemotePath -Server $install.Server -LocalPath $db.DatabaseName } else { $db.DatabaseName }
            $dbLogFile = if ($dbPath) { "$dbPath.lg" } else { $null }
            $items.Add([PSCustomObject]@{
                Component = "Database"
                App       = $install.App
                Tier      = $install.Tier
                Role      = $parsed.Role
                Server    = $install.Server
                Site      = $parsed.Site
                Env       = $parsed.Env
                OEVersion = $install.OEVersion
                Name      = $db.Name
                DbPath    = $dbPath                # physical db path (for probkup/prorest)
                Port      = $install.Port          # AdminServer port (management)
                BrokerPort= $brokerPorts[$db.Name.ToLower()]  # 4GL client-connect port (may be $null / a service name)
                Manager   = "dbman"
                DLC       = $itemDLC
                LogFile   = $dbLogFile
            })
        }

        # ---- NameServer (nsman) ----
        foreach ($ns in (Get-BrokerNames -PropertiesDir $install.PropertiesDir -Prefix "NameServer")) {
            $items.Add([PSCustomObject]@{
                Component = "NameServer"
                App       = $install.App
                Tier      = $install.Tier
                Role      = "NameServer"
                Server    = $install.Server
                Site      = "All"
                Env       = "All"
                OEVersion = $install.OEVersion
                Name      = $ns
                Port      = $install.Port
                Manager   = "nsman"
                DLC       = $itemDLC
            })
        }

        # ---- MS SQL DataServer broker (mssman) ----
        # If you do NOT use the MS SQL DataServer, these simply won't be found in
        # ubroker.properties and nothing is added - no change needed.
        foreach ($ms in (Get-BrokerNames -PropertiesDir $install.PropertiesDir -Prefix "UBroker.MS")) {
            $items.Add([PSCustomObject]@{
                Component = "MSSQLBroker"
                App       = $install.App
                Tier      = $install.Tier
                Role      = "MSSQLBroker"
                Server    = $install.Server
                Site      = "All"
                Env       = "All"
                OEVersion = $install.OEVersion
                Name      = $ms
                Port      = $install.Port
                Manager   = "mssman"
                DLC       = $itemDLC
            })
        }
    }
    return $items
}

## ============================================================================
## SELECTOR FILTER  (apply -Server/-Site/-Env/-Component/-OEVersion)
## ============================================================================
function Select-Inventory {
    param([parameter(Mandatory=$true)] $Inventory)
    $matched = @($Inventory | Where-Object {
        ($App       -eq "All" -or $_.App       -eq $App)       -and
        ($Server    -eq "All" -or $_.Server    -eq $Server)    -and
        ($Component -eq "All" -or $_.Component  -eq $Component) -and
        ($OEVersion -eq "Matrix" -or $_.OEVersion -eq $OEVersion) -and
        # Site/Env only constrain Database rows; NS/MSSQL are server-wide ("All")
        ($_.Site -eq "All" -or $Site -eq "All" -or $_.Site -eq $Site) -and
        ($_.Env  -eq "All" -or $Env  -eq "All" -or $_.Env  -eq $Env)
    })

    # NameServer/MSSQLBroker rows are server-wide (Site=Env="All"), so a Site/Env
    # restriction never removes them - they'd tag along even when the selected
    # databases are all in a different OEVersion. Keep a server-wide component only
    # if the SAME (Server, OEVersion) has a selected Database.  (Only prune when
    # Site or Env is actually restricting; with both "All" the server-wide
    # components are legitimately wanted.)
    if ($Site -ne "All" -or $Env -ne "All") {
        $dbKeys = @($matched | Where-Object Component -eq "Database" |
                        ForEach-Object { "{0}|{1}" -f $_.Server, $_.OEVersion }) | Select-Object -Unique
        $matched = @($matched | Where-Object {
            $_.Component -eq "Database" -or
            $dbKeys -contains ("{0}|{1}" -f $_.Server, $_.OEVersion)
        })
    }
    $matched
}

## ============================================================================
## OUTPUT / LOGGING
## ============================================================================

# Write a message to the screen and (when enabled) append it to the log file.
# Use $script:LogFile explicitly so the logger always targets OEAdmin's own log.
function Write-Message {
    param($Message, $Fore="Gray")
    # Add-Content -Encoding ascii (not '>>'): in Windows PowerShell 5.1 the '>>'
    # redirection writes UTF-16LE + a BOM, which shows up as garbled bytes at the
    # head of the log.  ASCII keeps it plain text.  -ErrorAction SilentlyContinue:
    # if the log is briefly locked mid-run, drop that one line quietly rather than
    # throwing on every write (the screen output below still shows the message).
    if ($LogFileWrite -eq $true) { Add-Content -Path $script:LogFile -Value $Message -Encoding ascii -ErrorAction SilentlyContinue }
    Write-Host $Message -ForegroundColor $Fore
}

# Write a magenta section banner, padded to a fixed width.
function Write-Section {
    param($Title)
    $line = "========= $Title "
    if ($line.Length -lt 58) { $line = $line.PadRight(58, '=') }
    Write-Message $line -Fore Magenta
}

## ============================================================================
## LOW-LEVEL HELPERS
## ============================================================================

# Test whether a TCP port is accepting connections (AdminServer reachability).
function Test-TcpPort {
    param($ComputerName="localhost", [int]$Port, [int]$TimeoutMs=2000)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $client.EndConnect($iar); $client.Close(); return $true
        }
        $client.Close(); return $false
    } catch { return $false }
}

# A conmgr broker "port" may be a numeric port OR a service NAME that the OS
# resolves via its services file at connect time.  Resolve a service name to its
# numeric TCP port by reading the LOCAL services file.  The file lives at
# %windir%\System32\drivers\etc\services on Windows and /etc/services on Linux.
# Returns the numeric port as [int], or 0 if it can't be resolved.
function Resolve-ServicePort {
    param([parameter(Mandatory=$true)] $PortValue)
    $n = 0
    if ([int]::TryParse([string]$PortValue, [ref]$n)) { return $n }   # already numeric
    $svcFile = if ($IsWindowsHost) { Join-Path $env:windir "System32\drivers\etc\services" } else { "/etc/services" }
    if (-not (Test-Path -Path $svcFile -PathType Leaf)) { return 0 }
    $name = ([string]$PortValue).Trim()
    # services lines: "<name>  <port>/<proto>  [aliases...]"  (# starts a comment)
    foreach ($line in (Get-Content -Path $svcFile)) {
        $l = $line.Trim()
        if ($l -eq "" -or $l.StartsWith("#")) { continue }
        $cols = $l -split '\s+'
        if ($cols.Count -lt 2) { continue }
        if ($cols[0] -ieq $name) {
            $p = ($cols[1] -split '/')[0]
            if ([int]::TryParse($p, [ref]$n)) { return $n }
        }
    }
    return 0
}

# Build the argument list for an instance + action flag (-query/-start/-stop).
# dbman uses -database <name>; nsman/mssman use -name <name>.  Host and port are
# always included; -user is added only when the -User parameter is set.
function Get-InstanceArgs {
    param($Item, $ActionFlag)
    # -Remote targets the instance's own AdminServer by name; otherwise localhost.
    $hostName = if ($Remote -eq $true) { $Item.Server } else { "localhost" }
    if ($Item.Component -eq "Database") {
        $a = @("-host",$hostName,"-port","$($Item.Port)","-database",$Item.Name,$ActionFlag)
    } else {
        $a = @("-host",$hostName,"-port","$($Item.Port)","-name",$Item.Name,$ActionFlag)
    }
    if (-not [string]::IsNullOrWhiteSpace($User)) { $a += @("-user",$User) }
    return $a
}

# Invoke an OpenEdge admin utility (dbman/nsman/mssman) from the correct DLC.
# In -DryRun mode it prints the command instead of running it.
function Invoke-OECommand {
    param($Item, $ActionFlag)
    $exe  = Get-OEToolPath $Item.DLC $Item.Manager
    $args = Get-InstanceArgs -Item $Item -ActionFlag $ActionFlag
    $display = "$exe " + ($args -join ' ')
    if ($DryRun -eq $true) {
        Write-Message "  [DRYRUN] DLC=$($Item.DLC)  $($Item.Manager) $($args -join ' ')" -Fore DarkGray
        return [PSCustomObject]@{ ExitCode=0; Output="[dry-run]"; Command=$display }
    }
    $prevDLC = $env:DLC
    $env:DLC = $Item.DLC
    try {
        $out  = & $exe @args 2>&1 | Out-String
        $code = $LASTEXITCODE
    } catch {
        $out = $_.Exception.Message; $code = -1
    } finally {
        $env:DLC = $prevDLC
    }
    return [PSCustomObject]@{ ExitCode=$code; Output=$out.Trim(); Command=$display }
}

# Determine "is it running" from a -query result, per component, matching the
# typical OpenEdge output wording:
#   dbman  -> "database is running: Running"
#   nsman  -> "NameServer <name> running on Host ..."
#   mssman -> "Broker Status : ACTIVE"
# CHANGE THIS only if your OpenEdge version phrases these differently.
function Test-InstanceRunning {
    param($Item, $QueryResult)
    if ($DryRun -eq $true) { return $null }         # unknown in dry-run
    $o = $QueryResult.Output
    if ([string]::IsNullOrWhiteSpace($o)) { return $false }
    switch ($Item.Component) {
        "Database" {
            if ($o -match '(?im)database is running:\s*Running') { return $true }
            if ($o -match '(?im)database is running:\s*Not')     { return $false }
            if ($o -match '(?i)no such database|not running|does not exist') { return $false }
        }
        "NameServer" {
            if ($o -match '(?im)NameServer\s+\S+\s+running on')  { return $true }
            if ($o -match '(?i)not running|could not|no such|not found') { return $false }
        }
        "MSSQLBroker" {
            if ($o -match '(?im)Broker Status\s*:\s*ACTIVE')     { return $true }
            if ($o -match '(?im)Broker Status\s*:\s*(INACTIVE|STOPPED|DISABLED)') { return $false }
            if ($o -match '(?i)not running|no such|not found')   { return $false }
        }
    }
    return $null
}

## ============================================================================
## PER-INSTANCE ACTIONS
## ============================================================================

$Label = { param($i) "{0,-16} {1,-6} {2,-11} {3}" -f $i.Server,$i.OEVersion,$i.Component,$i.Name }

function Do-Query {
    param($Item)
    $r = Invoke-OECommand -Item $Item -ActionFlag "-query"
    $running = Test-InstanceRunning -Item $Item -QueryResult $r
    $state = if ($running -eq $true) { "RUNNING" } elseif ($running -eq $false) { "NOT RUNNING" } else { "UNKNOWN" }
    $fore  = if ($running -eq $true) { "Green" } elseif ($running -eq $false) { "Red" } else { "Yellow" }
    Write-Message ("Status: {0,-50} {1}" -f (& $Label $Item), $state) -Fore $fore
    return $running
}

function Do-Stop {
    param($Item)
    Write-Message ("Stop:   {0}" -f (& $Label $Item)) -Fore Yellow
    # Pre-stop status check: dbman/nsman/mssman -stop errors out if the instance
    # is already down.  Query first and skip if not running, so a -Stop on an
    # already-stopped set doesn't spew errors or send error email.
    if ($DryRun -ne $true) {
        $pre = Invoke-OECommand -Item $Item -ActionFlag "-query"
        if ((Test-InstanceRunning -Item $Item -QueryResult $pre) -eq $false) {
            Write-Message ("  not running - skipping stop") -Fore Yellow
            Write-Message ("Status: {0,-50} {1}" -f (& $Label $Item), "NOT RUNNING") -Fore Yellow
            return
        }
    }
    $r = Invoke-OECommand -Item $Item -ActionFlag "-stop"
    if ($r.ExitCode -ne 0 -and $DryRun -ne $true) {
        Write-Message ("  ERROR (exit $($r.ExitCode)): $($r.Output)") -Fore Red
        $script:OnError = $true
    }
    if ($DryRun -ne $true) { Start-Sleep -Seconds $SleepAfterStop }
}

function Do-Start {
    param($Item)
    Write-Message ("Start:  {0}" -f (& $Label $Item)) -Fore Green
    # Pre-start status check: dbman/nsman/mssman -start errors out if the instance
    # is already running.  Query first and skip if already active, so a re-run of
    # -Start on a live set doesn't spew errors or send error email.
    if ($DryRun -ne $true) {
        $pre = Invoke-OECommand -Item $Item -ActionFlag "-query"
        if ((Test-InstanceRunning -Item $Item -QueryResult $pre) -eq $true) {
            Write-Message ("  already running - skipping start") -Fore Yellow
            Write-Message ("Status: {0,-50} {1}" -f (& $Label $Item), "RUNNING") -Fore Green
            return
        }
    }
    $r = Invoke-OECommand -Item $Item -ActionFlag "-start"
    if ($r.ExitCode -ne 0 -and $DryRun -ne $true) {
        Write-Message ("  ERROR (exit $($r.ExitCode)): $($r.Output)") -Fore Red
        $script:OnError = $true
    }
    if ($DryRun -ne $true) { Start-Sleep -Seconds $SleepAfterStart }
    Do-Query -Item $Item | Out-Null
}

function Do-Restart {
    param($Item)
    Write-Message ("Restart: {0}" -f (& $Label $Item)) -Fore Cyan
    Do-Stop  -Item $Item
    # Wait between stop and start so lingering processes from the stopped instance
    # finish exiting; a too-quick -start otherwise fails.
    if ($DryRun -ne $true -and $RestartDelay -gt 0) {
        Write-Message ("  waiting {0}s before start (settling)" -f $RestartDelay) -Fore Yellow
        Start-Sleep -Seconds $RestartDelay
    }
    Do-Start -Item $Item
}

## ============================================================================
## BACKUP / RESTORE / COPY HELPERS
## ============================================================================

# Full path of the PRODUCTION backup file for a database (used both as the probkup
# target on prod and the prorest source on dev, since -CopyBackup stages the prod
# backup on the dev server using the same directory structure).
# CHANGE THIS to match your backup file naming/layout.
function Get-BackupDevice {
    param($App, $Role, $Site)
    switch ($App) {
        "App1" {
            # <App1BackupDir>/app1dbProdS1.bk  /  app1auxProdS2.bk  (flat dir)
            $prefix = if ($Role -eq "App1Db") { "app1db" } else { "app1aux" }
            $file   = "{0}Prod{1}.bk" -f $prefix, $Site
            return (Join-PathX $App1BackupDir $file)
        }
        "App2" {
            # <App2BackupBase>/<subdir>/<file>.bk   (per-role subdirs)
            $map = @{
                Main   = @("main.db","main.bk")
                Aux    = @("aux.db","aux.bk")
                Report = @("report.db","report.bk")
            }
            $m = $map[$Role]
            if ($null -eq $m) { return $null }
            return (Join-PathX $App2BackupBase $m[0] $m[1])
        }
    }
    return $null
}

# Run an OpenEdge database utility (probkup/prorest) from the item's DLC/bin.
function Invoke-OEUtil {
    param($Item, $Util, [string[]]$Arguments)
    $exe = Get-OEToolPath $Item.DLC $Util
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] DLC={0}  {1} {2}" -f $Item.DLC, $Util, ($Arguments -join ' ')) -Fore DarkGray
        return [PSCustomObject]@{ ExitCode=0; Output="[dry-run]" }
    }
    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        $out  = & $exe @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } catch {
        $out = $_.Exception.Message; $code = -1
    } finally {
        $env:DLC = $prev
    }
    return [PSCustomObject]@{ ExitCode=$code; Output=$out.Trim() }
}

# Online backup of one production database (probkup online <db> <device>).
function Do-Backup {
    param($Item)
    $device = Get-BackupDevice -App $Item.App -Role $Item.Role -Site $Item.Site
    if (-not $device) { Write-Message ("  Backup: no device mapping for {0}" -f $Item.Name) -Fore Red; return }
    if ($Remote -eq $true) { $device = Convert-ToRemotePath -Server $Item.Server -LocalPath $device }
    Write-Message ("Backup: {0,-43} -> {1}" -f (& $Label $Item), $device) -Fore Cyan
    $r = Invoke-OEUtil -Item $Item -Util "probkup" -Arguments @("online", $Item.DbPath, $device)
    if ($r.ExitCode -ne 0 -and $DryRun -ne $true) {
        Write-Message ("  ERROR (exit $($r.ExitCode)): $($r.Output)") -Fore Red; $script:OnError = $true
    }
}

# Restore the production backup into one dev/test/sbox database.  The target must
# be offline, so: stop -> prorest -> start.
function Do-Restore {
    param($Item)
    $source = Get-BackupDevice -App $Item.App -Role $Item.Role -Site $Item.Site
    if (-not $source) { Write-Message ("  Restore: no source mapping for {0}" -f $Item.Name) -Fore Red; return }
    if ($Remote -eq $true) { $source = Convert-ToRemotePath -Server $Item.Server -LocalPath $source }
    Write-Message ("Restore: {0,-43} <- {1}" -f (& $Label $Item), $source) -Fore Cyan
    Do-Stop -Item $Item
    $r = Invoke-OEUtil -Item $Item -Util "prorest" -Arguments @($Item.DbPath, $source)
    if ($r.ExitCode -ne 0 -and $DryRun -ne $true) {
        Write-Message ("  ERROR (exit $($r.ExitCode)): $($r.Output)") -Fore Red; $script:OnError = $true
    }
    Do-Start -Item $Item
}

# ---- CLIENT (-Client) --------------------------------------------------------
#
# App2 environment -> setup file stem.  App2 INI/PF files are named by the plain
# environment word (no app prefix, no site).  CHANGE THIS map to match your files.
# Returns $null for any env without a client setup file (e.g. Prod/ProdCopy - the
# client/batch launch is a dev-side tool here).
function Get-App2EnvStem {
    param($Env)
    switch ($Env) {
        "Dev"  { "development" }
        "Test" { "test" }
        "SBox" { "sandbox" }
        default { $null }
    }
}

# Build the auto-derived INI path for a target.  Both apps keep INIs under
# <SetupDir>/ini/<server>/; the file stem differs by app:
#   App1 -> <App><Env><Site>.ini   (e.g. app1DevS2.ini) - same stem as the PF
#   App2 -> <env>.ini              (e.g. development.ini) - env word, no site
function Get-ClientIni {
    param($Item)
    if ($Item.App -eq "App2") {
        $stem = Get-App2EnvStem -Env $Item.Env
        if (-not $stem) { return $null }
        $p = Join-PathX $App2SetupDir "ini" $Item.Server ("$stem.ini")
    }
    else {
        # App1: needs a resolved Env + Site.
        if ([string]::IsNullOrWhiteSpace($Item.Env) -or [string]::IsNullOrWhiteSpace($Item.Site)) { return $null }
        $file = "{0}{1}{2}.ini" -f $Item.App, $Item.Env, $Item.Site
        $p = Join-PathX $App1SetupDir "ini" $Item.Server $file
    }
    if ($Remote -eq $true) { return (Convert-ToRemotePath -Server $Item.Server -LocalPath $p) }
    return $p
}

# Build the auto-derived PF path for a target.  Both apps keep PFs under
# <SetupDir>/userPfs/<server>/; stem as above (App1 <App><Env><Site>, App2 env word).
function Get-ClientPf {
    param($Item)
    if ($Item.App -eq "App2") {
        $stem = Get-App2EnvStem -Env $Item.Env
        if (-not $stem) { return $null }
        $p = Join-PathX $App2SetupDir "userPfs" $Item.Server ("$stem.pf")
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Item.Env) -or [string]::IsNullOrWhiteSpace($Item.Site)) { return $null }
        $file = "{0}{1}{2}.pf" -f $Item.App, $Item.Env, $Item.Site
        $p = Join-PathX $App1SetupDir "userPfs" $Item.Server $file
    }
    if ($Remote -eq $true) { return (Convert-ToRemotePath -Server $Item.Server -LocalPath $p) }
    return $p
}

# Turn a user-supplied -Ini/-Pf/-AddPfs value into a full path.  A bare filename
# (no / or \) is assumed to live in the target's standard setup subdirectory:
#   ini     -> <SetupDir>/ini/<server>/<file>
#   userPfs -> <SetupDir>/userPfs/<server>/<file>
# A value that already contains a path separator is returned verbatim.
function Resolve-ClientFileArg {
    param($Value, $Item, [ValidateSet("ini","userPfs")] $SubDir)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value -match '[\\/]') { return $Value }
    $root = if ($Item.App -eq "App2") { $App2SetupDir } else { $App1SetupDir }
    $p = Join-PathX $root $SubDir $Item.Server $Value
    if ($Remote -eq $true) { return (Convert-ToRemotePath -Server $Item.Server -LocalPath $p) }
    return $p
}

# Resolve the client launch parts (exe, ini, pf) shared by -Client and -Batch.
# Returns a PSCustomObject { Exe; ExeName; Ini; Pf; AddPfs } or $null on failure.
# CHANGE THIS exe map to the client executables your OpenEdge versions ship:
#   Windows GUI client: prowin.exe (64-bit) / prowin32.exe (32-bit)
#   Linux character client: _progres (there is no GUI client on Linux) - if you
#     run clients on Linux, set the exe accordingly and drop the .exe.
function Resolve-ClientLaunch {
    param($Item, $Tag = "Client")

    $exeName = switch ($Item.OEVersion) {
        "12.8"  { if ($IsWindowsHost) { "prowin.exe" }   else { "_progres" } }
        "12.2"  { if ($IsWindowsHost) { "prowin.exe" }   else { "_progres" } }
        "11.7"  { if ($IsWindowsHost) { "prowin.exe" }   else { "_progres" } }
        "10.2B" { if ($IsWindowsHost) { "prowin32.exe" } else { "_progres" } }
        "9.1E"  { if ($IsWindowsHost) { "prowin32.exe" } else { "_progres" } }
        default { $null }
    }
    if (-not $exeName) {
        Write-Message ("  {0}: no client exe mapping for OEVersion '{1}' ({2})" -f $Tag, $Item.OEVersion, $Item.Name) -Fore Red
        $script:OnError = $true; return $null
    }
    $exe = Join-PathX $Item.DLC "bin" $exeName

    # Resolve INI and PF: explicit override wins, else auto-derive from the target.
    $iniPath = if (-not [string]::IsNullOrWhiteSpace($Ini)) { Resolve-ClientFileArg -Value $Ini -Item $Item -SubDir "ini" }     else { Get-ClientIni -Item $Item }
    $pfPath  = if (-not [string]::IsNullOrWhiteSpace($Pf))  { Resolve-ClientFileArg -Value $Pf  -Item $Item -SubDir "userPfs" } else { Get-ClientPf  -Item $Item }
    if (-not $iniPath) { Write-Message ("  {0}: could not resolve INI for {1}" -f $Tag, $Item.Name) -Fore Red; $script:OnError = $true; return $null }
    if (-not $pfPath)  { Write-Message ("  {0}: could not resolve PF for {1}"  -f $Tag, $Item.Name) -Fore Red; $script:OnError = $true; return $null }

    # Optional secondary PF(s).  -AddPfs may be a PS array and/or comma-separated
    # strings; flatten, split on commas, trim, drop blanks, then resolve each.
    $addPfPaths = @()
    foreach ($entry in @($AddPfs)) {
        foreach ($one in ($entry -split ',')) {
            $one = $one.Trim()
            if ([string]::IsNullOrWhiteSpace($one)) { continue }
            $addPfPaths += (Resolve-ClientFileArg -Value $one -Item $Item -SubDir "userPfs")
        }
    }

    if ($DryRun -ne $true) {
        if (-not (Test-Path -Path $iniPath -PathType Leaf)) {
            Write-Message ("  {0}: INI not found: {1}" -f $Tag, $iniPath) -Fore Red; $script:OnError = $true; return $null
        }
        if (-not (Test-Path -Path $pfPath -PathType Leaf)) {
            Write-Message ("  {0}: PF not found: {1}" -f $Tag, $pfPath) -Fore Red; $script:OnError = $true; return $null
        }
        foreach ($ap in $addPfPaths) {
            if (-not (Test-Path -Path $ap -PathType Leaf)) {
                Write-Message ("  {0}: secondary PF (-AddPfs) not found: {1}" -f $Tag, $ap) -Fore Red; $script:OnError = $true; return $null
            }
        }
    }
    return [PSCustomObject]@{ Exe=$exe; ExeName=$exeName; Ini=$iniPath; Pf=$pfPath; AddPfs=$addPfPaths }
}

# Launch the Progress GUI client for one database target.  Command line (all
# options space-separated):  <exe> -ininame <ini> -pf <pf> [ -p <StartupProgram> ]
# -Ini / -Pf override the auto-derived paths.  In -DryRun the command is printed.
function Do-Client {
    param($Item)
    $L = Resolve-ClientLaunch -Item $Item -Tag "Client"
    if (-not $L) { return }

    # Real args use the full paths Progress needs; a parallel display list shows
    # just the leaf filenames for readability.
    $cargs = @("-ininame", $L.Ini, "-pf", $L.Pf)
    $dargs = @("-ininame", (Split-Path $L.Ini -Leaf), "-pf", (Split-Path $L.Pf -Leaf))
    foreach ($ap in $L.AddPfs) { $cargs += @("-pf", $ap); $dargs += @("-pf", (Split-Path $ap -Leaf)) }
    if ($Run -eq $true) { $cargs += @("-p", $StartupProgram); $dargs += @("-p", $StartupProgram) }

    $display = "$($L.ExeName) " + ($dargs -join ' ')
    Write-Message ("Client: {0,-43} {1}" -f (& $Label $Item), $L.ExeName) -Fore Cyan
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] {0}" -f $display) -Fore DarkGray
        return
    }
    Write-Message ("  {0}" -f $display) -Fore DarkGray
    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        # Launch the client without blocking the script (interactive session).
        Start-Process -FilePath $L.Exe -ArgumentList $cargs
    } catch {
        Write-Message ("  ERROR launching client: {0}" -f $_.Exception.Message) -Fore Red
        $script:OnError = $true
    } finally {
        $env:DLC = $prev
    }
}

# Run the Progress client in BATCH mode for one database target.  Same exe/ini/pf
# resolution as -Client, but the command line ends with the program and batch flag:
#   <exe> -ininame <ini> -pf <pf> -p <program> -b
# The session runs BLOCKING with stdout -> <script dir>/<program>.out and stderr
# -> <program>.err (<program> = base name of -Pgm).  Non-zero exit sets OnError.
function Do-Batch {
    param($Item)
    $L = Resolve-ClientLaunch -Item $Item -Tag "Batch"
    if (-not $L) { return }

    $pgmBase = [System.IO.Path]::GetFileNameWithoutExtension($Pgm)
    $outFile = Join-Path $PSScriptRoot ($pgmBase + ".out")
    $errFile = Join-Path $PSScriptRoot ($pgmBase + ".err")

    $cargs = @("-ininame", $L.Ini, "-pf", $L.Pf)
    $dargs = @("-ininame", (Split-Path $L.Ini -Leaf), "-pf", (Split-Path $L.Pf -Leaf))
    foreach ($ap in $L.AddPfs) { $cargs += @("-pf", $ap); $dargs += @("-pf", (Split-Path $ap -Leaf)) }
    $cargs += @("-p", $Pgm, "-b"); $dargs += @("-p", $Pgm, "-b")

    $display = "$($L.ExeName) " + ($dargs -join ' ')
    Write-Message ("Batch: {0,-44} {1}" -f (& $Label $Item), $L.ExeName) -Fore Cyan
    Write-Message ("  program: {0}   out: {1}   err: {2}" -f $Pgm, $outFile, $errFile) -Fore DarkGray
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] {0}  1> {1} 2> {2}" -f $display, $outFile, $errFile) -Fore DarkGray
        return
    }
    Write-Message ("  {0}" -f $display) -Fore DarkGray
    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        $p = Start-Process -FilePath $L.Exe -ArgumentList $cargs -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if ($p.ExitCode -ne 0) {
            Write-Message ("  Batch program exited {0} (see {1})" -f $p.ExitCode, $errFile) -Fore Red
            $script:OnError = $true
        } else {
            Write-Message ("  Batch program completed (exit 0)." ) -Fore Green
        }
    } catch {
        Write-Message ("  ERROR running batch: {0}" -f $_.Exception.Message) -Fore Red
        $script:OnError = $true
    } finally {
        $env:DLC = $prev
    }
}

# Copy production backups onto a development server.  Sources are the
# Production-tier installs of the same app.  On Windows this uses robocopy; on
# Linux it falls back to rsync (or cp) - CHANGE THIS if you prefer a different
# tool or a pull-over-ssh approach.  App1 backups live in a flat dir; App2
# backups live in per-role subdirs (recurse).
function Invoke-CopyBackup {
    param($DevServer, $App)
    $dir     = if ($App -eq "App1") { $App1BackupDir } else { $App2BackupBase }
    $recurse = ($App -eq "App2")
    $sources = @($Installs | Where-Object { $_.App -eq $App -and $_.Tier -eq "Production" } |
                Select-Object -ExpandProperty Server -Unique)
    if (-not $sources) { Write-Message "  No production source servers for $App." -Fore Yellow; return }
    foreach ($src in $sources) {
        $srcRemote = Convert-ToRemotePath -Server $src       -LocalPath $dir
        $dstRemote = Convert-ToRemotePath -Server $DevServer -LocalPath $dir
        if ($IsWindowsHost) {
            $rc = @($srcRemote, $dstRemote, "*.bk")
            if ($recurse) { $rc += "/S" }
            $rc += @("/Z","/J")
            if ($DryRun -eq $true) {
                Write-Message ("  [DRYRUN] robocopy {0}" -f ($rc -join ' ')) -Fore DarkGray
            } else {
                Write-Message ("  robocopy {0}" -f ($rc -join ' ')) -Fore Cyan
                $null = & robocopy @rc 2>&1 | Out-String
                if ($LASTEXITCODE -ge 8) {          # robocopy: exit >=8 is a failure
                    Write-Message ("  robocopy ERROR (exit $LASTEXITCODE) copying from $src") -Fore Red
                    $script:OnError = $true
                }
            }
        } else {
            # Linux: rsync the .bk files.  Adjust the source/dest to however you
            # reach the two servers (local mount, user@host:path over ssh, ...).
            $rsyncArgs = @("-a")
            if ($recurse) { $rsyncArgs += "-r" }
            $rsyncArgs += @("--include=*/","--include=*.bk","--exclude=*", ($srcRemote.TrimEnd('/') + "/"), ($dstRemote.TrimEnd('/') + "/"))
            if ($DryRun -eq $true) {
                Write-Message ("  [DRYRUN] rsync {0}" -f ($rsyncArgs -join ' ')) -Fore DarkGray
            } else {
                Write-Message ("  rsync {0}" -f ($rsyncArgs -join ' ')) -Fore Cyan
                $null = & rsync @rsyncArgs 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    Write-Message ("  rsync ERROR (exit $LASTEXITCODE) copying from $src") -Fore Red
                    $script:OnError = $true
                }
            }
        }
    }
}

## ============================================================================
## CHECKS, BACKUP, NOTIFICATIONS
## ============================================================================

# Scan a database's .lg log for configured error patterns, but ONLY the portion
# at/after the most recent startup marker - so old history does not raise a false
# positive.  Returns $true if any error pattern matches in that window.
function Check-LogErrors {
    param($Item)
    if ($Item.Component -ne "Database" -or [string]::IsNullOrWhiteSpace($Item.LogFile)) { return $false }
    if (-not (Test-Path -Path $Item.LogFile -PathType Leaf)) {
        Write-Message ("Log scan: {0,-45} log not found ({1})" -f (& $Label $Item), $Item.LogFile) -Fore DarkGray
        return $false
    }

    $lines = @(Get-Content -Path $Item.LogFile)
    if ($lines.Count -eq 0) {
        Write-Message ("Log scan: {0,-45} empty log" -f (& $Label $Item)) -Fore DarkGray
        return $false
    }

    $startIdx = 0
    $found    = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in $LogStartupMarkers) {
            if ($lines[$i] -match $m) { $startIdx = $i; $found = $true; break }
        }
    }
    $window = $lines[$startIdx..($lines.Count - 1)]
    $scope  = if ($found) { "since last startup" } else { "whole log - no startup marker" }

    foreach ($pat in $LogErrorPatterns) {
        $hit = $window | Select-String -Pattern $pat -Quiet
        if ($hit) {
            Write-Message ("Log scan: {0,-45} ERROR MATCH '{1}' ({2})" -f (& $Label $Item), $pat, $scope) -Fore Red
            return $true
        }
    }
    Write-Message ("Log scan: {0,-45} clean ({1})" -f (& $Label $Item), $scope) -Fore Green
    return $false
}

# Backup an install's conmgr.properties + ubroker.properties before any
# state-changing action.  Skips if a .bak exists unless -ForceBackup.
function Backup-Settings {
    param($PropertiesDir)
    foreach ($name in @("conmgr.properties","ubroker.properties")) {
        $src = Join-PathX $PropertiesDir $name
        $bak = "$src.bak"
        if (-not (Test-Path -Path $src -PathType Leaf)) { continue }
        if ($ForceBackup -eq $true -or -not (Test-Path -Path $bak -PathType Leaf)) {
            if ($DryRun -eq $true) {
                Write-Message ("  [DRYRUN] backup $src -> $bak") -Fore DarkGray
            } else {
                Copy-Item -Path $src -Destination $bak -Force
                Write-Message ("  backed up $name in $PropertiesDir") -Fore Yellow
            }
        } else {
            Write-Message ("  $name already backed up in $PropertiesDir") -Fore Green
        }
    }
}

# Send a plain error email via the relay (needs SmtpServer + EmailTo).
function Send-Email-Error {
    param($Subject="OEAdmin - ERROR", $Body="An error occurred. See the OEAdmin log.")
    if ([string]::IsNullOrWhiteSpace($SmtpServer) -or [string]::IsNullOrWhiteSpace($EmailTo)) { return }
    $smtp = $null; $msg = $null
    try {
        $smtp = [Net.Mail.SmtpClient]::new($SmtpServer, $SmtpPort)
        $smtp.EnableSsl = $SmtpUseSsl
        $msg = [Net.Mail.MailMessage]::new($EmailFrom, $EmailTo, $Subject, $Body)
        $smtp.Send($msg)
        Write-Message "Notification: error email sent to $EmailTo" -Fore Yellow
    } catch {
        Write-Message "Notification: email FAILED - $($_.Exception.Message)" -Fore Red
    } finally {
        if ($msg)  { $msg.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}

# Email the run log via the relay (needs SmtpServer + EmailTo).
function Send-Email-Log {
    param($Subject="OEAdmin - Log", $Body="OEAdmin run log attached.")
    if ([string]::IsNullOrWhiteSpace($SmtpServer) -or [string]::IsNullOrWhiteSpace($EmailTo)) { return }
    # A [Net.Mail.Attachment] holds an OPEN read handle on the file until it is
    # disposed.  Dispose the attachment, the message, and the SmtpClient in a
    # finally block so the log handle is freed the moment we're done (otherwise
    # the next run can hit "file is being used by another process" on log reset).
    $smtp = $null; $msg = $null; $attach = $null
    try {
        $smtp = [Net.Mail.SmtpClient]::new($SmtpServer, $SmtpPort)
        $smtp.EnableSsl = $SmtpUseSsl
        $msg = [Net.Mail.MailMessage]::new($EmailFrom, $EmailTo, $Subject, $Body)
        if (Test-Path -Path $LogFile -PathType Leaf) {
            $attach = [Net.Mail.Attachment]::new($LogFile)
            $msg.Attachments.Add($attach)
        }
        $smtp.Send($msg)
    } catch {
        Write-Message "Notification: log email FAILED - $($_.Exception.Message)" -Fore Red
    } finally {
        if ($attach) { $attach.Dispose() }
        if ($msg)    { $msg.Dispose() }
        if ($smtp)   { $smtp.Dispose() }
    }
}

# Write a Windows Application EventLog entry (best-effort; Windows only - a no-op
# on Linux).  Uses .NET so it works in both Windows PowerShell 5.1 and pwsh 7.x.
function Write-OEEventLog {
    param($Message="OEAdmin error", [int]$EventID=2001, $EntryType="Error")
    if ($EventLogger -ne $true -or -not $IsWindowsHost) { return }
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EventSource, "Application")
        }
        $log = [System.Diagnostics.EventLog]::new("Application")
        $log.Source = $EventSource
        $log.WriteEntry($Message, [System.Diagnostics.EventLogEntryType]::$EntryType, $EventID)
    } catch {
        # EventLog unavailable/insufficient rights - ignore quietly.
    }
}

## ============================================================================
## INTERACTIVE MENU (-Menu)
## ============================================================================
# A drill-down front end so an operator does not have to memorize the switches.
# It PICKS an action and the parameters that action needs, prints the equivalent
# command line, and (after a y/n confirm) sets the same $script: variables the
# command line would - then falls through to the normal dispatch below.

# Prompt for one choice from a list.  Returns the chosen value (not the number).
# $Options is an array of [pscustomobject]@{ Label=..; Value=..; Valid=$true }.
# An option with Valid=$false (an App/Site/Env not present on this machine, and
# -Remote not used) is shown in RED and cannot be selected.  Blank input picks
# the first VALID option as the default.  "Q"/"quit" returns $null (cancel).
function Read-MenuChoice {
    param($Title, $Options, $AllowBack=$false)
    $defaultIdx = -1
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $v = $Options[$i].PSObject.Properties['Valid']
        if ($null -eq $v -or $v.Value -eq $true) { $defaultIdx = $i; break }
    }
    while ($true) {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $v = $Options[$i].PSObject.Properties['Valid']
            $isValid = ($null -eq $v -or $v.Value -eq $true)
            $mark = if ($i -eq $defaultIdx) { " (default)" } elseif (-not $isValid) { " (not available on this machine)" } else { "" }
            $line = "  {0}. {1}{2}" -f ($i + 1), $Options[$i].Label, $mark
            if ($isValid) { Write-Host $line } else { Write-Host $line -ForegroundColor Red }
        }
        $dnum = if ($defaultIdx -ge 0) { ", Enter=$($defaultIdx + 1)" } else { "" }
        $extra = if ($AllowBack) { "  (B=back, Q=quit$dnum)" } else { "  (Q=quit$dnum)" }
        $sel = Read-Host ("Select 1-{0}{1}" -f $Options.Count, $extra)
        if ([string]::IsNullOrWhiteSpace($sel)) {
            if ($defaultIdx -ge 0) { return $Options[$defaultIdx].Value }
            Write-Host "  No available option to default to; type Q to quit." -ForegroundColor Yellow
            continue
        }
        if ($sel -match '^(?i)q(uit)?$') { return $null }
        if ($AllowBack -and $sel -match '^(?i)b(ack)?$') { return "__BACK__" }
        if ($sel -match '^\d+$') {
            $n = [int]$sel
            if ($n -ge 1 -and $n -le $Options.Count) {
                $v = $Options[$n - 1].PSObject.Properties['Valid']
                if ($null -eq $v -or $v.Value -eq $true) { return $Options[$n - 1].Value }
                Write-Host "  That option is not available on this machine (use -Remote, or pick another)." -ForegroundColor Yellow
                continue
            }
        }
        Write-Host "  Invalid selection." -ForegroundColor Yellow
    }
}

# Simple yes/no prompt.  Default is applied on blank input.
function Read-YesNo {
    param($Prompt, [bool]$Default=$false)
    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $a = Read-Host ("{0} {1}" -f $Prompt, $suffix)
        if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
        if ($a -match '^(?i)y(es)?$') { return $true }
        if ($a -match '^(?i)n(o)?$')  { return $false }
        Write-Host "  Please answer y or n." -ForegroundColor Yellow
    }
}

# Run the interactive menu.  Sets $script: action/selector variables and returns
# $true to proceed with the run, or $false to cancel (nothing selected).
function Invoke-Menu {
    Write-Section "OEADMIN - INTERACTIVE MENU"

    $action = Read-MenuChoice -Title "What do you want to do?" -Options @(
        [pscustomobject]@{ Label="Status  - report instance status";           Value="Status" }
        [pscustomobject]@{ Label="Start   - start instances";                  Value="Start" }
        [pscustomobject]@{ Label="Stop    - stop instances";                   Value="Stop" }
        [pscustomobject]@{ Label="Restart - stop then start instances";        Value="Restart" }
        [pscustomobject]@{ Label="Backup  - probkup online (PROD servers)";    Value="Backup" }
        [pscustomobject]@{ Label="Restore - prorest prod backup (DEV servers)";Value="Restore" }
        [pscustomobject]@{ Label="CopyBackup - copy prod backups -> dev";      Value="CopyBackup" }
        [pscustomobject]@{ Label="Client  - launch Progress GUI client";       Value="Client" }
        [pscustomobject]@{ Label="Batch   - run a Progress program in batch";  Value="Batch" }
    )
    if ($null -eq $action) { return $false }

    # The menu owns the action set: clear the default -Status, then turn on the
    # one the operator chose.
    $script:Status=$false; $script:Start=$false; $script:Stop=$false
    $script:Restart=$false; $script:Backup=$false; $script:Restore=$false
    $script:CopyBackup=$false; $script:Client=$false; $script:Batch=$false

    # App picker (used by most actions).  Apps not installed on this machine are
    # shown red/disabled (unless -Remote); the default is the first valid one.
    $askApp = {
        param($allowAll=$true)
        $opts = @()
        if ($allowAll) { $opts += [pscustomobject]@{ Label="All (App1 + App2)"; Value="All"; Valid=(Test-AppAvail "All") } }
        $opts += [pscustomobject]@{ Label="App1"; Value="App1"; Valid=(Test-AppAvail "App1") }
        $opts += [pscustomobject]@{ Label="App2"; Value="App2"; Valid=(Test-AppAvail "App2") }
        Read-MenuChoice -Title "Which application?" -Options $opts
    }
    # Site picker.  $app scopes availability.  App2 has no site, so callers skip
    # this entirely for App=App2.
    $askSite = {
        param($app="All")
        Read-MenuChoice -Title "Which site?" -Options @(
            [pscustomobject]@{ Label="Site S1"; Value="S1"; Valid=(Test-SiteAvail $app "S1") }
            [pscustomobject]@{ Label="Site S2"; Value="S2"; Valid=(Test-SiteAvail $app "S2") }
        )
    }
    # Collect the Site/Env a client or batch launch needs, per app.  App1 asks a
    # site then an env; App2 has no site and only the dev-side envs.  Sets
    # $script:Site/$script:Env; returns $false if the user cancelled.
    $askClientEnv = {
        param($app)
        if ($app -eq "App2") {
            $script:Site = "All"   # App2 has no site: skip the site question.
            $env = Read-MenuChoice -Title "Which environment?" -Options @(
                [pscustomobject]@{ Label="Dev (development)"; Value="Dev";  Valid=(Test-EnvAvail "App2" "All" "Dev") }
                [pscustomobject]@{ Label="Test (test)";       Value="Test"; Valid=(Test-EnvAvail "App2" "All" "Test") }
                [pscustomobject]@{ Label="SBox (sandbox)";    Value="SBox"; Valid=(Test-EnvAvail "App2" "All" "SBox") }
            )
            if ($null -eq $env) { return $false }; $script:Env = $env
            return $true
        }
        # App1: site then env.  Client/Batch have no prod INI/PF, so Prod is shown
        # red/disabled here (Dev/Test/SBox gated by what exists locally).
        $site = & $askSite "App1"; if ($null -eq $site) { return $false }
        $script:Site = $site
        $env = Read-MenuChoice -Title "Which environment?" -Options @(
            [pscustomobject]@{ Label="Prod (no client INI/PF)"; Value="Prod"; Valid=$false }
            [pscustomobject]@{ Label="Dev";  Value="Dev";  Valid=(Test-EnvAvail "App1" $site "Dev") }
            [pscustomobject]@{ Label="Test"; Value="Test"; Valid=(Test-EnvAvail "App1" $site "Test") }
            [pscustomobject]@{ Label="SBox"; Value="SBox"; Valid=(Test-EnvAvail "App1" $site "SBox") }
        )
        if ($null -eq $env) { return $false }; $script:Env = $env
        return $true
    }
    # Optional explicit INI/PF override prompt shared by Client and Batch.
    $askIniPfOverride = {
        if (Read-YesNo -Prompt "Override the INI/PF files with explicit paths?" -Default:$false) {
            $iniIn = Read-Host "  INI file (Enter to keep derived)"
            if (-not [string]::IsNullOrWhiteSpace($iniIn)) { $script:Ini = $iniIn }
            $pfIn = Read-Host "  PF file (Enter to keep derived)"
            if (-not [string]::IsNullOrWhiteSpace($pfIn)) { $script:Pf = $pfIn }
        }
    }

    switch ($action) {

        { $_ -in @("Status","Start","Stop","Restart") } {
            Set-Variable -Name $action -Scope Script -Value $true
            $app = & $askApp $true;  if ($null -eq $app) { return $false }
            $script:App = $app
            # Site only applies to multi-site apps (App2 has no site).  Skip the
            # site question entirely for App=App2; otherwise offer it, graying
            # sites that don't exist locally.  Enter/skip = All sites.
            if ($app -eq "App2") {
                $script:Site = "All"
            } else {
                $site = Read-MenuChoice -Title "Restrict to a site? (or skip for All)" -Options @(
                    [pscustomobject]@{ Label="All sites"; Value="All"; Valid=$true }
                    [pscustomobject]@{ Label="Site S1"; Value="S1"; Valid=(Test-SiteAvail $app "S1") }
                    [pscustomobject]@{ Label="Site S2"; Value="S2"; Valid=(Test-SiteAvail $app "S2") }
                )
                if ($null -eq $site) { return $false }; $script:Site = $site
            }
            $curSite = $script:Site
            $env = Read-MenuChoice -Title "Restrict to an environment? (or skip for All)" -Options @(
                [pscustomobject]@{ Label="All envs"; Value="All"; Valid=$true }
                [pscustomobject]@{ Label="Prod"; Value="Prod"; Valid=(Test-EnvAvail $app $curSite "Prod") }
                [pscustomobject]@{ Label="Dev";  Value="Dev";  Valid=(Test-EnvAvail $app $curSite "Dev") }
                [pscustomobject]@{ Label="Test"; Value="Test"; Valid=(Test-EnvAvail $app $curSite "Test") }
                [pscustomobject]@{ Label="SBox"; Value="SBox"; Valid=(Test-EnvAvail $app $curSite "SBox") }
            )
            if ($null -eq $env) { return $false }; $script:Env = $env
        }

        "Backup" {
            $script:Backup = $true
            $app = & $askApp $true; if ($null -eq $app) { return $false }
            $script:App = $app
            # Backup is prod-servers + Prod-env only, chosen automatically.
        }

        "CopyBackup" {
            $script:CopyBackup = $true
            $app = & $askApp $true; if ($null -eq $app) { return $false }
            $script:App = $app
        }

        "Restore" {
            $script:Restore = $true
            $app = & $askApp $true; if ($null -eq $app) { return $false }
            $script:App = $app
            if ($app -ne "App2") {
                # -Site is REQUIRED for multi-site restores (both sites stage on one dev box).
                $site = & $askSite $app; if ($null -eq $site) { return $false }
                $script:Site = $site
            } else {
                $script:Site = "All"   # App2 has no site.
            }
            $rSite = $script:Site
            $env = Read-MenuChoice -Title "Restore into which environment?" -Options @(
                [pscustomobject]@{ Label="Dev";  Value="Dev";  Valid=(Test-EnvAvail $app $rSite "Dev") }
                [pscustomobject]@{ Label="Test"; Value="Test"; Valid=(Test-EnvAvail $app $rSite "Test") }
                [pscustomobject]@{ Label="SBox"; Value="SBox"; Valid=(Test-EnvAvail $app $rSite "SBox") }
            )
            if ($null -eq $env) { return $false }; $script:Env = $env
        }

        "Client" {
            $script:Client = $true
            $app = & $askApp $false; if ($null -eq $app) { return $false }
            $script:App = $app
            if (-not (& $askClientEnv $app)) { return $false }
            $script:Run = Read-YesNo -Prompt ("Run the startup program (-p {0}) on launch?" -f $StartupProgram) -Default:$false
            & $askIniPfOverride
        }

        "Batch" {
            $script:Batch = $true
            $app = & $askApp $false; if ($null -eq $app) { return $false }
            $script:App = $app
            if (-not (& $askClientEnv $app)) { return $false }
            do {
                $pgmIn = Read-Host "  Program to run in batch (-Pgm), e.g. sh/startup.p"
            } while ([string]::IsNullOrWhiteSpace($pgmIn))
            $script:Pgm = $pgmIn
            & $askIniPfOverride
        }
    }

    # DryRun preview offer (applies to every action).
    $script:DryRun = Read-YesNo -Prompt "Preview only (DryRun, make no changes)?" -Default:$false

    # Build the equivalent command line for display + confirmation.
    $parts = @("./OEAdmin.ps1", "-$action")
    if ($script:App   -and $script:App   -ne "All") { $parts += "-App $($script:App)" }
    if ($script:Site  -and $script:Site  -ne "All") { $parts += "-Site $($script:Site)" }
    if ($script:Env   -and $script:Env   -ne "All") { $parts += "-Env $($script:Env)" }
    if ($script:Run   -eq $true)                    { $parts += "-Run" }
    if (-not [string]::IsNullOrWhiteSpace($script:Pgm)) { $parts += "-Pgm $($script:Pgm)" }
    if (-not [string]::IsNullOrWhiteSpace($script:Ini)) { $parts += "-Ini `"$($script:Ini)`"" }
    if (-not [string]::IsNullOrWhiteSpace($script:Pf))  { $parts += "-Pf `"$($script:Pf)`"" }
    if (@($script:AddPfs).Count -gt 0) { $parts += "-AddPfs `"$(@($script:AddPfs) -join ',')`"" }
    if ($script:DryRun -eq $true)                   { $parts += "-DryRun" }
    $cmd = $parts -join ' '

    Write-Host ""
    Write-Host "Equivalent command line:" -ForegroundColor Cyan
    Write-Host ("  " + $cmd) -ForegroundColor White
    Write-Host ""

    if (-not (Read-YesNo -Prompt "Proceed with this?" -Default:$true)) {
        Write-Host "Cancelled - nothing run." -ForegroundColor Yellow
        return $false
    }
    Write-Message ("Menu selection: " + $cmd) -Fore DarkGray
    return $true
}

## ============================================================================
## MAIN LOGIC
## ============================================================================

# Reset/timestamp the log file.
if ($LogFileWrite -eq $true -and $LogFileReset -eq $true) {
    # The log can be locked by another holder at startup (a real second instance,
    # antivirus/indexer, or a prior run that died mid-write).  Rather than crash
    # and then flood every subsequent Write-Message, retry a few times, then fall
    # back to a timestamped log file for this run so it still logs cleanly.
    $stamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $reset = $false
    for ($try = 1; $try -le 5 -and -not $reset; $try++) {
        try {
            Set-Content -Path $script:LogFile -Value ("Script Start Time:    " + $stamp) -Encoding ascii -ErrorAction Stop
            $reset = $true
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }
    if (-not $reset) {
        $alt = [System.IO.Path]::Combine(
            [System.IO.Path]::GetDirectoryName($script:LogFile),
            [System.IO.Path]::GetFileNameWithoutExtension($script:LogFile) + "_" + $stamp +
            [System.IO.Path]::GetExtension($script:LogFile))
        Write-Host ("WARNING: {0} is locked by another process; logging this run to {1}" -f $script:LogFile, $alt) -ForegroundColor Yellow
        $script:LogFile = $alt
        try { Set-Content -Path $script:LogFile -Value ("Script Start Time:    " + $stamp) -Encoding ascii -ErrorAction Stop } catch { }
    }
}

# Build the live inventory ONCE, up front.  The menu (below) needs it to know
# which App/Site/Env combinations actually exist on this machine so it can gray
# out (red) the ones that don't; the normal dispatch reuses the same inventory.
$Inventory = Build-Inventory

# Availability model for the menu, derived from the Database items (those are what
# Client/Batch and most actions resolve against).  Under -Remote every option is
# valid.  Helpers return $true if at least one matching db exists.
$script:MenuAvail = @{
    Apps  = @($Inventory | Where-Object Component -eq "Database" | Select-Object -ExpandProperty App  -Unique)
    Sites = @($Inventory | Where-Object Component -eq "Database" | Select-Object -ExpandProperty Site -Unique)
}
function Test-AppAvail  { param($App)
    if ($Remote -eq $true) { return $true }
    if ($App -eq "All") { return ($script:MenuAvail.Apps.Count -gt 0) }
    return ($script:MenuAvail.Apps -contains $App)
}
function Test-SiteAvail { param($App, $Site)   # $App may be All/App1/App2
    if ($Remote -eq $true) { return $true }
    if ($Site -eq "All") { return $true }
    @($Inventory | Where-Object {
        $_.Component -eq "Database" -and $_.Site -eq $Site -and
        ($App -eq "All" -or $_.App -eq $App)
    }).Count -gt 0
}
function Test-EnvAvail  { param($App, $Site, $Env)   # any of App/Site may be All
    if ($Remote -eq $true) { return $true }
    if ($Env -eq "All") { return $true }
    @($Inventory | Where-Object {
        $_.Component -eq "Database" -and $_.Env -eq $Env -and
        ($App  -eq "All" -or $_.App  -eq $App) -and
        ($Site -eq "All" -or $_.Site -eq $Site)
    }).Count -gt 0
}

# -Menu: interactive drill-down.  Collects the action + parameters, shows the
# equivalent command line, and on confirm sets the $script: vars used below.
if ($Menu -eq $true) {
    if (-not (Invoke-Menu)) { Write-Section "SCRIPT COMPLETED"; exit 0 }
}

Write-Section "OEADMIN - PARAMETERS"
Write-Message "App / Server:         $App / $Server" -Fore Blue
Write-Message "Site / Env:           $Site / $Env"   -Fore Blue
Write-Message "OEVersion / Component:$OEVersion / $Component" -Fore Blue
Write-Message "Actions:              Status=$Status Start=$Start Stop=$Stop Restart=$Restart" -Fore Blue
Write-Message "Backup actions:       Backup=$Backup Restore=$Restore CopyBackup=$CopyBackup" -Fore Blue
Write-Message "Client action:        Client=$Client Run=$Run Ini='$Ini' Pf='$Pf'" -Fore Blue
Write-Message "Batch action:         Batch=$Batch Pgm='$Pgm'" -Fore Blue
Write-Message "Checks:               CheckAdminServer=$CheckAdminServer CheckPort=$CheckPort CheckLogErrors=$CheckLogErrors RestartOnError=$RestartOnError" -Fore Blue
Write-Message "SettingsBackup:       SettingsBackup=$SettingsBackup ForceBackup=$ForceBackup" -Fore Blue
Write-Message "DryRun / Menu:        DryRun=$DryRun Menu=$Menu" -Fore Blue
Write-Message "Remote:               Remote=$Remote" -Fore Blue

# With -Remote and no explicit -Server, target ALL servers.
if ($Remote -eq $true -and -not $PSBoundParameters.ContainsKey('Server')) {
    $Server = "All"
    Write-Message "Remote: no -Server given; targeting ALL servers." -Fore Blue
}

# Filter the (already-built) inventory to the requested targets.
$Targets   = @(Select-Inventory -Inventory $Inventory)

Write-Section "SELECTED TARGETS ($($Targets.Count))"
if ($Targets.Count -eq 0) {
    Write-Message "No matching instances for the given selectors." -Fore Yellow
    exit 0
}
foreach ($t in $Targets) { Write-Message ("  " + (& $Label $t)) -Fore Gray }

# Verify each distinct AdminServer (DLC + port) the targets depend on is up.
$Reachable = @{}
if ($CheckAdminServer -eq $true) {
    Write-Section "CHECKING ADMINSERVER REACHABILITY"
    $distinct = if ($Remote -eq $true) { $Targets | Select-Object Server,Port -Unique } else { $Targets | Select-Object DLC,Port -Unique }
    foreach ($d in $distinct) {
        $probeHost = if ($Remote -eq $true) { $d.Server } else { "localhost" }
        $key       = if ($Remote -eq $true) { "$($d.Server)|$($d.Port)" } else { "$($d.DLC)|$($d.Port)" }
        $ok = Test-TcpPort -ComputerName $probeHost -Port $d.Port
        $Reachable[$key] = $ok
        $msg = if ($ok) { "REACHABLE" } else { "NOT REACHABLE" }
        $fore = if ($ok) { "Green" } else { "Red" }
        $where = if ($Remote -eq $true) { $d.Server } else { $d.DLC }
        Write-Message ("AdminServer port {0,-6} ({1})  {2}" -f $d.Port, $where, $msg) -Fore $fore
        if (-not $ok) { $OnError = $true }
    }
}

# Helper: may we act on this target? (AdminServer up, or in dry-run preview)
function Test-CanAct {
    param($Item)
    if ($DryRun -eq $true) { return $true }
    if ($CheckAdminServer -ne $true) { return $true }
    $key = if ($Remote -eq $true) { "$($Item.Server)|$($Item.Port)" } else { "$($Item.DLC)|$($Item.Port)" }
    return [bool]$Reachable[$key]
}

# CHECK BROKER PORTS - verify each selected database's 4GL client-connect port is
# actually listening (distinct from the AdminServer management port above).
if ($CheckPort -eq $true) {
    $dbTargets = @($Targets | Where-Object Component -eq "Database")
    if ($dbTargets.Count -gt 0) {
        Write-Section "CHECKING DATABASE BROKER PORTS (4GL)"
        foreach ($t in $dbTargets) {
            if (-not (Test-CanAct -Item $t)) {
                Write-Message ("Broker port: {0,-45} SKIPPED (AdminServer down)" -f (& $Label $t)) -Fore Red
                continue
            }
            $bp = $t.BrokerPort
            if ([string]::IsNullOrWhiteSpace($bp)) {
                Write-Message ("Broker port: {0,-45} UNKNOWN (no 4GL port in conmgr)" -f (& $Label $t)) -Fore Yellow
                continue
            }
            $portNum = Resolve-ServicePort -PortValue $bp
            if ($portNum -le 0) {
                Write-Message ("Broker port: {0,-45} NAMED SERVICE '{1}' (unresolved, not probed)" -f (& $Label $t), $bp) -Fore Yellow
                continue
            }
            $portLabel = if ("$bp" -eq "$portNum") { "$portNum" } else { "$portNum ($bp)" }
            $probeHost = if ($Remote -eq $true) { $t.Server } else { "localhost" }
            $ok  = Test-TcpPort -ComputerName $probeHost -Port $portNum
            $msg = if ($ok) { "LISTENING" } else { "NOT LISTENING" }
            $fore= if ($ok) { "Green" } else { "Red" }
            Write-Message ("Broker port {0,-14} {1,-30} {2}" -f $portLabel, (& $Label $t), $msg) -Fore $fore
            if (-not $ok) { $OnPortError = $true }
        }
    }
}

# STATUS (default) - also drives RestartOnError.
if ($Status -eq $true) {
    Write-Section "STATUS"
    foreach ($t in $Targets) {
        if (-not (Test-CanAct -Item $t)) {
            Write-Message ("Status: {0,-50} SKIPPED (AdminServer down)" -f (& $Label $t)) -Fore Red
            continue
        }
        $running = Do-Query -Item $t
        if ($RestartOnError -eq $true -and $running -eq $false) {
            Write-Message "  -> RestartOnError: restarting" -Fore Red
            Do-Restart -Item $t
        }
    }
}

# CHECK LOG ERRORS - scan each database .lg; optionally auto-restart on a match.
if ($CheckLogErrors -eq $true) {
    Write-Section "CHECKING DATABASE LOG ERRORS"
    foreach ($t in ($Targets | Where-Object Component -eq "Database")) {
        if (-not (Test-CanAct -Item $t)) { continue }
        if (Check-LogErrors -Item $t) {
            $OnLogError = $true
            if ($RestartOnError -eq $true) {
                Write-Message "  -> RestartOnError: restarting on log error" -Fore Red
                Do-Restart -Item $t
            }
        }
    }
}

# SETTINGS BACKUP - before any state-changing action, back up each install's
# conmgr/ubroker properties for the installs the targets belong to.
if ($SettingsBackup -eq $true -and ($Stop -eq $true -or $Restart -eq $true -or $Start -eq $true)) {
    Write-Section "SETTINGS BACKUP"
    foreach ($p in ($Targets | Select-Object -ExpandProperty DLC -Unique)) {
        $pd = ($Installs | Where-Object DLC -eq $p | Select-Object -First 1).PropertiesDir
        if ($pd) { Backup-Settings -PropertiesDir $pd }
    }
}

# STOP
if ($Stop -eq $true) {
    Write-Section "STOP"
    foreach ($t in $Targets) {
        if (Test-CanAct -Item $t) { Do-Stop -Item $t }
    }
}

# RESTART
if ($Restart -eq $true) {
    Write-Section "RESTART"
    foreach ($t in $Targets) {
        if (Test-CanAct -Item $t) { Do-Restart -Item $t }
    }
}

# START
if ($Start -eq $true) {
    Write-Section "START"
    foreach ($t in $Targets) {
        if (Test-CanAct -Item $t) { Do-Start -Item $t }
    }
}

# BACKUP - Production servers only; only the Prod-environment databases.
if ($Backup -eq $true) {
    Write-Section "BACKUP (probkup online)"
    if ($Targets | Where-Object { $_.Component -eq "Database" -and $_.Tier -ne "Production" }) {
        Write-Message "  Refusing to back up non-Production databases (by design)." -Fore Yellow
    }
    $bt = @($Targets | Where-Object { $_.Component -eq "Database" -and $_.Tier -eq "Production" -and $_.Env -eq "Prod" })
    if ($bt.Count -eq 0) {
        Write-Message "  No Production databases selected to back up." -Fore Yellow
    }
    foreach ($t in $bt) { if (Test-CanAct -Item $t) { Do-Backup -Item $t } }
}

# COPY BACKUPS - App-driven (dest dev server is fixed per app): -App All copies
# both apps; -App App1 or -App App2 copies just that one.
if ($CopyBackup -eq $true) {
    Write-Section "COPY BACKUPS (prod -> dev)"
    $devInstalls = @($Installs | Where-Object {
        $_.Tier -eq "Development" -and ($App -eq "All" -or $_.App -eq $App)
    } | Select-Object Server,App -Unique)
    if ($devInstalls.Count -eq 0) {
        Write-Message "  No Development servers match -App $App for CopyBackup." -Fore Yellow
    }
    foreach ($d in $devInstalls) {
        Write-Message ("Copy {0} backups -> {1}" -f $d.App, $d.Server) -Fore Cyan
        Invoke-CopyBackup -DevServer $d.Server -App $d.App
    }
}

# RESTORE - Development servers only; prod backup -> selected Dev/Test/SBox DB.
if ($Restore -eq $true) {
    Write-Section "RESTORE (prorest prod backup -> dev/test/sbox)"
    if ($Targets | Where-Object { $_.Component -eq "Database" -and $_.Tier -ne "Development" }) {
        Write-Message "  Refusing to restore onto non-Development databases (by design)." -Fore Yellow
    }
    $rt = @($Targets | Where-Object { $_.Component -eq "Database" -and $_.Tier -eq "Development" -and $_.Env -in @("Dev","Test","SBox") })
    # -Site is REQUIRED for multi-site (App1) restores.  Both sites' production
    # backups stage onto the one dev server, so forcing an explicit -Site means a
    # restore can never silently fan out across both sites.  App2 has a single
    # production source, so it is exempt (Site is "All").
    if ($rt | Where-Object { $_.App -eq "App1" }) {
        if ($Site -notin $ValidSites) {
            Write-Message ("  -Site is REQUIRED for App1 restores. Specify -Site S1 or -Site S2; got '{0}'." -f $Site) -Fore Red
            Write-Message "  Refusing to restore App1 without an explicit site (by design)." -Fore Yellow
            $script:OnError = $true
            $rt = @($rt | Where-Object { $_.App -ne "App1" })
        }
    }
    if ($rt.Count -eq 0) {
        Write-Message "  No Development target databases selected to restore (use -Env Dev|Test|SBox, and -Site S1|S2 for App1)." -Fore Yellow
    }
    foreach ($t in $rt) { if (Test-CanAct -Item $t) { Do-Restore -Item $t } }
}

# Validate the selectors needed to resolve one INI/PF per client/batch target.
# Rules differ by app:
#   App1 (multi-site) - -Site AND a single -Env are required (INI/PF are
#         <App><Env><Site>).
#   App2 (single-site) - no site; a single -Env in {Dev,Test,SBox} is required.
# Supplying BOTH -Ini and -Pf explicitly bypasses all of this (any valid pair).
function Test-ClientTargets {
    param($Tag = "Client")
    $haveExplicit = (-not [string]::IsNullOrWhiteSpace($Ini)) -and (-not [string]::IsNullOrWhiteSpace($Pf))
    if ($haveExplicit) { return $true }

    $ok  = $true
    $dbs = @($Targets | Where-Object { $_.Component -eq "Database" })

    if ($dbs | Where-Object { $_.App -eq "App1" }) {
        if ($Site -notin $ValidSites) {
            Write-Message ("  -Site is REQUIRED for {0} (App1). Specify -Site S1 or -Site S2; got '{1}'." -f $Tag, $Site) -Fore Red
            $script:OnError = $true; $ok = $false
        }
        if ($Env -notin $ValidEnvs) {
            Write-Message ("  -Env is REQUIRED for {0} (App1). Specify -Env Prod|Dev|Test|SBox; got '{1}'." -f $Tag, $Env) -Fore Red
            $script:OnError = $true; $ok = $false
        }
    }
    if ($dbs | Where-Object { $_.App -eq "App2" }) {
        # App2 client/batch only exists for the dev-side envs.
        if (($Env -eq "All") -or (-not (Get-App2EnvStem -Env $Env))) {
            Write-Message ("  -Env is REQUIRED for {0} (App2) and must be Dev, Test, or SBox; got '{1}'." -f $Tag, $Env) -Fore Red
            $script:OnError = $true; $ok = $false
        }
    }
    return $ok
}

# CLIENT - launch the Progress GUI client for a single environment.
if ($Client -eq $true) {
    Write-Section "CLIENT (prowin/prowin32/_progres)"
    $ct = if (Test-ClientTargets -Tag "Client") {
        @($Targets | Where-Object { $_.Component -eq "Database" })
    } else { @() }

    if ($ct.Count -eq 0) {
        Write-Message "  No valid local database target selected for -Client (App1: -Site S1|S2 + -Env Dev|Test|SBox; App2: -Env Dev|Test|SBox; or pass -Ini and -Pf explicitly, or use the -Remote parameter)." -Fore Yellow
    }
    # The client launch (exe/ini/pf) is per ENVIRONMENT, not per database - the
    # INI/PF resolve from Server/App/Env/Site + DLC, never from the db name.  So
    # collapse the db targets to one launch per unique environment; otherwise the
    # client fires once for every database in the set (identical command lines).
    $ct = @($ct | Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.Server, $_.App, $_.Env, $_.Site, $_.DLC } |
                  ForEach-Object { $_.Group[0] })
    foreach ($t in $ct) { if (Test-CanAct -Item $t) { Do-Client -Item $t } }
}

# BATCH - run a Progress program in batch mode for a single environment.  Same
# target rules as -Client with one extra requirement: -Pgm <program>.p.
if ($Batch -eq $true) {
    Write-Section "BATCH (prowin/prowin32/_progres -b)"

    $havePgm = -not [string]::IsNullOrWhiteSpace($Pgm)
    if (-not $havePgm) {
        Write-Message "  -Pgm <program>.p is REQUIRED for -Batch (the program to run)." -Fore Red
        $script:OnError = $true
    }

    $bt = if ((Test-ClientTargets -Tag "Batch") -and $havePgm) {
        @($Targets | Where-Object { $_.Component -eq "Database" })
    } else { @() }

    if ($bt.Count -eq 0) {
        Write-Message "  No valid local database target selected for -Batch (use -Pgm <program>.p, plus App1: -Site S1|S2 + -Env Dev|Test|SBox, or App2: -Env Dev|Test|SBox, or pass -Ini and -Pf explicitly, or use the -Remote parameter)." -Fore Yellow
    }
    # One batch launch per environment, not per database (see -Client note above).
    $bt = @($bt | Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.Server, $_.App, $_.Env, $_.Site, $_.DLC } |
                  ForEach-Object { $_.Group[0] })
    foreach ($t in $bt) { if (Test-CanAct -Item $t) { Do-Batch -Item $t } }
}

# NOTIFICATIONS - email + Windows EventLog on any error.
if ($OnError -eq $true -or $OnLogError -eq $true -or $OnPortError -eq $true) {
    $summary = "OEAdmin run had errors. OnError=$OnError OnLogError=$OnLogError OnPortError=$OnPortError. See $LogFile."
    if ($EmailOnError -eq $true) {
        Send-Email-Error -Subject "OEAdmin - ERROR" -Body $summary
    }
    Write-OEEventLog -Message $summary -EventID 2001 -EntryType "Error"
}

# Email the full log when requested, or whenever an error occurred.
if ($LogFileEmail -eq $true -or (($OnError -eq $true -or $OnLogError -eq $true -or $OnPortError -eq $true) -and $EmailOnError -eq $true)) {
    Send-Email-Log -Subject "OEAdmin - Run Log"
}

Write-Section "SCRIPT COMPLETED"

if ($OnError -eq $true)     { exit 2001 }
if ($OnLogError -eq $true)  { exit 2002 }
if ($OnPortError -eq $true) { exit 2003 }
exit 0

## ============================================================================
## CUSTOMIZATION CHECKLIST (search for "CHANGE THIS" to find each spot)
## ============================================================================
##  1. $Installs table .......... your servers, tiers, OpenEdge versions, DLCs, ports
##  2. -App ValidateSet ......... your application names (keep in sync with $Installs)
##  3. $ValidSites / -Site ...... your site codes (or drop sites if you have none)
##  4. Parse-App1Database /
##     Parse-App2Database ....... your database NAMING CONVENTION (the regex + maps)
##  5. Path defaults ............ $DlcBase, $App1BackupDir/$App2BackupBase,
##                                $App1SetupDir/$App2SetupDir
##  6. Get-BackupDevice ......... your backup file names/layout
##  7. Get-App2EnvStem .......... your single-site app's INI/PF stem per env
##  8. Resolve-ClientLaunch ..... client exe per OpenEdge version (GUI vs _progres)
##  9. SMTP block ............... $SmtpServer/$SmtpPort/$EmailFrom/$EmailTo
## 10. Convert-ToRemotePath ..... only if you use -Remote (cross-server paths)
## 11. $StartupProgram ......... the -Run startup .p (if you use one)
