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

1.1.0 - Added five more -Client launch switches, each appending one "-p" program
        and MUTUALLY EXCLUSIVE with -Run and each other: -Editor (_edit.p),
        -AppBuilder (_ab.p), -Desktop (_desk.p), -Dict (_dict.p), -Admin
        (_admin.p).  -Run still appends the configurable $StartupProgram.  A new
        Get-ClientRunProgram helper resolves the single program.  Wired into -Menu
        (a single "Launch into which program?" picker replaces the old startup
        yes/no prompt).

#>

<#

.DESCRIPTION

OEAdmin.ps1 - a cross-platform PowerShell administration script for OpenEdge
databases.

Manages OpenEdge database brokers (via the "dbman" command through the
AdminServer), the NameServer (nsman), and optionally the MS SQL DataServer
broker (mssman) and Oracle DataServer broker (oradvman), across any number of
servers, sites, environments, and OpenEdge versions.

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
    -CopyBackup  Push production backups to the dev server's NAMED share
                 (\\<Dest>\<BackupShareName>\..., not the admin drive$ share;
                 -Dest overrides the per-app default dev server).  RUNS ON THE
                 PRODUCTION server (source is a local path).
                 A .bk over -SplitThresholdBytes is binary-split into
                 -SplitSliceBytes slices (progress meter), each slice copied with
                 retry/backoff and the local slice deleted on success; the dev
                 side reassembles slices at restore time.  Scoped by -App.
                 -AsyncCopy pipelines the split and the copy (disk + network
                 overlap, bounded by -AsyncQueueDepth); default is synchronous.
    -Restore     prorest a staged production backup into the -Env Dev/Test/SBox
                 target (stop -> prorest -> start).  DEVELOPMENT servers only.
                 If only split slices are staged, reassembles them first.
                 -Site is REQUIRED when an app has multiple sites (see below).
    -Client      Launch the Progress GUI client (prowin/prowin32) for one
                 environment.  See per-app rules under the -Client parameter.
    -Batch       Same as -Client but runs a program in batch: the command line
                 ends with "-p <program> -b".  -Pgm <program>.p is REQUIRED.

Backup / restore safety model:
    A server Tier (Production vs Development) is attached to every install.
    -Backup and -CopyBackup run on a PRODUCTION server (the backups are local
    there - -CopyBackup splits/pushes them to the dev share); -Restore runs on a
    DEVELOPMENT server.  This structurally prevents the atypical prod-restore /
    dev-backup cases.

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

    # ...and run the startup program on launch (-p $StartupProgram)
    ./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test -Run

    # ...or launch straight into a Progress tool (mutually exclusive with -Run):
    # -Editor -p _edit.p, -AppBuilder -p _ab.p, -Desktop -p _desk.p,
    # -Dict -p _dict.p, -Admin -p _admin.p
    ./OEAdmin.ps1 -Client -App App1 -Site S1 -Env Test -Editor

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
    # Valid: Database, NameServer, MSSQLBroker, OracleBroker, or "All".
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

    # Push production backups to the dev server's named share, splitting large
    # .bk files into slices (copied with retry) that the dev side reassembles at
    # restore time.  MUST RUN ON THE PRODUCTION server (source is a local path).
    # See the COPY-BACKUP param group for the share/split/retry settings.
    [switch]$CopyBackup,

    # -Git: the git action group (local repo/worktree maintenance under
    # $GitReposRoot).  Pair with a git sub-action; today -UpdateRepos and
    # -NewWorkspace.  Designed to grow (status / fetch).
    #   ./OEAdmin.ps1 -Git -UpdateRepos
    #   ./OEAdmin.ps1 -Git -NewWorkspace -App App1 -BaseBranch main -NewBranch my-fix
    [switch]$Git,

    # -UpdateRepos (a -Git sub-action): fast-forward every worktree of each mapped
    # repo under $GitReposRoot - fetch the bare repo, then `merge --ff-only
    # origin/<branch>` per worktree.  Safe (ff-only won't clobber local work).  Also
    # usable with -Client/-Batch to refresh the chosen -Workspace before launching.
    [switch]$UpdateRepos,

    # -NewWorkspace (a -Git sub-action): create a new git WORKING COPY (worktree)
    # under $GitReposRoot for a chosen repo/app, based on an existing branch and
    # (optionally) a new branch cut from it.  The worktree folder is named after the
    # branch (slashes -> hyphens), so it's immediately selectable as a
    # -Client/-Batch -Workspace.  Honors -DryRun.  ASSUMES the bare+worktree layout:
    # if no .bare exists it will NOT silently clone - see -BootstrapClone.  Refuses
    # if the target folder exists or the base branch is already checked out in
    # another worktree (git allows a branch in one worktree only).
    #   -App <name>      which app's repo (required; a specific app, not All).
    #   -BaseBranch <b>  existing branch to base on (menu -> pick from a list).
    #   -NewBranch <b>   optional new branch cut off -BaseBranch; blank = use
    #                    -BaseBranch as-is.
    #   -BootstrapClone  allow creating the .bare when missing (opt-in; see below).
    [switch]$NewWorkspace,
    $BaseBranch="",
    $NewBranch="",

    # -BootstrapClone (a -NewWorkspace modifier): allow -NewWorkspace to create a
    # fresh bare clone (<GitReposRoot>\<Repo>\.bare) when one doesn't exist yet.
    # OFF by default so a developer NOT using the bare+worktree layout isn't given a
    # surprise second copy of the repo: without this switch, -NewWorkspace detects
    # the missing .bare, explains the layout assumption, and aborts.  In the menu
    # this is offered as a yes/no prompt instead of the switch.
    [switch]$BootstrapClone,

    ##### ---- GIT "DAY IN THE LIFE" SUB-ACTIONS -------------------------------
    # Convenience wrappers around everyday git, for developers who aren't fully
    # comfortable on the git command line.  All are -Git sub-actions and all run
    # in ONE working copy (the "current context"): the worktree chosen with
    # -Workspace, else -RepoPath, else the current directory if it's inside a git
    # repo (see Resolve-GitWorkDir).  They do NOT replace real git - they just
    # package the common calls with friendly output and (for the write ones)
    # confirmations.  READ-ONLY (safe, change nothing):
    #   -GitStatus     status + ahead/behind + commits waiting on the server.
    #   -GitDiff       uncommitted changes; -DiffVs <ref> diffs against a ref.
    #   -GitLog        pretty history (log --oneline --graph --decorate).
    #   -GitStashList  git stash list.
    [switch]$GitStatus,
    [switch]$GitDiff,
    [switch]$GitLog,
    [switch]$GitStashList,

    # STASH save/restore (safe, but they move your uncommitted work around):
    #   -GitStash      shelve uncommitted changes (git stash push).
    #   -GitStashPop   restore the most recently shelved changes (git stash pop).
    [switch]$GitStash,
    [switch]$GitStashPop,

    # WRITE sub-actions (guarded - show what will happen + confirm; honor -DryRun;
    # never use --force):
    #   -GitCommit -Message "..."  stage + commit.  -Message REQUIRED.  -AddAll
    #                  stages everything (git add -A), else only staged changes.
    #   -GitPush       push current branch; first push auto-adds -u origin/<branch>.
    [switch]$GitCommit,
    [switch]$GitPush,

    # -GitHelp: print a "day in the life" git cheat sheet (common flow + the exact
    # commands for what OEAdmin does NOT automate - rebase, conflicts, push
    # --force-with-lease, plain git switch).  Prints only; runs nothing.
    [switch]$GitHelp,

    # Modifiers for the git sub-actions above:
    #   -Message <text>  commit message for -GitCommit (required for it).
    #   -AddAll          -GitCommit: stage ALL changes (git add -A) before commit.
    #   -DiffVs <ref>    -GitDiff: diff against this ref instead of the working tree.
    #   -RepoPath <dir>  run the git sub-action here (overrides the current-dir
    #                    fallback; -Workspace still wins if set).
    #   -Yes             skip the confirmation prompt on -GitCommit / -GitPush.
    $Message="",
    [switch]$AddAll,
    $DiffVs="",
    $RepoPath="",
    [switch]$Yes,

    # Launch the Progress GUI client (prowin/prowin32) for one environment.
    #   Multi-site app: requires -Site and a single -Env; INI/PF share the
    #        <App><Env><Site> stem (e.g. app1DevS2.ini + app1DevS2.pf).
    #   Single-site app: no site; requires a single -Env; INI/PF stem is the env
    #        word (see Get-App2EnvStem).  Prod/ProdCopy are refused (dev-side tool).
    # The exe is chosen by the target's OpenEdge version (see Resolve-ClientLaunch).
    # Command line (all options space-separated):
    #   <exe> -ininame <ini> -pf <pf> [ -p <program> ]
    # where the optional "-p <program>" comes from one of the mutually-exclusive
    # launch switches -Run/-Editor/-AppBuilder/-Desktop/-Dict/-Admin.
    [switch]$Client,

    # When set with -Client, append "-p <StartupProgram>" (see $StartupProgram)
    # so the session runs a startup program on launch.
    [switch]$Run,

    # -Editor/-AppBuilder/-Desktop/-Dict/-Admin: launch -Client straight into a
    # standard Progress tool instead of the startup program, by appending its "-p"
    # program to the command line:
    #   -Editor     -> -p _edit.p    (Procedure Editor)
    #   -AppBuilder -> -p _ab.p      (AppBuilder)
    #   -Desktop    -> -p _desk.p    (Desktop)
    #   -Dict       -> -p _dict.p    (Data Dictionary)
    #   -Admin      -> -p _admin.p   (Data Administration)
    # These five and -Run are MUTUALLY EXCLUSIVE (at most one may be set); the
    # winner supplies the single "-p" program on the -Client command line.
    # (They are convenience aliases for entries in the $Tools map below.)
    [switch]$Editor,
    [switch]$AppBuilder,
    [switch]$Desktop,
    [switch]$Dict,
    [switch]$Admin,

    # -Tool: which program a -Client/-Batch session runs, by NAME from the $Tools
    # map below (e.g. -Tool DbUtil).  A data-driven alternative to the fixed
    # switches above - add a tool by editing $Tools, no code change.  -Run and the
    # -Editor/... switches are shorthands for the matching $Tools entry.
    $Tool="",

    # TOOL MAP (CHANGE THIS) - the set of programs a -Client/-Batch session can
    # launch into.  Each entry: Name (the -Tool value / menu label), Pgm (the "-p"
    # program), Extra (optional extra client args, e.g. -debugalert), App (optional
    # app scope - blank = any), Startup ([bool] - the app's -Run startup tool).
    # (The Startup Pgm mirrors $StartupProgram's default; keep them in sync, or
    # resolve Startup from $StartupProgram in code if you prefer one source.)
    $Tools=@(
        [PSCustomObject]@{ Name="Startup";    Pgm="sh/startup.p"; Extra=""; App=""; Startup=$true }
        [PSCustomObject]@{ Name="DbUtil";     Pgm="StartUtils.p"; Extra=""; App=""; Startup=$false }
        [PSCustomObject]@{ Name="Editor";     Pgm="_edit.p";       Extra=""; App=""; Startup=$false }
        [PSCustomObject]@{ Name="AppBuilder"; Pgm="_ab.p";         Extra=""; App=""; Startup=$false }
        [PSCustomObject]@{ Name="Desktop";    Pgm="_desk.p";       Extra=""; App=""; Startup=$false }
        [PSCustomObject]@{ Name="Dict";       Pgm="_dict.p";       Extra=""; App=""; Startup=$false }
        [PSCustomObject]@{ Name="Admin";      Pgm="_admin.p";      Extra=""; App=""; Startup=$false }
    ),

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

    ##### ---- COPY-BACKUP (prod -> dev)  (CHANGE THIS) ------------------------
    # -CopyBackup RUNS ON THE PRODUCTION server and PUSHES backups to the dev
    # server (rather than running on dev and pulling - a pull of a very large .bk
    # over a slow link can take many hours).  Big files are binary-split into
    # slices, the slices are copied to a NAMED share on the dev server (not the
    # admin drive$ / UNC admin share), then reassembled on the dev side at restore.

    # Dev server that backups are pushed to (the restore target host).  OVERRIDE
    # for a one-off; leave blank to use the per-app default below.  On the -Menu
    # this is a picker of all Development servers for the chosen app.
    $Dest="",

    # Per-app DEFAULT destination dev server, used when -Dest is blank.  CHANGE
    # THIS to your apps' dev servers.  (A value in -Dest always wins.)
    $CopyDestDefaults=@{ App1="dbserver1-dev"; App2="dbserver2-dev" },

    # NAMED share on the dev server mapping to its backup directory.  The copy
    # destination is \\<dest>\<BackupShareName>\... on Windows (a real share, NOT
    # the admin drive$ share).  On Linux set this to however you reach the dev
    # server's backup dir and adjust the destination-root build below.
    $BackupShareName="backups",

    # Only split a .bk whose size EXCEEDS this (bytes).  Files at/under it copy
    # whole.  Default 1GB.
    [long]$SplitThresholdBytes=1GB,

    # Size of each binary slice when splitting (bytes).  Default 1GB.
    [long]$SplitSliceBytes=1GB,

    # Per-file copy retry policy: on a failed slice/file copy, pause
    # $CopyRetryDelay seconds and retry, up to $CopyMaxRetries attempts, then flag
    # an error.  (MaxRetries 0 = try once, no retry.)
    [int]$CopyMaxRetries=5,
    [int]$CopyRetryDelay=15,

    # -AsyncCopy: for the LARGE-file (split) path, pipeline the split and the copy
    # so slice N copies over the network while slice N+1 is still being carved from
    # disk (disk I/O and network I/O overlap).  A background runspace consumes a
    # bounded queue of finished slices, copying each (with the same retry/backoff)
    # and deleting the local slice on success.  Default OFF (the proven synchronous
    # split-then-copy path runs instead).  Whole-file copies are unaffected.
    # (Runspace + BlockingCollection work on both Windows PowerShell 5.1 and 7.)
    [switch]$AsyncCopy,

    # Max finished slices allowed on local disk awaiting copy when -AsyncCopy is on
    # (bounds scratch: ~ depth * $SplitSliceBytes).  Default 3 => ~3 GB with 1GB
    # slices.  The splitter blocks once this many are queued.
    [int]$AsyncQueueDepth=3,

    ##### ---- CLIENT (-Client) SETUP LOCATIONS -------------------------------
    # The -Client/-Batch setup-tree root (formerly the global $App1SetupDir /
    # $App2SetupDir params) now lives PER INSTALL in the $Installs table below, as
    # each row's SetupDir.  This lets the root differ by machine AND OpenEdge
    # version.  Layout under each root is unchanged:
    #   <SetupDir>/ini/<server>/<stem>.ini      (App1 stem <App><Env><Site>, e.g.
    #                                            app1TestS1; App2 stem = env word)
    #   <SetupDir>/userPfs/<server>/<stem>.pf
    # CHANGE THIS by editing the SetupDir on each $Installs row.

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

    ##### ---- GIT REPOS / WORKING COPIES  (CHANGE THIS) -----------------------
    # Root of the local git repo layout, if you use the bare-clone + per-branch-
    # worktree model: each repo is <GitReposRoot>/<Repo>/.bare with one worktree
    # folder per branch.  Used by -Client/-Batch -Workspace launches and by
    # -Git -UpdateRepos.  Default is machine-aware (edit to taste).  Leave the
    # worktree features unused by simply not passing -Workspace / -Git.
    $GitReposRoot="",

    # Which git repos map to which app, for workspace discovery.  Only these repos
    # are offered as -Client/-Batch working copies.  CHANGE THIS to your repo->app
    # mapping (repo folder name under $GitReposRoot -> an -App value).
    $GitRepoApps=@{ App1="App1"; App2="App2" },

    # Clone URLs per repo, used by -Git -NewWorkspace -BootstrapClone to create a
    # bare clone when none exists yet under <GitReposRoot>\<Repo>\.bare.  CHANGE
    # THIS to your repo clone URLs (keys match $GitRepoApps).  Bootstrapping is
    # OPT-IN (the -BootstrapClone switch / a menu confirmation) so a developer not
    # on the bare+worktree layout isn't handed a surprise second copy of the repo.
    $GitProjects=@{
        App1 = "https://git.example.com/org/_git/App1"
        App2 = "https://git.example.com/org/_git/App2"
    },

    # -Workspace: launch -Client/-Batch from a git WORKING COPY (worktree) instead
    # of the installed code.  Value is the worktree's branch/folder token (slashes
    # shown as hyphens; see the menu / Get-WorkingCopies).  When set, prowin's
    # working directory is the worktree app folder and the INI's PROPATH is
    # rewritten to point at the worktree (see Resolve-WorkspaceIni).  Blank = use
    # the installed code.
    $Workspace="",

    ##### ---- INSTALL TABLE  (CHANGE THIS - the heart of the config) ----------
    # The ONE place server topology is defined.  Each row is one OpenEdge install:
    #   App       - which application this install hosts (matches -App / ValidateSet)
    #   Tier      - "Production" or "Development" (gates Backup vs Restore/CopyBackup)
    #   Server    - the hostname (matches -Server; compared to $env:COMPUTERNAME)
    #   OEVersion - the OpenEdge version string (matches -OEVersion)
    #   DLC       - the OpenEdge install directory for THIS install
    #   Port      - the AdminServer management port for THIS install
    #   SetupDir  - root of this install's -Client/-Batch INI/PF tree (INI under
    #               <SetupDir>/ini/<server>/, PF under <SetupDir>/userPfs/<server>/).
    #               It lives PER INSTALL (not as one global) because the root can
    #               differ by machine AND OpenEdge version - e.g. a 12.8 install and
    #               a 10.2B install on the same box, or a laptop with its tree on a
    #               different drive.  CHANGE THIS to your setup-tree roots.
    #   InstalledComponents - ALLOWLIST of shared components this install actually
    #               runs: any of "NameServer" / "MSSQLBroker" / "OracleBroker" (or
    #               @() for none).  A component discovered in ubroker.properties is only
    #               inventoried if its type is listed here, and components are only
    #               started/stopped when the selection covers the WHOLE server (see
    #               the START/STOP/RESTART dispatch).  Databases ignore this list.
    #               NOTE: it is PER INSTALL/AdminServer - two OE versions on one box
    #               each with their own AdminServer list their own components.
    #               CHANGE THIS to what each install really runs.
    #
    # A single server can host MULTIPLE installs (e.g. two OpenEdge versions side
    # by side on different DLCs and ports) - just add a row for each.
    #
    # The databases/NameServers/brokers themselves are NOT listed here; they are
    # discovered from each install's property files at run time.
    $Installs=@(
        # ---- App1: prod on dbserver1, dev on dbserver1-dev (two OE versions) ----
        [PSCustomObject]@{ App="App1"; Tier="Production";  Server="dbserver1";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; SetupDir="/opt/app1/setup";      InstalledComponents=@("NameServer") }
        [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; SetupDir="/opt/app1/setup";      InstalledComponents=@("NameServer","MSSQLBroker","OracleBroker") }
        [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="10.2B"; DLC="/usr/dlc102b"; Port=20941; SetupDir="/opt/app1/setup-102b"; InstalledComponents=@() }
        # ---- App2: prod on dbserver2, dev on dbserver2-dev ----------------------
        [PSCustomObject]@{ App="App2"; Tier="Production";  Server="dbserver2";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; SetupDir="/opt/app2/setup";      InstalledComponents=@("NameServer") }
        [PSCustomObject]@{ App="App2"; Tier="Development"; Server="dbserver2-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; SetupDir="/opt/app2/setup";      InstalledComponents=@() }
    )
)

