# OEAdmin.ps1 — AI Customization Prompts

This file gives you two things:

1. A **master prompt** you can paste into any capable AI assistant (Claude,
   ChatGPT, etc.) along with `OEAdmin.ps1`. The assistant will interview you,
   one topic at a time, and then hand back a fully customized script.
2. The **underlying question set**, so you (or the AI) know exactly what to ask
   and why. You can also just answer these yourself and edit the script directly.

Every question maps to a `CHANGE THIS` marker in the script.

---

## Part 1 — Master prompt (paste this to your AI assistant)

> You are helping me customize a PowerShell script called **OEAdmin.ps1** that
> administers OpenEdge (Progress) databases. I will paste the script after this
> message.
>
> The script is a template with placeholder values marked `CHANGE THIS`. Your job
> is to interview me and then produce a customized copy.
>
> **Rules for the interview:**
> - Ask me about **one topic at a time**, in the order listed below. Wait for my
>   answer before moving on.
> - Explain briefly why each piece matters, in plain language — assume I know my
>   OpenEdge environment but not this script.
> - If I don't know an answer, tell me exactly where to find it (which file,
>   which command) and offer a sensible default.
> - Never invent server names, ports, paths, or naming conventions. If I'm vague,
>   ask a follow-up.
> - Keep a running summary of my answers so I can correct anything.
>
> **Topics, in order:** (1) Operating system & where the script will run;
> (2) Applications; (3) Servers and installs; (4) OpenEdge versions;
> (5) Database naming convention; (6) Sites/environments; (7) Backup layout &
> copy-to-dev (split/push settings); (8) Client (INI/PF) setup layout;
> (9) Email/SMTP; (10) Remote operation; (11) Launch tools (the `$Tools` map);
> (12) Git working copies (`-Workspace` / `-Git`, only if you launch from git).
>
> When the interview is complete:
> - Produce the fully edited `OEAdmin.ps1` with every `CHANGE THIS` spot updated
>   to my answers (and the `-App`/`-OEVersion`/site ValidateSets kept in sync
>   with what I gave you).
> - List anything I still need to verify on the box (e.g. real database names,
>   actual file paths) before running for real.
> - Remind me to test with `-DryRun` and `-Menu` first.
>
> Start by asking me topic 1. Here is the script:
>
> `<paste OEAdmin.ps1 here>`

---

## Part 2 — The question set (what the AI will ask, and why)

### Topic 1 — Operating system & where it runs
- **Q1.1** Will this run on **Linux**, **Windows**, or both?
  *Why:* decides the default paths (`/usr/dlc` vs `C:\Progress\OpenEdge`) and
  whether tools need the `.bat` extension. The script auto-detects at run time,
  but the *default strings* in the param block should match your usual host.
- **Q1.2** Will you run the script **on each database server** (local), or from
  **one management box** targeting others (`-Remote`)?
  *Why:* local is the simple default; `-Remote` needs `Convert-ToRemotePath`
  edited (Topic 10).

### Topic 2 — Applications
- **Q2.1** How many distinct **applications** do you manage with OpenEdge, and
  what should each be called? (e.g. `ERP`, `WMS`)
  *Why:* sets the `-App` ValidateSet and the `App=` values in `$Installs`. The
  template ships with `App1` and `App2`.
- **Q2.2** For each app: does it have **multiple sites** (locations/plants), or a
  single set of databases?
  *Why:* multi-site apps use the site-aware naming/parsers (like App1);
  single-site apps don't (like App2).

### Topic 3 — Servers and installs
For **each OpenEdge install** (a server + a DLC directory + a version):
- **Q3.1** Server **hostname** (exactly as `hostname` reports it).
- **Q3.2** Is it **Production** or **Development**? *Why:* drives the backup vs
  restore safety guard.
- **Q3.3** Which **application** does it host?
- **Q3.4** The **DLC** (OpenEdge install) path on that server.
- **Q3.5** The **AdminServer port** for that install (default 20931; a second
  OE version on the same box uses a different port).
