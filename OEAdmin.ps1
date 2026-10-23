<#PSScriptInfo

.VERSION 1.5.0

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

1.2.0 - Added -Compile: a headless Application Compiler.  Launches the SAME batch
        client session as -Batch (same exe by OE version, same INI/PF, same
        -Ini/-Pf/-AddPfs overrides, same App/Site/Env/Server selectors) but the
        "-p" program is the bundled driver OECompiler.p (passed by FULL PATH, so
        no PROPATH entry is needed) and all compile options travel in a generated
        PARAMETER FILE (-param), not via UI.  OECompiler.p is a stripped-down,
        9.1E-safe port of the OpenEdge Application Compiler (adecomp) - no UI, no
        VMS/license/XCODE, no MIN-SIZE/STREAM-IO/MD5/LANGUAGES/V6FRAME.  It walks
        the source recursively, compiles files matching -FileSpec (default
        "*.p *.w *.cls *.t", incl. *.t DB triggers), and SAVEs the .r beside the
        source.  -Incremental compiles only files whose .r is MISSING or whose
        source is NEWER than the .r; absent = full rebuild.  Source is the
        -Workspace worktree by default, or the installed tree with -Installed.
        Output under <sourceroot>/x/<yyyy-MM-dd_HHmmss>/: compile.log ALWAYS,
        plus per-file LISTING (-Listing) and XREF (-Xref / -XrefXml) when
        requested (OFF by default).  A file with COMPILER errors makes the driver
        QUIT 1; OEAdmin flags it (red, error count + log path) and sets OnError.
        Wired into -Menu (source/filespec/dir/mode/outputs flow).