## ============================================================================
## VARIOUS SETTINGS
## ============================================================================

# Seconds to wait after start/stop before re-checking.
$SleepAfterStart = 15
$SleepAfterStop  = 5

# Seconds to pause between successive operations on the SAME database within one
# multi-step sequence (e.g. restore's prodel -> prorest -> start).  Running those
# back-to-back can race the OS/OpenEdge releasing file handles from the previous
# step and throw a "database in use" error, so we settle for a few seconds in
# between.  3-5s is the sweet spot; skipped entirely in -DryRun.
$SettleDelay = 5

# Error state flags.
$OnError    = $false
$OnLogError = $false
$OnPortError= $false

# True when running on Windows (works in both Windows PowerShell 5.1 and pwsh 7).
# On PowerShell 7+ the automatic $IsWindows exists; on 5.1 it does not, so we
# fall back to the OS env var.  Used to decide tool extension (.bat) and EventLog.
$IsWindowsHost = if ($null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) { $IsWindows } else { ($env:OS -eq 'Windows_NT') }

# Resolve the git-repos root default if the caller didn't set it.  CHANGE THIS to
# your layout (e.g. E:\gitRepos on servers, C:\gitRepos on workstations, or a
# Linux path).  Only used by -Workspace / -Git.
if ([string]::IsNullOrWhiteSpace($GitReposRoot)) {
    $GitReposRoot = if (Test-Path "E:\gitRepos") { "E:\gitRepos" } elseif (Test-Path "/opt/gitRepos") { "/opt/gitRepos" } else { "C:\gitRepos" }
}

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
        # Accept the group if it is an explicit 4GL/combined group, OR if it has a
        # port but no type= line at all.  Older OE / single-default-group installs
        # (e.g. a lone [servergroup.*.defaultservergroup] with no type=) serve 4GL
        # clients implicitly, so a typeless port IS the 4GL listener.
        if ($curDb -and $curPort -and ($curType -eq "4gl" -or $curType -eq "both" -or -not $curType)) {
            $dedicated = ($curType -eq "4gl")   # only an explicit 4gl group is "dedicated"
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
                SetupDir  = $install.SetupDir      # -Client/-Batch INI/PF root for THIS install (per machine + version)
                Manager   = "dbman"
                DLC       = $itemDLC
                LogFile   = $dbLogFile
            })
        }

        # Allowlist of shared components this install actually runs.  A discovered
        # component is only inventoried if its type is in InstalledComponents (an
        # absent/empty list means "no shared components here", so none are added).
        $allowed = @($install.InstalledComponents)

        # ---- NameServer (nsman) ----
        if ($allowed -contains "NameServer") {
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
        }

        # ---- MS SQL DataServer broker (mssman) ----
        # If you do NOT use the MS SQL DataServer, leave MSSQLBroker out of this
        # install's InstalledComponents (or it simply won't be found in
        # ubroker.properties and nothing is added).
        if ($allowed -contains "MSSQLBroker") {
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

        # ---- Oracle DataServer broker (oradvman) ----
        # Same AdminServer-managed broker model as MS SQL (sections [UBroker.OR.*]
        # in ubroker.properties), just a different admin utility.  Leave OracleBroker
        # out of InstalledComponents on installs that don't run it.
        if ($allowed -contains "OracleBroker") {
        foreach ($or in (Get-BrokerNames -PropertiesDir $install.PropertiesDir -Prefix "UBroker.OR")) {
            $items.Add([PSCustomObject]@{
                Component = "OracleBroker"
                App       = $install.App
                Tier      = $install.Tier
                Role      = "OracleBroker"
                Server    = $install.Server
                Site      = "All"
                Env       = "All"
                OEVersion = $install.OEVersion
                Name      = $or
                Port      = $install.Port
                Manager   = "oradvman"
                DLC       = $itemDLC
            })
        }
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
    # 9.1E dbman accepts the same -host/-port/-database flags as 12.x, so the flag
    # form below is used for all versions (required for -Remote). 9.1E only differs
    # in -query OUTPUT wording, handled in Test-InstanceRunning.
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
            # 12.x wording: "database is running: Running" / "... Not running"
            # 9.1E wording: "database is running: true" / "... false"
            if ($o -match '(?im)database is running:\s*(Running|true|yes)') { return $true }
            if ($o -match '(?im)database is running:\s*(Not|false|no)')     { return $false }
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
        "OracleBroker" {
            # oradvman mirrors mssman's "Broker Status : ACTIVE" wording.
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

# Delete an existing OpenEdge database (prodel) so a subsequent prorest can
# recreate it - Progress refuses to prorest over an existing database.  prodel
# prompts "Are you sure? (y/n)"; we pipe "y" so it completes unattended.  The db
# argument is the databasename stem (no .db extension), same value probkup/prorest
# take; the physical file on disk is "<stem>.db".
function Invoke-OEDelete {
    param($Item)
    $exe = Get-OEToolPath $Item.DLC "prodel"
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] DLC={0}  prodel {1}  (auto-answering 'y')" -f $Item.DLC, $Item.DbPath) -Fore DarkGray
        return [PSCustomObject]@{ ExitCode=0; Output="[dry-run]" }
    }
    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        # Feed "y" to stdin so the "Are you sure?" prompt auto-confirms.
        $out  = "y" | & $exe $Item.DbPath 2>&1 | Out-String
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
    Write-Message ("  RUNNING: probkup online {0} {1}  (this can take a while)..." -f $Item.DbPath, $device) -Fore Cyan
    $r = Invoke-OEUtil -Item $Item -Util "probkup" -Arguments @("online", $Item.DbPath, $device)
    if ($r.ExitCode -ne 0 -and $DryRun -ne $true) {
        Write-Message ("  ERROR (exit $($r.ExitCode)): $($r.Output)") -Fore Red; $script:OnError = $true
    } else {
        Write-Message ("  COMPLETED: probkup of {0} -> {1}" -f $Item.Name, $device) -Fore Green
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

    # If the whole .bk isn't staged but a split/<basename>/ folder of slices is
    # (left by -CopyBackup for a large backup), reassemble it into the .bk first
    # so prorest has a normal file to restore from.
    if (-not (Test-Path -Path $source -PathType Leaf)) {
        $srcName  = [System.IO.Path]::GetFileName($source)
        $srcDir   = [System.IO.Path]::GetDirectoryName($source)
        $splitDir = Join-PathX $srcDir "split" $srcName
        if (Test-Path -Path $splitDir) {
            Write-Message ("  Backup not staged whole; reassembling {0} from slices in {1}..." -f $srcName, $splitDir) -Fore Cyan
            if ($DryRun -eq $true) {
                Write-Message ("  [DRYRUN] would reassemble {0} from {1} before prorest." -f $srcName, $splitDir) -Fore DarkGray
            } elseif (Join-BackupFile -SplitFolder $splitDir -OutFile $source) {
                Remove-Item -Path $splitDir -Recurse -Force -ErrorAction SilentlyContinue   # drop slices once whole
            } else {
                Write-Message ("  Restore: could not reassemble {0} - aborting restore." -f $srcName) -Fore Red
                $script:OnError = $true
                return
            }
        }
    }

    Do-Stop -Item $Item
    # prorest refuses to overwrite an existing database.  If one is present at the
    # target ("<DbPath>.db"), delete it first with prodel (auto-answering "y").
    $dbFile = "$($Item.DbPath).db"
    if (Test-Path -Path $dbFile -PathType Leaf) {
        Write-Message ("  RUNNING: prodel {0}  (existing db present, deleting before restore)..." -f $Item.DbPath) -Fore Cyan
        $d = Invoke-OEDelete -Item $Item
        if ($d.ExitCode -ne 0 -and $DryRun -ne $true) {
            Write-Message ("  ERROR deleting existing db (exit $($d.ExitCode)): $($d.Output)") -Fore Red
            $script:OnError = $true
            Do-Start -Item $Item
            return
        } else {
            Write-Message ("  COMPLETED: prodel of {0}" -f $Item.Name) -Fore Green
            # Settle after prodel so the OS/OpenEdge finishes releasing the
            # deleted db's file handles before prorest recreates it; otherwise a
            # back-to-back prorest can hit a "database in use" error.
            if ($DryRun -ne $true -and $SettleDelay -gt 0) {
                Write-Message ("  waiting {0}s after prodel (settling)" -f $SettleDelay) -Fore Yellow
                Start-Sleep -Seconds $SettleDelay
            }
        }
    } elseif ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] would prodel {0} first if an existing db is present." -f $Item.DbPath) -Fore DarkGray
    }
    Write-Message ("  RUNNING: prorest {0} {1}  (this can take a while)..." -f $Item.DbPath, $source) -Fore Cyan
    $r = Invoke-OEUtil -Item $Item -Util "prorest" -Arguments @($Item.DbPath, $source)
    if ($r.ExitCode -ne 0 -and $DryRun -ne $true) {
        Write-Message ("  ERROR (exit $($r.ExitCode)): $($r.Output)") -Fore Red; $script:OnError = $true
    } else {
        Write-Message ("  COMPLETED: prorest of {0} <- {1}" -f $Item.Name, $source) -Fore Green
    }
    # Settle after prorest so the restored db's file handles are fully released
    # before dbman -start opens it; a too-quick start can otherwise hit a
    # "database in use" error.
    if ($DryRun -ne $true -and $SettleDelay -gt 0) {
        Write-Message ("  waiting {0}s after prorest (settling)" -f $SettleDelay) -Fore Yellow
        Start-Sleep -Seconds $SettleDelay
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
    # Setup root comes from the install this item belongs to (per machine + version).
    $root = $Item.SetupDir
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
    if ($Item.App -eq "App2") {
        $stem = Get-App2EnvStem -Env $Item.Env
        if (-not $stem) { return $null }
        $p = Join-PathX $root "ini" $Item.Server ("$stem.ini")
    }
    else {
        # App1: needs a resolved Env + Site.
        if ([string]::IsNullOrWhiteSpace($Item.Env) -or [string]::IsNullOrWhiteSpace($Item.Site)) { return $null }
        $file = "{0}{1}{2}.ini" -f $Item.App, $Item.Env, $Item.Site
        $p = Join-PathX $root "ini" $Item.Server $file
    }
    # -Workspace: launch from a git working copy - use a per-workspace INI variant
    # with its PROPATH rewritten to the worktree (local runs only; see
    # Resolve-WorkspaceIni).
    if (-not [string]::IsNullOrWhiteSpace($Workspace) -and $Remote -ne $true) {
        $p = Resolve-WorkspaceIni -Item $Item -DefaultIni $p
        if (-not $p) { return $null }
    }
    if ($Remote -eq $true) { return (Convert-ToRemotePath -Server $Item.Server -LocalPath $p) }
    return $p
}

# Build the auto-derived PF path for a target.  Both apps keep PFs under
# <SetupDir>/userPfs/<server>/; stem as above (App1 <App><Env><Site>, App2 env word).
function Get-ClientPf {
    param($Item)
    # Setup root comes from the install this item belongs to (per machine + version).
    $root = $Item.SetupDir
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
    if ($Item.App -eq "App2") {
        $stem = Get-App2EnvStem -Env $Item.Env
        if (-not $stem) { return $null }
        $p = Join-PathX $root "userPfs" $Item.Server ("$stem.pf")
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Item.Env) -or [string]::IsNullOrWhiteSpace($Item.Site)) { return $null }
        $file = "{0}{1}{2}.pf" -f $Item.App, $Item.Env, $Item.Site
        $p = Join-PathX $root "userPfs" $Item.Server $file
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
    # Bare filename -> place it in the standard setup subdirectory for this item's
    # install (SetupDir comes from the $Installs row, per machine + version).
    $root = $Item.SetupDir
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
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

# Decide the single "-p" program to append to a -Client launch, based on which of
# the mutually-exclusive launch switches is set:
#   -Run        -> $StartupProgram (your configurable startup .p)
#   -Editor     -> _edit.p     -AppBuilder -> _ab.p     -Desktop -> _desk.p
#   -Dict       -> _dict.p     -Admin      -> _admin.p
# Returns $null when none is set (plain client launch, no -p).
function Get-ClientRunProgram {
    param($App = "")
    # -Tool <name> (data-driven) takes precedence over the fixed switches.
    if (-not [string]::IsNullOrWhiteSpace($Tool)) {
        $cands = @($Tools | Where-Object { $_.Name -ieq $Tool -and ($_.App -eq "" -or $_.App -eq $App) })
        $pick  = @($cands | Sort-Object { if ($_.App -eq $App) { 0 } else { 1 } })[0]
        if (-not $pick) {
            Write-Message ("  Unknown -Tool '{0}'. Valid: {1}" -f $Tool, ((@($Tools | Where-Object { $_.App -eq '' -or $_.App -eq $App }) | Select-Object -ExpandProperty Name -Unique) -join ', ')) -Fore Red
            $script:OnError = $true; return $null
        }
        $prog = $pick.Pgm
        if (-not [string]::IsNullOrWhiteSpace($pick.Extra)) { $prog = "$prog $($pick.Extra)" }
        return $prog
    }
    if ($Run        -eq $true) { return $StartupProgram }
    if ($Editor     -eq $true) { return "_edit.p" }
    if ($AppBuilder -eq $true) { return "_ab.p" }
    if ($Desktop    -eq $true) { return "_desk.p" }
    if ($Dict       -eq $true) { return "_dict.p" }
    if ($Admin      -eq $true) { return "_admin.p" }
    return $null
}

# Launch the Progress GUI client for one database target.  Command line (all
# options space-separated):  <exe> -ininame <ini> -pf <pf> [ -p <program> ]
# The optional "-p <program>" comes from Get-ClientRunProgram (the -Run startup
# program or a -Editor/-AppBuilder/-Desktop/-Dict/-Admin tool).
# ---- GIT WORKING COPIES + -Workspace launch (CHANGE THIS for your layout) ----
# These assume the bare-clone + per-branch-worktree layout: each repo at
# <GitReposRoot>/<Repo>/.bare with one worktree folder per branch.  If you use a
# different git layout, adjust Get-WorkingCopies / the AppPath probe.

# Discover the git working copies (worktrees) on disk for an app, via each mapped
# repo's bare clone.  Returns { App; Repo; Branch; Token; WorktreePath; AppPath }.
# Token is a filename-safe branch id; AppPath is the launchable content folder
# inside the worktree (probed: <wt>/<repo>, else <wt>).
function Get-WorkingCopies {
    param($App = "All")
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($repo in $GitRepoApps.Keys) {
        $repoApp = $GitRepoApps[$repo]
        if ($App -ne "All" -and $repoApp -ne $App) { continue }
        $bare = Join-PathX $GitReposRoot $repo ".bare"
        if (-not (Test-Path -Path $bare)) { continue }
        $lines = @()
        try { $lines = & git --git-dir="$bare" worktree list --porcelain 2>$null } catch { $lines = @() }
        $wt = $null; $br = $null
        $flush = {
            if ($wt -and ($wt -notmatch '[\\/]\.bare$')) {
                $appPath = $wt
                $cand = Join-PathX $wt $repo
                if (Test-Path -Path $cand) { $appPath = $cand }
                $branch = if ($br) { $br } else { Split-Path $wt -Leaf }
                $token  = ($branch -replace '[\\/]+','-')
                $results.Add([PSCustomObject]@{ App=$repoApp; Repo=$repo; Branch=$branch; Token=$token; WorktreePath=$wt; AppPath=$appPath })
            }
            $wt = $null; $br = $null
        }
        foreach ($ln in $lines) {
            if ($ln -match '^worktree\s+(.+)$')   { & $flush; $wt = $Matches[1] }
            elseif ($ln -match '^branch\s+(.+)$')  { $br = ($Matches[1] -replace '^refs/heads/','') }
        }
        & $flush
    }
    return $results
}

# The prowin working directory for a -Workspace launch (the chosen working copy's
# AppPath), or $null when no/invalid -Workspace.
function Get-WorkspaceWorkDir {
    param($App)
    if ([string]::IsNullOrWhiteSpace($Workspace)) { return $null }
    $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
    if ($wc) { return $wc.AppPath }
    return $null
}

# Produce the per-WORKSPACE INI for a working-copy launch: target name
# "<default-stem>-<Token>.ini"; if it exists use it, else copy the default INI and
# rewrite its PROPATH= line, replacing path segments under the install root
# ($Item.SetupDir) with the worktree AppPath (Progress/UNC segments untouched).
function Resolve-WorkspaceIni {
    param($Item, $DefaultIni)
    $wc = @(Get-WorkingCopies -App $Item.App | Where-Object { $_.Token -ieq $Workspace })[0]
    if (-not $wc) {
        Write-Message ("  Workspace '{0}' not found for app {1} under {2}." -f $Workspace, $Item.App, $GitReposRoot) -Fore Red
        $script:OnError = $true; return $null
    }
    $dir  = [System.IO.Path]::GetDirectoryName($DefaultIni)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($DefaultIni)
    $wsIni = Join-PathX $dir ("{0}-{1}.ini" -f $stem, $wc.Token)
    if (Test-Path -Path $wsIni -PathType Leaf) { return $wsIni }
    if (-not (Test-Path -Path $DefaultIni -PathType Leaf)) {
        Write-Message ("  Workspace: default INI not found to derive from: {0}" -f $DefaultIni) -Fore Red
        $script:OnError = $true; return $null
    }
    $installRoot = $Item.SetupDir.TrimEnd('/','\')
    $worktree    = $wc.AppPath.TrimEnd('/','\')
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] would create {0} (PROPATH {1} -> {2})" -f (Split-Path $wsIni -Leaf), $installRoot, $worktree) -Fore DarkGray
        return $DefaultIni
    }
    $lines = Get-Content -Path $DefaultIni
    $out = foreach ($ln in $lines) {
        if ($ln -match '^(?i)PROPATH\s*=') {
            $eq = $ln.IndexOf('='); $key = $ln.Substring(0,$eq+1); $val = $ln.Substring($eq+1)
            $newSegs = foreach ($s in ($val -split ',')) {
                $st = $s.Trim()
                if ($st -ieq $installRoot) { $worktree }
                elseif ($st -ilike ($installRoot + '\*') -or $st -ilike ($installRoot + '/*')) { $worktree + $st.Substring($installRoot.Length) }
                else { $s }
            }
            $key + ($newSegs -join ',')
        } else { $ln }
    }
    Set-Content -Path $wsIni -Value $out -Encoding ascii
    return $wsIni
}

# Run a git command (local to the box's repos); -DryRun just prints it.  Returns
# $true on success.  A fetch touches the remote - works from the user's session.
function Invoke-Git {
    param([string[]]$Arguments, $Label)
    $display = "git " + ($Arguments -join ' ')
    if ($DryRun -eq $true) { Write-Message ("  [DRYRUN] {0}" -f $display) -Fore DarkGray; return $true }
    try {
        $out = & git @Arguments 2>&1 | Out-String; $code = $LASTEXITCODE
    } catch {
        Write-Message ("  {0}: git error: {1}" -f $Label, $_.Exception.Message) -Fore Red; $script:OnError = $true; return $false
    }
    if ($code -ne 0) {
        Write-Message ("  {0}: git exit {1}`n{2}" -f $Label, $code, $out.Trim()) -Fore Red; $script:OnError = $true; return $false
    }
    if ($out.Trim()) { Write-Message ("    {0}" -f ($out.Trim() -replace "`r?`n", "`n    ")) -Fore DarkGray }
    return $true
}

# Fast-forward every worktree of the mapped repos under $GitReposRoot: fetch the
# bare repo, then `merge --ff-only origin/<branch>` per worktree (ff-only won't
# clobber local work).  -App scopes to one app's repos; -OnlyRepo/-OnlyToken to
# one repo/worktree (used by the -Client/-Batch refresh-before-launch).
function Invoke-UpdateRepos {
    param($App = "All", $OnlyRepo = "", $OnlyToken = "")
    Write-Section "GIT - UPDATE REPOS (fetch + ff-only per worktree)"
    $anyRepo = $false
    foreach ($repo in $GitRepoApps.Keys) {
        if ($App -ne "All" -and $GitRepoApps[$repo] -ne $App) { continue }
        if (-not [string]::IsNullOrWhiteSpace($OnlyRepo) -and $repo -ne $OnlyRepo) { continue }
        $bare = Join-PathX $GitReposRoot $repo ".bare"
        if (-not (Test-Path -Path $bare)) { Write-Message ("  {0}: no bare repo at {1} - skipping" -f $repo, $bare) -Fore Yellow; continue }
        $anyRepo = $true
        Write-Message ("Repo: {0}" -f $repo) -Fore Cyan
        [void](Invoke-Git -Arguments @("--git-dir=$bare","fetch","origin") -Label "$repo fetch")
        $wcs = @(Get-WorkingCopies -App $GitRepoApps[$repo] | Where-Object { $_.Repo -eq $repo })
        if (-not [string]::IsNullOrWhiteSpace($OnlyToken)) { $wcs = @($wcs | Where-Object { $_.Token -ieq $OnlyToken }) }
        foreach ($wc in $wcs) {
            Write-Message ("  {0} ({1})" -f $wc.Token, $wc.Branch) -Fore Gray
            [void](Invoke-Git -Arguments @("-C",$wc.WorktreePath,"merge","--ff-only","origin/$($wc.Branch)") -Label "$($wc.Token) ff-only")
        }
    }
    if (-not $anyRepo) { Write-Message ("  No git repos found under {0}." -f $GitReposRoot) -Fore Yellow }
}

# Reject names with characters illegal in a Windows folder (and so in a worktree
# folder / branch token).  Returns $true when the name is usable.
function Test-GitWorkspaceName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return ($Name -notmatch '[\\/:*?"<>|]')
}

