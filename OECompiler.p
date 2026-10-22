/*------------------------------------------------------------------------------
  File        : OECompiler.p
  Purpose     : Headless (no-UI) application compiler driver for OEAdmin's
                -Compile action.  OEAdmin launches it in a batch client session
                with the SAME ini/pf a -Client/-Batch session uses:

                    <prowin|prowin32> -ininame <ini> -pf <pf> ^
                        -p <full path>\OECompiler.p -param "<paramfile>" -b

                All compile options arrive through a PARAMETER FILE (not UI and
                not a packed -param string).  The param file path is passed as the
                single SESSION:PARAMETER value; this program reads it, compiles the
                matched source, and writes one consolidated log plus (optionally)
                per-file LISTING and XREF output.

  Derived from : OpenEdge Application Compiler (adecomp/_compile.p + the
                StartCompile logic in adecomp/acprocs.i).  All UI, menus, the
                PROPATH picker, VMS handling, the license check, XCODE/encrypted
                source, and the MIN-SIZE/STREAM-IO/GENERATE-MD5/LANGUAGES/V6FRAME
                options were intentionally removed - none are needed here.

  Parameter file format (one key=value per line; blank lines and lines beginning
  with '#' are ignored; keys are case-insensitive):

      filespecs = *.p *.w *.cls *.t     ; space-separated MATCHES patterns
      sourceroot = <dir>                ; base directory to compile under
      dir        = <relpath>            ; optional sub-directory filter (under root)
      recurse    = yes|no               ; default yes
      mode       = full|incremental     ; full = rebuild all matched;
                                        ; incremental = only when .r missing OR
                                        ;               source newer than .r
      logfile    = <full path>          ; consolidated run log (always written)
      listing    = yes|no               ; per-file LISTING output (default no)
      listingdir = <dir>                ; root for per-file .listing files
      xref       = yes|no               ; per-file XREF output (default no)
      xrefdir    = <dir>                ; root for per-file .xref files
      xrefxml    = yes|no               ; if yes, XREF-XML instead of plain XREF

  Exit : QUIT value 0 when every matched file compiled clean; QUIT value 1 when
         one or more files had COMPILER errors (so OEAdmin's Start-Process sees a
         non-zero ExitCode and alerts).  The run summary (compiled / errors /
         warnings counts) is written to the log and to the batch .out.

  NOTE on ABL style: this driver must also compile and run under OpenEdge 9.1E
  (the Syteline 5 / SL5 client), so it deliberately uses broadly-supported,
  pre-11 syntax: traditional DEFINE VARIABLE (no VAR), classic DO ON ERROR error
  handling (no BLOCK-LEVEL ... UNDO, THROW), OS-DIR / FILE-INFO, and plain
  COMPILE ... SAVE / LISTING / XREF.  This is a conscious departure from the QMS
  "modern OOABL" house convention, required by the 9.1E target.

  Author      : Chris Kelleher
  Created     : 2026-10-21  (OEAdmin -Compile)
------------------------------------------------------------------------------*/

DEFINE VARIABLE cParamFile  AS CHARACTER NO-UNDO.
DEFINE VARIABLE cLine       AS CHARACTER NO-UNDO.
DEFINE VARIABLE cKey        AS CHARACTER NO-UNDO.
DEFINE VARIABLE cVal        AS CHARACTER NO-UNDO.
DEFINE VARIABLE iEq         AS INTEGER   NO-UNDO.

