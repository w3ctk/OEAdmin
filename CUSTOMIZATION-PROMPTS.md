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
> (5) Database naming convention; (6) Sites/environments; (7) Backup layout;
> (8) Client (INI/PF) setup layout; (9) Email/SMTP; (10) Remote operation.
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
  *Why:* these become the rows of `$Installs`. One server can have several rows.
  *Where to find it:* AdminServer port is in the install's config /
  `proadsv -query`; DLC is your `$DLC` env var.

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

### Topic 7 — Backup layout
- **Q7.1** Where do **backup files** live for each app? (directory + filename
  pattern, e.g. `/opt/erp/backups/erpProdS1.bk`)
  *Why:* sets `$App1BackupDir`/`$App2BackupBase` and the `Get-BackupDevice` map.
- **Q7.2** Flat directory, or **per-role subdirectories**? *Why:* affects the
  copy recursion in `Invoke-CopyBackup`.

### Topic 8 — Client (INI/PF) setup layout
*(Skip if you won't use `-Client`/`-Batch`.)*
- **Q8.1** Where are the **INI and PF files** kept, and how are they named?
  The template expects `<SetupDir>/ini/<server>/<stem>.ini` and
  `<SetupDir>/userPfs/<server>/<stem>.pf`.
  *Why:* sets `$App1SetupDir`/`$App2SetupDir`, `Get-ClientIni`/`Get-ClientPf`,
  and the single-site stem in `Get-App2EnvStem`.
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

---

## Part 3 — After customizing

1. Parse-check: `pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./OEAdmin.ps1),[ref]$null,[ref]$null); 'OK'"`
2. Dry run: `./OEAdmin.ps1 -DryRun` and `./OEAdmin.ps1 -Menu`
3. Confirm the discovered inventory matches reality (bare `./OEAdmin.ps1` shows
   what it found). If a database is missing, fix the parser regex (Topic 5).
4. Only then run a real action, starting with read-only `-Status`.