# Is <GitReposRoot>\<Repo>\.bare an actual bare repo?  The worktree feature set
# (-NewWorkspace, -UpdateRepos, -Workspace discovery) assumes the "bare clone +
# per-branch worktree" layout.  Returns $true only when .bare exists AND git
# agrees it is a repository - so a developer on a conventional single clone (no
# .bare) is correctly detected as "not this layout".
function Test-BareLayout {
    param([string]$Bare)
    if (-not (Test-Path -Path $Bare)) { return $false }
    try {
        $out = & git --git-dir="$Bare" rev-parse --is-bare-repository 2>$null
        return (($out | Select-Object -First 1) -match '^(?i)true$')
    } catch { return $false }
}

# List the branches known to a bare repo (remote-tracking refs, origin/ stripped,
# HEAD pointer dropped, sorted unique) - what a fresh worktree would base on.
function Get-GitBranchList {
    param([string]$Bare)
    $raw = @()
    try { $raw = & git --git-dir="$Bare" branch -r 2>$null } catch { $raw = @() }
    $names = foreach ($ln in $raw) {
        $t = $ln.Trim()
        if ($t -match 'HEAD\s*->') { continue }
        ($t -replace '^origin/','')
    }
    return @($names | Where-Object { $_ } | Sort-Object -Unique)
}