- **Q3.6** The **InstallDir** (install root) and **SetupDir** (always
  `<InstallDir>/setup`, the root of this install's `-Client`/`-Batch` INI/PF tree)
  — skip if you won't use the client. *Why:* sets each row's `InstallDir` and
  `SetupDir`; they're per install because the root can differ by machine and OE
  version. `InstallDir` is also what the `-Workspace` launch swaps out of the
  master INI's PROPATH.
- **Q3.7** Which **shared components** does this install run — NameServer,
  MS SQL DataServer broker, Oracle DataServer broker, any combination, or none?
  *Why:* sets each row's `InstalledComponents` allowlist, which gates what
  `-Start`/`-Stop`/`-Restart` will touch (and is per install/AdminServer — two OE
  versions on one box each declare their own).
- **Q3.8** Does this install's AdminServer manage any **extra databases that are
  NOT application databases** — e.g. a **schema-holder** database — that you still
  want listed and actionable? If so, give me their **exact** database names.
  *Why:* sets each row's `ExtraDatabases` allowlist (default `@()`). The database
  name-parser (Topic 5) only recognizes application databases and silently skips
  everything else; a schema-holder or other non-app DB would therefore never
  appear. Listing it here forces it into the inventory as a Database row with
  Role="Extra" and Site/Env="All", tagged with this install's App. Use exact
  names (case-insensitive); it's per install because the extras differ by box.
  *Where to find it:* the `[database.*]` section headers in `conmgr.properties` —
  any managed DB whose name does NOT fit your app naming convention from Topic 5.
  *Why (the rows):* Q3.1–Q3.8 become the rows of `$Installs`. One server can have
  several rows.
  *Where to find it:* AdminServer port is in the install's config /
  `proadsv -query`; DLC is your `$DLC` env var; the components are the
  `[NameServer.*]` / `[UBroker.MS.*]` / `[UBroker.OR.*]` sections in
  `ubroker.properties`.

### Topic 4 — OpenEdge versions
- **Q4.1** Which **OpenEdge versions** are in play across all installs?
  (e.g. `12.8`, `11.7`, `10.2B`)
  *Why:* sets the `-OEVersion` ValidateSet and the client-exe map in
  `Resolve-ClientLaunch` (which prowin/prowin32/_progres to launch).

### Topic 5 — Database naming convention (the important one)
- **Q5.1** For each app, give me **3–5 real database names** as they appear in
  `conmgr.properties` (e.g. `erpprods1`, `erpdevs1`, `wms_prod`).
- **Q5.2** Describe the **pattern**: which part is the app/role, which is the
  environment, which (if any) is the site?
  *Why:* this is how the script derives each database's env/site without you
  listing them by hand. The AI will turn this into the regex + maps in
  `Parse-App1Database` / `Parse-App2Database`. **A name that doesn't match is
  silently ignored** — that's how scratch/QA databases get skipped.
  *Where to find it:* `<DLC>/properties/conmgr.properties`, the `[database.*]`
  section headers.

### Topic 6 — Sites & environments
- **Q6.1** What are your **site codes** (if any)? (e.g. `S1`, `S2`, or plant
  names.) *Why:* sets `$ValidSites`.
- **Q6.2** What **environments** do you use? The template assumes
  `Prod / Dev / Test / SBox`. Add/remove to match yours. *Why:* sets
  `$ValidEnvs` and the env maps in the parsers.

### Topic 7 — Backup layout and copy-to-dev
- **Q7.1** Where do **backup files** live for each app? (directory + filename
  pattern, e.g. `/opt/erp/backups/erpProdS1.bk`)
  *Why:* sets `$App1BackupDir`/`$App2BackupBase` and the `Get-BackupDevice` map.
  Note: `-CopyBackup` runs **on the production server** and treats this as a
  **local** path (not a share).
- **Q7.2** Flat directory, or **per-role subdirectories**? *Why:* the subdir
  layout is preserved on the destination share by `Invoke-CopyBackup`.
- **Q7.3** Which **dev server** do each app's backups get pushed to, and what
  **named share** on it maps to the backup directory? (e.g. App1 → `dbserver1-dev`,
  App2 → `dbserver2-dev`, share `backups`.) *Why:* sets the per-app map
  `$CopyDestDefaults` and `$BackupShareName`; the destination is
  `\\<dest>\<BackupShareName>\...` — deliberately **not** the admin `drive$`
  share. At run time `-Dest <server>` overrides the per-app default for a one-off.
- **Q7.4** Are any backups large enough to want **splitting**? Default splits any
  `.bk` over 1 GB into 1 GB slices and can pipeline the copy (`-AsyncCopy`).
  *Why:* sets `$SplitThresholdBytes`, `$SplitSliceBytes`, `$AsyncQueueDepth`, and
  the retry policy `$CopyMaxRetries`/`$CopyRetryDelay`. On Linux you'll also point
  the destination-root build in `Invoke-CopyBackup` at your mount/ssh scheme.

### Topic 8 — Client (INI/PF) setup layout
*(Skip if you won't use `-Client`/`-Batch`.)*
- **Q8.1** Where are the **INI and PF files** kept, and how are they named?
  The template expects `<SetupDir>/ini/<server>/<stem>.ini` and
  `<SetupDir>/userPfs/<server>/<stem>.pf`, where **`SetupDir` is a column on each
  `$Installs` row** (per machine + OE version), not a global.
  *Why:* sets each row's `SetupDir`, plus `Get-ClientIni`/`Get-ClientPf` and the
  single-site stem in `Get-App2EnvStem`.
- **Q8.2** Do you launch a **startup program** on client launch? What's its path?
  *Why:* sets `$StartupProgram` (used by `-Run`).

### Topic 9 — Email / SMTP
*(Skip if you don't want email alerts.)*
- **Q9.1** SMTP **server + port**, and does it need **TLS/SSL**?
- **Q9.2** **From** and **To** addresses for alerts.
  *Why:* sets `$SmtpServer`/`$SmtpPort`/`$SmtpUseSsl`/`$EmailFrom`/`$EmailTo`.

### Topic 10 — Remote operation
*(Skip unless you answered "one management box" in Q1.2.)*
- **Q10.1** How do you reach **another server's filesystem** from the management
  box? (Windows admin share `\\server\D$\...`, an NFS/autofs mount, ssh, …)
  *Why:* the AI will rewrite `Convert-ToRemotePath` to match. The shipped version
  uses the Windows UNC admin-share convention.

### Topic 11 — Launch tools (the `$Tools` map)
*(Skip if you only ever launch a plain client / `-Run`.)*
- **Q11.1** Besides the startup program, what **named programs** do you launch via
  the client? (e.g. a procedure editor, a data dictionary, an app-specific
  console.) For each: a short **name**, the `.p`/`.r` it runs, any extra client
  args, and whether it's **app-specific** or shared.
  *Why:* sets the `$Tools` map (`Name`/`Pgm`/`Extra`/`App`/`Startup`) that
  `-Tool <name>` and the menu's launch picker use. The template ships
  Run/Editor/AppBuilder/Desktop/Dict/Admin; you just add rows.

### Topic 12 — Git working copies (`-Workspace` / `-Git`)
*(Skip unless you want to launch the client from a git working copy, or do light
worktree maintenance, from this tool.)*
- **Q12.1** Where do your git repos live on the machine(s) that run this, and is
  the layout a **bare clone + per-branch worktree** (`<root>/<Repo>/.bare` plus a
  worktree folder per branch)?
  *Why:* sets `$GitReposRoot` (and its machine-aware default); if the layout
  differs, the AI adjusts `Get-WorkingCopies` and the `AppPath` probe. This layout
  is what `-Workspace`, `-Git -UpdateRepos`, and `-Git -NewWorkspace` assume — on a
  plain single clone, `-NewWorkspace`/`-UpdateRepos` detect the missing `.bare` and
  stop/skip safely rather than cloning blindly (see the user manual §7.10). **If
  your developers are *not* standardized on this layout, say so** — the standalone
  CreateGitWorkspace-style full-clone approach may suit them better, and you may
  want to leave the git sub-actions unused.
- **Q12.2** Which **repos map to which apps**? (e.g. `AppRepo` → `App1`.)
  *Why:* sets `$GitRepoApps`; only mapped repos are discovered.
- **Q12.3** When launching from a worktree, the client's PROPATH must point at the
  worktree instead of the installed code. Confirm your **INI PROPATH** contains
  the install root (the `InstallDir`) so the script can rewrite it, and that the
  **PF** (DB connections) should stay unchanged.
  *Why:* drives `Resolve-WorkspaceIni` (copy default INI + rewrite `PROPATH=`,
  leave the PF alone).
- **Q12.4** *(only if you want `-Git -NewWorkspace` to be able to create a repo
  that doesn't exist locally yet)* What are the **clone URLs** for each repo?
  *Why:* sets `$GitProjects` (repo → URL). `-NewWorkspace` uses it **only** when
  you pass `-BootstrapClone` (or confirm the menu prompt) to create a fresh bare
  clone; by default it never clones a repo that isn't already present, so a
  developer on a different layout isn't handed a surprise second copy.
- **Q12.5** *(nothing to configure — just so you know)* The **day-in-the-life**
  git helpers (`-GitStatus` / `-GitDiff` / `-GitLog` / `-GitStash` /
  `-GitStashPop` / `-GitStashList` / `-GitCommit` / `-GitPush` / `-GitHelp`) wrap
  everyday git for developers who aren't comfortable on the command line. They
  need **no** config: they run in whatever working copy you point them at
  (`-Workspace`, `-RepoPath`, or the current directory). The write ones
  (`-GitCommit` / `-GitPush`) confirm first and never `--force`; rebase, conflict
  resolution and `push --force-with-lease` are intentionally left to the user and
  only shown by `-GitHelp`. Nothing to answer here — just decide whether to tell
  your team about them.

### Topic 13 — Compile (`-Compile`) — nothing to configure

*(Informational — no interview questions.)* `-Compile` runs the OpenEdge
Application Compiler headlessly. It needs **no** customization: it reuses the same
client exe / INI / PF resolution you already set up for `-Client`/`-Batch`, so it
inherits your PROPATH and database connections automatically. The one requirement
is that the bundled driver **`OECompiler.p`** stays **beside `OEAdmin.ps1`** (the
script passes it to `-p` by full path, so it does not need to be on PROPATH). The
compiler saves `.r` beside the source and writes its log/listing/xref under
`<sourceroot>/x/<timestamp>/` (the driver's own stdout/err go to
`<script dir>/batch/OECompiler/`, alongside `-Batch` output). Defaults (file spec
`*.p *.w *.cls *.t`, full rebuild, log-only) work out of the box; `-Incremental`,
`-FileSpec`, `-Dir`, `-Listing`, `-Xref`/`-XrefXml`, and `-Installed` tune a run.
To skip source that never compiles standalone (vendor sample code, etc.), use
`-Exclude "pat,pat"` and/or keep a standing **`compile-excludes.txt`** in the
script folder (one wildcard pattern per line, matched against each file's path
relative to the source root) and pass `-ExcludeFile compile-excludes.txt`. If you
support a very old OpenEdge (9.x), note `OECompiler.p` is written in pre-11 ABL on
purpose so it compiles there too.

### Topic 14 — Package (`-Package`) — almost nothing to configure

*(Informational — one optional default.)* `-Package` builds a release bundle from
one project's change set. It reuses the `-Compile` machinery, so like `-Compile`
it needs **no** environment customization beyond what `-Client`/`-Batch` already
have. Two assumptions to know:

- It runs against a **local git worktree** (`-Workspace`); `-Remote` is refused.
  So the box running `-Package` needs the repo checked out with the bare-clone +
  worktree layout OEAdmin already uses for `-Workspace` (see Topic 12 / `-Git`).
- The change set is read from git history (`-Grep` on commit messages,
  `-FromCommit`..`-ToCommit`, or an explicit `-FileList`). The advisory
  marker-drift check looks for an inline change marker of the form
  `/* XX 2026-01-31 ... changes */`; if your team uses a different marker style it
  simply reports no match (it never blocks), so there is nothing to change.

The **one** optional default is **`-PackageBackupDir`**: the backup-before-
overwrite root baked into the generated `deploy.ps1`. Blank falls back to the
App1 backup dir; set it (CLI or the default in the param block) to wherever
deploy-time backups should land on your target servers. Everything else — the zip
name, manifest, dependency-aware r-code set, and the fail-closed compile against
the required `-Site`/`-Env` — is automatic. Delta schema files passed with
`-DeltaDf` are bundled and the generated `deploy.ps1` **prints** the DBA load
steps and awaits confirmation; it never loads a `.df` itself, so no DB credentials
live in the bundle.

`-ShipPL` (optional, nothing to configure) also bundles a single `<App>.pl`
procedure library at the zip root, built with the OpenEdge `prolib` utility that
ships with every install (resolved from the target's `DLC`, so no extra setup).
With it, the generated `deploy.ps1` backs up + replaces only that one `.pl` on the
server instead of the loose `rcode/` tree — one file to verify. `source/` and
`rcode/` still ride along as documentation. It is off by default.

### Topic 15 — Test (`-Test`) — one PROPATH requirement

*(Informational — no interview questions.)* `-Test` runs the **ABLUnit** suite
headlessly via the Progress driver `ABLUnitCore.p`. Like `-Compile`, it reuses the
`-Client`/`-Batch` exe/INI/PF resolution, so it needs almost no customization. The
**one** requirement: the ABLUnit framework — `ABLUnitCore.p` plus the
`OpenEdge.ABLUnit.*` / `OpenEdge.Core.*` classes — must be on the target
environment's **INI `PROPATH`**. OEAdmin does **not** ship the framework; it comes
with OpenEdge (Developer Studio ships it, and it's available in the product's
`src/ablunit` tree). Add that path to the INI `PROPATH=` for each environment you
want to test in (the same place your app's own `{includes}`/classes resolve).

`-Test` is **OpenEdge 12+ only** (the framework is 12-era OOABL); a pre-12 target
is refused automatically. The test spec is `-TestSpec` (a class/proc,
`Foo.cls#Method`, a comma-list, or a folder; blank = a `tests` folder under the
source root). OEAdmin writes a generated config JSON, runs the suite, and parses
the `results.xml` it produces — if that file is missing, the most common cause is
the framework not being on the INI PROPATH, which OEAdmin reports explicitly. A
test failure/error (or a missing `results.xml`) sets exit `2004`.

---

## Part 3 — After customizing

1. Parse-check: `pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./OEAdmin.ps1),[ref]$null,[ref]$null); 'OK'"`
2. Dry run: `./OEAdmin.ps1 -DryRun` and `./OEAdmin.ps1 -Menu`
3. Confirm the discovered inventory matches reality (bare `./OEAdmin.ps1` shows
   what it found). If a database is missing, fix the parser regex (Topic 5).
4. Only then run a real action, starting with read-only `-Status`.