1.3.0 - -Compile gains -Exclude / -ExcludeFile; batch + compile output grouped in
        subdirectories.  -Exclude "pat,pat" and -ExcludeFile <file> (bare name =
        the standing compile-excludes.txt in the script folder; one pattern per
        line, '#' comments ok) SKIP files whose path (relative to the source root,
        '\'/'/' interchangeable) matches - ideal for vendor sample code that never
        compiles standalone.  Skipped files are logged ("SKIP (excluded): ...") and
        counted (compiled/errors/warnings/skipped).  Batch artifacts moved to
        <script dir>/batch/<program>/...; the -Compile driver's stdout/err go to
        <script dir>/batch/OECompiler/.  (compile.log/listing/xref still live under
        <sourceroot>/x/<stamp>/.)

1.4.0 - Added -Package: a release bundler that packages the SOURCE changed for a
        project plus its dependency-complete R-CODE and a manifest into a
        versioned zip with a safe deploy.ps1.  The change set is resolved from the
        -Workspace git worktree three ways (any mix): -Grep "<text>" (commit-
        message search), -FromCommit <sha> [-ToCommit <sha>] (commit range),
        and/or -FileList <file> (explicit path list); all normalized to app-root-
        relative.  The ship set is dependency-aware: OECompiler XREF maps each
        changed program to the includes/classes/procedures it pulls in, and the
        R-CODE superset is shipped so a changed .i doesn't orphan a caller; -Full
        ships r-code for the whole source tree instead.  The bundle is built from a
        FRESH fail-closed compile against the REQUIRED -Site/-Env (r-code CRC is
        tied to that schema), reusing the -Compile engine (inherits the standing
        compile-excludes.txt when -ExcludeFile is blank).  Delta schema is carried
        via -DeltaDf "<file,...>": the .df is bundled and deploy.ps1 PRINTS load
        instructions for the DBA and awaits confirmation (it never shells
        load_df.p); -DfLoadedConfirmed records that the DBA loaded it (separate from
        -Accept; both cannot be set at once).  Two-pass gate: a first run resolves +
        prints the change set for review; -Accept -Project <tok> re-hashes the
        reviewed set and HARD-STOPS on any drift before compiling/zipping.
        deploy.ps1 is dry-run by default (-Execute to apply), backs up each target
        before overwrite, and has a -Rollback.  LOCAL worktree only (-Remote
        refused).  -DryRun throughout.  Wired into -Menu.

1.5.0 - Added -Test: run the ABLUnit suite headlessly.  A -Batch-style launch
        whose "-p" program is the Progress driver ABLUnitCore.p, resolved off the
        ENVIRONMENT's INI PROPATH (the ablunit framework must be on that PROPATH;
        add it to the INI where needed - OEAdmin does not ship it).  The test spec
        comes from -TestSpec (a class/proc, Foo.cls#Method, a comma-list, or a
        folder); blank defaults to a "tests" folder under the source root (narrow
        with -TestDir).  Same exe/INI/PF/App/Site/Env/Workspace/Installed machinery
        as -Compile/-Batch.  OEAdmin writes a generated CONFIG json (CFG=<file>)
        pinning the results location + quitOnEnd, runs blocking (driver out/err
        under <script dir>/batch/ABLUnitCore/), then PARSES the JUnit-style
        results.xml (-TestResults dir, default <sourceroot>/x/<stamp>/test/) and
        prints a pass/fail summary.  Any failure/error - or a missing results.xml
        (usually the framework not on PROPATH) - sets OnTestError and exit 2004.
        OpenEdge 12+ ONLY (9.1E/10.2B targets are refused).  Wired into -Menu.

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
                 ends with "-p <program> -b".  -Pgm <program>.p is REQUIRED.  Output
                 is grouped per program under <script dir>/batch/<program>/.
    -Compile     Headless Application Compiler.  Same launch/selectors/overrides as
                 -Batch, but the "-p" program is the bundled OECompiler.p (full
                 path, no PROPATH needed) and compile options pass in a generated
                 parameter file.  Compiles -FileSpec (default "*.p *.w *.cls *.t")
                 under the source root (recursive), SAVEing .r beside the source.
                 -Dir restricts to a sub-directory; -Incremental compiles only
                 missing/newer-than-.r files (absent = full rebuild).  -Exclude
                 "pat,pat" and -ExcludeFile <file> SKIP files (wildcard on the path
                 relative to the source root) - e.g. vendor sample code; skipped
                 files are logged + counted.  Source is the -Workspace worktree by
                 default, or -Installed for the install tree.  Output under
                 <sourceroot>/x/<stamp>/: compile.log always, plus -Listing
                 (listing/) and -Xref/-XrefXml (xref/) per-file when set; the
                 driver's stdout/err go to <script dir>/batch/OECompiler/.  Any
                 COMPILER error is flagged loudly and sets the error exit.
    -Package     Release bundler.  Resolves one project's change set from the
                 -Workspace worktree (-Grep message search, -FromCommit/-ToCommit
                 range, and/or -FileList - any mix), then ships the changed SOURCE
                 plus its dependency-complete R-CODE (via OECompiler XREF; -Full
                 ships the whole tree's r-code) and a manifest in a versioned zip
                 with a safe deploy.ps1.  R-code is built by a FRESH fail-closed
                 compile against the REQUIRED -Site/-Env (CRC tied to that schema).
                 -DeltaDf "<file,...>" carries schema deltas: bundled, and the
                 deploy script PRINTS load steps for the DBA (never auto-loads);
                 -DfLoadedConfirmed records the DBA's load (separate from -Accept,
                 mutually exclusive with it).  Two passes: run once to resolve +
                 review the change set, then -Accept -Project <tok> re-hashes it and
                 HARD-STOPS on drift before building.  deploy.ps1 is dry-run by
                 default (-Execute to apply), backs up before overwrite, -Rollback
                 restores.  LOCAL worktree only (-Remote refused).
    -Test        Run the ABLUnit suite headlessly via the Progress driver
                 ABLUnitCore.p (resolved off the environment's INI PROPATH).  Same
                 launch machinery as -Compile/-Batch.  -TestSpec picks what to run
                 (class/proc, Foo.cls#Method, comma-list, or folder; blank = a
                 "tests" folder under the source root, narrow with -TestDir).
                 OEAdmin writes a CONFIG json, runs blocking, then parses the
                 results.xml (-TestResults dir) and prints a pass/fail summary; any
                 failure/error (or a missing results.xml) sets exit 2004.  OpenEdge
                 12+ ONLY.

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

    # Compile (headless Application Compiler) - full compile of a worktree
    ./OEAdmin.ps1 -Compile -App App1 -Site S1 -Env Test -Workspace feature-x

    # ...incremental (missing/newer-than-.r only), with per-file listing + xref
    ./OEAdmin.ps1 -Compile -App App1 -Site S1 -Env Test -Workspace feature-x -Incremental -Listing -Xref

    # ...one sub-directory of the INSTALLED code, specific file spec
    ./OEAdmin.ps1 -Compile -App App1 -Site S1 -Env Test -Installed -Dir src -FileSpec "*.p *.t"

    # ...skip vendor sample code (ad-hoc patterns, path relative to source root)
    ./OEAdmin.ps1 -Compile -App App1 -Site S1 -Env Test -Workspace feature-x -Exclude "vendor\*,*sample*"

    # ...using the standing exclude file in the script folder (compile-excludes.txt)
    ./OEAdmin.ps1 -Compile -App App1 -Site S1 -Env Test -Workspace feature-x -ExcludeFile compile-excludes.txt

    # Package (release bundler) - PASS 1: resolve + review the change set, no build
    ./OEAdmin.ps1 -Package -App App1 -Site S1 -Env Test -Workspace feature-x -Grep "TICKET-123"

    # ...by commit range (and/or -FileList <file>) instead of a message search
    ./OEAdmin.ps1 -Package -App App1 -Site S1 -Env Test -Workspace feature-x -FromCommit abc1234 -ToCommit HEAD

    # ...PASS 2: accept the reviewed set (re-hashes; hard-stops on drift), build zip
    ./OEAdmin.ps1 -Package -App App1 -Site S1 -Env Test -Workspace feature-x -Grep "TICKET-123" -Accept -Project TICKET-123

    # ...carry a schema delta (deploy.ps1 prints DBA load steps + awaits them)
    ./OEAdmin.ps1 -Package -App App1 -Site S1 -Env Test -Workspace feature-x -Grep "TICKET-123" -Accept -Project TICKET-123 -DeltaDf "schema/delta.df"

    # ...ship the WHOLE source tree's r-code (DB/CRC-wide change)
    ./OEAdmin.ps1 -Package -App App1 -Site S1 -Env Test -Workspace feature-x -Accept -Project FullRelease -Full

    # ...preview the whole run (resolve + compile launch) without building
    ./OEAdmin.ps1 -Package -App App1 -Site S1 -Env Test -Workspace feature-x -Grep "TICKET-123" -Accept -Project TICKET-123 -DryRun

    # Test (ABLUnit, OpenEdge 12+ only) - run the default 'tests' folder of a worktree
    ./OEAdmin.ps1 -Test -App App1 -Site S1 -Env Test -Workspace feature-x

    # ...one test class, or a single method of it
    ./OEAdmin.ps1 -Test -App App1 -Site S1 -Env Test -Workspace feature-x -TestSpec "tests/MyThingTest.cls"
    ./OEAdmin.ps1 -Test -App App1 -Site S1 -Env Test -Workspace feature-x -TestSpec "MyThingTest.cls#HappyPath"

    # ...a sub-dir of the default tests folder, custom results location
    ./OEAdmin.ps1 -Test -App App1 -Site S1 -Env Test -Workspace feature-x -TestDir tests/data -TestResults /tmp/testout

    # ...preview the launch + CFG json without running
    ./OEAdmin.ps1 -Test -App App1 -Site S1 -Env Test -Workspace feature-x -DryRun

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

    ##### ---- COMPILE (-Compile) ----------------------------------------------
    # -Compile: compile the application source with the OpenEdge Application
    # Compiler, headless.  It launches EXACTLY the same batch client session as
    # -Batch (same exe by OE version, same INI and PF, same -Ini/-Pf/-AddPfs
    # overrides, same App/Site/Env/Server selectors), but the "-p" program is the
    # bundled headless driver OECompiler.p (passed by FULL PATH, so it needs no
    # PROPATH entry) and the compile options travel in a generated PARAMETER FILE
    # (-param), not via UI.  Source is the -Workspace worktree by default, or the
    # installed tree with -Installed.  r-code is saved beside the source.  Output:
    # always a consolidated log, plus optional per-file LISTING / XREF, under
    #   <sourceroot>/x/<yyyy-MM-dd_HHmmss>/{compile.log, listing/, xref/}
    [switch]$Compile,

    # Space-separated MATCHES file spec(s) to compile.  Default compiles ABL
    # procedures, windows, classes, and database-trigger code.
    $FileSpec="*.p *.w *.cls *.t",

    # Optional sub-directory (relative to the source root) to restrict the compile
    # to one branch of the tree.  Blank = whole source root.
    $Dir="",

    # -Incremental: compile only what NEEDS it - a source whose .r is MISSING or
    # whose source file is NEWER than its .r.  Absent = full rebuild.
    [switch]$Incremental,

    # -Listing / -Xref: also generate per-file LISTING / XREF output (OFF by
    # default; the log is always written).  -XrefXml makes XREF output XML format.
    [switch]$Listing,
    [switch]$Xref,
    [switch]$XrefXml,

    # -Installed: compile the INSTALLED code (the install's InstallDir) instead of
    # a git working copy.  Absent = the -Workspace worktree (default); with no
    # -Workspace either, it falls back to the installed tree.
    [switch]$Installed,

    # -Exclude: wildcard pattern(s) of files to SKIP during -Compile.  Each is
    # matched (case-insensitive, ABL MATCHES) against the file's path RELATIVE to
    # the source root; '\' and '/' are interchangeable.  Comma-separated list, e.g.
    # -Exclude "vendor\*,*sample*".  Skipped files are logged + counted separately,
    # so the error total reflects only your own code.  -Compile only.
    [string[]]$Exclude=@(),

    # -ExcludeFile: path to a text file of exclude patterns, one per line (blank
    # lines and '#' comments ignored).  A bare filename resolves in the script's
    # own folder (a standing "compile-excludes.txt"); a path with a separator is
    # used verbatim.  Combined with -Exclude.  -Compile only.
    $ExcludeFile="",

    ##### ---- PACKAGE (-Package) ----------------------------------------------
    # -Package: build a versioned release bundle (zip) from ONE project's change
    # set - the changed source, a dependency-aware set of freshly-compiled r-code,
    # any schema delta .df files, a manifest, and a safe deploy.ps1 with rollback.
    # Reuses the -Compile launch machinery; -Site AND -Env are REQUIRED (the r-code
    # CRC is tied to the schema).  LOCAL git worktree only (-Remote refused).
    [switch]$Package,

    # -Project: project / ticket token - names the zip + manifest and keys the
    # review file.  REQUIRED with -Accept.
    $Project="",

    # Change-set inputs (union; any mix, or -Full): -Grep searches commit messages
    # (git log --grep); -FromCommit..-ToCommit is a commit range; -FileList is an
    # explicit path-list file (one per line, '#' comments ok).
    $Grep="",
    $FromCommit="",
    $ToCommit="",
    $FileList="",

    # -Accept: second pass - re-hash the reviewed change set (hard-stop on drift),
    # compile fresh, and build the zip.  Without it, -Package only RESOLVES the set
    # for review.  -Full ships the WHOLE source tree's r-code (DB/CRC-wide change).
    [switch]$Accept,
    [switch]$Full,

    # -DeltaDf: schema-delta .df file(s) (comma list) to carry in the bundle; the
    # generated deploy.ps1 PRINTS the DBA load steps and awaits them (never auto-
    # loads).  -DfLoadedConfirmed non-interactively affirms the DF(s) are already
    # loaded into the compile DB (so the r-code CRC can be trusted); it is SEPARATE
    # from -Accept and the two confirmations are independent.
    [string[]]$DeltaDf=@(),
    [switch]$DfLoadedConfirmed,

    # -PackageBackupDir: default PackageBackupDir baked into the generated
    # deploy.ps1 (its backup-before-overwrite root).  Blank = the App1 backup dir.
    $PackageBackupDir="",

    ##### ---- TEST (-Test : ABLUnit) -----------------------------------------
    # -Test: run the ABLUnit suite headlessly via the Progress driver
    # ABLUnitCore.p (resolved off the environment's INI PROPATH - the ablunit
    # framework must be on that PROPATH; add it to the INI where needed).  Same
    # launch machinery as -Batch/-Compile.  OpenEdge 12+ ONLY.
    [switch]$Test,

    # -TestSpec: what to run - a test class/procedure (Foo.cls / Foo.p), a single
    # method (Foo.cls#MethodName), a comma-separated list of those, or a test
    # FOLDER (full or relative path).  Blank = a "tests" folder under the source
    # root (narrowed by -TestDir if given); errors if neither exists.
    $TestSpec="",

    # -TestDir: restrict the default test-folder spec to this sub-directory
    # (relative to the source root).  Ignored when -TestSpec is given.
    $TestDir="",

    # -TestResults: directory for the ABLUnit results.xml.  Blank = the per-run
    # tree <sourceroot>/x/<stamp>/test/.
    $TestResults="",

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
    # each row's SetupDir (= <InstallDir>/setup).  This lets the root differ by machine AND OpenEdge
    # version.  Layout under each root is unchanged:
    #   <SetupDir>/ini/<server>/<stem>.ini      (App1 stem <App><Env><Site>, e.g.
    #                                            app1TestS1; App2 stem = env word)
    #   <SetupDir>/userPfs/<server>/<stem>.pf
    # CHANGE THIS by editing the InstallDir / SetupDir on each $Installs row.

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
    #   * inventory is read over the network share instead of only the local
    #     machine's.  With an explicit -Server, ONLY that server's property files
    #     are read; with no -Server, ALL mapped servers are read.  File failures
    #     (missing / no permission / unreachable) are caught and the install is
    #     skipped silently (Test-PathSafe), so one unreachable box doesn't abort.
    #   * every path used at runtime is rewritten to that server's network form
    #     (see Convert-ToRemotePath - CHANGE THIS to match your share layout).
    #   * dbman/nsman/mssman and the reachability/broker-port probes target
    #     "-host <server>" instead of localhost.
    # Without -Remote the script behaves exactly as before (localhost only).
    #
    # REQUIREMENTS / LIMITATIONS (environmental, not fixable in script): -Remote
    # needs rights ON each remote box - share read access for the property files
    # AND AdminServer access over its port.  From a locked-down / non-domain /
    # non-elevated session those can be denied or unreachable; such a server simply
    # reports NOT REACHABLE and its targets are skipped.  Prefer an explicit
    # -Server so a run only touches the one box you actually have rights to.
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
    #   InstallDir- the install ROOT (e.g. /opt/app1).  This is what appears in the
    #               master INI's PROPATH, so the -Workspace launch rewrites
    #               InstallDir -> the chosen worktree's app folder (see
    #               Resolve-WorkspaceIni).  CHANGE THIS to your install roots.
    #   SetupDir  - root of this install's -Client/-Batch INI/PF tree, ALWAYS
    #               <InstallDir>/setup (INI under <SetupDir>/ini/<server>/, PF under
    #               <SetupDir>/userPfs/<server>/).  Both live PER INSTALL (not as one
    #               global) because the root can differ by machine AND OpenEdge
    #               version - e.g. a 12.8 install and a 10.2B install on the same box,
    #               or a laptop with its tree on a different drive.  CHANGE THIS.
    #   InstalledComponents - ALLOWLIST of shared components this install actually
    #               runs: any of "NameServer" / "MSSQLBroker" / "OracleBroker" (or
    #               @() for none).  A component discovered in ubroker.properties is only
    #               inventoried if its type is listed here, and components are only
    #               started/stopped when the selection covers the WHOLE server (see
    #               the START/STOP/RESTART dispatch).  Databases ignore this list.
    #               NOTE: it is PER INSTALL/AdminServer - two OE versions on one box
    #               each with their own AdminServer list their own components.
    #               CHANGE THIS to what each install really runs.
    #   ExtraDatabases - ALLOWLIST of EXTRA databases this install's AdminServer
    #               manages that are NOT application databases (so the app name-parser
    #               returns $null and they would normally be skipped) but that you
    #               still want inventoried and actionable - e.g. a schema-holder
    #               database.  EXACT database names (case-insensitive), or @() for
    #               none.  Each listed DB is added as a Database row with Role="Extra"
    #               and Site/Env="All" (like the server-wide components), tagged with
    #               this install's App.  PER INSTALL (the extras differ by box/AdminServer).
    #               CHANGE THIS (default @()) to any non-app DBs each install manages.
    #
    # A single server can host MULTIPLE installs (e.g. two OpenEdge versions side
    # by side on different DLCs and ports) - just add a row for each.
    #
    # The databases/NameServers/brokers themselves are NOT listed here; they are
    # discovered from each install's property files at run time.
    $Installs=@(
        # ---- App1: prod on dbserver1, dev on dbserver1-dev (two OE versions) ----
        [PSCustomObject]@{ App="App1"; Tier="Production";  Server="dbserver1";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app1";      SetupDir="/opt/app1/setup";      InstalledComponents=@("NameServer"); ExtraDatabases=@() }
        [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app1";      SetupDir="/opt/app1/setup";      InstalledComponents=@("NameServer","MSSQLBroker","OracleBroker"); ExtraDatabases=@("schemaholder1") }
        [PSCustomObject]@{ App="App1"; Tier="Development"; Server="dbserver1-dev"; OEVersion="10.2B"; DLC="/usr/dlc102b"; Port=20941; InstallDir="/opt/app1-102b"; SetupDir="/opt/app1-102b/setup"; InstalledComponents=@(); ExtraDatabases=@() }
        # ---- App2: prod on dbserver2, dev on dbserver2-dev ----------------------
        [PSCustomObject]@{ App="App2"; Tier="Production";  Server="dbserver2";     OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app2";      SetupDir="/opt/app2/setup";      InstalledComponents=@("NameServer"); ExtraDatabases=@() }
        [PSCustomObject]@{ App="App2"; Tier="Development"; Server="dbserver2-dev"; OEVersion="12.8";  DLC="/usr/dlc";     Port=20931; InstallDir="/opt/app2";      SetupDir="/opt/app2/setup";      InstalledComponents=@(); ExtraDatabases=@() }
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
$OnTestError= $false   # -Test: a test failure/error (or missing results.xml) -> exit 2004

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

# Test-Path that never throws.  A remote path we lack rights to (or an unreachable
# server) makes Test-Path raise UnauthorizedAccessException / IO errors instead of
# returning $false; under -Remote we want those treated as "not present" (skip the
# install silently), not spewed to the console.
function Test-PathSafe {
    param($Path, $PathType = "Any")
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try   { return [bool](Test-Path -LiteralPath $Path -PathType $PathType -ErrorAction Stop) }
    catch { return $false }
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
    if (-not (Test-PathSafe -Path $file -PathType Leaf)) { return @() }
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
    if (-not (Test-PathSafe -Path $file -PathType Leaf)) { return @() }
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
    if (-not (Test-PathSafe -Path $file -PathType Leaf)) { return $ports }
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

        # -Remote reads each install's property files over the network, so scope the
        # loop to the targeted server(s)/app FIRST - otherwise -Server X would still
        # reach out to every other server (slow, and it throws Access Denied on boxes
        # we have no rights to).  "All" (the -Remote default) reads them all.  Locally
        # this is a no-op cost-wise (files are on this box) but keeps behavior
        # identical.  Site/Env/Component/OEVersion are applied later (Select-Inventory).
        if ($Remote -eq $true) {
            if ($Server -ne "All" -and $install.Server -ne $Server) { continue }
            if ($App    -ne "All" -and $install.App    -ne $App)    { continue }
        }

        # Locally (default), property files are read from THIS machine's filesystem
        # (every command runs against -host localhost), so only installs hosted on
        # this server can be inventoried; an install for another server legitimately
        # has no local files and is skipped silently, and we warn (red) only when an
        # install that IS for this server is missing its files.  With -Remote the
        # files are pulled from EVERY server, so a missing/unreachable/denied path is
        # expected for some servers and is skipped silently (no warning).
        $conmgrFile  = Join-PathX $install.PropertiesDir "conmgr.properties"
        $ubrokerFile = Join-PathX $install.PropertiesDir "ubroker.properties"
        if (-not (Test-PathSafe -Path $conmgrFile -PathType Leaf) -and
            -not (Test-PathSafe -Path $ubrokerFile -PathType Leaf)) {
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
        # Allowlist of EXTRA databases this install's AdminServer manages that are
        # NOT application databases (so Parse-Database returns $null for them) but we
        # still want to see and act on - e.g. a schema-holder database.  Exact-name
        # match (case-insensitive).  Each matched DB is inventoried as a Database row
        # with Role="Extra", Site/Env="All" (like the server-wide components), tagged
        # with the install's App.  Absent/empty list => no extras added (default).
        $extraDbs = @($install.ExtraDatabases)

        foreach ($db in (Get-ManagedDatabases -PropertiesDir $install.PropertiesDir)) {
            $parsed = Parse-Database -App $install.App -DBName $db.Name
            if ($null -eq $parsed) {
                # Not an application DB.  Keep it ONLY if it's on this install's
                # ExtraDatabases allowlist; otherwise skip (as before).
                if ($extraDbs -contains $db.Name) {
                    $parsed = [PSCustomObject]@{ Role = "Extra"; Site = "All"; Env = "All" }
                } else {
                    continue   # outside the app's managed set and not an allowed extra
                }
            }
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
                InstallDir= $install.InstallDir    # install ROOT (PROPATH root for -Workspace rewrite)
                SetupDir  = $install.SetupDir      # -Client/-Batch INI/PF root (<InstallDir>/setup) for THIS install
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

        # ---- Oracle DataServer broker (oraman) ----
        # Same AdminServer-managed broker model as MS SQL (sections [UBroker.OR.*]
        # in ubroker.properties), just a different admin utility (oraman, using the
        # same -host/-port/-name/-query/-start/-stop flags).  Leave OracleBroker
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
                Manager   = "oraman"
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
            # Documented not-running wordings: "Not Running" (OE status views) and
            # the INACTIVE/STOPPED/DISABLED variants.
            if ($o -match '(?im)Broker Status\s*:\s*(Not\s*Running|INACTIVE|STOPPED|DISABLED)') { return $false }
            if ($o -match '(?i)not running|no such|not found')   { return $false }
        }
        "OracleBroker" {
            # oraman mirrors mssman's "Broker Status : ACTIVE" wording.
            if ($o -match '(?im)Broker Status\s*:\s*ACTIVE')     { return $true }
            if ($o -match '(?im)Broker Status\s*:\s*(Not\s*Running|INACTIVE|STOPPED|DISABLED)') { return $false }
            if ($o -match '(?i)not running|no such|not found')   { return $false }
        }
    }
    return $null
}

## ============================================================================
## PER-INSTANCE ACTIONS
## ============================================================================

$Label = { param($i) "{0,-16} {1,-6} {2,-12} {3}" -f $i.Server,$i.OEVersion,$i.Component,$i.Name }

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
# ($Item.InstallDir) with the worktree AppPath (Progress/UNC segments untouched).
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
    $installRoot = $Item.InstallDir.TrimEnd('/','\')
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

    # Output files, grouped per program under <script dir>/batch/<ProgramName>/.
    $pgmBase = [System.IO.Path]::GetFileNameWithoutExtension($Pgm)
    $pgmDir  = Join-PathX (Join-PathX $PSScriptRoot "batch") $pgmBase
    if ($DryRun -ne $true) { $null = New-Item -ItemType Directory -Path $pgmDir -Force -ErrorAction SilentlyContinue }
    $outFile = Join-PathX $pgmDir ($pgmBase + ".out")
    $errFile = Join-PathX $pgmDir ($pgmBase + ".err")

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

# Resolve the SOURCE ROOT a -Compile run compiles under for one target.  Default
# is the -Workspace worktree app folder (same resolution -Client/-Batch use); with
# -Installed (or when no -Workspace is given) it is the install's InstallDir.  The
# session's PROPATH/INI still comes from the same -Client/-Batch machinery, so a
# -Workspace compile resolves references against the worktree exactly like a
# -Workspace client launch.  Returns $null if it can't be resolved.
function Get-CompileSourceRoot {
    param($Item)
    if ($Installed -ne $true -and -not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wd = Get-WorkspaceWorkDir -App $Item.App
        if ($wd) { return $wd }
        Write-Message ("  Compile: workspace '{0}' not resolved for {1}; falling back to installed tree." -f $Workspace, $Item.App) -Fore Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace($Item.InstallDir)) {
        if ($Remote -eq $true) { return (Convert-ToRemotePath -Server $Item.Server -LocalPath $Item.InstallDir) }
        return $Item.InstallDir
    }
    return $null
}

# Run the headless Application Compiler (OECompiler.p) for one environment.  This
# is a -Batch launch with a fixed "-p <full path>/OECompiler.p -param <paramfile>":
#   <exe> -ininame <ini> -pf <pf> -p <...>/OECompiler.p -param <paramfile> -b
# OEAdmin writes the per-run output tree <sourceroot>/x/<stamp>/ (compile.log,
# and listing/ / xref/ when enabled) and a temp parameter file carrying the
# compile options, then launches blocking and captures stdout/stderr.  A non-zero
# program exit (OECompiler QUITs 1 when any file had COMPILER errors) is surfaced
# loudly and sets $script:OnError.
function Do-Compile {
    param(
        $Item,
        # Optional overrides so -Package can drive a fresh fail-closed compile with
        # its own run dir / excludes and learn the result.  All default to the
        # normal -Compile behavior, so a plain -Compile call is unchanged.
        $OverrideXref       = $null,   # $true forces xref on (for the dependency map)
        $OverrideMode       = $null,   # "full" / "incremental" (else -Incremental)
        $OverrideRunDir     = $null,   # put the per-run tree here instead of <src>/x/<stamp>
        $OverrideExcludeFile = $null,  # use this excludes file instead of -ExcludeFile
        [switch]$ReturnInfo            # return a result object (RunDir/XrefDir/Errors/...)
    )
    # Hoisted so the -ReturnInfo block (after try/catch/finally) can read it.
    $errCount = $null
    $L = Resolve-ClientLaunch -Item $Item -Tag "Compile"
    if (-not $L) { return }

    # The driver ships beside this script; pass it to -p by FULL PATH (no PROPATH).
    $driver = Join-PathX $PSScriptRoot "OECompiler.p"
    if ($DryRun -ne $true -and -not (Test-Path -Path $driver -PathType Leaf)) {
        Write-Message ("  Compile: driver not found: {0}" -f $driver) -Fore Red
        $script:OnError = $true; return
    }

    # Source root (worktree or installed tree).
    $srcRoot = Get-CompileSourceRoot -Item $Item
    if (-not $srcRoot) {
        Write-Message ("  Compile: could not resolve a source root for {0}" -f $Item.Name) -Fore Red
        $script:OnError = $true; return
    }

    # Per-run output tree under <sourceroot>/x/<stamp>/ (or the caller's dir).
    $stamp   = [DateTime]::Now.ToString("yyyy-MM-dd_HHmmss")
    $runDir  = if ($null -ne $OverrideRunDir -and "$OverrideRunDir" -ne "") { $OverrideRunDir } `
               else { Join-PathX (Join-PathX $srcRoot "x") $stamp }
    $logFile = Join-PathX $runDir "compile.log"
    $listDir = Join-PathX $runDir "listing"
    $xrefDir = Join-PathX $runDir "xref"
    $mode    = if ($null -ne $OverrideMode -and "$OverrideMode" -ne "") { $OverrideMode } `
               elseif ($Incremental -eq $true) { "incremental" } else { "full" }
    # -Package forces xref on (it needs the dependency map) regardless of -Xref.
    $xrefOn  = ($Xref -eq $true) -or ($OverrideXref -eq $true)
    # -Package passes its own excludes file; otherwise honor -ExcludeFile.
    $effExcludeFile = if ($null -ne $OverrideExcludeFile) { $OverrideExcludeFile } else { $ExcludeFile }

    # Build the merged EXCLUDE pattern list from -Exclude (comma lists / array) and
    # -ExcludeFile (one pattern per line; '#' comments + blanks ignored).  A bare
    # -ExcludeFile name resolves in the script folder (the standing excludes file);
    # a path with a separator is used verbatim.  Patterns go to the driver as a
    # single CHR(1)-delimited value (patterns may contain spaces/commas).
    $exPatterns = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($Exclude)) {
        foreach ($one in ($entry -split ',')) {
            $one = $one.Trim()
            if (-not [string]::IsNullOrWhiteSpace($one)) { $exPatterns.Add($one) }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($effExcludeFile)) {
        $exPath = if ($effExcludeFile -match '[\\/]') { $effExcludeFile } else { Join-PathX $PSScriptRoot $effExcludeFile }
        if (Test-Path -Path $exPath -PathType Leaf) {
            $exFileCount = 0
            foreach ($ln in (Get-Content -Path $exPath)) {
                $ln = $ln.Trim()
                if ([string]::IsNullOrWhiteSpace($ln) -or $ln.StartsWith('#')) { continue }
                $exPatterns.Add($ln); $exFileCount++
            }
            Write-Message ("  Excludes: loaded {0} pattern(s) from {1}" -f $exFileCount, $exPath) -Fore DarkGray
        } else {
            # The exclude FILE was named (explicitly via -ExcludeFile, or auto-
            # defaulted by -Package to the standing compile-excludes.txt) but is
            # not on disk.  Warn LOUDLY: with no excludes, vendor/sample code that
            # never compiles standalone will error and (for -Package) fail-close
            # the whole bundle - which looks like "everything is broken".
            $exWhy = if ($null -ne $OverrideExcludeFile) {
                         "the standing exclude file was not found (so NOTHING will be excluded)"
                     } else {
                         "-ExcludeFile not found (so NOTHING will be excluded)"
                     }
            Write-Message ("  WARNING: {0}: {1}" -f $exWhy, $exPath) -Fore Red
            Write-Message  "           Expected-error files (vendor/sample code) will COMPILE and ERROR." -Fore Red
            if ($null -ne $OverrideExcludeFile) {
                Write-Message ("           Put compile-excludes.txt in the OEAdmin folder ({0}), or pass -ExcludeFile <path>." -f $PSScriptRoot) -Fore Red
            }
        }
    }
    $excludesValue = ($exPatterns -join ([char]1))

    # The parameter file the driver reads (SESSION:PARAMETER).
    $paramFile = Join-PathX $PSScriptRoot ("oecompile_{0}.param" -f $stamp)
    # ABL QUIT carries no OS exit code, so the driver reports pass/fail by writing
    # a status file ("ERRORS=<n>", or -1 on a setup abort) that we read afterward.
    $statusFile = Join-PathX $runDir "compile.status"

    Write-Message ("Compile: {0,-40} {1}  [{2}]" -f (& $Label $Item), $L.ExeName, $mode) -Fore Cyan
    Write-Message ("  source root: {0}" -f $srcRoot) -Fore DarkGray
    Write-Message ("  output dir : {0}" -f $runDir) -Fore DarkGray
    $dirNote = if ([string]::IsNullOrWhiteSpace($Dir)) { "" } else { "   dir: $Dir" }
    Write-Message ("  file specs : {0}{1}" -f $FileSpec, $dirNote) -Fore DarkGray
    if ($exPatterns.Count -gt 0) {
        Write-Message ("  excludes   : {0} pattern(s): {1}" -f $exPatterns.Count, ($exPatterns -join ', ')) -Fore DarkGray
    }

    # Compose the param-file content (the driver defaults recurse=yes).
    $pfLines = @(
        "# OECompiler parameter file - generated by OEAdmin -Compile",
        "sourceroot = $srcRoot",
        "filespecs = $FileSpec",
        "recurse = yes",
        "mode = $mode",
        "logfile = $logFile",
        ("listing = " + $(if ($Listing -eq $true) { "yes" } else { "no" })),
        "listingdir = $listDir",
        ("xref = " + $(if ($xrefOn) { "yes" } else { "no" })),
        "xrefdir = $xrefDir",
        ("xrefxml = " + $(if ($XrefXml -eq $true) { "yes" } else { "no" })),
        "statusfile = $statusFile"
    )
    if (-not [string]::IsNullOrWhiteSpace($Dir)) { $pfLines += "dir = $Dir" }
    if ($exPatterns.Count -gt 0) { $pfLines += "excludes = $excludesValue" }

    # Driver stdout/err grouped under <script dir>/batch/OECompiler/.
    $pgmDir  = Join-PathX (Join-PathX $PSScriptRoot "batch") "OECompiler"
    if ($DryRun -ne $true) { $null = New-Item -ItemType Directory -Path $pgmDir -Force -ErrorAction SilentlyContinue }
    $outFile = Join-PathX $pgmDir ("OECompiler_{0}.out" -f $stamp)
    $errFile = Join-PathX $pgmDir ("OECompiler_{0}.err" -f $stamp)

    $cargs = @("-ininame", $L.Ini, "-pf", $L.Pf)
    $dargs = @("-ininame", (Split-Path $L.Ini -Leaf), "-pf", (Split-Path $L.Pf -Leaf))
    foreach ($ap in $L.AddPfs) { $cargs += @("-pf", $ap); $dargs += @("-pf", (Split-Path $ap -Leaf)) }
    $cargs += @("-p", $driver, "-param", $paramFile, "-b")
    $dargs += @("-p", "OECompiler.p", "-param", (Split-Path $paramFile -Leaf), "-b")

    $display = "$($L.ExeName) " + ($dargs -join ' ')
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] {0}  1> {1} 2> {2}" -f $display, (Split-Path $outFile -Leaf), (Split-Path $errFile -Leaf)) -Fore DarkGray
        Write-Message  "  [DRYRUN] parameter file contents:" -Fore DarkGray
        foreach ($pl in $pfLines) { Write-Message ("    " + $pl) -Fore DarkGray }
        return
    }

    try {
        $null = New-Item -ItemType Directory -Path $runDir -Force -ErrorAction Stop
        if ($Listing -eq $true) { $null = New-Item -ItemType Directory -Path $listDir -Force -ErrorAction Stop }
        if ($xrefOn)            { $null = New-Item -ItemType Directory -Path $xrefDir -Force -ErrorAction Stop }
        Set-Content -Path $paramFile -Value $pfLines -Encoding ascii -ErrorAction Stop
    } catch {
        Write-Message ("  Compile: could not create output dir / param file: {0}" -f $_.Exception.Message) -Fore Red
        $script:OnError = $true; return
    }

    $workDir = Get-WorkspaceWorkDir -App $Item.App
    Write-Message ("  {0}" -f $display) -Fore DarkGray
    if ($workDir) { Write-Message ("  working dir: {0}" -f $workDir) -Fore DarkGray }

    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        # Launch WITHOUT -Wait so we can show a heartbeat while OECompiler.p runs.
        # The ABL compile is a single blocking call we can't see into (its stdout is
        # redirected to a file), so this is an elapsed-time "working on it" marquee,
        # not a true percentage.  We poll the process + a periodic Write-Progress,
        # then clear it once the compiler exits.
        $spArgs = @{ FilePath=$L.Exe; ArgumentList=$cargs; NoNewWindow=$true; PassThru=$true;
                     RedirectStandardOutput=$outFile; RedirectStandardError=$errFile }
        if ($workDir) { $spArgs['WorkingDirectory'] = $workDir }
        $p = Start-Process @spArgs

        Write-Message "  Compiling (this can take a while; see the log for per-file results)..." -Fore DarkGray
        $swTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $spin = '|','/','-','\'; $si = 0
        while (-not $p.HasExited) {
            $el = $swTimer.Elapsed
            $elapsedStr = "{0:D2}:{1:D2}" -f [int]$el.TotalMinutes, $el.Seconds
            $logCount = 0
            if (Test-Path -Path $logFile -PathType Leaf) {
                $logCount = @(Get-Content -Path $logFile -ErrorAction SilentlyContinue).Count
            }
            Write-Progress -Activity ("Compiling {0}" -f (& $Label $Item)) `
                -Status ("{0} working... elapsed {1}   log lines: {2}" -f $spin[$si % 4], $elapsedStr, $logCount) `
                -PercentComplete -1
            $si++
            Start-Sleep -Milliseconds 400
        }
        $swTimer.Stop()
        Write-Progress -Activity ("Compiling {0}" -f (& $Label $Item)) -Completed
        Write-Message ("  Compile process finished in {0:D2}:{1:D2}." -f [int]$swTimer.Elapsed.TotalMinutes, $swTimer.Elapsed.Seconds) -Fore DarkGray

        # The driver writes compile.status ("ERRORS=<n>"); -1 or a missing file
        # means a setup/abort failure.  This - not $p.ExitCode (ABL QUIT has none) -
        # is the authoritative pass/fail signal.
        $errCount = -1
        if (Test-Path -Path $statusFile -PathType Leaf) {
            # (errCount is function-scoped; set here so -ReturnInfo can read it)
            $m = (Get-Content -Path $statusFile -ErrorAction SilentlyContinue | Select-String -Pattern 'ERRORS=(-?\d+)')
            if ($m) { $errCount = [int]$m.Matches[0].Groups[1].Value }
        }

        if ($errCount -eq 0) {
            Write-Message  "  Compile completed clean (0 errors)." -Fore Green
            Write-Message ("    log: {0}" -f $logFile) -Fore DarkGray
        } elseif ($errCount -gt 0) {
            Write-Message ("  COMPILE ERRORS detected ({0} file(s)).  Review the log:" -f $errCount) -Fore Red
            Write-Message ("    {0}" -f $logFile) -Fore Red
            Write-Message ("    driver summary: {0}" -f $outFile) -Fore Red
            $script:OnError = $true
        } else {
            Write-Message ("  Compile did not complete (no status / setup error).  See:") -Fore Red
            Write-Message ("    driver summary: {0}" -f $outFile) -Fore Red
            Write-Message ("    driver errors : {0}" -f $errFile) -Fore Red
            $script:OnError = $true
        }
    } catch {
        Write-Message ("  ERROR running compile: {0}" -f $_.Exception.Message) -Fore Red
        $script:OnError = $true
    } finally {
        $env:DLC = $prev
        Remove-Item -Path $paramFile -Force -ErrorAction SilentlyContinue
    }

    # -Package calls with -ReturnInfo to learn where the artifacts are and whether
    # the compile was clean.  Errors: $null=never ran, -1=setup/abort, 0=clean,
    # >0=that many files errored.  Callers treat $null/-1/>0 all as "do not ship".
    if ($ReturnInfo) {
        return [PSCustomObject]@{ RunDir=$runDir; XrefDir=$xrefDir; LogFile=$logFile;
                                  StatusFile=$statusFile; Errors=$errCount; DryRun=$false; SourceRoot=$srcRoot }
    }
}

## ============================================================================
## PACKAGE  (-Package : build a release bundle from one project's change set)
## ============================================================================
# -Package turns ONE project's change set into a versioned, auditable release
# bundle (a zip): the CHANGED source, a dependency-aware set of freshly-compiled
# r-code, any schema delta .df files, a manifest (JSON + text), and a safe self-
# deploying deploy.ps1 with rollback.  It reuses the -Compile / -Batch launch
# machinery verbatim (Resolve-ClientLaunch / Get-CompileSourceRoot / Do-Compile /
# OECompiler.p); the only existing-code change is Do-Compile's backward-compatible
# override params above.  -Site AND -Env are REQUIRED (the r-code CRC is tied to
# the schema it compiles against).  LOCAL git worktree only (-Remote refused).
#
# Two gated passes:
#   RESOLVE (no -Accept): union the change-set inputs, cross-check any inline
#     change markers (advisory), write a human-reviewable change-set file carrying
#     a hash of the reviewed set, and STOP.
#   ACCEPT (-Accept, which REQUIRES -Project): re-resolve, refuse unless the fresh
#     set matches the reviewed hash, run ONE full xref-on fresh compile against
#     -Site/-Env (fail-closed, inheriting the standing compile excludes), compute
#     the dependency-aware ship set from the xref, confirm delta DFs are loaded
#     (a gate distinct from -Accept), then assemble + zip the bundle.
# -DryRun previews every pass without writing the zip.

# Slugify a project/tag token into a filename-safe string.
function Get-PackageSlug {
    param($Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $s = ($Value -replace '[\\/:*?"<>|]', ' ').Trim()
    $s = ($s -replace '\s+', '-')
    return $s
}

# Resolve the git repo root for $srcRoot and the "app segment" (the relative path
# from the repo root down to $srcRoot), forward-slashed.  git reports repo-relative
# paths WITH this segment; we strip it to get the app-root-relative base used
# everywhere (source/, rcode/, manifest, deploy.ps1).  Returns $null (and writes a
# reason) if $srcRoot is not inside a local git worktree.
function Get-PackageRepoInfo {
    param($SrcRoot)
    $top = & git -C $SrcRoot rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $top) {
        Write-Message ("  Package: '{0}' is not inside a git worktree ({1}). -Package must run against a LOCAL git worktree." -f $SrcRoot, ($top -join ' ').Trim()) -Fore Red
        return $null
    }
    $repoRoot = ("$top".Trim() -replace '\\', '/').TrimEnd('/')
    $src      = ($SrcRoot -replace '\\', '/').TrimEnd('/')
    $appSeg   = ""
    if ($src.ToLower().StartsWith($repoRoot.ToLower()) -and $src.Length -gt $repoRoot.Length) {
        $appSeg = $src.Substring($repoRoot.Length).Trim('/')
    }
    return [PSCustomObject]@{ RepoRoot=$repoRoot; AppSegment=$appSeg }
}

# Convert a git repo-relative path (e.g. "App1/Bin/prog.p") to app-root-relative
# (e.g. "Bin/prog.p") by stripping the leading app segment.  Forward-slashed.
function ConvertTo-AppRootRelative {
    param($RepoRelPath, $AppSegment)
    $p = ($RepoRelPath -replace '\\', '/').Trim('/')
    if ($AppSegment -ne "" -and $p.ToLower().StartsWith(($AppSegment.ToLower() + '/'))) {
        $p = $p.Substring($AppSegment.Length + 1)
    } elseif ($AppSegment -ne "" -and $p.ToLower() -eq $AppSegment.ToLower()) {
        $p = ""
    }
    return $p
}

# Resolve the change set: union -Grep / -FromCommit..-ToCommit / -FileList, all
# normalized to app-root-relative paths.  Also returns the change-set git commit
# hashes for the manifest.  Writes a reason + returns $null on a hard error.
function Resolve-PackageChangeSet {
    param($SrcRoot, $AppSegment)
    $files   = New-Object System.Collections.Generic.List[string]
    $commits = New-Object System.Collections.Generic.List[string]
    $used    = $false

    # Input 1: -Grep tag -> git log --grep (its commits ARE the change-set commits).
    if (-not [string]::IsNullOrWhiteSpace($Grep)) {
        $used = $true
        $raw = & git -C $SrcRoot log -i --grep $Grep --name-only --pretty=format:"__COMMIT__%H" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Message ("  Package: git log --grep failed: {0}" -f ($raw -join ' ').Trim()) -Fore Red
            return $null
        }
        foreach ($ln in $raw) {
            $t = "$ln".Trim()
            if ($t -eq "") { continue }
            if ($t.StartsWith("__COMMIT__")) { $commits.Add($t.Substring(10)); continue }
            $files.Add((ConvertTo-AppRootRelative -RepoRelPath $t -AppSegment $AppSegment))
        }
    }

    # Input 2: -FromCommit..-ToCommit range (both required together).
    $haveFrom = -not [string]::IsNullOrWhiteSpace($FromCommit)
    $haveTo   = -not [string]::IsNullOrWhiteSpace($ToCommit)
    if ($haveFrom -ne $haveTo) {
        Write-Message "  Package: both -FromCommit and -ToCommit are required together." -Fore Red
        return $null
    }
    if ($haveFrom -and $haveTo) {
        $used = $true
        $raw = & git -C $SrcRoot diff --name-only ("{0}..{1}" -f $FromCommit, $ToCommit) 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Message ("  Package: git diff {0}..{1} failed: {2}" -f $FromCommit, $ToCommit, ($raw -join ' ').Trim()) -Fore Red
            return $null
        }
        foreach ($ln in $raw) { $t = "$ln".Trim(); if ($t -ne "") { $files.Add((ConvertTo-AppRootRelative -RepoRelPath $t -AppSegment $AppSegment)) } }
        $rc = & git -C $SrcRoot log --pretty=format:"%H" ("{0}..{1}" -f $FromCommit, $ToCommit) 2>&1
        if ($LASTEXITCODE -eq 0) { foreach ($h in $rc) { $t = "$h".Trim(); if ($t -ne "") { $commits.Add($t) } } }
    }

    # Input 3: -FileList explicit list.
    if (-not [string]::IsNullOrWhiteSpace($FileList)) {
        $used = $true
        $flPath = if ($FileList -match '[\\/]') { $FileList } else { Join-PathX $SrcRoot $FileList }
        if (-not (Test-Path -Path $flPath -PathType Leaf)) {
            Write-Message ("  Package: -FileList not found: {0}" -f $flPath) -Fore Red
            return $null
        }
        foreach ($ln in (Get-Content -Path $flPath)) {
            $t = "$ln".Trim()
            if ($t -eq "" -or $t.StartsWith('#')) { continue }
            # A -FileList entry may be absolute, $srcRoot-relative, or repo-relative;
            # normalize to app-root-relative.  If it is already app-root-relative it
            # passes through ConvertTo-AppRootRelative unchanged (no app segment prefix).
            $t = $t -replace '\\', '/'
            if ([System.IO.Path]::IsPathRooted($t)) {
                $full = ($t -replace '\\','/'); $srcN = ($SrcRoot -replace '\\','/').TrimEnd('/')
                if ($full.ToLower().StartsWith($srcN.ToLower() + '/')) { $t = $full.Substring($srcN.Length + 1) }
            } else {
                $t = ConvertTo-AppRootRelative -RepoRelPath $t -AppSegment $AppSegment
            }
            $files.Add($t)
        }
    }

    if (-not $used) {
        Write-Message "  Package: needs a change-set input (-Grep / -FromCommit+-ToCommit / -FileList) or -Full." -Fore Red
        return $null
    }

    # De-dup (case-insensitive), drop blanks, sort for a stable review + hash.
    $seen = @{}
    $out  = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $k = $f.ToLower()
        if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $out.Add($f) }
    }
    $sorted = @($out | Sort-Object)
    $cseen = @{}; $cout = New-Object System.Collections.Generic.List[string]
    foreach ($c in $commits) { if ($c -ne "" -and -not $cseen.ContainsKey($c)) { $cseen[$c]=$true; $cout.Add($c) } }
    return [PSCustomObject]@{ Files=$sorted; Commits=@($cout) }
}