# Branches ALREADY checked out in some worktree of this bare repo.  Git allows a
# branch in only ONE worktree, so `worktree add` on an already-checked-out branch
# fails; we pre-flight against this to give a friendly message instead of git's
# raw "fatal: '<b>' is already checked out".
function Get-WorktreeCheckedOutBranches {
    param([string]$Bare)
    $lines = @()
    try { $lines = & git --git-dir="$Bare" worktree list --porcelain 2>$null } catch { $lines = @() }
    $branches = foreach ($ln in $lines) {
        if ($ln -match '^branch\s+refs/heads/(.+)$') { $Matches[1] }
    }
    return @($branches | Where-Object { $_ })
}

# -Git -NewWorkspace: create a new git WORKING COPY (worktree) for one app's repo,
# based on an existing branch and optionally a new branch cut from it.  Rather than
# a fresh full clone into a folder, we `git worktree add` a new folder off the
# repo's existing .bare, so the result plugs straight into the -Client/-Batch
# -Workspace picker.  All git goes through Invoke-Git (so -DryRun is honored).
# Non-destructive: refuses if the target folder exists or the base branch is
# already checked out elsewhere; `worktree add` never disturbs other worktrees.
#
# LAYOUT SAFETY: assumes the bare+worktree layout.  If no .bare is found for the
# repo (a developer on a plain single clone), it does NOT silently create a second
# copy.  It explains the situation and only bootstrap-clones a bare repo when
# explicitly allowed (-BootstrapClone on the CLI, or confirmed in the menu);
# otherwise it aborts with guidance.
#   -App             which app's repo (required; resolved to the mapped repo).
#   -BaseBranch      existing branch to base on (caller validates it exists).
#   -NewBranch       optional new branch cut off BaseBranch; blank = use BaseBranch.
#   -BootstrapClone  allow creating the .bare if it's missing (opt-in).
function Invoke-NewWorkspace {
    param($App = "", $BaseBranch = "", $NewBranch = "", [bool]$BootstrapClone = $false)
    Write-Section "GIT - NEW WORKSPACE (git worktree add)"

    if ([string]::IsNullOrWhiteSpace($App) -or $App -eq "All") {
        Write-Message "  -NewWorkspace needs a specific -App (e.g. -App App1), not All." -Fore Red
        $script:OnError = $true; return
    }
    $repo = @($GitRepoApps.Keys | Where-Object { $GitRepoApps[$_] -eq $App })[0]
    if (-not $repo) {
        Write-Message ("  No git repo mapped to app {0} (see `$GitRepoApps)." -f $App) -Fore Red
        $script:OnError = $true; return
    }
    $bare = Join-PathX $GitReposRoot $repo ".bare"

    # LAYOUT CHECK: is this the expected bare+worktree layout?  If not, explain and
    # only continue (bootstrap a bare clone) when the caller allowed it.
    if (-not (Test-BareLayout -Bare $bare)) {
        Write-Message ("  No bare repo found at {0}." -f $bare) -Fore Yellow
        Write-Message  "  -NewWorkspace expects the bare-clone + per-branch-worktree layout" -Fore Yellow
        Write-Message ("  under {0} (each repo at <root>\<Repo>\.bare, one worktree folder" -f $GitReposRoot) -Fore Yellow
        Write-Message  "  per branch).  It looks like this machine does not use that layout." -Fore Yellow
        if (-not $BootstrapClone) {
            Write-Message  "  Not continuing (no change made).  Re-run with -BootstrapClone to create" -Fore Yellow
            Write-Message  "  a fresh bare repo here (a SEPARATE copy from any existing clone), or use" -Fore Yellow
            Write-Message  "  your own plain `git clone` if you're not on the bare+worktree layout." -Fore Yellow
            $script:OnError = $true; return
        }
        $url = $null
        if ($GitProjects -and $GitProjects.ContainsKey($repo)) { $url = $GitProjects[$repo] }
        if ([string]::IsNullOrWhiteSpace($url)) {
            Write-Message ("  -BootstrapClone requested but no clone URL in `$GitProjects for {0}." -f $repo) -Fore Red
            $script:OnError = $true; return
        }
        Write-Message ("  Bootstrapping a bare clone from {0}" -f $url) -Fore Cyan
        if (-not (Invoke-Git -Arguments @("clone","--bare",$url,$bare) -Label "$repo bare clone")) { return }
        [void](Invoke-Git -Arguments @("--git-dir=$bare","config","remote.origin.fetch","+refs/heads/*:refs/remotes/origin/*") -Label "$repo refspec")
    }

    Write-Message ("Repo: {0}  ({1})" -f $repo, $bare) -Fore Cyan
    [void](Invoke-Git -Arguments @("--git-dir=$bare","fetch","origin") -Label "$repo fetch")

    if ([string]::IsNullOrWhiteSpace($BaseBranch)) {
        Write-Message "  No -BaseBranch given (required for -NewWorkspace outside the menu)." -Fore Red
        $script:OnError = $true; return
    }
    if ($DryRun -ne $true) {
        $known = Get-GitBranchList -Bare $bare
        if ($known.Count -gt 0 -and ($known -notcontains $BaseBranch)) {
            Write-Message ("  Base branch '{0}' not found in {1}. Known: {2}" -f $BaseBranch, $repo, ($known -join ', ')) -Fore Red
            $script:OnError = $true; return
        }
    }

    $makeNew  = -not [string]::IsNullOrWhiteSpace($NewBranch)
    $checkout = if ($makeNew) { $NewBranch } else { $BaseBranch }
    if (-not (Test-GitWorkspaceName $checkout)) {
        Write-Message ("  Invalid branch/folder name '{0}' (no \ / : * ? `" < > |)." -f $checkout) -Fore Red
        $script:OnError = $true; return
    }
    $token  = ($checkout -replace '[\\/]+','-')
    $wtPath = Join-PathX $GitReposRoot $repo $token

    if (Test-Path -Path $wtPath) {
        Write-Message ("  Worktree folder already exists: {0}" -f $wtPath) -Fore Red
        $script:OnError = $true; return
    }

    # PRE-FLIGHT the "branch already checked out" case (git: one worktree per
    # branch).  Friendly message instead of git's raw fatal.  Skipped under -DryRun.
    if ($DryRun -ne $true) {
        $already = Get-WorktreeCheckedOutBranches -Bare $bare
        if ($already -contains $checkout) {
            Write-Message ("  Branch '{0}' is already checked out in another worktree of {1}." -f $checkout, $repo) -Fore Red
            Write-Message  "  Git allows a branch in only one worktree at a time.  Pick a different" -Fore Yellow
            Write-Message  "  base/new branch, or launch the existing worktree with -Workspace." -Fore Yellow
            $script:OnError = $true; return
        }
    }

    if ($makeNew) {
        Write-Message ("New branch '{0}' off '{1}' -> {2}" -f $NewBranch, $BaseBranch, $wtPath) -Fore Gray
        if (-not (Invoke-Git -Arguments @("--git-dir=$bare","worktree","add","-b",$NewBranch,$wtPath,"origin/$BaseBranch") -Label "$token worktree add")) { return }
    } else {
        Write-Message ("Branch '{0}' -> {1}" -f $BaseBranch, $wtPath) -Fore Gray
        if (-not (Invoke-Git -Arguments @("--git-dir=$bare","worktree","add",$wtPath,$BaseBranch) -Label "$token worktree add")) { return }
    }

    Write-Message "" -Fore Gray
    Write-Message "New workspace created:" -Fore Green
    Write-Message ("  App / Repo   : {0} / {1}" -f $App, $repo) -Fore Gray
    Write-Message ("  Base branch  : {0}" -f $BaseBranch) -Fore Gray
    if ($makeNew) { Write-Message ("  New branch   : {0}" -f $NewBranch) -Fore Gray }
    Write-Message ("  Worktree     : {0}" -f $wtPath) -Fore Gray
    Write-Message ("  Workspace id : {0}   (use: -Client -App {1} -Workspace {0})" -f $token, $App) -Fore Gray
}

## ============================================================================
## GIT "DAY IN THE LIFE" HELPERS  (everyday git, scoped to one working copy)
## ============================================================================

# Resolve the working directory a git sub-action runs in, in priority order:
#   1. -Workspace <token>  -> that worktree's folder (Get-WorkingCopies; -App
#      scopes the search, "All" searches every mapped app).
#   2. -RepoPath <dir>     -> an explicit folder.
#   3. the current directory, IF it is inside a git work tree.
# Returns the path, or $null (with a message) when nothing usable is found.
function Resolve-GitWorkDir {
    param($App = "All")
    if (-not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
        if ($wc) { return $wc.WorktreePath }
        Write-Message ("  -Workspace '{0}' not found for app {1} under {2}." -f $Workspace, $App, $GitReposRoot) -Fore Red
        return $null
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoPath)) {
        if (Test-Path -Path $RepoPath) { return $RepoPath }
        Write-Message ("  -RepoPath not found: {0}" -f $RepoPath) -Fore Red
        return $null
    }
    $here = (Get-Location).Path
    $inside = $null
    try { $inside = & git -C "$here" rev-parse --is-inside-work-tree 2>$null } catch { $inside = $null }
    if (($inside | Select-Object -First 1) -match '^(?i)true$') { return $here }
    Write-Message "  No working copy selected.  Use -Workspace <token> or -RepoPath <dir>," -Fore Red
    Write-Message "  or run from inside a git working copy." -Fore Red
    return $null
}

# The short branch name HEAD points at in a work tree (or "" if detached/none).
function Get-GitCurrentBranch {
    param($WorkDir)
    $b = ""
    try { $b = (& git -C "$WorkDir" rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1) } catch { $b = "" }
    if ($b -eq "HEAD") { $b = "" }
    return ($b | ForEach-Object { "$_".Trim() })
}

# Run a read-only git command in $WorkDir and echo its output verbatim (these
# change nothing, so they run even under -DryRun).  Keeps git's own formatting.
function Show-Git {
    param($WorkDir, [string[]]$Arguments, $Heading)
    if ($Heading) { Write-Message $Heading -Fore Cyan }
    Write-Message ("  > git " + ($Arguments -join ' ')) -Fore DarkGray
    try {
        $out = & git -C "$WorkDir" @Arguments 2>&1 | Out-String
    } catch {
        Write-Message ("  git error: {0}" -f $_.Exception.Message) -Fore Red; $script:OnError = $true; return
    }
    if ($out.Trim()) { Write-Host $out.TrimEnd() } else { Write-Message "  (no output)" -Fore DarkGray }
    Write-Host ""
}

# -GitStatus: status + ahead/behind upstream + commits waiting on the server.
function Invoke-GitStatus {
    param($App = "All")
    Write-Section "GIT - STATUS"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    $br = Get-GitCurrentBranch -WorkDir $wd
    Write-Message ("Working copy: {0}   Branch: {1}" -f $wd, $(if ($br) { $br } else { "(detached)" })) -Fore Blue
    Show-Git -WorkDir $wd -Arguments @("status","-sb") -Heading "Status (short):"
    if ($br) {
        Show-Git -WorkDir $wd -Arguments @("log","--oneline","HEAD..origin/$br") -Heading "Waiting on origin/$br (a pull would bring these in):"
    }
}

# -GitDiff: uncommitted changes, or (with -DiffVs <ref>) the diff against a ref.
function Invoke-GitDiff {
    param($App = "All")
    Write-Section "GIT - DIFF"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    if (-not [string]::IsNullOrWhiteSpace($DiffVs)) {
        Show-Git -WorkDir $wd -Arguments @("diff","--stat",$DiffVs) -Heading ("Changed files vs {0}:" -f $DiffVs)
        Show-Git -WorkDir $wd -Arguments @("diff",$DiffVs) -Heading ("Diff vs {0}:" -f $DiffVs)
    } else {
        Show-Git -WorkDir $wd -Arguments @("diff","--stat") -Heading "Changed files (uncommitted):"
        Show-Git -WorkDir $wd -Arguments @("diff") -Heading "Uncommitted diff:"
    }
}

# -GitLog: compact, graphed, decorated recent history.
function Invoke-GitLog {
    param($App = "All")
    Write-Section "GIT - LOG"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    Show-Git -WorkDir $wd -Arguments @("log","--oneline","--graph","--decorate","-30") -Heading "Recent history (last 30):"
}

# -GitStashList: what you've shelved.
function Invoke-GitStashList {
    param($App = "All")
    Write-Section "GIT - STASH LIST"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    Show-Git -WorkDir $wd -Arguments @("stash","list") -Heading "Stashes:"
}

# -GitStash: shelve uncommitted changes so you can switch tasks with a clean tree.
function Invoke-GitStash {
    param($App = "All")
    Write-Section "GIT - STASH (shelve uncommitted changes)"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    Show-Git -WorkDir $wd -Arguments @("status","-sb") -Heading "Before stashing:"
    [void](Invoke-Git -Arguments @("-C",$wd,"stash","push","-m","OEAdmin stash $(Get-Date -Format 'yyyy-MM-dd HH:mm')") -Label "stash push")
    if ($DryRun -ne $true) { Write-Message "  Shelved.  Restore later with -Git -GitStashPop (git stash pop)." -Fore Green }
}

# -GitStashPop: restore the most recently shelved changes.
function Invoke-GitStashPop {
    param($App = "All")
    Write-Section "GIT - STASH POP (restore shelved changes)"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    [void](Invoke-Git -Arguments @("-C",$wd,"stash","pop") -Label "stash pop")
    if ($DryRun -ne $true) { Show-Git -WorkDir $wd -Arguments @("status","-sb") -Heading "After pop:" }
}