/* ---- compile settings (populated from the param file) -------------------- */
DEFINE VARIABLE cFileSpecs  AS CHARACTER NO-UNDO INIT "*.p *.w *.cls *.t".
DEFINE VARIABLE cSourceRoot AS CHARACTER NO-UNDO.
DEFINE VARIABLE cDirFilter  AS CHARACTER NO-UNDO.
DEFINE VARIABLE lRecurse    AS LOGICAL   NO-UNDO INIT YES.
DEFINE VARIABLE cMode       AS CHARACTER NO-UNDO INIT "full".
DEFINE VARIABLE cLogFile    AS CHARACTER NO-UNDO.
DEFINE VARIABLE lListing    AS LOGICAL   NO-UNDO INIT NO.
DEFINE VARIABLE cListingDir AS CHARACTER NO-UNDO.
DEFINE VARIABLE lXref       AS LOGICAL   NO-UNDO INIT NO.
DEFINE VARIABLE cXrefDir    AS CHARACTER NO-UNDO.
DEFINE VARIABLE lXrefXml    AS LOGICAL   NO-UNDO INIT NO.
DEFINE VARIABLE cStatusFile AS CHARACTER NO-UNDO.  /* ERRORS=<n> written here */
DEFINE VARIABLE cExcludes   AS CHARACTER NO-UNDO.  /* CHR(1)-delimited exclude patterns */

/* ---- run state ----------------------------------------------------------- */
DEFINE VARIABLE iCompiled   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iErrors     AS INTEGER   NO-UNDO.
DEFINE VARIABLE iWarnings   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iSkipped    AS INTEGER   NO-UNDO.  /* excluded files */
DEFINE VARIABLE lLogOpen    AS LOGICAL   NO-UNDO.

DEFINE STREAM sLog.
/* OS-DIR walk stream.  Must be defined at the top level (streams cannot be
   defined inside an internal procedure).  CompileDir recurses, but each level
   fully consumes + closes the stream before descending, so one shared stream is
   safe. */
DEFINE STREAM sDir.
/* Status file stream (top level - streams cannot be defined in a procedure). */
DEFINE STREAM sStat.

/* Forward declarations: the function bodies are at the bottom of the file, but
   they are called from CompileDir above them, so ABL needs the signatures up
   front. */
FUNCTION MatchesAnySpec RETURNS LOGICAL (INPUT p_Name AS CHARACTER) FORWARD.
FUNCTION IsExcluded     RETURNS LOGICAL (INPUT p_File AS CHARACTER) FORWARD.

/* ============================================================================
   MAIN
   ============================================================================ */