# SHA-256 of the sorted, lowercased, newline-joined change-set paths (order-
# independent); drives the -Accept reviewed-set gate.
function Get-ChangeSetHash {
    param([string[]]$Files)
    $norm = (@($Files | ForEach-Object { $_.ToLower() } | Sort-Object) -join "`n")
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($norm)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally { $sha.Dispose() }
}

# Advisory marker cross-check: warn on drift between git-reported files and files
# carrying an inline change marker (/* XX YYYY-MM-DD ... changes */).  NEVER blocks.
# Also returns the matched marker text per file (for the manifest revisionHistory).
function Test-PackageMarkers {
    param($SrcRoot, [string[]]$Files)
    $markerRx = '/\*\s*[A-Za-z]{2,4}\s+\d{4}-\d{2}-\d{2}\b.*changes\b.*\*/'
    $markerNoGit = New-Object System.Collections.Generic.List[string]
    $gitNoMarker = New-Object System.Collections.Generic.List[string]
    $markerText  = @{}
    # 1) each git-reported file: does it carry a marker?
    foreach ($f in $Files) {
        $full = Join-PathX $SrcRoot ($f -replace '/', '\')
        if (-not (Test-Path -Path $full -PathType Leaf)) { continue }
        $hit = Select-String -Path $full -Pattern $markerRx -AllMatches -ErrorAction SilentlyContinue
        if ($hit) { $markerText[$f] = @($hit.Matches | ForEach-Object { $_.Value.Trim() }) }
        else      { $gitNoMarker.Add($f) }
    }
    # 2) files in the tree carrying a marker git did NOT report (bounded to source).
    $gitLower = @{}; foreach ($f in $Files) { $gitLower[$f.ToLower()] = $true }
    $scan = Get-ChildItem -Path $SrcRoot -Recurse -File -Include *.p,*.w,*.cls,*.i,*.t -ErrorAction SilentlyContinue
    foreach ($fi in $scan) {
        $hit = Select-String -Path $fi.FullName -Pattern $markerRx -ErrorAction SilentlyContinue
        if (-not $hit) { continue }
        $rel = ($fi.FullName -replace '\\','/')
        $srcN = ($SrcRoot -replace '\\','/').TrimEnd('/')
        if ($rel.ToLower().StartsWith($srcN.ToLower() + '/')) { $rel = $rel.Substring($srcN.Length + 1) }
        if (-not $gitLower.ContainsKey($rel.ToLower())) { $markerNoGit.Add($rel) }
    }
    return [PSCustomObject]@{ MarkerNoGit=@($markerNoGit); GitNoMarker=@($gitNoMarker); MarkerText=$markerText }
}

# Parse the XREF tree (one .xref per compile unit) into an include->units map and
# the set of all compile units, both keyed app-root-relative.  Two signals:
#  (a) column-2 referenced-file full paths (captures includes that emit code);
#  (b) INCLUDE reference-type rows (captures define-only / preprocessor-only
#      includes whose path appears ONLY in the INCLUDE detail), filtered so
#      {&named-arg} refs ("get"/"set"/"fn"...) are discarded.
function Get-PackageDependencyMap {
    param($XrefDir, $SrcRoot, $AppSegment)
    $srcN = ($SrcRoot -replace '\\','/').TrimEnd('/')
    # include(app-rel) -> hashset of compile-unit(app-rel)
    $inv   = @{}
    $units = @{}   # app-rel compile unit -> $true

    # Nested helpers (real functions, not scriptblocks).  A scriptblock's
    # .Invoke() wraps its return in a collection, so $toAppRel.Invoke(x) handed
    # back a 1-element Collection instead of a string; that collection then got
    # used as a hashtable key / value and PowerShell tried to coerce the path to
    # an Int32 index ("Cannot convert 'Bin/admf100.w' to System.Int32").  Plain
    # functions return the natural scalar and bind args by name - no wrapping.
    function ToAppRel {
        param($full)
        $p = ("$full" -replace '\\','/')
        if ($p.ToLower().StartsWith($srcN.ToLower() + '/')) { return $p.Substring($srcN.Length + 1) }
        return $p   # out-of-tree (vendor DLC includes) kept verbatim; never matches a changed file
    }
    function AddDep {
        param($unitRel, $depRel)
        if ([string]::IsNullOrEmpty($depRel)) { return }
        if (-not $inv.ContainsKey($depRel)) { $inv[$depRel] = @{} }
        $inv[$depRel][$unitRel] = $true
    }

    $xrefFiles = Get-ChildItem -Path $XrefDir -Recurse -File -Filter *.xref -ErrorAction SilentlyContinue
    foreach ($xf in $xrefFiles) {
        # The owning compile unit is THIS .xref's source (authoritative), derived
        # from the xref's mirrored path: <XrefDir>/<app-rel>.xref  ->  <app-rel>.
        $xrel = ($xf.FullName -replace '\\','/')
        $xdirN = ($XrefDir -replace '\\','/').TrimEnd('/')
        $unitRel = $xrel
        if ($xrel.ToLower().StartsWith($xdirN.ToLower() + '/')) { $unitRel = $xrel.Substring($xdirN.Length + 1) }
        $unitRel = $unitRel -replace '\.xref$', ''
        $units[$unitRel] = $true
        AddDep -unitRel $unitRel -depRel $unitRel   # a unit depends on itself

        foreach ($line in (Get-Content -Path $xf.FullName -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # Signal (a): column-2 referenced-file full path.  Tokenize honoring a
            # possible quoted path; we only need token[1] and the ref-type token[3].
            $toks = $line -split '\s+'
            if ($toks.Count -ge 2) {
                $ref = $toks[1]
                if ($ref -match '^[A-Za-z]:[\\/]' -or $ref -match '^[\\/]') {
                    $depRel = ToAppRel -full $ref
                    AddDep -unitRel $unitRel -depRel $depRel
                }
            }
            # Signal (b): INCLUDE rows.  Find the INCLUDE ref-type and the detail.
            $m = [regex]::Match($line, '\bINCLUDE\b\s+(.*)$')
            if ($m.Success) {
                $detail = $m.Groups[1].Value.Trim()
                $inc = ""
                if ($detail.StartsWith('"')) {
                    # quoted (include has args): first ws-item inside the quotes
                    $inner = $detail.Substring(1)
                    $inner = $inner -replace '".*$', ''        # drop at the closing quote region
                    $inc = (($inner -split '\s+') | Where-Object { $_ -ne "" } | Select-Object -First 1)
                } else {
                    $inc = (($detail -split '\s+') | Where-Object { $_ -ne "" } | Select-Object -First 1)
                }
                if ($inc) {
                    $inc = $inc.Trim('"')
                    # Filter {&named-arg} refs: keep only real include/source names
                    # (known extension) or tokens that resolve to a real file.
                    $isFileName = ($inc -match '\.(i|p|w|cls|t)$')
                    $resolved = ""
                    if ($isFileName) {
                        $unitDir = Split-Path (Join-PathX $SrcRoot ($unitRel -replace '/','\')) -Parent
                        foreach ($cand in @((Join-PathX $unitDir ($inc -replace '/','\')), (Join-PathX $SrcRoot ($inc -replace '/','\')))) {
                            if (Test-Path -Path $cand -PathType Leaf) { $resolved = ($cand -replace '\\','/'); break }
                        }
                        $depRel = if ($resolved -ne "") { ToAppRel -full $resolved } else { ($inc -replace '\\','/') }
                        AddDep -unitRel $unitRel -depRel $depRel
                    }
                    # not a filename-looking token -> {&name} arg ref, discard.
                }
            }
        }
    }
    return [PSCustomObject]@{ Inverted=$inv; Units=$units }
}

# Build the r-code ship set (app-rel compile-unit paths) from the dependency map
# and the changed files: every unit that references/includes a changed file, plus
# every changed file that is itself a compile unit (.p .w .cls .t).
function Get-PackageRcodeSet {
    param($DepMap, [string[]]$ChangedFiles)
    $ship = @{}
    foreach ($f in $ChangedFiles) {
        $fl = $f.ToLower()
        # changed file that is itself a compile unit
        if ($f -match '\.(p|w|cls|t)$' -and $DepMap.Units.ContainsKey($f)) { $ship[$f] = $true }
        elseif ($f -match '\.(p|w|cls|t)$') {
            # a compile unit present in the tree even if the xref key cased differently
            foreach ($u in $DepMap.Units.Keys) { if ($u.ToLower() -eq $fl) { $ship[$u] = $true } }
        }
        # every unit that depends on this changed file (include or direct)
        foreach ($depKey in $DepMap.Inverted.Keys) {
            if ($depKey.ToLower() -eq $fl) {
                foreach ($u in $DepMap.Inverted[$depKey].Keys) { $ship[$u] = $true }
            }
        }
    }
    return @($ship.Keys | Sort-Object)
}

# Extract header "Revisions:" block lines + inline markers from a changed file
# (best-effort; missing block -> empty).
function Get-PackageRevisionLines {
    param($FullPath, [string[]]$MarkerHits)
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -Path $FullPath -PathType Leaf) {
        $inRev = $false; $n = 0
        foreach ($ln in (Get-Content -Path $FullPath -ErrorAction SilentlyContinue)) {
            $n++
            if ($n -gt 120) { break }   # header block only
            if ($ln -match '(?i)revisions\s*:') { $inRev = $true; continue }
            if ($inRev) {
                if ($ln -match '\*/' -or [string]::IsNullOrWhiteSpace(($ln -replace '[\*\s]',''))) { $inRev = $false; continue }
                $t = $ln.Trim(); if ($t -ne "") { $lines.Add($t) }
            }
        }
    }
    foreach ($mk in @($MarkerHits)) { if ($mk) { $lines.Add("[marker] " + $mk) } }
    return @($lines)
}

# The -Package action for one resolved environment target.
function Do-Package {
    param($Item)

    $L = Resolve-ClientLaunch -Item $Item -Tag "Package"
    if (-not $L) { return }

    # -Package is a LOCAL build action: -Remote source roots are UNC and not git
    # worktrees, so refuse early with a clear message.
    if ($Remote -eq $true) {
        Write-Message "  Package: -Remote is not supported; -Package must run against a LOCAL git worktree." -Fore Red
        $script:OnError = $true; return
    }

    $srcRoot = Get-CompileSourceRoot -Item $Item
    if (-not $srcRoot) {
        Write-Message ("  Package: could not resolve a source root for {0}" -f $Item.Name) -Fore Red
        $script:OnError = $true; return
    }

    # -Accept requires -Project (the stable review file is keyed by project).
    if ($Accept -eq $true -and [string]::IsNullOrWhiteSpace($Project)) {
        Write-Message "  Package: -Accept requires -Project <token> (the review file is keyed by project)." -Fore Red
        $script:OnError = $true; return
    }
    # Require a change-set input unless -Full.
    $haveInput = (-not [string]::IsNullOrWhiteSpace($Grep)) -or
                 (-not [string]::IsNullOrWhiteSpace($FromCommit)) -or
                 (-not [string]::IsNullOrWhiteSpace($ToCommit))  -or
                 (-not [string]::IsNullOrWhiteSpace($FileList))
    if (-not $haveInput -and $Full -ne $true) {
        Write-Message "  Package: needs a change-set input (-Grep / -FromCommit+-ToCommit / -FileList) or -Full." -Fore Red
        $script:OnError = $true; return
    }

    $repoInfo = Get-PackageRepoInfo -SrcRoot $srcRoot
    if (-not $repoInfo) { $script:OnError = $true; return }
    $appSeg = $repoInfo.AppSegment

    $stamp   = [DateTime]::Now.ToString("yyyy-MM-dd_HHmmss")
    $projTok = Get-PackageSlug -Value $Project
    if ($projTok -eq "") { $projTok = Get-PackageSlug -Value $Grep }
    if ($projTok -eq "") { $projTok = "package" }

    $pkgRoot    = Join-PathX $PSScriptRoot "packages"
    $reviewFile = Join-PathX $pkgRoot ("{0}.changeset.txt" -f $projTok)        # stable, keyed by project
    $stampedRev = Join-PathX $pkgRoot ("{0}_{1}.changeset.txt" -f $projTok, $stamp)
    $staging    = Join-PathX $pkgRoot ("{0}_{1}" -f $projTok, $stamp)
    $zipPath    = Join-PathX $pkgRoot ("{0}_{1}.zip" -f $projTok, $stamp)

    Write-Message ("Package: {0,-38} {1}  [{2}]" -f (& $Label $Item), $L.ExeName, $(if ($Full -eq $true){"full"}else{"changes"})) -Fore Cyan
    Write-Message ("  source root : {0}   (repo {1}, app segment '{2}')" -f $srcRoot, $repoInfo.RepoRoot, $appSeg) -Fore DarkGray
    Write-Message ("  project     : {0}" -f $projTok) -Fore DarkGray

    # ---- Resolve the change set (unless -Full with no inputs) ----------------
    $changed = @()
    $csCommits = @()
    if ($haveInput) {
        $cs = Resolve-PackageChangeSet -SrcRoot $srcRoot -AppSegment $appSeg
        if (-not $cs) { $script:OnError = $true; return }
        $changed = @($cs.Files)
        $csCommits = @($cs.Commits)
        if ($changed.Count -eq 0) {
            Write-Message "  Package: no files resolved from the change-set inputs." -Fore Red
            $script:OnError = $true; return
        }
    }

    # ---- Advisory marker cross-check -----------------------------------------
    $markers = $null
    if ($changed.Count -gt 0) {
        $markers = Test-PackageMarkers -SrcRoot $srcRoot -Files $changed
        foreach ($f in @($markers.MarkerNoGit)) { Write-Message ("  WARN: marker present but git did not report: {0}" -f $f) -Fore Yellow }
        foreach ($f in @($markers.GitNoMarker)) { Write-Message ("  WARN: git reported but no inline marker found: {0}" -f $f) -Fore Yellow }
    }

    # ---- Reviewed-set hash ----------------------------------------------------
    $setHash = if ($changed.Count -gt 0) { Get-ChangeSetHash -Files $changed } else { "FULL-NO-CHANGESET" }

    if (-not (Test-Path -Path $pkgRoot)) {
        if ($DryRun -ne $true) { $null = New-Item -ItemType Directory -Path $pkgRoot -Force -ErrorAction SilentlyContinue }
    }

    # Compose the review-file content.
    $revHeader = @(
        "# OEAdmin -Package change set for review",
        "# project   : $projTok",
        "# stamp     : $stamp",
        "# target    : $($Item.App) / $($Item.Site) / $($Item.Env)  (server $($Item.Server))",
        "# source    : $srcRoot",
        "# appSegment: $appSeg",
        "# inputs    : Grep='$Grep' FromCommit='$FromCommit' ToCommit='$ToCommit' FileList='$FileList' Full=$Full",
        "# drift     : markerNoGit=$(@($markers.MarkerNoGit).Count) gitNoMarker=$(@($markers.GitNoMarker).Count)",
        "# SETHASH=$setHash",
        "#",
        "# One app-root-relative path per line.  Review, then re-run with -Accept."
    ) + @($changed)

    # ---- Gate logic -----------------------------------------------------------
    if ($Accept -ne $true) {
        # RESOLVE pass: write the review files and STOP (no compile, no zip).
        if ($DryRun -ne $true) {
            Set-Content -Path $reviewFile -Value $revHeader -Encoding ascii
            Set-Content -Path $stampedRev -Value $revHeader -Encoding ascii
        }
        Write-Message ("  Resolved {0} changed source file(s):" -f $changed.Count) -Fore Green
        foreach ($f in $changed) { Write-Message ("    {0}" -f $f) -Fore Gray }
        if ($DryRun -eq $true) {
            Write-Message "  [DRYRUN] resolve pass - no review file written." -Fore DarkGray
        } else {
            Write-Message ("  Review file: {0}" -f $reviewFile) -Fore DarkGray
        }
        Write-Message  "  To build the bundle, review the list then re-run with -Accept:" -Fore Cyan
        Write-Message ("    .\OEAdmin.ps1 -Package -App {0} -Site {1} -Env {2} -Project {3} ... -Accept" -f $Item.App, $Item.Site, $Item.Env, $projTok) -Fore Cyan
        return
    }

    # ACCEPT pass: the reviewed set must match the stable review file's hash.
    if (-not (Test-Path -Path $reviewFile -PathType Leaf)) {
        Write-Message ("  Package: no reviewed change set found ({0}). Re-run WITHOUT -Accept to produce a review, confirm it, then -Accept." -f $reviewFile) -Fore Red
        $script:OnError = $true; return
    }
    $reviewedHash = ""
    $rh = Select-String -Path $reviewFile -Pattern 'SETHASH=([0-9a-fA-F]+)' -ErrorAction SilentlyContinue
    if ($rh) { $reviewedHash = $rh.Matches[0].Groups[1].Value }
    if ($reviewedHash -ne $setHash) {
        Write-Message "  Package: the change set has changed since review (hash mismatch)." -Fore Red
        Write-Message "    Re-run WITHOUT -Accept to produce a fresh review, confirm it, then re-run with -Accept." -Fore Red
        $script:OnError = $true; return
    }

    # ---- Delta-DF confirmation gate (distinct from -Accept) -------------------
    $dfFiles = @()
    foreach ($entry in @($DeltaDf)) {
        foreach ($one in ($entry -split ',')) {
            $one = $one.Trim()
            if ([string]::IsNullOrWhiteSpace($one)) { continue }
            $dfPath = if ($one -match '[\\/]') { $one } else { Join-PathX $srcRoot $one }
            if (-not (Test-Path -Path $dfPath -PathType Leaf)) {
                Write-Message ("  Package: -DeltaDf file not found: {0}" -f $dfPath) -Fore Red
                $script:OnError = $true; return
            }
            if ($one -notmatch '\.df$') { Write-Message ("  Package: -DeltaDf '{0}' is not a .df file (continuing)." -f $one) -Fore Yellow }
            $dfFiles += $dfPath
        }
    }
    if ($dfFiles.Count -gt 0) {
        if ($DryRun -eq $true) {
            Write-Message ("  [DRYRUN] delta-DF gate WOULD require confirmation the {0} DF(s) are loaded into {1}/{2}/{3} (-DfLoadedConfirmed or interactive yes)." -f $dfFiles.Count, $Item.App, $Item.Site, $Item.Env) -Fore DarkGray
        } else {
            $confirmed = $false
            if ($DfLoadedConfirmed -eq $true) { $confirmed = $true }
            elseif ([Environment]::UserInteractive) {
                $confirmed = Read-YesNo -Prompt ("Delta DF(s) [{0}] - confirm these are ALREADY LOADED into {1}/{2}/{3} before trusting the compiled r-code?" -f (($dfFiles | ForEach-Object { Split-Path $_ -Leaf }) -join ', '), $Item.App, $Item.Site, $Item.Env) -Default:$false
            }
            if (-not $confirmed) {
                Write-Message "  Package: delta-DF load not confirmed. Pass -DfLoadedConfirmed (non-interactive) or answer yes. Aborting." -Fore Red
                $script:OnError = $true; return
            }
        }
    }

    # ---- Fresh fail-closed compile (xref on, full) ----------------------------
    # Inherit the SAME excludes as -Compile, defaulting to the standing
    # compile-excludes.txt whenever -ExcludeFile is blank (independent of -Exclude),
    # so the full-root compile does not fail closed on vendor sample code.
    $effExcludeFile = if ([string]::IsNullOrWhiteSpace($ExcludeFile)) { "compile-excludes.txt" } else { $ExcludeFile }
    $pkgRunDir = Join-PathX $staging "compile"
    Write-Message "  Running fresh fail-closed compile (xref on, full)..." -Fore Cyan
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] would compile source root {0} against {1}/{2}/{3}, excludes file '{4}'." -f $srcRoot, $Item.App, $Item.Site, $Item.Env, $effExcludeFile) -Fore DarkGray
    }
    $ci = Do-Compile -Item $Item -OverrideXref $true -OverrideMode "full" `
                     -OverrideRunDir $pkgRunDir -OverrideExcludeFile $effExcludeFile -ReturnInfo

    if ($DryRun -ne $true) {
        if ($null -eq $ci -or $null -eq $ci.Errors -or $ci.Errors -ne 0) {
            $ec = if ($null -eq $ci) { "(compile did not run)" } else { $ci.Errors }
            Write-Message ("  Package: fresh compile did not complete clean (errors={0}). Bundle aborted." -f $ec) -Fore Red
            if ($ci -and $ci.LogFile) { Write-Message ("    log: {0}" -f $ci.LogFile) -Fore Red }
            # Keep the staging tree (it holds compile/compile.log with the per-file
            # ERROR/SKIP lines) so the failure can be diagnosed; it is small without
            # the source/rcode/zip, and a later clean run writes a fresh stamped dir.
            Write-Message ("    (staging kept for review: {0})" -f $staging) -Fore DarkGray
            $script:OnError = $true; return
        }
    }

    # ---- Dependency-aware r-code ship set -------------------------------------
    $rcodeSet = @()
    if ($Full -eq $true) {
        # ship every .r produced beside source under $srcRoot
        $rItems = Get-ChildItem -Path $srcRoot -Recurse -File -Filter *.r -ErrorAction SilentlyContinue
        $srcN = ($srcRoot -replace '\\','/').TrimEnd('/')
        foreach ($ri in $rItems) {
            $rel = ($ri.FullName -replace '\\','/')
            if ($rel.ToLower().StartsWith($srcN.ToLower() + '/')) { $rcodeSet += $rel.Substring($srcN.Length + 1) -replace '\.r$','' }
        }
        $rcodeSet = @($rcodeSet | Sort-Object)
    } elseif ($DryRun -ne $true) {
        $depMap = Get-PackageDependencyMap -XrefDir $ci.XrefDir -SrcRoot $srcRoot -AppSegment $appSeg
        if ($depMap.Units.Count -eq 0) {
            Write-Message "  Package: XREF scan produced no compile units; aborting (fail closed)." -Fore Red
            Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
            $script:OnError = $true; return
        }
        $rcodeSet = @(Get-PackageRcodeSet -DepMap $depMap -ChangedFiles $changed)
    }

    # ---- Assemble the bundle --------------------------------------------------
    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] would ship {0} changed source file(s) and {1} r-code unit(s):" -f $changed.Count, $rcodeSet.Count) -Fore DarkGray
        foreach ($f in $changed)  { Write-Message ("    source  {0}" -f $f) -Fore DarkGray }
        foreach ($u in $rcodeSet) { Write-Message ("    rcode   {0}.r" -f $u) -Fore DarkGray }
        foreach ($d in $dfFiles)  { Write-Message ("    df      {0}" -f (Split-Path $d -Leaf)) -Fore DarkGray }
        Write-Message ("  [DRYRUN] would write: {0}" -f $zipPath) -Fore DarkGray
        Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    $srcStage = Join-PathX $staging "source"
    $rStage   = Join-PathX $staging "rcode"
    $dfStage  = Join-PathX $staging "df"
    foreach ($d in @($srcStage, $rStage, $dfStage)) { $null = New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue }

    $changedManifest = New-Object System.Collections.Generic.List[object]
    foreach ($f in $changed) {
        $full = Join-PathX $srcRoot ($f -replace '/','\')
        $onDisk = Test-Path -Path $full -PathType Leaf
        $hash = ""; $bytes = 0
        if ($onDisk) {
            # ship only shippable source extensions into source/
            if ($f -match '\.(p|w|cls|i|t)$') {
                $dest = Join-PathX $srcStage ($f -replace '/','\')
                $null = New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force -ErrorAction SilentlyContinue
                Copy-Item -Path $full -Destination $dest -Force
            }
            $hash = (Get-FileHash -Path $full -Algorithm SHA256).Hash
            $bytes = (Get-Item -Path $full).Length
        }
        $revLines = if ($onDisk) { Get-PackageRevisionLines -FullPath $full -MarkerHits $(if ($markers -and $markers.MarkerText.ContainsKey($f)) { $markers.MarkerText[$f] } else { @() }) } else { @() }
        $changedManifest.Add([PSCustomObject]@{ path=$f; sha256=$hash; bytes=$bytes; onDisk=$onDisk; revisionHistory=@($revLines) })
    }

    $rcodeManifest = New-Object System.Collections.Generic.List[object]
    foreach ($u in $rcodeSet) {
        # OpenEdge COMPILE ... SAVE writes r-code as the source basename with the
        # source extension REPLACED by .r (foo.w -> foo.r), NOT appended (foo.w.r).
        # Dependency-mode units carry the source extension (dir/foo.w); -Full units
        # are already extensionless.  Strip any .p/.w/.cls/.t so both forms resolve
        # to the real <base>.r.
        $rBase = $u -replace '\.(p|w|cls|t)$',''
        $rFull = Join-PathX $srcRoot (($rBase -replace '/','\') + ".r")
        if (-not (Test-Path -Path $rFull -PathType Leaf)) {
            Write-Message ("  Package: expected r-code missing after clean compile: {0}.r - aborting (fail closed)." -f $rBase) -Fore Red
            Write-Message ("    (source unit: {0}; expected r-code beside source: {1})" -f $u, $rFull) -Fore Red
            # Keep staging for review (holds compile/compile.log + the change-set).
            Write-Message ("    (staging kept for review: {0})" -f $staging) -Fore DarkGray
            $script:OnError = $true; return
        }
        $dest = Join-PathX $rStage (($rBase -replace '/','\') + ".r")
        $null = New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force -ErrorAction SilentlyContinue
        Copy-Item -Path $rFull -Destination $dest -Force
        $rcodeManifest.Add([PSCustomObject]@{ path=($rBase + ".r"); sha256=(Get-FileHash -Path $rFull -Algorithm SHA256).Hash; bytes=(Get-Item -Path $rFull).Length })
    }

    $dfNames = @()
    foreach ($d in $dfFiles) {
        $leaf = Split-Path $d -Leaf
        Copy-Item -Path $d -Destination (Join-PathX $dfStage $leaf) -Force
        $dfNames += $leaf
    }

    # ---- Manifest -------------------------------------------------------------
    $gitCommits = @()
    if (-not [string]::IsNullOrWhiteSpace($FileList) -and [string]::IsNullOrWhiteSpace($Grep) -and [string]::IsNullOrWhiteSpace($FromCommit)) {
        $gitCommits = @("N/A (explicit file list)")
    } else {
        $gitCommits = @($csCommits)
        if (-not [string]::IsNullOrWhiteSpace($FileList)) { $gitCommits += "N/A (explicit file list)" }
    }
    $gitBranch = (& git -C $srcRoot rev-parse --abbrev-ref HEAD 2>&1 | Select-Object -First 1)

    # Build the manifest.  A [PSCustomObject]@{...} literal with nested
    # [PSCustomObject]/List values throws in Windows PowerShell 5.1, and casting an
    # [ordered] that holds those values can silently yield an EMPTY object (which is
    # why stamp/author/gitBranch and the JSON came out blank).  The reliable 5.1
    # pattern is to create a PSObject and Add-Member each property, preserving order.
    $markerNoGit = if ($markers) { @($markers.MarkerNoGit) } else { @() }
    $gitNoMarker = if ($markers) { @($markers.GitNoMarker) } else { @() }
    $builtStamp  = (Get-Date).ToString("o")
    $builtBy     = $env:USERNAME
    $gitBranchStr= "$gitBranch".Trim()
    $compiledAgainst = New-Object PSObject
    Add-Member -InputObject $compiledAgainst -NotePropertyName app    -NotePropertyValue $Item.App
    Add-Member -InputObject $compiledAgainst -NotePropertyName site   -NotePropertyValue $Item.Site
    Add-Member -InputObject $compiledAgainst -NotePropertyName env    -NotePropertyValue $Item.Env
    Add-Member -InputObject $compiledAgainst -NotePropertyName server -NotePropertyValue $Item.Server
    $markerDrift = New-Object PSObject
    Add-Member -InputObject $markerDrift -NotePropertyName markerNoGit -NotePropertyValue $markerNoGit
    Add-Member -InputObject $markerDrift -NotePropertyName gitNoMarker -NotePropertyValue $gitNoMarker
    $manifestObj = New-Object PSObject
    Add-Member -InputObject $manifestObj -NotePropertyName project         -NotePropertyValue $projTok
    Add-Member -InputObject $manifestObj -NotePropertyName stamp           -NotePropertyValue $builtStamp
    Add-Member -InputObject $manifestObj -NotePropertyName author          -NotePropertyValue $builtBy
    Add-Member -InputObject $manifestObj -NotePropertyName oeVersion       -NotePropertyValue $Item.OEVersion
    Add-Member -InputObject $manifestObj -NotePropertyName compiledAgainst -NotePropertyValue $compiledAgainst
    Add-Member -InputObject $manifestObj -NotePropertyName full            -NotePropertyValue ([bool]$Full)
    Add-Member -InputObject $manifestObj -NotePropertyName mode            -NotePropertyValue $(if ($Full -eq $true) { "full" } else { "changes" })
    Add-Member -InputObject $manifestObj -NotePropertyName gitBranch       -NotePropertyValue $gitBranchStr
    Add-Member -InputObject $manifestObj -NotePropertyName gitCommits      -NotePropertyValue @($gitCommits)
    Add-Member -InputObject $manifestObj -NotePropertyName deltaDf         -NotePropertyValue @($dfNames)
    Add-Member -InputObject $manifestObj -NotePropertyName changedSource   -NotePropertyValue @($changedManifest)
    Add-Member -InputObject $manifestObj -NotePropertyName rcode           -NotePropertyValue @($rcodeManifest)
    Add-Member -InputObject $manifestObj -NotePropertyName markerDrift     -NotePropertyValue $markerDrift
    Add-Member -InputObject $manifestObj -NotePropertyName deployNotes     -NotePropertyValue "Load any df/ deltas FIRST (DBA-run, in listed order), then r-code + source. deploy.ps1 is dry-run by default; use -Execute."
    Set-Content -Path (Join-PathX $staging "manifest.json") -Value ($manifestObj | ConvertTo-Json -Depth 8) -Encoding ascii

    # Human-readable manifest.txt
    $mt = New-Object System.Collections.Generic.List[string]
    $mt.Add("OEAdmin -Package manifest"); $mt.Add("=========================")
    $mt.Add("Project        : $projTok")
    $mt.Add("Built          : $builtStamp  by $builtBy")
    $mt.Add("Compiled on    : $($Item.App) / $($Item.Site) / $($Item.Env)  (OE $($Item.OEVersion), server $($Item.Server))")
    $mt.Add("Mode           : " + $(if ($Full -eq $true) { "FULL (all r-code)" } else { "changes (dependency-aware)" }))
    $mt.Add("Git branch     : $gitBranchStr")
    $mt.Add("Git commits    : " + (@($gitCommits) -join ', '))
    $mt.Add("Delta DFs      : " + $(if ($dfNames.Count) { ($dfNames -join ', ') } else { "(none)" }))
    $mt.Add("")
    $mt.Add("Changed source ($($changedManifest.Count)):")
    foreach ($c in $changedManifest) { $mt.Add(("  {0}  {1} bytes  sha256 {2}{3}" -f $c.path, $c.bytes, $c.sha256, $(if ($c.onDisk) { "" } else { "  [MISSING ON DISK]" }))) }
    $mt.Add("")
    $mt.Add("R-code shipped ($($rcodeManifest.Count)):")
    foreach ($r in $rcodeManifest) { $mt.Add(("  {0}  {1} bytes  sha256 {2}" -f $r.path, $r.bytes, $r.sha256)) }
    $mt.Add("")
    if ($markerNoGit.Count -or $gitNoMarker.Count) {
        $mt.Add("Marker drift (advisory):")
        foreach ($f in $markerNoGit) { $mt.Add("  marker-no-git : $f") }
        foreach ($f in $gitNoMarker) { $mt.Add("  git-no-marker : $f") }
        $mt.Add("")
    }
    $mt.Add("Deploy: $($manifestObj.deployNotes)")
    Set-Content -Path (Join-PathX $staging "manifest.txt") -Value $mt -Encoding ascii

    # ---- deploy.ps1 -----------------------------------------------------------
    $deployDefaultBackup = if (-not [string]::IsNullOrWhiteSpace($PackageBackupDir)) { $PackageBackupDir } else { $App1BackupDir }
    $deployScript = Get-PackageDeployScript -DefaultBackupDir $deployDefaultBackup
    Set-Content -Path (Join-PathX $staging "deploy.ps1") -Value $deployScript -Encoding ascii

    # ---- Zip ------------------------------------------------------------------
    try {
        if (Test-Path -Path $zipPath) { Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-PathX $staging '*') -DestinationPath $zipPath -Force -ErrorAction Stop
    } catch {
        Write-Message ("  Package: zip write failed: {0}  (staging left for inspection: {1})" -f $_.Exception.Message, $staging) -Fore Red
        $script:OnError = $true; return
    }

    Write-Message ("  Package built: {0}" -f $zipPath) -Fore Green
    Write-Message ("    changed source: {0}   r-code: {1}   delta DF: {2}" -f $changedManifest.Count, $rcodeManifest.Count, $dfNames.Count) -Fore DarkGray
    Write-Message ("    review file  : {0}" -f $reviewFile) -Fore DarkGray
    # Keep the zip, review files, and compile log; remove the bulky staging tree.
    Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
}

# The deploy.ps1 shipped inside each bundle.  Safe by default: dry-run preview
# unless -Execute; backs up each target before overwrite; -Rollback restores a
# prior backup set; delta-DF load is PRINTED for the DBA and awaited, never shelled.
function Get-PackageDeployScript {
    param($DefaultBackupDir)
    $backupDefault = ($DefaultBackupDir -replace "'", "''")
    return @"
<#
  deploy.ps1 - OEAdmin release-bundle deployer (ships inside the package).
  SAFE BY DEFAULT: with no -Execute it only PREVIEWS (changes nothing).
  Backs up every target file before overwriting; -Rollback restores a backup set.
  Delta .df loads are PRINTED for the DBA to run, then awaited - never shelled.
#>
param(
  [switch]`$Execute,                 # make changes; default = dry-run preview
  [switch]`$Rollback,                # restore a prior backup set (needs -Stamp)
  `$Stamp = "",                      # which backup set to roll back
  `$PackageBackupDir = '$backupDefault',   # backup root (CHANGE THIS if needed)
  `$TargetRoot = "",                 # production app root the app-rel paths map onto (REQUIRED)
  [switch]`$DfLoadConfirmed          # non-interactive: affirm the DF load succeeded
)

`$ErrorActionPreference = 'Stop'
`$here = Split-Path -Parent `$MyInvocation.MyCommand.Path
function Say(`$m, `$c = 'Gray') { Write-Host `$m -ForegroundColor `$c }

if ([string]::IsNullOrWhiteSpace(`$TargetRoot)) {
  Say "ERROR: -TargetRoot <production app root> is required (where source/ and rcode/ deploy to)." Red
  exit 1
}
`$manifestPath = Join-Path `$here 'manifest.json'
if (-not (Test-Path `$manifestPath)) { Say "ERROR: manifest.json not found beside deploy.ps1." Red; exit 1 }
`$manifestRaw = (Get-Content `$manifestPath -Raw)
if ([string]::IsNullOrWhiteSpace(`$manifestRaw)) {
  Say "ERROR: manifest.json is empty - this bundle was built by a defective packager; rebuild the package." Red
  exit 1
}
try { `$manifest = `$manifestRaw | ConvertFrom-Json } catch {
  Say ("ERROR: manifest.json is not valid JSON ({0}); rebuild the package." -f `$_.Exception.Message) Red
  exit 1
}
`$deployStamp = [DateTime]::Now.ToString('yyyy-MM-dd_HHmmss')

# ---- Rollback -------------------------------------------------------------
if (`$Rollback) {
  if ([string]::IsNullOrWhiteSpace(`$Stamp)) { Say "ERROR: -Rollback requires -Stamp <backup set>." Red; exit 1 }
  `$bset = Join-Path (Join-Path `$PackageBackupDir 'oeadmin-deploy') `$Stamp
  if (-not (Test-Path `$bset)) { Say "ERROR: backup set not found: `$bset" Red; exit 1 }
  Say "Rolling back from `$bset -> `$TargetRoot" Cyan
  Get-ChildItem -Path `$bset -Recurse -File | ForEach-Object {
    `$rel = `$_.FullName.Substring(`$bset.Length).TrimStart('\','/')
    `$tgt = Join-Path `$TargetRoot `$rel
    if (`$Execute) {
      `$null = New-Item -ItemType Directory -Path (Split-Path `$tgt -Parent) -Force
      Copy-Item -Path `$_.FullName -Destination `$tgt -Force
      Say "  restored `$rel" Green
    } else { Say "  [PREVIEW] would restore `$rel" DarkGray }
  }
  if (-not `$Execute) { Say "Preview only. Re-run with -Execute to restore." Yellow }
  exit 0
}

# ---- Delta DF step (FIRST) - printed for the DBA, then awaited ------------
`$dfs = @(`$manifest.deltaDf)
if (`$dfs.Count -gt 0) {
  Say "" ; Say "This release carries `$(`$dfs.Count) schema delta .df file(s). They MUST be loaded FIRST," Yellow
  Say "in this order, into the target database BEFORE the code is deployed:" Yellow
  foreach (`$d in `$dfs) {
    Say "   df\`$d" Yellow
    Say "     REM prodict/load_df.p takes an INPUT PARAMETER - RUN it from a driver (cannot use -param):" DarkGray
    Say "     REM   _loaddf.p :  RUN prodict/load_df.p (INPUT `"`$here\df\`$d`")." DarkGray
    Say "     REM   `"%DLC%\bin\_progres`" -db <targetdb> -ld <ld> -1 -p _loaddf.p   (driver reads the .df path from an env var, e.g. DF_FILE=`$here\df\`$d)" DarkGray
  }
  if (`$Execute) {
    `$ok = if (`$DfLoadConfirmed) { `$true } elseif ([Environment]::UserInteractive) {
      (Read-Host "Have ALL delta DF(s) above been loaded successfully into the target DB? (y/N)") -match '^(y|yes)$'
    } else { `$false }
    if (-not `$ok) { Say "DF load not confirmed (pass -DfLoadConfirmed non-interactively, or answer y). Aborting before any code change." Red; exit 1 }
  } else {
    Say "  [PREVIEW] -Execute would await confirmation the DF(s) are loaded before deploying code." DarkGray
  }
}

# ---- Code swap (source\ + rcode\), backup-before-overwrite ----------------
`$backupSet = Join-Path (Join-Path `$PackageBackupDir 'oeadmin-deploy') `$deployStamp
`$changed = 0; `$errors = 0
foreach (`$sub in @('source','rcode')) {
  `$base = Join-Path `$here `$sub
  if (-not (Test-Path `$base)) { continue }
  Get-ChildItem -Path `$base -Recurse -File | ForEach-Object {
    `$rel = `$_.FullName.Substring(`$base.Length).TrimStart('\','/')
    `$tgt = Join-Path `$TargetRoot `$rel
    if (`$Execute) {
      if (Test-Path `$tgt) {
        `$bkp = Join-Path `$backupSet `$rel
        `$null = New-Item -ItemType Directory -Path (Split-Path `$bkp -Parent) -Force
        Copy-Item -Path `$tgt -Destination `$bkp -Force
        if (-not (Test-Path `$bkp) -or (Get-Item `$bkp).Length -ne (Get-Item `$tgt).Length) {
          Say "  ERROR: backup verify failed for `$rel - NOT overwriting." Red; `$errors++; return
        }
      }
      `$null = New-Item -ItemType Directory -Path (Split-Path `$tgt -Parent) -Force
      Copy-Item -Path `$_.FullName -Destination `$tgt -Force
      Say "  deployed `$sub\`$rel" Green; `$changed++
    } else {
      `$act = if (Test-Path `$tgt) { 'replace (backup first)' } else { 'create' }
      Say "  [PREVIEW] would `$act : `$rel  -> `$tgt" DarkGray
    }
  }
}

if (`$Execute) {
  Say "" ; Say "Deployed `$changed file(s). Backup set: `$backupSet" Green
  if (`$errors -gt 0) { Say "`$errors file(s) skipped due to backup-verify failure - review above." Red }
  Say "Rollback with:  .\deploy.ps1 -Rollback -Stamp `$deployStamp -TargetRoot `"`$TargetRoot`" -Execute" Cyan
} else {
  Say "" ; Say "Preview only. Re-run with -Execute (and -TargetRoot) to deploy." Yellow
}
"@
}

## ============================================================================
## TEST  (-Test : run the ABLUnit suite headlessly via ABLUnitCore.p)
## ============================================================================
# -Test is a -Batch-style launch whose "-p" program is the Progress ABLUnit driver
# ABLUnitCore.p, resolved off the ENVIRONMENT's INI PROPATH (the ablunit framework
# - OpenEdge.ABLUnit.* + ABLUnitCore.p - must be on that PROPATH; add it to the INI
# where needed; OEAdmin does not ship it).  The test spec travels in a generated
# CONFIG JSON (CFG=<file>) - the JSON pins the results output location and quitOnEnd
# and sidesteps the space-splitting the raw "-param <spec>" form suffers:
#   <exe> -ininame <ini> -pf <pf> -p ABLUnitCore.p -param "CFG=<cfg.json>" -b
# ABLUnitCore QUITs with no OS exit code, so the authoritative pass/fail signal is
# the JUnit-style results.xml it writes; OEAdmin parses it, prints a loud summary,
# and sets exit 2004 on any failure/error (or a missing results.xml, which usually
# means the framework is not on PROPATH).  12+ ONLY (the framework is 12-era).
function Do-Test {
    param($Item)

    # 12+ only: the ABLUnit framework (OpenEdge.ABLUnit.*) is 12-era OOABL.
    $major = 0
    if ($Item.OEVersion -match '^(\d+)') { $major = [int]$Matches[1] }
    if ($major -lt 12) {
        Write-Message ("  Test: -Test requires OpenEdge 12+; target {0} is {1}. Skipped." -f $Item.Name, $Item.OEVersion) -Fore Red
        $script:OnError = $true; return
    }

    $L = Resolve-ClientLaunch -Item $Item -Tag "Test"
    if (-not $L) { return }

    # Source root (worktree or installed tree) - same resolution as -Compile.
    $srcRoot = Get-CompileSourceRoot -Item $Item
    if (-not $srcRoot) {
        Write-Message ("  Test: could not resolve a source root for {0}" -f $Item.Name) -Fore Red
        $script:OnError = $true; return
    }

    # Resolve the test spec.  Explicit -TestSpec wins (a class/proc, Foo.cls#Method,
    # a comma-list, or a folder).  Otherwise default to a "tests" folder under the
    # source root (optionally narrowed by -TestDir).  Fail if neither exists.
    $spec = ""
    if (-not [string]::IsNullOrWhiteSpace($TestSpec)) {
        $spec = $TestSpec.Trim()
    } else {
        $testRoot = if (-not [string]::IsNullOrWhiteSpace($TestDir)) {
            Join-PathX $srcRoot ($TestDir -replace '/','\')
        } else {
            Join-PathX $srcRoot "tests"
        }
        if ($DryRun -ne $true -and -not (Test-Path -Path $testRoot)) {
            Write-Message ("  Test: no test spec given and default test folder not found: {0}" -f $testRoot) -Fore Red
            Write-Message  "        Pass -TestSpec <class|proc|folder|Foo.cls#Method> or create a 'tests' folder (or use -TestDir)." -Fore Red
            $script:OnError = $true; return
        }
        $spec = $testRoot
    }

    # Per-run output tree under <sourceroot>/x/<stamp>/test/ (or -TestResults).
    $stamp      = [DateTime]::Now.ToString("yyyy-MM-dd_HHmmss")
    $resultsDir = if (-not [string]::IsNullOrWhiteSpace($TestResults)) { $TestResults } `
                  else { Join-PathX (Join-PathX (Join-PathX $srcRoot "x") $stamp) "test" }
    $resultsXml = Join-PathX $resultsDir "results.xml"
    # Transient CFG json consumed by ABLUnitCore.p (CFG=<file>).
    $cfgFile    = Join-PathX $PSScriptRoot ("abltest_{0}.cfg.json" -f $stamp)

    # Build the ABLUnit config JSON.  "tests" is an array of {test:<resource>}
    # (optionally {cases:[...]} for a Foo.cls#Method form); options pin the xml
    # output location + quitOnEnd so the batch session exits when done.
    $testsJson = @()
    foreach ($one in ($spec -split ',')) {
        $one = $one.Trim()
        if ([string]::IsNullOrWhiteSpace($one)) { continue }
        if ($one -match '^(.*)#(.+)$') {
            $testsJson += [PSCustomObject]@{ test = $Matches[1]; cases = @($Matches[2]) }
        } else {
            $testsJson += [PSCustomObject]@{ test = $one }
        }
    }
    if ($testsJson.Count -eq 0) {
        Write-Message "  Test: empty test spec after parsing." -Fore Red
        $script:OnError = $true; return
    }
    $cfgObj = [PSCustomObject]@{
        options = [PSCustomObject]@{
            output    = [PSCustomObject]@{ location = $resultsDir; format = "xml"; fileName = "results" }
            quitOnEnd = $true
            writeLog  = $false
            throwError= $false
        }
        tests = @($testsJson)
    }

    # Driver stdout/err grouped under <script dir>/batch/ABLUnitCore/.
    $pgmDir  = Join-PathX (Join-PathX $PSScriptRoot "batch") "ABLUnitCore"
    if ($DryRun -ne $true) { $null = New-Item -ItemType Directory -Path $pgmDir -Force -ErrorAction SilentlyContinue }
    $outFile = Join-PathX $pgmDir ("ABLUnitCore_{0}.out" -f $stamp)
    $errFile = Join-PathX $pgmDir ("ABLUnitCore_{0}.err" -f $stamp)

    $cargs = @("-ininame", $L.Ini, "-pf", $L.Pf)
    $dargs = @("-ininame", (Split-Path $L.Ini -Leaf), "-pf", (Split-Path $L.Pf -Leaf))
    foreach ($ap in $L.AddPfs) { $cargs += @("-pf", $ap); $dargs += @("-pf", (Split-Path $ap -Leaf)) }
    $cargs += @("-p", "ABLUnitCore.p", "-param", ("CFG=" + $cfgFile), "-b")
    $dargs += @("-p", "ABLUnitCore.p", "-param", ("CFG=" + (Split-Path $cfgFile -Leaf)), "-b")

    $display = "$($L.ExeName) " + ($dargs -join ' ')
    Write-Message ("Test: {0,-40} {1}" -f (& $Label $Item), $L.ExeName) -Fore Cyan
    Write-Message ("  source root : {0}" -f $srcRoot) -Fore DarkGray
    Write-Message ("  test spec   : {0}" -f $spec) -Fore DarkGray
    Write-Message ("  results     : {0}" -f $resultsXml) -Fore DarkGray

    if ($DryRun -eq $true) {
        Write-Message ("  [DRYRUN] {0}  1> {1} 2> {2}" -f $display, (Split-Path $outFile -Leaf), (Split-Path $errFile -Leaf)) -Fore DarkGray
        Write-Message  "  [DRYRUN] CFG json contents:" -Fore DarkGray
        foreach ($cl in (($cfgObj | ConvertTo-Json -Depth 6) -split "`n")) { Write-Message ("    " + $cl.TrimEnd()) -Fore DarkGray }
        return
    }

    try {
        $null = New-Item -ItemType Directory -Path $resultsDir -Force -ErrorAction Stop
        Set-Content -Path $cfgFile -Value ($cfgObj | ConvertTo-Json -Depth 6) -Encoding ascii -ErrorAction Stop
    } catch {
        Write-Message ("  Test: could not create results dir / CFG file: {0}" -f $_.Exception.Message) -Fore Red
        $script:OnError = $true; return
    }

    # Remove any stale results.xml so a crash can't leave a prior pass showing.
    Remove-Item -Path $resultsXml -Force -ErrorAction SilentlyContinue

    $workDir = Get-WorkspaceWorkDir -App $Item.App
    Write-Message ("  {0}" -f $display) -Fore DarkGray
    if ($workDir) { Write-Message ("  working dir: {0}" -f $workDir) -Fore DarkGray }

    $prev = $env:DLC; $env:DLC = $Item.DLC
    try {
        $spArgs = @{ FilePath=$L.Exe; ArgumentList=$cargs; NoNewWindow=$true; Wait=$true; PassThru=$true;
                     RedirectStandardOutput=$outFile; RedirectStandardError=$errFile }
        if ($workDir) { $spArgs['WorkingDirectory'] = $workDir }
        $p = Start-Process @spArgs

        # ABLUnitCore QUITs with no meaningful OS code; results.xml is authoritative.
        if (-not (Test-Path -Path $resultsXml -PathType Leaf)) {
            Write-Message  "  Test: no results.xml produced - the run did not complete." -Fore Red
            Write-Message  "        Likely the ABLUnit framework (ABLUnitCore.p / OpenEdge.ABLUnit.*) is not on this environment's INI PROPATH." -Fore Red
            Write-Message ("        driver summary: {0}" -f $outFile) -Fore Red
            Write-Message ("        driver errors : {0}" -f $errFile) -Fore Red
            $script:OnTestError = $true
            return
        }

        # Parse the JUnit-style results.xml: sum tests/failures/errors across suites.
        $tests = 0; $failures = 0; $errors = 0; $skipped = 0
        try {
            [xml]$rx = Get-Content -Path $resultsXml -Raw -ErrorAction Stop
            # <testsuites> wrapping <testsuite>, or a single <testsuite>.
            $suites = @()
            if ($rx.testsuites -and $rx.testsuites.testsuite) { $suites = @($rx.testsuites.testsuite) }
            elseif ($rx.testsuite) { $suites = @($rx.testsuite) }
            foreach ($s in $suites) {
                if ($s.tests)    { $tests    += [int]$s.tests }
                if ($s.failures) { $failures += [int]$s.failures }
                if ($s.errors)   { $errors   += [int]$s.errors }
                if ($s.skipped)  { $skipped  += [int]$s.skipped }
            }
        } catch {
            Write-Message ("  Test: could not parse results.xml ({0})." -f $_.Exception.Message) -Fore Red
            Write-Message ("        results: {0}" -f $resultsXml) -Fore Red
            $script:OnTestError = $true
            return
        }

        $passed = $tests - $failures - $errors - $skipped
        if ($failures -eq 0 -and $errors -eq 0) {
            Write-Message ("  Tests PASSED: {0} run, {1} passed{2}." -f $tests, $passed, $(if ($skipped) { ", $skipped skipped" } else { "" })) -Fore Green
            Write-Message ("    results: {0}" -f $resultsXml) -Fore DarkGray
        } else {
            Write-Message ("  TEST FAILURES: {0} run, {1} failed, {2} error(s){3}.  Review:" -f $tests, $failures, $errors, $(if ($skipped) { ", $skipped skipped" } else { "" })) -Fore Red
            Write-Message ("    results: {0}" -f $resultsXml) -Fore Red
            Write-Message ("    driver : {0}" -f $outFile) -Fore Red
            $script:OnTestError = $true
        }
    } catch {
        Write-Message ("  ERROR running tests: {0}" -f $_.Exception.Message) -Fore Red
        $script:OnError = $true
    } finally {
        $env:DLC = $prev
        Remove-Item -Path $cfgFile -Force -ErrorAction SilentlyContinue
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
        [pscustomobject]@{ Label="Status     - report instance status";               Value="Status" }
        [pscustomobject]@{ Label="Client     - launch Progress GUI client";           Value="Client" }
        [pscustomobject]@{ Label="Batch      - run a Progress program in batch";      Value="Batch" }
        [pscustomobject]@{ Label="Git        - local repo/worktree maintenance";      Value="Git" }
        [pscustomobject]@{ Label="Compile    - compile app source (OECompiler.p)";    Value="Compile" }
        [pscustomobject]@{ Label="Test       - run the ABLUnit suite (12+)";          Value="Test" }
        [pscustomobject]@{ Label="Package    - build a release bundle (source+rcode+manifest)"; Value="Package" }
        [pscustomobject]@{ Label="Start      - start instances";                      Value="Start" }
        [pscustomobject]@{ Label="Stop       - stop instances";                       Value="Stop" }
        [pscustomobject]@{ Label="Restart    - stop then start instances";            Value="Restart" }
        [pscustomobject]@{ Label="Backup     - probkup online (PROD servers)";        Value="Backup" }
        [pscustomobject]@{ Label="Restore    - prorest prod backup (DEV servers)";    Value="Restore" }
        [pscustomobject]@{ Label="CopyBackup - split+push prod backups -> dev (run on PROD)"; Value="CopyBackup" }
    )
    if ($null -eq $action) { return $false }

    # The menu owns the action set: clear the default -Status, then turn on the
    # one the operator chose.
    $script:Status=$false; $script:Start=$false; $script:Stop=$false
    $script:Restart=$false; $script:Backup=$false; $script:Restore=$false
    $script:CopyBackup=$false; $script:Client=$false; $script:Batch=$false
    $script:Compile=$false; $script:FileSpec="*.p *.w *.cls *.t"; $script:Dir=""
    $script:Incremental=$false; $script:Listing=$false; $script:Xref=$false
    $script:XrefXml=$false; $script:Installed=$false
    $script:Exclude=@(); $script:ExcludeFile=""
    $script:Package=$false; $script:Project=""; $script:Grep=""
    $script:FromCommit=""; $script:ToCommit=""; $script:FileList=""
    $script:Accept=$false; $script:DeltaDf=@(); $script:DfLoadedConfirmed=$false
    $script:Full=$false; $script:PackageBackupDir=""
    $script:Test=$false; $script:TestSpec=""; $script:TestDir=""; $script:TestResults=""
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

        "Compile" {
            $script:Compile = $true
            $app = & $askApp $false; if ($null -eq $app) { return $false }
            $script:App = $app
            if (-not (& $askClientEnv $app)) { return $false }

            # Source: a git working copy (default) or the installed code.
            $wcs = @(Get-WorkingCopies -App $app)
            if ($wcs.Count -gt 0) {
                $wsOpts = @()
                foreach ($w in $wcs) { $wsOpts += [pscustomobject]@{ Label=("{0}  [{1}]" -f $w.Token, $w.Repo); Value=$w.Token; Valid=$true } }
                $wsOpts += [pscustomobject]@{ Label="(installed code - -Installed)"; Value="__INSTALLED__"; Valid=$true }
                $wsPick = Read-MenuChoice -Title "Compile which source?" -Options $wsOpts
                if ($null -eq $wsPick) { return $false }
                if ($wsPick -eq "__INSTALLED__") {
                    $script:Installed = $true
                } else {
                    $script:Workspace = $wsPick
                    $script:UpdateRepos = Read-YesNo -Prompt "Fast-forward (pull) this working copy before compiling?" -Default:$false
                }
            } else {
                Write-Host "  No worktrees discovered - compiling the installed code." -ForegroundColor Yellow
                $script:Installed = $true
            }

            $fsIn = Read-Host "  File spec(s) to compile [default: *.p *.w *.cls *.t]"
            if (-not [string]::IsNullOrWhiteSpace($fsIn)) { $script:FileSpec = $fsIn.Trim() }

            $dirIn = Read-Host "  Restrict to sub-directory (relative, Enter for all)"
            if (-not [string]::IsNullOrWhiteSpace($dirIn)) { $script:Dir = $dirIn.Trim() }

            $script:Incremental = Read-YesNo -Prompt "Incremental (only missing/newer-than-.r)?" -Default:$false
            $script:Listing = Read-YesNo -Prompt "Generate per-file LISTING output?" -Default:$false
            $script:Xref    = Read-YesNo -Prompt "Generate per-file XREF output?" -Default:$false
            if ($script:Xref) {
                $script:XrefXml = Read-YesNo -Prompt "  XREF in XML format?" -Default:$false
            }

            # Exclude patterns (optional): offer the standing compile-excludes.txt
            # if present, plus ad-hoc patterns.
            $defExcl = Join-PathX $PSScriptRoot "compile-excludes.txt"
            if (Test-Path -Path $defExcl -PathType Leaf) {
                if (Read-YesNo -Prompt "Use the standing exclude file (compile-excludes.txt)?" -Default:$true) {
                    $script:ExcludeFile = "compile-excludes.txt"
                }
            }
            $exIn = Read-Host "  Extra exclude pattern(s), comma-separated (Enter for none)"
            if (-not [string]::IsNullOrWhiteSpace($exIn)) { $script:Exclude = @($exIn.Trim()) }

            & $askIniPfOverride
        }

        "Package" {
            $script:Package = $true
            # App + required Site/Env (same as Compile/Client/Batch).
            $app = & $askApp $false; if ($null -eq $app) { return $false }
            $script:App = $app
            if (-not (& $askClientEnv $app)) { return $false }

            # Source: a git working copy (default) or the installed code.
            $wcs = @(Get-WorkingCopies -App $app)
            if ($wcs.Count -gt 0) {
                $wsOpts = @()
                foreach ($w in $wcs) { $wsOpts += [pscustomobject]@{ Label=("{0}  [{1}]" -f $w.Token, $w.Repo); Value=$w.Token; Valid=$true } }
                $wsOpts += [pscustomobject]@{ Label="(installed code - -Installed)"; Value="__INSTALLED__"; Valid=$true }
                $wsPick = Read-MenuChoice -Title "Package which source?" -Options $wsOpts
                if ($null -eq $wsPick) { return $false }
                if ($wsPick -eq "__INSTALLED__") {
                    $script:Installed = $true
                } else {
                    $script:Workspace = $wsPick
                    $script:UpdateRepos = Read-YesNo -Prompt "Fast-forward (pull) this working copy before packaging?" -Default:$false
                }
            } else {
                Write-Host "  No worktrees discovered - packaging the installed code." -ForegroundColor Yellow
                $script:Installed = $true
            }

            # -Project is REQUIRED (keys the review file + names the bundle).
            do { $pjIn = (Read-Host "  Project / ticket name (required)").Trim() } while ([string]::IsNullOrWhiteSpace($pjIn))
            $script:Project = $pjIn

            # -Full?  If yes, change-set inputs are optional.
            $script:Full = Read-YesNo -Prompt "Full package (recompile + ship EVERYTHING; DB/CRC-change case)?" -Default:$false

            # Change-set inputs (at least one required unless -Full).
            if (-not $script:Full) {
                do {
                    $grepIn = (Read-Host "  Change-set: git --grep tag (Enter to use a commit range / file list instead)").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($grepIn)) { $script:Grep = $grepIn }
                    $fromIn = (Read-Host "  Change-set: -FromCommit (Enter to skip)").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($fromIn)) {
                        $script:FromCommit = $fromIn
                        do { $toIn = (Read-Host "  Change-set: -ToCommit (required with -FromCommit)").Trim() } while ([string]::IsNullOrWhiteSpace($toIn))
                        $script:ToCommit = $toIn
                    }
                    $flIn = (Read-Host "  Change-set: -FileList path (Enter to skip)").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($flIn)) { $script:FileList = $flIn }
                    $haveOne = (-not [string]::IsNullOrWhiteSpace($script:Grep)) -or (-not [string]::IsNullOrWhiteSpace($script:FromCommit)) -or (-not [string]::IsNullOrWhiteSpace($script:FileList))
                    if (-not $haveOne) { Write-Host "  At least one change-set input is required (or choose Full)." -ForegroundColor Yellow }
                } while (-not $haveOne)
            }

            # Delta DFs (optional) + the SEPARATE DF-loaded confirmation.
            $dfIn = (Read-Host "  Delta .df file(s) to carry, comma-separated (Enter for none)").Trim()
            if (-not [string]::IsNullOrWhiteSpace($dfIn)) {
                $script:DeltaDf = @($dfIn)
                $script:DfLoadedConfirmed = Read-YesNo -Prompt "  Confirm these delta DF(s) are ALREADY LOADED into the compile DB (required to trust the r-code CRC)?" -Default:$false
            }

            & $askIniPfOverride

            # Two-pass gate: resolve-and-review, or accept-and-build now.
            Write-Host ""
            Write-Host "  -Package runs in two passes: RESOLVE writes a change-set file for you to review," -ForegroundColor Cyan
            Write-Host "  then ACCEPT (re-checks it matches) compiles fresh and builds the bundle." -ForegroundColor Cyan
            $script:Accept = Read-YesNo -Prompt "Accept and BUILD now? (No = resolve + review only)" -Default:$false
        }

        "Test" {
            $script:Test = $true
            # App + required Site/Env (same as Compile/Client/Batch).  12+ only, but
            # the version gate is enforced per-target in Do-Test, not here.
            $app = & $askApp $false; if ($null -eq $app) { return $false }
            $script:App = $app
            if (-not (& $askClientEnv $app)) { return $false }

            # Source: a git working copy (default) or the installed code.
            $wcs = @(Get-WorkingCopies -App $app)
            if ($wcs.Count -gt 0) {
                $wsOpts = @()
                foreach ($w in $wcs) { $wsOpts += [pscustomobject]@{ Label=("{0}  [{1}]" -f $w.Token, $w.Repo); Value=$w.Token; Valid=$true } }
                $wsOpts += [pscustomobject]@{ Label="(installed code - -Installed)"; Value="__INSTALLED__"; Valid=$true }
                $wsPick = Read-MenuChoice -Title "Test which source?" -Options $wsOpts
                if ($null -eq $wsPick) { return $false }
                if ($wsPick -eq "__INSTALLED__") {
                    $script:Installed = $true
                } else {
                    $script:Workspace = $wsPick
                    $script:UpdateRepos = Read-YesNo -Prompt "Fast-forward (pull) this working copy before testing?" -Default:$false
                }
            } else {
                Write-Host "  No worktrees discovered - testing the installed code." -ForegroundColor Yellow
                $script:Installed = $true
            }

            # Test spec: a class/proc/folder/Foo.cls#Method, or Enter for the
            # default "tests" folder under the source root.
            $tsIn = (Read-Host "  Test spec - class/proc, Foo.cls#Method, comma-list, or folder (Enter = 'tests' folder)").Trim()
            if (-not [string]::IsNullOrWhiteSpace($tsIn)) { $script:TestSpec = $tsIn }
            else {
                $tdIn = (Read-Host "  Restrict the default 'tests' folder to sub-directory (Enter for all)").Trim()
                if (-not [string]::IsNullOrWhiteSpace($tdIn)) { $script:TestDir = $tdIn }
            }
            $trIn = (Read-Host "  Results directory (Enter = <sourceroot>/x/<stamp>/test)").Trim()
            if (-not [string]::IsNullOrWhiteSpace($trIn)) { $script:TestResults = $trIn }

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
    if ($script:Compile -eq $true) {
        if (-not [string]::IsNullOrWhiteSpace($script:FileSpec) -and $script:FileSpec -ne "*.p *.w *.cls *.t") { $parts += "-FileSpec `"$($script:FileSpec)`"" }
        if (-not [string]::IsNullOrWhiteSpace($script:Dir)) { $parts += "-Dir `"$($script:Dir)`"" }
        if ($script:Incremental -eq $true) { $parts += "-Incremental" }
        if ($script:Listing -eq $true)     { $parts += "-Listing" }
        if ($script:Xref -eq $true)        { $parts += "-Xref" }
        if ($script:XrefXml -eq $true)     { $parts += "-XrefXml" }
        if ($script:Installed -eq $true)   { $parts += "-Installed" }
        if (@($script:Exclude).Count -gt 0) { $parts += "-Exclude `"$(@($script:Exclude) -join ',')`"" }
        if (-not [string]::IsNullOrWhiteSpace($script:ExcludeFile)) { $parts += "-ExcludeFile `"$($script:ExcludeFile)`"" }
    }
    if ($script:Package -eq $true) {
        if (-not [string]::IsNullOrWhiteSpace($script:Project))    { $parts += "-Project `"$($script:Project)`"" }
        if (-not [string]::IsNullOrWhiteSpace($script:Grep))       { $parts += "-Grep `"$($script:Grep)`"" }
        if (-not [string]::IsNullOrWhiteSpace($script:FromCommit)) { $parts += "-FromCommit $($script:FromCommit)" }
        if (-not [string]::IsNullOrWhiteSpace($script:ToCommit))   { $parts += "-ToCommit $($script:ToCommit)" }
        if (-not [string]::IsNullOrWhiteSpace($script:FileList))   { $parts += "-FileList `"$($script:FileList)`"" }
        if (@($script:DeltaDf).Count -gt 0) { $parts += "-DeltaDf `"$(@($script:DeltaDf) -join ',')`"" }
        if ($script:DfLoadedConfirmed -eq $true) { $parts += "-DfLoadedConfirmed" }
        if ($script:Full -eq $true)              { $parts += "-Full" }
        if ($script:Accept -eq $true)            { $parts += "-Accept" }
        if (-not [string]::IsNullOrWhiteSpace($script:PackageBackupDir)) { $parts += "-PackageBackupDir `"$($script:PackageBackupDir)`"" }
        if ($script:Installed -eq $true)   { $parts += "-Installed" }
    }
    if ($script:Test -eq $true) {
        if (-not [string]::IsNullOrWhiteSpace($script:TestSpec))    { $parts += "-TestSpec `"$($script:TestSpec)`"" }
        if (-not [string]::IsNullOrWhiteSpace($script:TestDir))     { $parts += "-TestDir `"$($script:TestDir)`"" }
        if (-not [string]::IsNullOrWhiteSpace($script:TestResults)) { $parts += "-TestResults `"$($script:TestResults)`"" }
        if ($script:Installed -eq $true)   { $parts += "-Installed" }
    }
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

# Resolve the -Server scope BEFORE building the inventory, so -Remote reads ONLY
# the targeted server(s) instead of fanning out to every server.  With -Remote and
# no explicit -Server, target ALL servers; an explicit -Server is always honored.
if ($Remote -eq $true -and -not $PSBoundParameters.ContainsKey('Server')) {
    $Server = "All"
    Write-Message "Remote: no -Server given; targeting ALL servers." -Fore Blue
}

# Build the live inventory ONCE, up front.  The menu (below) needs it to know
# which App/Site/Env combinations actually exist on this machine so it can gray
# out (red) the ones that don't; the normal dispatch reuses the same inventory.
# Build-Inventory honors -Server (and -App) so -Remote only touches what it needs.
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

# Resolve the DEFAULT action.  -Status defaults to $true so a bare run reports
# status, but it must NOT tag along when the operator chose another primary
# action: selecting -Compile (or -Package / -Start / ... ) should run ONLY that,
# not also print a STATUS report.  So unless -Status was named EXPLICITLY, turn
# it off whenever any other primary action is set.  (The -Menu flow already sets
# exactly one action, so this is a no-op there; this covers the CLI.)
if (-not $PSBoundParameters.ContainsKey('Status')) {
    $otherAction = $Start -or $Stop -or $Restart -or $Backup -or $Restore -or
                   $CopyBackup -or $Client -or $Batch -or $Compile -or $Package -or $Test -or $Git
    if ($otherAction) { $Status = $false }
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
Write-Message "OEVersion / Component:$(if ($OEVersion -eq 'Matrix') { 'Matrix (each instance''s own version)' } else { $OEVersion }) / $Component" -Fore Blue
Write-Message "Actions:              Status=$Status Start=$Start Stop=$Stop Restart=$Restart" -Fore Blue
Write-Message "Backup actions:       Backup=$Backup Restore=$Restore CopyBackup=$CopyBackup" -Fore Blue
Write-Message "Client action:        Client=$Client Run=$Run Ini='$Ini' Pf='$Pf'" -Fore Blue
Write-Message "Batch action:         Batch=$Batch Pgm='$Pgm'" -Fore Blue
Write-Message "Compile action:       Compile=$Compile FileSpec='$FileSpec' Dir='$Dir' Incremental=$Incremental Listing=$Listing Xref=$Xref XrefXml=$XrefXml Installed=$Installed" -Fore Blue
Write-Message "Compile excludes:     Exclude='$(@($Exclude) -join ',')' ExcludeFile='$ExcludeFile'" -Fore Blue
Write-Message "Package action:       Package=$Package Project='$Project' Accept=$Accept Full=$Full DfLoadedConfirmed=$DfLoadedConfirmed" -Fore Blue
Write-Message "Package change-set:   Grep='$Grep' FromCommit='$FromCommit' ToCommit='$ToCommit' FileList='$FileList' DeltaDf='$(@($DeltaDf) -join ',')'" -Fore Blue
Write-Message "Test action:          Test=$Test TestSpec='$TestSpec' TestDir='$TestDir' TestResults='$TestResults'" -Fore Blue
Write-Message "Checks:               CheckAdminServer=$CheckAdminServer CheckPort=$CheckPort CheckLogErrors=$CheckLogErrors RestartOnError=$RestartOnError" -Fore Blue
Write-Message "SettingsBackup:       SettingsBackup=$SettingsBackup ForceBackup=$ForceBackup" -Fore Blue
Write-Message "DryRun / Menu:        DryRun=$DryRun Menu=$Menu" -Fore Blue
Write-Message "Remote:               Remote=$Remote" -Fore Blue

# Filter the (already-built) inventory to the requested targets.  (The -Server
# scope was resolved before Build-Inventory so -Remote only read the right boxes.)
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
            Write-Message ("Broker port {0,-22} {1,-50} {2}" -f $portLabel, (& $Label $t), $msg) -Fore $fore
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

# COMPILE - headless Application Compiler run (OECompiler.p) for one environment.
# Same target rules and launch machinery as -Batch (the INI/PF decide PROPATH and
# DB connections; the -p program is the bundled compiler driver, not -Pgm).  Source
# is the -Workspace worktree by default or the installed tree with -Installed.
if ($Compile -eq $true) {
    Write-Section "COMPILE (OECompiler.p via prowin/prowin32/_progres -b)"
    # -UpdateRepos with a -Workspace: fast-forward the chosen working copy first.
    if ($UpdateRepos -eq $true -and -not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
        if ($wc) { Invoke-UpdateRepos -App $wc.App -OnlyRepo $wc.Repo -OnlyToken $wc.Token }
    }

    $pt = if (Test-ClientTargets -Tag "Compile") {
        @($Targets | Where-Object { $_.Component -eq "Database" })
    } else { @() }

    if ($pt.Count -eq 0) {
        Write-Message "  No valid target selected for -Compile (App1: -Site S1|S2 + -Env Dev|Test|SBox; App2: -Env Dev|Test|SBox; or pass -Ini and -Pf explicitly, or use -Remote)." -Fore Yellow
    }
    # One compile per environment, not per database (exe/ini/pf resolve from
    # Server/App/Env/Site + DLC, so multiple dbs in an env would recompile the
    # same source tree repeatedly).
    $pt = @($pt | Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.Server, $_.App, $_.Env, $_.Site, $_.DLC } |
                  ForEach-Object { $_.Group[0] })
    foreach ($t in $pt) { if (Test-CanAct -Item $t) { Do-Compile -Item $t } }
}

# PACKAGE - build a release bundle (changed source + dependency-aware r-code +
# manifest + deploy.ps1) for one environment.  Same target rules / launch
# machinery as -Compile (-Site AND -Env REQUIRED; r-code CRC tied to the schema).
# LOCAL build only (-Remote refused).  Two-pass resolve/accept gate inside Do-Package.
if ($Package -eq $true) {
    Write-Section "PACKAGE (release bundle)"
    # -UpdateRepos with a -Workspace: fast-forward the chosen working copy first.
    if ($UpdateRepos -eq $true -and -not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
        if ($wc) { Invoke-UpdateRepos -App $wc.App -OnlyRepo $wc.Repo -OnlyToken $wc.Token }
    }

    # Same environment selection as -Compile.  -Site and -Env are REQUIRED because
    # the compiled r-code CRC is tied to the schema.
    $pkgt = if (Test-ClientTargets -Tag "Package") {
        @($Targets | Where-Object { $_.Component -eq "Database" })
    } else { @() }

    if ($pkgt.Count -eq 0) {
        Write-Message "  No valid target selected for -Package (App1: -Site S1|S2 + -Env Dev|Test|SBox; App2: -Env Dev|Test|SBox; or pass -Ini and -Pf explicitly). -Site AND -Env are REQUIRED." -Fore Yellow
    }
    # One package per environment (exe/ini/pf resolve per env; see -Compile note).
    $pkgt = @($pkgt | Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.Server, $_.App, $_.Env, $_.Site, $_.DLC } |
                      ForEach-Object { $_.Group[0] })
    foreach ($t in $pkgt) { if (Test-CanAct -Item $t) { Do-Package -Item $t } }
}

# TEST - run the ABLUnit suite headlessly (ABLUnitCore.p via CFG json) for one
# environment.  Same target rules / launch machinery as -Compile/-Batch.  12+
# ONLY (the framework is 12-era).  Test failures set OnTestError (exit 2004).
if ($Test -eq $true) {
    Write-Section "TEST (ABLUnit via ABLUnitCore.p -b)"
    # -UpdateRepos with a -Workspace: fast-forward the chosen working copy first.
    if ($UpdateRepos -eq $true -and -not [string]::IsNullOrWhiteSpace($Workspace)) {
        $wc = @(Get-WorkingCopies -App $App | Where-Object { $_.Token -ieq $Workspace })[0]
        if ($wc) { Invoke-UpdateRepos -App $wc.App -OnlyRepo $wc.Repo -OnlyToken $wc.Token }
    }

    # Same environment selection as -Compile/-Batch.
    $tt = if (Test-ClientTargets -Tag "Test") {
        @($Targets | Where-Object { $_.Component -eq "Database" })
    } else { @() }

    if ($tt.Count -eq 0) {
        Write-Message "  No valid target selected for -Test (App1: -Site S1|S2 + -Env Dev|Test|SBox; App2: -Env Dev|Test|SBox; or pass -Ini and -Pf explicitly).  OpenEdge 12+ only." -Fore Yellow
    }
    # One test run per environment (exe/ini/pf resolve per env; see -Compile note).
    $tt = @($tt | Group-Object { "{0}|{1}|{2}|{3}|{4}" -f $_.Server, $_.App, $_.Env, $_.Site, $_.DLC } |
                  ForEach-Object { $_.Group[0] })
    foreach ($t in $tt) { if (Test-CanAct -Item $t) { Do-Test -Item $t } }
}

# NOTIFICATIONS - email + Windows EventLog on any error.
if ($OnError -eq $true -or $OnLogError -eq $true -or $OnPortError -eq $true -or $OnTestError -eq $true) {
    $summary = "OEAdmin run had errors. OnError=$OnError OnLogError=$OnLogError OnPortError=$OnPortError OnTestError=$OnTestError. See $LogFile."
    if ($EmailOnError -eq $true) {
        Send-Email-Error -Subject "OEAdmin - ERROR" -Body $summary
    }
    Write-OEEventLog -Message $summary -EventID 2001 -EntryType "Error"
}

# Email the full log when requested, or whenever an error occurred.
if ($LogFileEmail -eq $true -or (($OnError -eq $true -or $OnLogError -eq $true -or $OnPortError -eq $true -or $OnTestError -eq $true) -and $EmailOnError -eq $true)) {
    Send-Email-Log -Subject "OEAdmin - Run Log"
}

Write-Section "SCRIPT COMPLETED"

if ($OnError -eq $true)     { exit 2001 }
if ($OnLogError -eq $true)  { exit 2002 }
if ($OnPortError -eq $true) { exit 2003 }
if ($OnTestError -eq $true) { exit 2004 }
exit 0

## ============================================================================
## CUSTOMIZATION CHECKLIST (search for "CHANGE THIS" to find each spot)
## ============================================================================
##  1. $Installs table .......... your servers, tiers, OpenEdge versions, DLCs,
##                                ports, each row's InstallDir (the install root /
##                                PROPATH root) and SetupDir (= <InstallDir>/setup,
##                                the -Client/-Batch INI/PF root), and
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