# -GitCommit: guarded stage + commit.  -Message REQUIRED.  -AddAll stages
# everything first; else only already-staged changes.  Shows status + staged diff
# and confirms (unless -Yes).  Never amends/force.
function Invoke-GitCommit {
    param($App = "All")
    Write-Section "GIT - COMMIT"
    if ([string]::IsNullOrWhiteSpace($Message)) {
        Write-Message "  -GitCommit requires -Message ""...""  (a short what + why; no empty messages)." -Fore Red
        $script:OnError = $true; return
    }
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    $br = Get-GitCurrentBranch -WorkDir $wd
    Write-Message ("Working copy: {0}   Branch: {1}" -f $wd, $(if ($br) { $br } else { "(detached)" })) -Fore Blue
    if ($AddAll -eq $true) { [void](Invoke-Git -Arguments @("-C",$wd,"add","-A") -Label "add -A") }
    Show-Git -WorkDir $wd -Arguments @("status","-sb") -Heading "Status:"
    Show-Git -WorkDir $wd -Arguments @("diff","--staged","--stat") -Heading "Staged for commit:"
    if ($DryRun -ne $true) {
        $staged = ""
        try { $staged = & git -C "$wd" diff --staged --name-only 2>$null | Out-String } catch { $staged = "" }
        if ([string]::IsNullOrWhiteSpace($staged)) {
            Write-Message "  Nothing staged to commit.  Use -AddAll to stage everything, or" -Fore Yellow
            Write-Message "  `git add <file>` the specific files you want, then re-run." -Fore Yellow
            return
        }
    }
    Write-Message ("Commit message: {0}" -f $Message) -Fore Blue
    if ($Yes -ne $true -and $DryRun -ne $true) {
        if (-not (Read-YesNo -Prompt "Create this commit?" -Default:$false)) { Write-Message "  Cancelled - nothing committed." -Fore Yellow; return }
    }
    if (Invoke-Git -Arguments @("-C",$wd,"commit","-m",$Message) -Label "commit") {
        if ($DryRun -ne $true) { Write-Message "  Committed.  Push it up with -Git -GitPush." -Fore Green }
    }
}

# -GitPush: push the current branch.  First push (no upstream) auto-adds
# `-u origin <branch>`; later pushes are plain.  Shows what's ahead, confirms
# (unless -Yes).  Never --force.
function Invoke-GitPush {
    param($App = "All")
    Write-Section "GIT - PUSH"
    $wd = Resolve-GitWorkDir -App $App; if (-not $wd) { $script:OnError = $true; return }
    $br = Get-GitCurrentBranch -WorkDir $wd
    if (-not $br) {
        Write-Message "  Detached HEAD (no branch) - nothing to push.  Switch to a branch first." -Fore Red
        $script:OnError = $true; return
    }
    Write-Message ("Working copy: {0}   Branch: {1}" -f $wd, $br) -Fore Blue
    $hasUpstream = $false
    if ($DryRun -ne $true) {
        try {
            & git -C "$wd" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
            $hasUpstream = ($LASTEXITCODE -eq 0)
        } catch { $hasUpstream = $false }
    } else { $hasUpstream = $true }
    if ($hasUpstream) {
        Show-Git -WorkDir $wd -Arguments @("log","--oneline",'@{u}..HEAD') -Heading "Commits to push (ahead of upstream):"
    } else {
        Write-Message ("  No upstream set yet - first push will set it (-u origin {0})." -f $br) -Fore Yellow
    }
    if ($Yes -ne $true -and $DryRun -ne $true) {
        if (-not (Read-YesNo -Prompt "Push now?" -Default:$false)) { Write-Message "  Cancelled - nothing pushed." -Fore Yellow; return }
    }
    if ($hasUpstream) {
        [void](Invoke-Git -Arguments @("-C",$wd,"push") -Label "push")
    } else {
        [void](Invoke-Git -Arguments @("-C",$wd,"push","-u","origin",$br) -Label "push -u")
    }
}