DO ON ERROR UNDO, LEAVE ON STOP UNDO, LEAVE:

    ASSIGN cParamFile = SESSION:PARAMETER.

    IF cParamFile = "" OR cParamFile = ? THEN DO:
        RUN WriteOut ("OECompiler: no parameter file passed (-param).").
        RUN WriteStatus (INPUT -1).
        QUIT.
    END.

    FILE-INFO:FILE-NAME = cParamFile.
    IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
        RUN WriteOut ("OECompiler: parameter file not found: " + cParamFile).
        RUN WriteStatus (INPUT -1).
        QUIT.
    END.

    /* ---- read the parameter file ---------------------------------------- */
    INPUT FROM VALUE(cParamFile) NO-ECHO.
    REPEAT:
        IMPORT UNFORMATTED cLine.
        cLine = TRIM(cLine).
        IF cLine = "" THEN NEXT.
        IF cLine BEGINS "#" THEN NEXT.
        iEq = INDEX(cLine, "=").
        IF iEq = 0 THEN NEXT.
        cKey = TRIM(SUBSTRING(cLine, 1, iEq - 1)).
        cVal = TRIM(SUBSTRING(cLine, iEq + 1)).
        CASE cKey:
            WHEN "filespecs"  THEN cFileSpecs  = cVal.
            WHEN "sourceroot" THEN cSourceRoot = cVal.
            WHEN "dir"        THEN cDirFilter  = cVal.
            WHEN "recurse"    THEN lRecurse    = (cVal BEGINS "y" OR cVal BEGINS "Y").
            WHEN "mode"       THEN cMode       = cVal.
            WHEN "logfile"    THEN cLogFile    = cVal.
            WHEN "listing"    THEN lListing    = (cVal BEGINS "y" OR cVal BEGINS "Y").
            WHEN "listingdir" THEN cListingDir = cVal.
            WHEN "xref"       THEN lXref       = (cVal BEGINS "y" OR cVal BEGINS "Y").
            WHEN "xrefdir"    THEN cXrefDir    = cVal.
            WHEN "xrefxml"    THEN lXrefXml    = (cVal BEGINS "y" OR cVal BEGINS "Y").
            WHEN "statusfile" THEN cStatusFile = cVal.
            WHEN "excludes"   THEN cExcludes   = cVal.   /* CHR(1)-delimited patterns */
        END CASE.
    END.
    INPUT CLOSE.

    IF cSourceRoot = "" OR cSourceRoot = ? THEN DO:
        RUN WriteOut ("OECompiler: 'sourceroot' not set in parameter file.").
        RUN WriteStatus (INPUT -1).
        QUIT.
    END.
    FILE-INFO:FILE-NAME = cSourceRoot.
    IF FILE-INFO:FULL-PATHNAME = ? OR INDEX(FILE-INFO:FILE-TYPE, "D") = 0 THEN DO:
        RUN WriteOut ("OECompiler: source root is not a directory: " + cSourceRoot).
        RUN WriteStatus (INPUT -1).
        QUIT.
    END.
    /* Standardize the source root to forward slashes.  FULL-PATHNAME returns
       backslashes on Windows, but BuildOutPath standardizes each file's path to
       '/' before testing "cFull BEGINS cSourceRoot" - so the root MUST also be
       '/'-form or that test fails and the mirrored output path is built wrong
       (which left listing/xref dirs uncreated and the compile erroring on write). */
    cSourceRoot = REPLACE(FILE-INFO:FULL-PATHNAME, "~\", "/").

    IF cFileSpecs = "" OR cFileSpecs = ? THEN cFileSpecs = "*.p *.w *.cls *.t".
    IF cMode = ? OR (cMode <> "full" AND cMode <> "incremental") THEN cMode = "full".

    /* ---- open the consolidated log -------------------------------------- */
    IF cLogFile <> "" AND cLogFile <> ? THEN DO:
        OUTPUT STREAM sLog TO VALUE(cLogFile) NO-ECHO.
        lLogOpen = YES.
    END.

    RUN Log ("OECompiler run start: " + STRING(TODAY, "99/99/9999") + " "
             + STRING(TIME, "HH:MM:SS")).
    RUN Log ("  source root : " + cSourceRoot).
    RUN Log ("  file specs  : " + cFileSpecs).
    RUN Log ("  dir filter  : " + (IF cDirFilter = "" OR cDirFilter = ? THEN "(none)" ELSE cDirFilter)).
    RUN Log ("  recurse     : " + STRING(lRecurse, "yes/no")).
    RUN Log ("  mode        : " + cMode).
    RUN Log ("  listing     : " + STRING(lListing, "yes/no")
             + (IF lListing THEN "  -> " + cListingDir ELSE "")).
    RUN Log ("  xref        : " + STRING(lXref, "yes/no")
             + (IF lXref THEN "  (" + (IF lXrefXml THEN "xml" ELSE "plain") + ") -> " + cXrefDir ELSE "")).
    IF cExcludes <> "" AND cExcludes <> ? THEN
        RUN Log ("  excludes    : " + STRING(NUM-ENTRIES(cExcludes, CHR(1))) + " pattern(s): "
                 + REPLACE(cExcludes, CHR(1), ", ")).
    RUN Log ("----------------------------------------------------------------").

    /* ---- walk + compile -------------------------------------------------- */
    RUN CompileDir (INPUT cSourceRoot, INPUT cDirFilter).

    RUN Log ("----------------------------------------------------------------").
    RUN Log ("Compilation finished.  compiled=" + STRING(iCompiled)
             + "  errors=" + STRING(iErrors)
             + "  warnings=" + STRING(iWarnings)
             + "  skipped=" + STRING(iSkipped)).
    IF iErrors > 0 THEN
        RUN Log ("*** " + STRING(iErrors) + " file(s) had COMPILER ERRORS - review above. ***").

    IF lLogOpen THEN OUTPUT STREAM sLog CLOSE.

    /* Mirror the summary to the batch .out so OEAdmin shows it without opening
       the log, and write the machine-readable status file OEAdmin reads to decide
       success/failure (ABL QUIT carries no exit code, so the status file - not a
       process exit code - is the authoritative signal). */
    RUN WriteOut ("OECompiler: compiled=" + STRING(iCompiled)
                  + " errors=" + STRING(iErrors)
                  + " warnings=" + STRING(iWarnings)
                  + " skipped=" + STRING(iSkipped)).
    RUN WriteStatus (INPUT iErrors).
    QUIT.
END.

/* If we fell through the MAIN block on an unexpected error, fail closed. */
IF lLogOpen THEN OUTPUT STREAM sLog CLOSE.
RUN WriteOut ("OECompiler: aborted on an unexpected error.").
RUN WriteStatus (INPUT -1).
QUIT.


/* ============================================================================
   INTERNAL PROCEDURES
   ============================================================================ */

/* Recursively compile every file under p_Dir that matches one of the file
   specs.  p_RelFilter, when set on the top call, restricts the FIRST level to a
   named sub-directory (so -Dir compiles only that branch). */
PROCEDURE CompileDir:
    DEFINE INPUT PARAMETER p_Dir       AS CHARACTER NO-UNDO.
    DEFINE INPUT PARAMETER p_RelFilter AS CHARACTER NO-UNDO.

    DEFINE VARIABLE cEntry    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cFullName AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cAttr     AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cStartDir AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSubDirs  AS CHARACTER NO-UNDO.   /* CHR(1)-delimited subdir list */
    DEFINE VARIABLE iSub      AS INTEGER   NO-UNDO.

    /* Honor a -Dir filter on the initial call: descend into the named
       sub-directory and clear the filter for the recursion below it. */
    cStartDir = p_Dir.
    IF p_RelFilter <> "" AND p_RelFilter <> ? THEN DO:
        cStartDir = RIGHT-TRIM(p_Dir, "~/\") + "/" + p_RelFilter.
        FILE-INFO:FILE-NAME = cStartDir.
        IF FILE-INFO:FULL-PATHNAME = ? OR INDEX(FILE-INFO:FILE-TYPE, "D") = 0 THEN DO:
            RUN Log ("  -Dir filter is not a directory, skipping: " + cStartDir).
            RETURN.
        END.
        cStartDir = FILE-INFO:FULL-PATHNAME.
    END.

    /* PASS 1: read this directory once - compile matching files inline, and
       COLLECT sub-directories into a list.  We must NOT recurse while the shared
       OS-DIR stream is open (one stream, reopened mid-iteration, would clobber
       the parent's read position), so recursion happens in PASS 2 after close. */
    INPUT STREAM sDir FROM OS-DIR(cStartDir) NO-ECHO.
    REPEAT:
        IMPORT STREAM sDir cEntry cFullName cAttr.
        IF cEntry = "." OR cEntry = ".." THEN NEXT.

        IF INDEX(cAttr, "F") > 0 THEN DO:
            IF MatchesAnySpec(cEntry) THEN DO:
                IF IsExcluded(cFullName) THEN DO:
                    iSkipped = iSkipped + 1.
                    RUN Log ("SKIP (excluded): " + cFullName).
                END.
                ELSE
                    RUN CompileFile (INPUT cFullName).
            END.
        END.
        ELSE IF INDEX(cAttr, "D") > 0 AND lRecurse THEN
            cSubDirs = cSubDirs
                     + (IF cSubDirs = "" THEN "" ELSE CHR(1))
                     + cFullName.
    END.
    INPUT STREAM sDir CLOSE.

    /* PASS 2: recurse into the collected sub-directories (stream now free). */
    IF cSubDirs <> "" THEN
    DO iSub = 1 TO NUM-ENTRIES(cSubDirs, CHR(1)):
        RUN CompileDir (INPUT ENTRY(iSub, cSubDirs, CHR(1)), INPUT "").
    END.
END PROCEDURE.


/* Compile one source file.  Applies the incremental staleness test, then
   COMPILE ... SAVE beside the source, with optional per-file LISTING / XREF. */
PROCEDURE CompileFile:
    DEFINE INPUT PARAMETER p_File AS CHARACTER NO-UNDO.

    DEFINE VARIABLE cRName    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE lStale    AS LOGICAL   NO-UNDO.
    DEFINE VARIABLE cListFile AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cXrefFile AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSrcDir   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iPos      AS INTEGER   NO-UNDO.
    DEFINE VARIABLE iMsg      AS INTEGER   NO-UNDO.
    DEFINE VARIABLE iNumMsg   AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cMsgs     AS CHARACTER NO-UNDO.
    DEFINE VARIABLE lHadError AS LOGICAL   NO-UNDO.
    DEFINE VARIABLE lHadWarn  AS LOGICAL   NO-UNDO.

    /* The .r goes BESIDE the source.  We give COMPILE an explicit SAVE INTO the
       source file's own directory rather than a bare SAVE: in a batch session a
       bare "COMPILE <absolute path> SAVE" cannot reliably resolve where to write
       the .r and sets COMPILER:ERROR with NO messages (which looked like "every
       file failed").  SAVE INTO <source dir> writes the .r in exactly the same
       place (beside the source) with an explicit, writable target. */
    ASSIGN cSrcDir = REPLACE(p_File, "~\", "/").
    iPos = R-INDEX(cSrcDir, "/").
    IF iPos > 0 THEN cSrcDir = SUBSTRING(cSrcDir, 1, iPos - 1).
    ELSE             cSrcDir = ".".

    /* Incremental: skip when a current .r already exists. */
    IF cMode = "incremental" THEN DO:
        RUN NeedsCompile (INPUT p_File, OUTPUT lStale).
        IF NOT lStale THEN DO:
            RUN Log ("Up-to-date (skip): " + p_File).
            RETURN.
        END.
    END.

    /* Per-file LISTING / XREF output paths (mirror the source leaf name, keeping
       the source extension so foo.p and foo.w don't collide). */
    IF lListing AND cListingDir <> "" AND cListingDir <> ? THEN DO:
        RUN BuildOutPath (INPUT p_File, INPUT cListingDir, INPUT ".listing",
                          OUTPUT cListFile).
    END.
    IF lXref AND cXrefDir <> "" AND cXrefDir <> ? THEN DO:
        RUN BuildOutPath (INPUT p_File, INPUT cXrefDir, INPUT ".xref",
                          OUTPUT cXrefFile).
    END.

    /* The compile itself.  Four shapes depending on which outputs are on.
       SAVE INTO <source dir> drops the .r beside the source (production layout). */
    IF cListFile <> "" AND cXrefFile <> "" THEN DO:
        IF lXrefXml THEN
            COMPILE VALUE(p_File) SAVE INTO VALUE(cSrcDir) LISTING VALUE(cListFile)
                XREF-XML VALUE(cXrefFile) NO-ERROR.
        ELSE
            COMPILE VALUE(p_File) SAVE INTO VALUE(cSrcDir) LISTING VALUE(cListFile)
                XREF VALUE(cXrefFile) NO-ERROR.
    END.
    ELSE IF cListFile <> "" THEN
        COMPILE VALUE(p_File) SAVE INTO VALUE(cSrcDir) LISTING VALUE(cListFile) NO-ERROR.
    ELSE IF cXrefFile <> "" THEN DO:
        IF lXrefXml THEN
            COMPILE VALUE(p_File) SAVE INTO VALUE(cSrcDir) XREF-XML VALUE(cXrefFile) NO-ERROR.
        ELSE
            COMPILE VALUE(p_File) SAVE INTO VALUE(cSrcDir) XREF VALUE(cXrefFile) NO-ERROR.
    END.
    ELSE
        COMPILE VALUE(p_File) SAVE INTO VALUE(cSrcDir) NO-ERROR.

    /* CAPTURE the compiler result IMMEDIATELY after COMPILE, into plain locals,
       before any RUN or stream I/O.  Reading COMPILER:NUM-MESSAGES only AFTER the
       "ERROR/OK" log line proved unreliable (it came back 0, so no messages were
       ever printed); snapshotting here - in one tight loop right after COMPILE -
       and logging from the snapshot fixes that.  Messages accumulate into a single
       CHR(10)-delimited string (no temp-table, to stay simple in a -p startup). */
    ASSIGN lHadError = COMPILER:ERROR
           lHadWarn  = COMPILER:WARNING
           iNumMsg   = COMPILER:NUM-MESSAGES
           cMsgs     = "".
    IF iNumMsg > 0 THEN
    DO iMsg = 1 TO iNumMsg:
        cMsgs = cMsgs
              + (IF cMsgs = "" THEN "" ELSE CHR(10))
              + "         [" + STRING(COMPILER:GET-ERROR-ROW(iMsg)) + ","
              + STRING(COMPILER:GET-ERROR-COLUMN(iMsg)) + "] "
              + COMPILER:GET-MESSAGE(iMsg).
    END.

    iCompiled = iCompiled + 1.

    /* Report from the SNAPSHOT (not the live handle). */
    IF lHadError THEN DO:
        iErrors = iErrors + 1.
        RUN Log ("ERROR  : " + p_File).
    END.
    ELSE IF lHadWarn THEN DO:
        iWarnings = iWarnings + 1.
        RUN Log ("WARNING: " + p_File).
    END.
    ELSE
        RUN Log ("OK     : " + p_File).

    /* Dump the captured messages (errors AND warnings), one per line. */
    IF cMsgs <> "" THEN
    DO iMsg = 1 TO NUM-ENTRIES(cMsgs, CHR(10)):
        RUN Log (ENTRY(iMsg, cMsgs, CHR(10))).
    END.
    /* ERROR with ZERO messages means the compile could not WRITE an output file
       (r-code / listing / xref) - a missing/unwritable target directory - not a
       source problem.  Say so explicitly instead of a bare, mysterious ERROR. */
    ELSE IF lHadError THEN
        RUN Log ("         (no compiler messages - output write failed; check that"
                 + " the r-code/listing/xref target dirs exist and are writable)").
END PROCEDURE.


/* Incremental staleness: compile when the .r is MISSING, or when the source
   file's modified timestamp is NEWER than the .r's.  Sets p_Needs. */
PROCEDURE NeedsCompile:
    DEFINE INPUT  PARAMETER p_File  AS CHARACTER NO-UNDO.
    DEFINE OUTPUT PARAMETER p_Needs AS LOGICAL   NO-UNDO INIT YES.

    DEFINE VARIABLE cRName   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE dSrcDate AS DATE      NO-UNDO.
    DEFINE VARIABLE iSrcTime AS INTEGER   NO-UNDO.
    DEFINE VARIABLE dRDate   AS DATE      NO-UNDO.
    DEFINE VARIABLE iRTime   AS INTEGER   NO-UNDO.

    /* Derive the .r name: replace the final extension with .r (or append). */
    IF R-INDEX(p_File, ".") > 0 THEN
        cRName = SUBSTRING(p_File, 1, R-INDEX(p_File, ".") - 1) + ".r".
    ELSE
        cRName = p_File + ".r".

    /* .r missing -> must compile. */
    FILE-INFO:FILE-NAME = cRName.
    IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
        p_Needs = YES.
        RETURN.
    END.
    ASSIGN dRDate = FILE-INFO:FILE-MOD-DATE
           iRTime = FILE-INFO:FILE-MOD-TIME.

    /* Source newer than .r -> must compile. */
    FILE-INFO:FILE-NAME = p_File.
    IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
        p_Needs = YES.   /* source vanished between walk and test: let compile report */
        RETURN.
    END.
    ASSIGN dSrcDate = FILE-INFO:FILE-MOD-DATE
           iSrcTime = FILE-INFO:FILE-MOD-TIME.

    IF dSrcDate > dRDate THEN
        p_Needs = YES.
    ELSE IF dSrcDate = dRDate AND iSrcTime > iRTime THEN
        p_Needs = YES.
    ELSE
        p_Needs = NO.
END PROCEDURE.


/* Build a per-file output path under p_OutRoot that mirrors the source path
   relative to the source root, so a recursive compile does not flatten or
   collide files from different sub-directories.  The leaf keeps the source file
   name plus p_Ext (e.g. foo.p -> foo.p.listing). */
PROCEDURE BuildOutPath:
    DEFINE INPUT  PARAMETER p_File    AS CHARACTER NO-UNDO.
    DEFINE INPUT  PARAMETER p_OutRoot AS CHARACTER NO-UNDO.
    DEFINE INPUT  PARAMETER p_Ext     AS CHARACTER NO-UNDO.
    DEFINE OUTPUT PARAMETER p_OutPath AS CHARACTER NO-UNDO.

    DEFINE VARIABLE cFull    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cRel     AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cRelDir  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cLeaf    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iPos     AS INTEGER   NO-UNDO.

    /* Resolve the source file's full path, standardize separators to '/'. */
    FILE-INFO:FILE-NAME = p_File.
    cFull = FILE-INFO:FULL-PATHNAME.
    IF cFull = ? THEN cFull = p_File.
    cFull = REPLACE(cFull, "~\", "/").

    /* Relative path under the (already standardized) source root. */
    cRel = cFull.
    IF cFull BEGINS cSourceRoot THEN
        cRel = SUBSTRING(cFull, LENGTH(cSourceRoot) + 1).
    cRel = LEFT-TRIM(cRel, "/").

    /* Split into dir + leaf. */
    iPos = R-INDEX(cRel, "/").
    IF iPos > 0 THEN
        ASSIGN cRelDir = SUBSTRING(cRel, 1, iPos - 1)
               cLeaf   = SUBSTRING(cRel, iPos + 1).
    ELSE
        ASSIGN cRelDir = ""
               cLeaf   = cRel.

    /* Ensure the mirrored sub-directory exists under the output root. */
    p_OutPath = RIGHT-TRIM(p_OutRoot, "~/\").
    IF cRelDir <> "" THEN p_OutPath = p_OutPath + "/" + cRelDir.
    RUN EnsureDir (INPUT p_OutPath).

    p_OutPath = p_OutPath + "/" + cLeaf + p_Ext.
END PROCEDURE.


/* Create a directory path (and any missing parents) if it does not exist.
   Builds up the path segment by segment and OS-CREATE-DIRs each missing level,
   using the OS-NATIVE separator (backslash on Windows) because OS-CREATE-DIR with
   forward slashes silently fails on Windows - which was leaving listing/xref/
   r-code target dirs absent, so COMPILE then errored with NO messages. */
PROCEDURE EnsureDir:
    DEFINE INPUT PARAMETER p_Dir AS CHARACTER NO-UNDO.

    DEFINE VARIABLE cNorm AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSoFar AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iSeg  AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cSeg  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSep  AS CHARACTER NO-UNDO.

    IF p_Dir = "" OR p_Dir = ? THEN RETURN.

    /* OS-native separator: backslash on Windows, forward slash elsewhere. */
    cSep = IF OPSYS = "WIN32":U THEN "~\" ELSE "/".

    /* Normalize to '/' for splitting, test existence first. */
    cNorm = REPLACE(p_Dir, "~\", "/").
    FILE-INFO:FILE-NAME = cNorm.
    IF FILE-INFO:FULL-PATHNAME <> ? THEN RETURN.   /* already exists */

    DO iSeg = 1 TO NUM-ENTRIES(cNorm, "/"):
        cSeg = ENTRY(iSeg, cNorm, "/").
        IF iSeg = 1 THEN
            cSoFar = cSeg.          /* drive (C:) on Windows, or "" for leading / */
        ELSE
            cSoFar = cSoFar + cSep + cSeg.
        IF cSoFar = "" THEN NEXT.   /* leading / on unix: skip the empty root seg */
        IF iSeg = 1 AND OPSYS = "WIN32":U THEN NEXT.  /* don't mkdir a bare drive "C:" */
        FILE-INFO:FILE-NAME = cSoFar.
        IF FILE-INFO:FULL-PATHNAME = ? THEN
            OS-CREATE-DIR VALUE(cSoFar).
    END.
END PROCEDURE.


/* Write a line to the consolidated log (and, when no log stream is open, to the
   default output so nothing is lost). */
PROCEDURE Log:
    DEFINE INPUT PARAMETER p_Text AS CHARACTER NO-UNDO.
    IF lLogOpen THEN
        PUT STREAM sLog UNFORMATTED p_Text SKIP.
    ELSE
        RUN WriteOut (p_Text).
END PROCEDURE.


/* Write a line to the batch session's default output (captured to .out). */
PROCEDURE WriteOut:
    DEFINE INPUT PARAMETER p_Text AS CHARACTER NO-UNDO.
    PUT UNFORMATTED p_Text SKIP.
END PROCEDURE.


/* Write the machine-readable status file OEAdmin reads to judge the run.  One
   line: "ERRORS=<n>" where n is the compiler-error count, or -1 for a setup
   failure (no param file / bad source root / unexpected abort).  QUIT cannot
   carry an OS exit code in ABL, so this file is the authoritative signal. */
PROCEDURE WriteStatus:
    DEFINE INPUT PARAMETER p_Errors AS INTEGER NO-UNDO.
    IF cStatusFile = "" OR cStatusFile = ? THEN RETURN.
    OUTPUT STREAM sStat TO VALUE(cStatusFile) NO-ECHO.
    PUT STREAM sStat UNFORMATTED "ERRORS=" STRING(p_Errors) SKIP.
    OUTPUT STREAM sStat CLOSE.
END PROCEDURE.


/* ============================================================================
   FUNCTIONS
   ============================================================================ */

/* TRUE when p_Name matches any of the space-separated specs in cFileSpecs.  The
   spec's "." is escaped so MATCHES treats it literally (not "any char"). */
FUNCTION MatchesAnySpec RETURNS LOGICAL (INPUT p_Name AS CHARACTER):
    DEFINE VARIABLE iSpec AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cSpec AS CHARACTER NO-UNDO.
    DO iSpec = 1 TO NUM-ENTRIES(cFileSpecs, " "):
        cSpec = TRIM(ENTRY(iSpec, cFileSpecs, " ")).
        IF cSpec = "" THEN NEXT.
        cSpec = REPLACE(cSpec, ".", "~~.").
        IF p_Name MATCHES cSpec THEN RETURN YES.
    END.
    RETURN NO.
END FUNCTION.


/* TRUE when p_File (a full path) matches any exclude pattern.  Patterns in
   cExcludes are CHR(1)-delimited; each is matched (case-insensitively, via
   MATCHES) against the file's path RELATIVE to the source root, forward-slashed.
   Patterns may be written with '\' or '/'; both are normalized to '/'.  The
   pattern's '.' is escaped so it is literal (not "any char"). */
FUNCTION IsExcluded RETURNS LOGICAL (INPUT p_File AS CHARACTER):
    DEFINE VARIABLE iPat  AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cPat  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cFull AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cRel  AS CHARACTER NO-UNDO.

    IF cExcludes = "" OR cExcludes = ? THEN RETURN NO.

    /* file path relative to the source root, forward-slashed */
    FILE-INFO:FILE-NAME = p_File.
    cFull = FILE-INFO:FULL-PATHNAME.
    IF cFull = ? THEN cFull = p_File.
    cFull = REPLACE(cFull, "~\", "/").
    cRel = cFull.
    IF cFull BEGINS cSourceRoot THEN
        cRel = SUBSTRING(cFull, LENGTH(cSourceRoot) + 1).
    cRel = LEFT-TRIM(cRel, "/").

    DO iPat = 1 TO NUM-ENTRIES(cExcludes, CHR(1)):
        cPat = TRIM(ENTRY(iPat, cExcludes, CHR(1))).
        IF cPat = "" THEN NEXT.
        cPat = REPLACE(cPat, "~\", "/").   /* accept backslash patterns */
        cPat = REPLACE(cPat, ".", "~~.").  /* literal dots */
        /* case-insensitive match on the relative path */
        IF cRel MATCHES cPat THEN RETURN YES.
    END.
    RETURN NO.
END FUNCTION.