# -GitHelp: print a "day in the life" cheat sheet.  Prints only - nothing runs.
function Invoke-GitHelp {
    Write-Section "GIT - DAY IN THE LIFE (cheat sheet)"
    $lines = @(
        "OEAdmin wraps the safe, everyday git calls (status/diff/log/stash/commit/push)",
        "so you don't have to memorize them.  The raw commands are below so you can see",
        "what's happening - and for the few things OEAdmin leaves to you on purpose.",
        "",
        "-- Start the day: update your working copy ------------------------------------",
        "  OEAdmin: -Git -UpdateRepos            (fast-forward every worktree, safe)",
        "  raw git: git pull     (or: git fetch; git log HEAD..origin/<br>; git merge)",
        "",
        "-- Start new work: a branch as its own working copy ---------------------------",
        "  OEAdmin: -Git -NewWorkspace -App <app> -BaseBranch <base> -NewBranch <new>",
        "  raw git: git switch -c feature/TICKET-123-desc      (in an existing clone)",
        "  naming : feature/...  bugfix/...  hotfix/...  experiment/...",
        "",
        "-- See what changed -----------------------------------------------------------",
        "  OEAdmin: -Git -GitStatus              (status + what's waiting on the server)",
        "           -Git -GitDiff                (your uncommitted changes)",
        "           -Git -GitDiff -DiffVs origin/main     (what I changed vs production)",
        "           -Git -GitLog                 (pretty history)",
        "  raw git: git status ; git diff ; git diff <file> ; git log --oneline --graph",
        "",
        "-- Stage + commit (small + often) ---------------------------------------------",
        "  OEAdmin: -Git -GitCommit -AddAll -Message ""what + why""",
        "  raw git: git add <file>   (or git add .) ; git commit -m ""...""",
        "  good   : ""Prevent save when status is inactive""      weak: ""stuff""",
        "",
        "-- Push your work -------------------------------------------------------------",
        "  OEAdmin: -Git -GitPush                (first push sets -u automatically)",
        "  raw git: git push      (first time: git push -u origin <branch>)",
        "",
        "-- Park work to jump to something else ----------------------------------------",
        "  OEAdmin: -Git -GitStash    then later   -Git -GitStashPop     (-GitStashList)",
        "  raw git: git stash ; git stash pop ; git stash list",
        "",
        "-- Things OEAdmin does NOT automate (do these yourself, on purpose) ------------",
        "  Rebase onto latest main (cleaner history before a PR):",
        "      git fetch ; git rebase origin/main",
        "      (conflicts) edit files ; git add <file> ; git rebase --continue",
        "  Push a rebased branch (history changed) - NEVER plain --force:",
        "      git push --force-with-lease",
        "  Resolve a merge conflict from a pull:",
        "      edit the <<<<<<< / ======= / >>>>>>> markers ; git add <file> ; git commit",
        "  Plain branch switch inside one working copy (vs OEAdmin's worktree model):",
        "      git switch <branch>    /    git switch -c <new-branch>",
        "",
        "-- Before a pull request ------------------------------------------------------",
        "  git diff origin/main                   (review the whole change)",
        "  git log origin/main..HEAD --oneline    (make each commit tell a story)",
        "",
        "Rule of thumb (coming from a lock-based VCS): commit small, commit often,",
        "branch liberally.  Git is built around frequent local commits."
    )
    foreach ($ln in $lines) { Write-Host ("  " + $ln) }
    Write-Host ""
}

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
    # -Tool / -Run / -Editor / -AppBuilder / -Desktop / -Dict / -Admin add one "-p"
    # (the resolved tool may include trailing Extra args, so split on whitespace:
    # first token is the program, the rest are extra client args).
    $runPgm = Get-ClientRunProgram -App $Item.App
    if ($runPgm) {
        $toks = @($runPgm -split '\s+' | Where-Object { $_ })
        $cargs += @("-p", $toks[0]); $dargs += @("-p", $toks[0])
        foreach ($x in ($toks | Select-Object -Skip 1)) { $cargs += $x; $dargs += $x }
    }

    $display = "$($L.ExeName) " + ($dargs -join ' ')
    Write-Message ("Client: {0,-43} {1}" -f (& $Label $Item), $L.ExeName) -Fore Cyan
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] {0}" -f $display) -Fore DarkGray
        return
    }
    Write-Message ("  {0}" -f $display) -Fore DarkGray
    $prev = $env:DLC; $env:DLC = $Item.DLC
    # -Workspace: run prowin with its working directory set to the worktree app
    # folder; no workspace -> prowin's default working dir.
    $workDir = Get-WorkspaceWorkDir -App $Item.App
    if ($workDir) { Write-Message ("  working dir: {0}" -f $workDir) -Fore DarkGray }
    try {
        # Launch the client without blocking the script (interactive session).
        if ($workDir) {
            Start-Process -FilePath $L.Exe -ArgumentList $cargs -WorkingDirectory $workDir
        } else {
            Start-Process -FilePath $L.Exe -ArgumentList $cargs
        }
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
    # -Workspace: run from the worktree app folder (same as -Client).
    $workDir = Get-WorkspaceWorkDir -App $Item.App
    if ($workDir) { Write-Message ("  working dir: {0}" -f $workDir) -Fore DarkGray }
    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        $spArgs = @{ FilePath=$L.Exe; ArgumentList=$cargs; NoNewWindow=$true; Wait=$true; PassThru=$true;
                     RedirectStandardOutput=$outFile; RedirectStandardError=$errFile }
        if ($workDir) { $spArgs['WorkingDirectory'] = $workDir }
        $p = Start-Process @spArgs
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

# ---- Binary file split / join (for large-backup copy) ------------------------
# Split a big .bk into fixed-size slices so each piece copies independently (and
# a failed piece can be retried) instead of restarting a multi-hour whole-file
# copy.  Slices are "<basename>.<NNNN>.part" (zero-padded so a lexical sort =
# numeric order); a "<basename>.split.manifest" records the original name, size,
# slice size and part count so the dev side can reassemble + sanity-check.

# Binary-split $SourceFile into $SliceBytes slices under $OutFolder, writing a
# manifest.  Returns $true on success.  Shows a byte-based percent meter.
function Split-BackupFile {
    param(
        [parameter(Mandatory=$true)] $SourceFile,
        [parameter(Mandatory=$true)] $OutFolder,
        [long]$SliceBytes = 1GB
    )
    if (-not (Test-Path -Path $SourceFile -PathType Leaf)) {
        Write-Message ("  Split: source not found: {0}" -f $SourceFile) -Fore Red; return $false
    }
    if (-not (Test-Path -Path $OutFolder)) { $null = New-Item -ItemType Directory -Path $OutFolder -Force }
    $baseName  = [System.IO.Path]::GetFileName($SourceFile)
    $totalSize = (Get-Item -LiteralPath $SourceFile).Length
    $reader = [System.IO.FileStream]::new($SourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    try {
        $buffer  = New-Object byte[] $SliceBytes
        $index   = 0
        $written = [long]0
        while ($true) {
            $bytesRead = $reader.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -le 0) { break }
            $partPath = Join-PathX $OutFolder ("{0}.{1:D4}.part" -f $baseName, $index)
            $writer = [System.IO.FileStream]::new($partPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try { $writer.Write($buffer, 0, $bytesRead) } finally { $writer.Dispose() }
            $written += $bytesRead
            $index++
            $pct = if ($totalSize -gt 0) { [int](($written * 100) / $totalSize) } else { 100 }
            Write-Progress -Activity ("Splitting {0}" -f $baseName) `
                -Status ("part {0} - {1:N0} / {2:N0} bytes ({3}%)" -f $index, $written, $totalSize, $pct) `
                -PercentComplete $pct
        }
        Write-Progress -Activity ("Splitting {0}" -f $baseName) -Completed
    } finally {
        $reader.Dispose()
    }
    $manifest = @(
        "OriginalName=$baseName"
        "OriginalSize=$totalSize"
        "SliceBytes=$SliceBytes"
        "PartCount=$index"
    )
    Set-Content -Path (Join-PathX $OutFolder ("$baseName.split.manifest")) -Value $manifest -Encoding ascii
    Write-Message ("  Split: {0} -> {1} slice(s) in {2}" -f $baseName, $index, $OutFolder) -Fore Green
    return $true
}

# Reassemble the slices in $SplitFolder back into $OutFile using the manifest.
# Returns $true on success.  Shows a byte-based percent meter.  Used by -Restore
# on the dev side when it finds slices instead of a whole .bk.
function Join-BackupFile {
    param(
        [parameter(Mandatory=$true)] $SplitFolder,
        [parameter(Mandatory=$true)] $OutFile
    )
    $baseName     = [System.IO.Path]::GetFileName($OutFile)
    $manifestPath = Join-PathX $SplitFolder ("$baseName.split.manifest")
    $expectedSize = $null; $expectedParts = $null
    if (Test-Path -Path $manifestPath -PathType Leaf) {
        foreach ($line in (Get-Content -Path $manifestPath)) {
            if ($line -match '^\s*OriginalSize\s*=\s*(\d+)\s*$') { $expectedSize  = [long]$Matches[1] }
            if ($line -match '^\s*PartCount\s*=\s*(\d+)\s*$')    { $expectedParts = [int]$Matches[1] }
        }
    }
    $parts = @(Get-ChildItem -Path $SplitFolder -Filter ("$baseName.*.part") |
               Sort-Object {
                   if ($_.Name -match '\.(\d+)\.part$') { [int]$Matches[1] } else { $_.Name }
               })
    if ($parts.Count -eq 0) {
        Write-Message ("  Join: no slices found for {0} in {1}" -f $baseName, $SplitFolder) -Fore Red; return $false
    }
    if ($null -ne $expectedParts -and $parts.Count -ne $expectedParts) {
        Write-Message ("  Join: part count mismatch for {0} (found {1}, manifest says {2}) - aborting" -f `
            $baseName, $parts.Count, $expectedParts) -Fore Red
        $script:OnError = $true; return $false
    }
    $totalSize = ($parts | Measure-Object -Property Length -Sum).Sum
    $writer = [System.IO.FileStream]::new($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $written = [long]0
        foreach ($file in $parts) {
            $reader = [System.IO.FileStream]::new($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
            try { $reader.CopyTo($writer) } finally { $reader.Dispose() }
            $written += $file.Length
            $pct = if ($totalSize -gt 0) { [int](($written * 100) / $totalSize) } else { 100 }
            Write-Progress -Activity ("Reassembling {0}" -f $baseName) `
                -Status ("{0:N0} / {1:N0} bytes ({2}%)" -f $written, $totalSize, $pct) `
                -PercentComplete $pct
        }
        Write-Progress -Activity ("Reassembling {0}" -f $baseName) -Completed
    } finally {
        $writer.Dispose()
    }
    if ($null -ne $expectedSize -and (Get-Item -LiteralPath $OutFile).Length -ne $expectedSize) {
        Write-Message ("  Join: size mismatch for {0} (got {1}, manifest says {2})" -f `
            $baseName, (Get-Item -LiteralPath $OutFile).Length, $expectedSize) -Fore Red
        $script:OnError = $true; return $false
    }
    Write-Message ("  Join: reassembled {0} from {1} slice(s)" -f $baseName, $parts.Count) -Fore Green
    return $true
}

# Copy one file with retry/backoff.  On failure, waits $CopyRetryDelay seconds and
# retries up to $CopyMaxRetries times, then flags OnError and returns $false.
function Copy-FileWithRetry {
    param(
        [parameter(Mandatory=$true)] $SourcePath,
        [parameter(Mandatory=$true)] $DestPath
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force -ErrorAction Stop
            return $true
        } catch {
            if ($attempt -gt $CopyMaxRetries) {
                Write-Message ("  Copy FAILED after {0} attempt(s): {1} -> {2}: {3}" -f `
                    $attempt, $SourcePath, $DestPath, $_.Exception.Message) -Fore Red
                $script:OnError = $true
                return $false
            }
            Write-Message ("  Copy attempt {0} failed ({1}); retrying in {2}s..." -f `
                $attempt, $_.Exception.Message, $CopyRetryDelay) -Fore Yellow
            if ($CopyRetryDelay -gt 0) { Start-Sleep -Seconds $CopyRetryDelay }
        }
    }
}

# PIPELINED (async) split+copy of ONE large .bk (used when -AsyncCopy is set).
# The split (local disk I/O) and the slice copy (network I/O) overlap: a
# background runspace consumes slices from a BOUNDED queue (depth $AsyncQueueDepth)
# while this thread keeps carving the next slice.  Each slice is copied with the
# same retry/backoff, then its local copy is deleted; the consumer pushes a result
# record back so this thread can draw progress and detect a failure.  Writes the
# .split.manifest and copies it last once all slices are in.  Returns $true on OK.
#
# Boundary notes: the consumer runspace can't see this script's functions or
# $script:OnError, so the copy+retry logic is passed in as a scriptblock and
# failures are surfaced via the result queue (this thread sets $script:OnError).
# Runspace + BlockingCollection are full-language and work on 5.1 and 7.
function Invoke-SplitCopyAsync {
    param(
        [parameter(Mandatory=$true)] $SourceFile,
        [parameter(Mandatory=$true)] $LocalSplitFolder,
        [parameter(Mandatory=$true)] $DestSplitFolder,
        [long]$SliceBytes = 1GB,
        [int]$QueueDepth  = 3
    )
    if (-not (Test-Path -Path $SourceFile -PathType Leaf)) {
        Write-Message ("  AsyncCopy: source not found: {0}" -f $SourceFile) -Fore Red; $script:OnError = $true; return $false
    }
    if (Test-Path -Path $LocalSplitFolder) { Remove-Item -Path $LocalSplitFolder -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $LocalSplitFolder -Force
    if (-not (Test-Path -Path $DestSplitFolder)) { $null = New-Item -ItemType Directory -Path $DestSplitFolder -Force }

    $baseName  = [System.IO.Path]::GetFileName($SourceFile)
    $totalSize = (Get-Item -LiteralPath $SourceFile).Length

    # Bounded work queue (producer blocks when QueueDepth slices are outstanding,
    # which caps local scratch) and an unbounded result queue (consumer -> us).
    $workQ   = [System.Collections.Concurrent.BlockingCollection[object]]::new($QueueDepth)
    $resultQ = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()

    # The consumer runspace: pull {Src;Dst} items, copy with retry, delete local
    # slice on success, push a result record.  Self-contained (no script funcs).
    $consumer = {
        param($workQ, $resultQ, $maxRetries, $retryDelay)
        foreach ($job in $workQ.GetConsumingEnumerable()) {
            $attempt = 0; $ok = $false; $err = $null
            while ($true) {
                $attempt++
                try {
                    Copy-Item -LiteralPath $job.Src -Destination $job.Dst -Force -ErrorAction Stop
                    $ok = $true; break
                } catch {
                    $err = $_.Exception.Message
                    if ($attempt -gt $maxRetries) { break }
                    if ($retryDelay -gt 0) { Start-Sleep -Seconds $retryDelay }
                }
            }
            if ($ok) { Remove-Item -LiteralPath $job.Src -Force -ErrorAction SilentlyContinue }
            $resultQ.Enqueue([PSCustomObject]@{ Name=[System.IO.Path]::GetFileName($job.Src); Ok=$ok; Attempts=$attempt; Error=$err })
        }
    }

    $rs = [RunspaceFactory]::CreateRunspace(); $rs.Open()
    $ps = [PowerShell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($consumer).AddArgument($workQ).AddArgument($resultQ).AddArgument($CopyMaxRetries).AddArgument($CopyRetryDelay)
    $async = $ps.BeginInvoke()

    $drain = {
        $item = $null
        while ($resultQ.TryDequeue([ref]$item)) {
            if (-not $item.Ok) {
                $script:failedName = $item.Name; $script:failedErr = $item.Error; $script:asyncFailed = $true
            } else {
                $script:asyncCopied++
            }
        }
    }
    $script:asyncCopied = 0; $script:asyncFailed = $false; $script:failedName = $null; $script:failedErr = $null

    # Producer: carve slices, enqueue each.  Add blocks when the queue is full.
    $reader = [System.IO.FileStream]::new($SourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    $index = 0; $written = [long]0
    try {
        $buffer = New-Object byte[] $SliceBytes
        while (-not $script:asyncFailed) {
            $bytesRead = $reader.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -le 0) { break }
            $partName = ("{0}.{1:D4}.part" -f $baseName, $index)
            $localPart = Join-PathX $LocalSplitFolder $partName
            $writer = [System.IO.FileStream]::new($localPart, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            try { $writer.Write($buffer, 0, $bytesRead) } finally { $writer.Dispose() }
            $written += $bytesRead
            $index++
            $workQ.Add([PSCustomObject]@{ Src=$localPart; Dst=(Join-PathX $DestSplitFolder $partName) })
            $pct = if ($totalSize -gt 0) { [int](($written * 100) / $totalSize) } else { 100 }
            Write-Progress -Id 1 -Activity ("Splitting {0}" -f $baseName) `
                -Status ("carved {0} slice(s) - {1:N0}/{2:N0} bytes ({3}%)" -f $index, $written, $totalSize, $pct) `
                -PercentComplete $pct
            & $drain
            Write-Progress -Id 2 -Activity ("Copying slices of {0}" -f $baseName) `
                -Status ("{0}/{1} copied" -f $script:asyncCopied, $index)
        }
    } finally {
        $reader.Dispose()
        $workQ.CompleteAdding()
    }

    while (-not $async.IsCompleted) {
        & $drain
        $copyPct = if ($index -gt 0) { [int](($script:asyncCopied * 100) / $index) } else { 100 }
        Write-Progress -Id 2 -Activity ("Copying slices of {0}" -f $baseName) `
            -Status ("{0}/{1} copied" -f $script:asyncCopied, $index) -PercentComplete $copyPct
        Start-Sleep -Milliseconds 300
    }
    & $drain
    try { $ps.EndInvoke($async) } catch { }
    $ps.Dispose(); $rs.Close(); $rs.Dispose()
    Write-Progress -Id 1 -Activity ("Splitting {0}" -f $baseName) -Completed
    Write-Progress -Id 2 -Activity ("Copying slices of {0}" -f $baseName) -Completed

    if ($script:asyncFailed) {
        Write-Message ("  AsyncCopy FAILED on slice {0}: {1} - left local slices in {2} for retry" -f `
            $script:failedName, $script:failedErr, $LocalSplitFolder) -Fore Red
        $script:OnError = $true
        return $false
    }

    $manifest = @(
        "OriginalName=$baseName"
        "OriginalSize=$totalSize"
        "SliceBytes=$SliceBytes"
        "PartCount=$index"
    )
    $localManifest = Join-PathX $LocalSplitFolder ("$baseName.split.manifest")
    Set-Content -Path $localManifest -Value $manifest -Encoding ascii
    if (-not (Copy-FileWithRetry -SourcePath $localManifest -DestPath (Join-PathX $DestSplitFolder ("$baseName.split.manifest")))) {
        return $false
    }
    Remove-Item -Path $LocalSplitFolder -Recurse -Force -ErrorAction SilentlyContinue
    Write-Message ("  COMPLETED (async): {0} ({1} slice(s)) -> {2}" -f $baseName, $script:asyncCopied, $DestSplitFolder) -Fore Green
    return $true
}

# Resolve the destination dev server for -CopyBackup of a given app: an explicit
# -Dest always wins; otherwise fall back to the per-app default in
# $CopyDestDefaults.  Returns $null if nothing resolves (caller flags the error).
function Resolve-CopyDest {
    param($App)
    if (-not [string]::IsNullOrWhiteSpace($Dest)) { return $Dest }
    if ($CopyDestDefaults.ContainsKey($App))      { return $CopyDestDefaults[$App] }
    return $null
}

# Copy production backups to the dev server.  MUST RUN ON THE PRODUCTION server:
# the source is a plain LOCAL path (not UNC); the destination is the dev server's
# NAMED share \\<DestServer>\<BackupShareName>\... (not the admin drive$ share).
# $DestServer is resolved from -Dest or the per-app default (see Resolve-CopyDest).
# A .bk larger than $SplitThresholdBytes is binary-split into $SplitSliceBytes
# slices (progress meter), each slice copied with retry/backoff; the local slice
# is deleted as soon as it lands.  The dev side reassembles slices at restore time
# (see Do-Restore / Join-BackupFile).  Files at/under the threshold copy whole
# (same retry logic).  App1 backups live in a flat dir; App2 backups live in
# per-role subdirs (the subdir path is preserved on the dest).
#
# CHANGE THIS: the $destRoot build below uses the Windows "\\server\share" UNC
# form.  On Linux, change it to however you reach the dev server's backup dir
# (NFS/autofs mount, user@host:path over scp/rsync, etc.).
function Invoke-CopyBackup {
    param($App, $DestServer)
    $srcDir = if ($App -eq "App1") { $App1BackupDir } else { $App2BackupBase }
    if (-not (Test-Path -Path $srcDir)) {
        Write-Message ("  CopyBackup: source dir not found on this (production) server: {0}" -f $srcDir) -Fore Red
        $script:OnError = $true; return
    }
    # Destination root on the dev server's NAMED share (NOT the admin drive$).
    $destRoot = "\\{0}\{1}" -f $DestServer, $BackupShareName.TrimStart('\')
    Write-Message ("Copy {0} backups: {1} -> {2}" -f $App, $srcDir, $destRoot) -Fore Cyan

    $bkFiles = @(Get-ChildItem -Path $srcDir -Filter "*.bk" -File -Recurse)
    if ($bkFiles.Count -eq 0) { Write-Message ("  No .bk files under {0}." -f $srcDir) -Fore Yellow; return }

    foreach ($bk in $bkFiles) {
        # Preserve any subdir structure (App2 per-role dirs) under the dest root.
        $relDir  = $bk.DirectoryName.Substring($srcDir.TrimEnd('/','\').Length).Trim('/','\')
        $destDir = if ($relDir) { Join-PathX $destRoot $relDir } else { $destRoot }

        if ($bk.Length -le $SplitThresholdBytes) {
            # Small enough: copy the whole file with retry.
            $destFile = Join-PathX $destDir $bk.Name
            Write-Message ("  Copy whole: {0} ({1:N0} bytes) -> {2}" -f $bk.Name, $bk.Length, $destDir) -Fore Cyan
            if ($DryRun -eq $true) {
                Write-Message ("  [DRYRUN] copy {0} -> {1}" -f $bk.FullName, $destFile) -Fore DarkGray
                continue
            }
            if (-not (Test-Path -Path $destDir)) { $null = New-Item -ItemType Directory -Path $destDir -Force }
            if (Copy-FileWithRetry -SourcePath $bk.FullName -DestPath $destFile) {
                Write-Message ("  COMPLETED: {0}" -f $bk.Name) -Fore Green
            }
            continue
        }

        # Large file: split locally, copy slices to <destDir>/split/<basename>/,
        # then delete the local slices.
        $localSplit = Join-PathX $bk.DirectoryName "split" $bk.Name
        $destSplit  = Join-PathX $destDir "split" $bk.Name
        $mode = if ($AsyncCopy -eq $true) { "async (pipelined split+copy, queue depth $AsyncQueueDepth)" } else { "sync (split then copy)" }
        Write-Message ("  Large ({0:N0} bytes > {1:N0}); {2}; slices {3:N0} bytes" -f `
            $bk.Length, $SplitThresholdBytes, $mode, $SplitSliceBytes) -Fore Cyan
        if ($DryRun -eq $true) {
            Write-Message ("  [DRYRUN] split {0} -> {1}, copy slices -> {2}, then delete local slices." -f `
                $bk.FullName, $localSplit, $destSplit) -Fore DarkGray
            continue
        }

        # -AsyncCopy: pipeline split + copy (disk and network overlap).  Does its
        # own split/copy/cleanup/manifest and reports via OnError on failure.
        if ($AsyncCopy -eq $true) {
            [void](Invoke-SplitCopyAsync -SourceFile $bk.FullName -LocalSplitFolder $localSplit `
                -DestSplitFolder $destSplit -SliceBytes $SplitSliceBytes -QueueDepth $AsyncQueueDepth)
            continue
        }

        # ---- synchronous path: split fully, then copy each slice ----
        if (Test-Path -Path $localSplit) { Remove-Item -Path $localSplit -Recurse -Force }
        if (-not (Split-BackupFile -SourceFile $bk.FullName -OutFolder $localSplit -SliceBytes $SplitSliceBytes)) {
            continue
        }
        if (-not (Test-Path -Path $destSplit)) { $null = New-Item -ItemType Directory -Path $destSplit -Force }

        $slices = @(Get-ChildItem -Path $localSplit -File)
        $copied = 0; $ok = $true
        foreach ($s in $slices) {
            $destFile = Join-PathX $destSplit $s.Name
            if (Copy-FileWithRetry -SourcePath $s.FullName -DestPath $destFile) {
                $copied++
                Remove-Item -LiteralPath $s.FullName -Force -ErrorAction SilentlyContinue   # cleanup ASAP
                Write-Progress -Activity ("Copying slices of {0}" -f $bk.Name) `
                    -Status ("{0} / {1} slice(s)" -f $copied, $slices.Count) `
                    -PercentComplete ([int](($copied * 100) / $slices.Count))
            } else {
                $ok = $false; break
            }
        }
        Write-Progress -Activity ("Copying slices of {0}" -f $bk.Name) -Completed

        if ($ok) {
            Remove-Item -Path $localSplit -Recurse -Force -ErrorAction SilentlyContinue
            Write-Message ("  COMPLETED: {0} ({1} slice(s)) -> {2}" -f $bk.Name, $copied, $destSplit) -Fore Green
        } else {
            Write-Message ("  INCOMPLETE: {0} - left local slices in {1} for retry" -f $bk.Name, $localSplit) -Fore Red
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
        [pscustomobject]@{ Label="CopyBackup - split+push prod backups -> dev (run on PROD)"; Value="CopyBackup" }
        [pscustomobject]@{ Label="Client  - launch Progress GUI client";       Value="Client" }
        [pscustomobject]@{ Label="Batch   - run a Progress program in batch";  Value="Batch" }
        [pscustomobject]@{ Label="Git     - local repo/worktree maintenance";  Value="Git" }
    )
    if ($null -eq $action) { return $false }

    # The menu owns the action set: clear the default -Status, then turn on the
    # one the operator chose.
    $script:Status=$false; $script:Start=$false; $script:Stop=$false
    $script:Restart=$false; $script:Backup=$false; $script:Restore=$false
    $script:CopyBackup=$false; $script:Client=$false; $script:Batch=$false
    $script:AsyncCopy=$false; $script:Dest=""
    $script:Git=$false; $script:UpdateRepos=$false
    $script:NewWorkspace=$false; $script:BaseBranch=""; $script:NewBranch=""; $script:BootstrapClone=$false
    $script:GitStatus=$false; $script:GitDiff=$false; $script:GitLog=$false
    $script:GitStash=$false; $script:GitStashPop=$false; $script:GitStashList=$false
    $script:GitCommit=$false; $script:GitPush=$false; $script:GitHelp=$false
    $script:Message=""; $script:AddAll=$false; $script:DiffVs=""; $script:RepoPath=""; $script:Yes=$false
    $script:Tool=""; $script:Workspace=""
    # Clear the mutually-exclusive -Client launch switches too.
    $script:Run=$false; $script:Editor=$false; $script:AppBuilder=$false
    $script:Desktop=$false; $script:Dict=$false; $script:Admin=$false

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
            # Destination dev server.  For a specific app, offer a picker of all
            # that app's Development servers, defaulting to its $CopyDestDefaults
            # entry.  For -App All we leave -Dest blank so each app uses its own
            # default (one picker can't serve both apps).
            if ($app -ne "All") {
                $devServers = @($Installs | Where-Object { $_.App -eq $app -and $_.Tier -eq "Development" } |
                                Select-Object -ExpandProperty Server -Unique)
                if ($devServers.Count -gt 0) {
                    $defDest = if ($CopyDestDefaults.ContainsKey($app)) { $CopyDestDefaults[$app] } else { $devServers[0] }
                    # Order so the app default is first (Read-MenuChoice defaults to the first valid option).
                    $ordered = @($devServers | Sort-Object { if ($_ -eq $defDest) { 0 } else { 1 } }, { $_ })
                    $destOpts = foreach ($s in $ordered) {
                        $tag = if ($s -eq $defDest) { " (app default)" } else { "" }
                        [pscustomobject]@{ Label=("{0}{1}" -f $s, $tag); Value=$s; Valid=$true }
                    }
                    $destPick = Read-MenuChoice -Title "Copy to which development server?" -Options $destOpts
                    if ($null -eq $destPick) { return $false }
                    $script:Dest = $destPick
                }
            }
            # Async (pipelined split+copy) is opt-in; prompt for it here.
            $script:AsyncCopy = Read-YesNo -Prompt "Use async (pipelined split+copy) for large backups?" -Default:$false
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
            # Workspace picker: the installed code, or a git working copy (worktree).
            # Only offered when worktrees are actually discovered for this app.
            $wcs = @(Get-WorkingCopies -App $app)
            if ($wcs.Count -gt 0) {
                $wsOpts = @([pscustomobject]@{ Label="(installed code - no workspace)"; Value=""; Valid=$true })
                foreach ($w in $wcs) { $wsOpts += [pscustomobject]@{ Label=("{0}  [{1}]" -f $w.Token, $w.Repo); Value=$w.Token; Valid=$true } }
                $wsPick = Read-MenuChoice -Title "Launch from which working copy?" -Options $wsOpts
                if ($null -eq $wsPick) { return $false }
                $script:Workspace = $wsPick
                if (-not [string]::IsNullOrWhiteSpace($script:Workspace)) {
                    $script:UpdateRepos = Read-YesNo -Prompt "Fast-forward (pull) this working copy before launching?" -Default:$false
                }
            }
            # Launch program: pick a tool by NAME from the $Tools map (scoped to the
            # app), plus "(none)".  Sets -Tool; the resolver maps it to a -p program.
            $toolNames = @($Tools | Where-Object { $_.App -eq "" -or $_.App -eq $app } |
                           Select-Object -ExpandProperty Name -Unique)
            $toolOpts  = @([pscustomobject]@{ Label="(none - plain client)"; Value=""; Valid=$true })
            foreach ($tn in $toolNames) { $toolOpts += [pscustomobject]@{ Label=$tn; Value=$tn; Valid=$true } }
            $toolPick = Read-MenuChoice -Title "Launch into which tool/program?" -Options $toolOpts
            if ($null -eq $toolPick) { return $false }
            $script:Tool = $toolPick
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

        "Git" {
            $script:Git = $true
            # Two groups: everyday "day in the life" commands (operate in ONE working
            # copy) and repo/worktree MAINTENANCE (operate across worktrees), plus a
            # printed cheat sheet.
            $gitCat = Read-MenuChoice -Title "Git - what do you want to do?" -Options @(
                [pscustomobject]@{ Label="Daily workflow - status / diff / log / stash / commit / push"; Value="Daily" }
                [pscustomobject]@{ Label="Maintenance    - update all worktrees / add a new working copy"; Value="Maint" }
                [pscustomobject]@{ Label="Cheat sheet    - print the day-in-the-life git commands"; Value="Help" }
            )
            if ($null -eq $gitCat) { return $false }

            if ($gitCat -eq "Help") { $script:GitHelp = $true }

            elseif ($gitCat -eq "Daily") {
                # Pick which working copy the command runs in.  Prefer a worktree from
                # Get-WorkingCopies; if none are found, fall back to the current dir.
                $allWcs = @(Get-WorkingCopies -App "All")
                if ($allWcs.Count -gt 0) {
                    $wsOpts = foreach ($w in $allWcs) { [pscustomobject]@{ Label=("{0}  [{1}]" -f $w.Token, $w.Repo); Value=$w.Token; Valid=$true } }
                    $wsOpts += [pscustomobject]@{ Label="(current directory)"; Value=""; Valid=$true }
                    $wsPick = Read-MenuChoice -Title "Which working copy?" -Options $wsOpts
                    if ($null -eq $wsPick) { return $false }
                    $script:Workspace = $wsPick
                } else {
                    Write-Host "  No worktrees discovered - the command will run in the current directory." -ForegroundColor Yellow
                }
                $daily = Read-MenuChoice -Title "Which git command?" -Options @(
                    [pscustomobject]@{ Label="Status      - what changed + what's waiting on the server"; Value="GitStatus" }
                    [pscustomobject]@{ Label="Diff        - your uncommitted changes"; Value="GitDiff" }
                    [pscustomobject]@{ Label="Diff vs ... - compare against a ref (e.g. origin/main)"; Value="GitDiffVs" }
                    [pscustomobject]@{ Label="Log         - recent history (graph)"; Value="GitLog" }
                    [pscustomobject]@{ Label="Stash       - shelve uncommitted changes"; Value="GitStash" }
                    [pscustomobject]@{ Label="Stash pop   - restore shelved changes"; Value="GitStashPop" }
                    [pscustomobject]@{ Label="Stash list  - show shelved changes"; Value="GitStashList" }
                    [pscustomobject]@{ Label="Commit      - stage + commit (asks for a message)"; Value="GitCommit" }
                    [pscustomobject]@{ Label="Push        - push the current branch"; Value="GitPush" }
                )
                if ($null -eq $daily) { return $false }
                switch ($daily) {
                    "GitStatus"    { $script:GitStatus = $true }
                    "GitDiff"      { $script:GitDiff = $true }
                    "GitDiffVs"    {
                        $script:GitDiff = $true
                        do { $dv = (Read-Host "  Compare against which ref? (e.g. origin/main)").Trim() } while ([string]::IsNullOrWhiteSpace($dv))
                        $script:DiffVs = $dv
                    }
                    "GitLog"       { $script:GitLog = $true }
                    "GitStash"     { $script:GitStash = $true }
                    "GitStashPop"  { $script:GitStashPop = $true }
                    "GitStashList" { $script:GitStashList = $true }
                    "GitCommit"    {
                        $script:GitCommit = $true
                        $script:AddAll = Read-YesNo -Prompt "Stage ALL changes first (git add -A)?" -Default:$true
                        do { $msg = (Read-Host "  Commit message (what + why)").Trim() } while ([string]::IsNullOrWhiteSpace($msg))
                        $script:Message = $msg
                    }
                    "GitPush"      { $script:GitPush = $true }
                }
            }

            elseif ($gitCat -eq "Maint") {
              $gitSub = Read-MenuChoice -Title "Which maintenance operation?" -Options @(
                [pscustomobject]@{ Label="UpdateRepos  - fast-forward all worktrees (fetch + ff-only)"; Value="UpdateRepos" }
                [pscustomobject]@{ Label="NewWorkspace - add a new working copy (worktree) for a branch"; Value="NewWorkspace" }
              )
              if ($null -eq $gitSub) { return $false }
              switch ($gitSub) {
                "UpdateRepos" {
                    $script:UpdateRepos = $true
                    # Optional: scope to one app's repos (All = every mapped repo).
                    $gapp = & $askApp $true; if ($null -eq $gapp) { return $false }
                    $script:App = $gapp
                }
                "NewWorkspace" {
                    $script:NewWorkspace = $true
                    # NewWorkspace needs a SPECIFIC app (one repo), not All.
                    $gapp = & $askApp $false; if ($null -eq $gapp) { return $false }
                    $script:App = $gapp
                    $repo = @($GitRepoApps.Keys | Where-Object { $GitRepoApps[$_] -eq $gapp })[0]
                    $bare = if ($repo) { Join-PathX $GitReposRoot $repo ".bare" } else { "" }
                    # LAYOUT CHECK up front: if this machine isn't on the bare+worktree
                    # layout, explain and let the operator choose to continue
                    # (bootstrap a bare clone) or back out.
                    $haveBare = ($bare -and (Test-BareLayout -Bare $bare))
                    if (-not $haveBare) {
                        Write-Host ""
                        Write-Host "  No bare repo found at $bare." -ForegroundColor Yellow
                        Write-Host "  -NewWorkspace expects the bare-clone + per-branch-worktree layout" -ForegroundColor Yellow
                        Write-Host "  (each repo at <GitReposRoot>\<Repo>\.bare, one worktree per branch)." -ForegroundColor Yellow
                        Write-Host "  This machine does not appear to use that layout." -ForegroundColor Yellow
                        Write-Host "  Continuing will BOOTSTRAP a fresh bare clone here - a SEPARATE copy" -ForegroundColor Yellow
                        Write-Host "  from any existing working clone you may already have." -ForegroundColor Yellow
                        if (-not (Read-YesNo -Prompt "Bootstrap a bare clone and continue?" -Default:$false)) {
                            Write-Host "  Cancelled - no git changes made." -ForegroundColor Yellow
                            return $false
                        }
                        $script:BootstrapClone = $true
                    }
                    # Base branch: list the repo's branches so the operator picks one
                    # (only possible once a bare repo exists).
                    $branches = @()
                    if ($haveBare) { $branches = @(Get-GitBranchList -Bare $bare) }
                    if ($branches.Count -gt 0) {
                        $brOpts = foreach ($b in $branches) { [pscustomobject]@{ Label=$b; Value=$b; Valid=$true } }
                        $brPick = Read-MenuChoice -Title "Base the workspace on which branch?" -Options $brOpts
                        if ($null -eq $brPick) { return $false }
                        $script:BaseBranch = $brPick
                    } else {
                        do { $bIn = Read-Host "  Base branch name (e.g. main)" } while ([string]::IsNullOrWhiteSpace($bIn))
                        $script:BaseBranch = $bIn.Trim()
                    }
                    # Optionally cut a NEW branch off the base.
                    if (Read-YesNo -Prompt "Create a new branch off this base?" -Default:$false) {
                        do {
                            $nbIn = (Read-Host "  New branch name").Trim()
                            if ([string]::IsNullOrWhiteSpace($nbIn)) { Write-Host "  Name cannot be blank." -ForegroundColor Yellow; continue }
                            if (-not (Test-GitWorkspaceName $nbIn)) { Write-Host '  Invalid characters (no \ / : * ? " < > |).' -ForegroundColor Yellow; $nbIn = "" }
                        } until (-not [string]::IsNullOrWhiteSpace($nbIn))
                        $script:NewBranch = $nbIn
                    }
                }
            }
        }
    }

    # DryRun preview offer (applies to every action).
    $script:DryRun = Read-YesNo -Prompt "Preview only (DryRun, make no changes)?" -Default:$false

    # Build the equivalent command line for display + confirmation.
    $parts = @("./OEAdmin.ps1", "-$action")
    if ($script:App   -and $script:App   -ne "All") { $parts += "-App $($script:App)" }
    if ($script:Site  -and $script:Site  -ne "All") { $parts += "-Site $($script:Site)" }
    if ($script:Env   -and $script:Env   -ne "All") { $parts += "-Env $($script:Env)" }
    if ($script:Run        -eq $true)               { $parts += "-Run" }
    if ($script:Editor     -eq $true)               { $parts += "-Editor" }
    if ($script:AppBuilder -eq $true)               { $parts += "-AppBuilder" }
    if ($script:Desktop    -eq $true)               { $parts += "-Desktop" }
    if ($script:Dict       -eq $true)               { $parts += "-Dict" }
    if ($script:Admin      -eq $true)               { $parts += "-Admin" }
    if (-not [string]::IsNullOrWhiteSpace($script:Tool))      { $parts += "-Tool $($script:Tool)" }
    if (-not [string]::IsNullOrWhiteSpace($script:Workspace)) { $parts += "-Workspace $($script:Workspace)" }
    if ($script:UpdateRepos -eq $true)              { $parts += "-UpdateRepos" }
    if ($script:NewWorkspace -eq $true)             { $parts += "-NewWorkspace" }
    if (-not [string]::IsNullOrWhiteSpace($script:BaseBranch)) { $parts += "-BaseBranch $($script:BaseBranch)" }
    if (-not [string]::IsNullOrWhiteSpace($script:NewBranch))  { $parts += "-NewBranch $($script:NewBranch)" }
    if ($script:BootstrapClone -eq $true)           { $parts += "-BootstrapClone" }
    if ($script:GitStatus -eq $true)                { $parts += "-GitStatus" }
    if ($script:GitDiff -eq $true)                  { $parts += "-GitDiff" }
    if (-not [string]::IsNullOrWhiteSpace($script:DiffVs)) { $parts += "-DiffVs $($script:DiffVs)" }
    if ($script:GitLog -eq $true)                   { $parts += "-GitLog" }
    if ($script:GitStash -eq $true)                 { $parts += "-GitStash" }
    if ($script:GitStashPop -eq $true)              { $parts += "-GitStashPop" }
    if ($script:GitStashList -eq $true)             { $parts += "-GitStashList" }
    if ($script:GitCommit -eq $true)                { $parts += "-GitCommit" }
    if ($script:AddAll -eq $true)                   { $parts += "-AddAll" }
    if (-not [string]::IsNullOrWhiteSpace($script:Message)) { $parts += "-Message `"$($script:Message)`"" }
    if ($script:GitPush -eq $true)                  { $parts += "-GitPush" }
    if ($script:GitHelp -eq $true)                  { $parts += "-GitHelp" }
    if (-not [string]::IsNullOrWhiteSpace($script:RepoPath)) { $parts += "-RepoPath `"$($script:RepoPath)`"" }
    if (-not [string]::IsNullOrWhiteSpace($script:Pgm)) { $parts += "-Pgm $($script:Pgm)" }
    if (-not [string]::IsNullOrWhiteSpace($script:Ini)) { $parts += "-Ini `"$($script:Ini)`"" }
    if (-not [string]::IsNullOrWhiteSpace($script:Pf))  { $parts += "-Pf `"$($script:Pf)`"" }
    if (@($script:AddPfs).Count -gt 0) { $parts += "-AddPfs `"$(@($script:AddPfs) -join ',')`"" }
    if (-not [string]::IsNullOrWhiteSpace($script:Dest)) { $parts += "-Dest $($script:Dest)" }
    if ($script:AsyncCopy -eq $true)                { $parts += "-AsyncCopy" }
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

# GIT ACTION GROUP - local repo/worktree maintenance; does NOT need the OpenEdge
# inventory, so it runs and exits before the DB dispatch.  Extensible: dispatch a
# git sub-action switch (today -UpdateRepos / -NewWorkspace).
if ($Git -eq $true) {
    Write-Section "OEADMIN - GIT"
    Write-Message "GitReposRoot: $GitReposRoot   App: $App   DryRun: $DryRun" -Fore Blue
    if ($NewWorkspace -eq $true) {
        Write-Message "NewWorkspace: BaseBranch=$BaseBranch  NewBranch=$NewBranch  BootstrapClone=$BootstrapClone" -Fore Blue
    }
    if (-not [string]::IsNullOrWhiteSpace($Workspace)) { Write-Message "Workspace: $Workspace" -Fore Blue }
    if (-not [string]::IsNullOrWhiteSpace($RepoPath))  { Write-Message "RepoPath:  $RepoPath"  -Fore Blue }
    # Dispatch exactly one sub-action (menu enforces one; on the CLI first match
    # wins).  Maintenance first, then the day-in-the-life set.
    if ($UpdateRepos -eq $true) {
        Invoke-UpdateRepos -App $App
    } elseif ($NewWorkspace -eq $true) {
        Invoke-NewWorkspace -App $App -BaseBranch $BaseBranch -NewBranch $NewBranch -BootstrapClone:$BootstrapClone
    } elseif ($GitStatus -eq $true) {
        Invoke-GitStatus -App $App
    } elseif ($GitDiff -eq $true) {
        Invoke-GitDiff -App $App
    } elseif ($GitLog -eq $true) {
        Invoke-GitLog -App $App
    } elseif ($GitStash -eq $true) {
        Invoke-GitStash -App $App
    } elseif ($GitStashPop -eq $true) {
        Invoke-GitStashPop -App $App
    } elseif ($GitStashList -eq $true) {
        Invoke-GitStashList -App $App
    } elseif ($GitCommit -eq $true) {
        Invoke-GitCommit -App $App
    } elseif ($GitPush -eq $true) {
        Invoke-GitPush -App $App
    } elseif ($GitHelp -eq $true) {
        Invoke-GitHelp
    } else {
        Write-Message "  No git sub-action given.  Maintenance:" -Fore Yellow
        Write-Message "    -UpdateRepos                        fast-forward all worktrees" -Fore Yellow
        Write-Message "    -NewWorkspace -App <a> -BaseBranch <b> [-NewBranch <n>]  add a worktree" -Fore Yellow
        Write-Message "  Day-in-the-life (scope with -Workspace <token> / -RepoPath <dir> / current dir):" -Fore Yellow
        Write-Message "    -GitStatus  -GitDiff [-DiffVs <ref>]  -GitLog" -Fore Yellow
        Write-Message "    -GitStash   -GitStashPop  -GitStashList" -Fore Yellow
        Write-Message "    -GitCommit -Message ""..."" [-AddAll] [-Yes]   -GitPush [-Yes]" -Fore Yellow
        Write-Message "    -GitHelp                            print the cheat sheet" -Fore Yellow
    }
    Write-Section "SCRIPT COMPLETED"
    if ($OnError -eq $true) { exit 2001 }
    exit 0
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

# Component gating for -Start/-Stop/-Restart: NameServer/MSSQLBroker components
# are shared, server-wide resources, so we only start/stop them when the action
# is a WHOLE-SERVER operation - i.e. the selection covers EVERY database that
# install manages (within the -App filter).  If -Site/-Env (or -App) narrow the
# selection to a subset of an install's databases, that install's components are
# dropped from the state change (databases are still acted on normally).
# Returns the subset of $Targets to act on for a state-change action.
function Resolve-StateChangeTargets {
    param($Targets, $Inventory)
    $dbTargets = @($Targets | Where-Object Component -eq "Database")
    $result    = New-Object System.Collections.Generic.List[object]
    foreach ($t in $dbTargets) { $result.Add($t) }

    foreach ($c in @($Targets | Where-Object { $_.Component -ne "Database" })) {
        # All databases this install manages, per the FULL inventory, honoring -App.
        $installDbs = @($Inventory | Where-Object {
            $_.Component -eq "Database" -and
            $_.Server    -eq $c.Server  -and
            $_.OEVersion -eq $c.OEVersion -and
            ($App -eq "All" -or $_.App -eq $App)
        })
        $selectedNames = @($dbTargets | Where-Object {
            $_.Server -eq $c.Server -and $_.OEVersion -eq $c.OEVersion
        } | ForEach-Object { $_.Name })
        $allCovered = $true
        if ($installDbs.Count -eq 0) {
            # No databases discovered for this install (e.g. a NS-only box): treat
            # as whole-server only when the selection isn't narrowed by Site/Env.
            $allCovered = ($Site -eq "All" -and $Env -eq "All")
        } else {
            foreach ($d in $installDbs) {
                if ($selectedNames -notcontains $d.Name) { $allCovered = $false; break }
            }
        }
        if ($allCovered) {
            $result.Add($c)
        } else {
            Write-Message ("  Skipping component (partial selection): {0,-6} {1} on {2}" -f `
                $c.OEVersion, $c.Name, $c.Server) -Fore DarkGray
        }
    }
    return $result
}

# STOP
if ($Stop -eq $true) {
    Write-Section "STOP"
    foreach ($t in (Resolve-StateChangeTargets -Targets $Targets -Inventory $Inventory)) {
        if (Test-CanAct -Item $t) { Do-Stop -Item $t }
    }
}

# RESTART
if ($Restart -eq $true) {
    Write-Section "RESTART"
    foreach ($t in (Resolve-StateChangeTargets -Targets $Targets -Inventory $Inventory)) {
        if (Test-CanAct -Item $t) { Do-Restart -Item $t }
    }
}

# START
if ($Start -eq $true) {
    Write-Section "START"
    foreach ($t in (Resolve-StateChangeTargets -Targets $Targets -Inventory $Inventory)) {
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

# COPY BACKUPS - runs ON THE PRODUCTION server and PUSHES backups to the dev
# server's named share (\\<Dest>\<BackupShareName>\..., -Dest or per-app default).
# The source is a plain LOCAL path, so this must run where the backups live (prod);
# hence it is PRODUCTION-tier only.  Large .bk files are binary-split, the slices
# copied with retry, and the dev side reassembles at restore time.  -App scopes
# which app's backups are copied (All = both).
if ($CopyBackup -eq $true) {
    Write-Section "COPY BACKUPS (split + push prod -> dev share)"
    # This machine must host a Production install for the selected app(s).
    $prodHere = @($Installs | Where-Object {
        $_.Tier -eq "Production" -and $_.Server -eq $env:COMPUTERNAME -and ($App -eq "All" -or $_.App -eq $App)
    } | Select-Object -ExpandProperty App -Unique)
    if ($prodHere.Count -eq 0) {
        Write-Message ("  CopyBackup must run ON a Production server for -App $App (this host {0} has no matching Production install)." -f $env:COMPUTERNAME) -Fore Red
        Write-Message "  Refusing to run CopyBackup off the production server (source backups are local, by design)." -Fore Yellow
        $script:OnError = $true
    }
    foreach ($a in $prodHere) {
        $destServer = Resolve-CopyDest -App $a
        if (-not $destServer) {
            Write-Message ("  CopyBackup: no destination dev server resolved for {0} (set -Dest or add a `$CopyDestDefaults entry)." -f $a) -Fore Red
            $script:OnError = $true; continue
        }
        Invoke-CopyBackup -App $a -DestServer $destServer
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
    # -UpdateRepos with a -Workspace: fast-forward the chosen working copy first.
    if ($UpdateRepos -eq $true -and -not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
        if ($wc) { Invoke-UpdateRepos -App $wc.App -OnlyRepo $wc.Repo -OnlyToken $wc.Token }
    }

    # -Run / -Editor / -AppBuilder / -Desktop / -Dict / -Admin each supply the one
    # "-p" program on the client command line, so at most one may be set.
    $launchSwitches = @()
    if ($Run        -eq $true) { $launchSwitches += "-Run" }
    if ($Editor     -eq $true) { $launchSwitches += "-Editor" }
    if ($AppBuilder -eq $true) { $launchSwitches += "-AppBuilder" }
    if ($Desktop    -eq $true) { $launchSwitches += "-Desktop" }
    if ($Dict       -eq $true) { $launchSwitches += "-Dict" }
    if ($Admin      -eq $true) { $launchSwitches += "-Admin" }
    if ($launchSwitches.Count -gt 1) {
        Write-Message ("  {0} are mutually exclusive - specify at most one." -f ($launchSwitches -join ", ")) -Fore Red
        $script:OnError = $true
    }

    $ct = if (($launchSwitches.Count -le 1) -and (Test-ClientTargets -Tag "Client")) {
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
    # -UpdateRepos with a -Workspace: fast-forward the chosen working copy first.
    if ($UpdateRepos -eq $true -and -not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
        if ($wc) { Invoke-UpdateRepos -App $wc.App -OnlyRepo $wc.Repo -OnlyToken $wc.Token }
    }

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
##  1. $Installs table .......... your servers, tiers, OpenEdge versions, DLCs,
##                                ports, each row's SetupDir (the -Client/-Batch
##                                INI/PF root, per machine + version), and
##                                InstalledComponents (which shared components -
##                                NameServer/MSSQLBroker - that install runs)
##  2. -App ValidateSet ......... your application names (keep in sync with $Installs)
##  3. $ValidSites / -Site ...... your site codes (or drop sites if you have none)
##  4. Parse-App1Database /
##     Parse-App2Database ....... your database NAMING CONVENTION (the regex + maps)
##  5. Path defaults ............ $DlcBase, $App1BackupDir/$App2BackupBase
##                                (setup-tree roots now live in $Installs - item 1)
##  5b. CopyBackup settings ..... $Dest/$CopyDestDefaults (dest dev server),
##                                $BackupShareName, $SplitThresholdBytes/$SplitSlice
##                                Bytes, $CopyMaxRetries/$CopyRetryDelay,
##                                $AsyncCopy/$AsyncQueueDepth; and the
##                                $destRoot build in Invoke-CopyBackup (Windows UNC
##                                vs Linux mount/ssh)
##  6. Get-BackupDevice ......... your backup file names/layout
##  7. Get-App2EnvStem .......... your single-site app's INI/PF stem per env
##  8. Resolve-ClientLaunch ..... client exe per OpenEdge version (GUI vs _progres)
##  9. SMTP block ............... $SmtpServer/$SmtpPort/$EmailFrom/$EmailTo
## 10. Convert-ToRemotePath ..... only if you use -Remote (cross-server paths)
## 11. $StartupProgram ......... the -Run startup .p (if you use one)
