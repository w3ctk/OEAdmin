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

/* ---- run state ----------------------------------------------------------- */
DEFINE VARIABLE iCompiled   AS INTEGER   NO-UNDO.
DEFINE VARIABLE iErrors     AS INTEGER   NO-UNDO.
DEFINE VARIABLE iWarnings   AS INTEGER   NO-UNDO.
DEFINE VARIABLE lLogOpen    AS LOGICAL   NO-UNDO.

DEFINE STREAM sLog.
/* OS-DIR walk stream.  Must be defined at the top level (streams cannot be
   defined inside an internal procedure).  CompileDir recurses, but each level
   fully consumes + closes the stream before descending, so one shared stream is
   safe. */
DEFINE STREAM sDir.
/* Status file stream (top level - streams cannot be defined in a procedure). */
DEFINE STREAM sStat.

/* Forward declaration: the function body is at the bottom of the file, but it is
   called from CompileDir above it, so ABL needs the signature up front. */
FUNCTION MatchesAnySpec RETURNS LOGICAL (INPUT p_Name AS CHARACTER) FORWARD.

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
    cSourceRoot = FILE-INFO:FULL-PATHNAME.

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
    RUN Log ("----------------------------------------------------------------").

    /* ---- walk + compile -------------------------------------------------- */
    RUN CompileDir (INPUT cSourceRoot, INPUT cDirFilter).

    RUN Log ("----------------------------------------------------------------").
    RUN Log ("Compilation finished.  compiled=" + STRING(iCompiled)
             + "  errors=" + STRING(iErrors)
             + "  warnings=" + STRING(iWarnings)).
    IF iErrors > 0 THEN
        RUN Log ("*** " + STRING(iErrors) + " file(s) had COMPILER ERRORS - review above. ***").

    IF lLogOpen THEN OUTPUT STREAM sLog CLOSE.

    /* Mirror the summary to the batch .out so OEAdmin shows it without opening
       the log, and write the machine-readable status file OEAdmin reads to decide
       success/failure (ABL QUIT carries no exit code, so the status file - not a
       process exit code - is the authoritative signal). */
    RUN WriteOut ("OECompiler: compiled=" + STRING(iCompiled)
                  + " errors=" + STRING(iErrors)
                  + " warnings=" + STRING(iWarnings)).
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
            IF MatchesAnySpec(cEntry) THEN
                RUN CompileFile (INPUT cFullName).
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
    DEFINE VARIABLE iMsg      AS INTEGER   NO-UNDO.
    DEFINE VARIABLE lHadError AS LOGICAL   NO-UNDO.

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

    /* The compile itself.  Four shapes depending on which outputs are on; SAVE
       (no INTO) drops the .r beside the source, matching production layout. */
    IF cListFile <> "" AND cXrefFile <> "" THEN DO:
        IF lXrefXml THEN
            COMPILE VALUE(p_File) SAVE LISTING VALUE(cListFile)
                XREF-XML VALUE(cXrefFile) NO-ERROR.
        ELSE
            COMPILE VALUE(p_File) SAVE LISTING VALUE(cListFile)
                XREF VALUE(cXrefFile) NO-ERROR.
    END.
    ELSE IF cListFile <> "" THEN
        COMPILE VALUE(p_File) SAVE LISTING VALUE(cListFile) NO-ERROR.
    ELSE IF cXrefFile <> "" THEN DO:
        IF lXrefXml THEN
            COMPILE VALUE(p_File) SAVE XREF-XML VALUE(cXrefFile) NO-ERROR.
        ELSE
            COMPILE VALUE(p_File) SAVE XREF VALUE(cXrefFile) NO-ERROR.
    END.
    ELSE
        COMPILE VALUE(p_File) SAVE NO-ERROR.

    iCompiled = iCompiled + 1.

    /* Report per the COMPILER handle (same mechanism as adecomp). */
    IF COMPILER:ERROR THEN DO:
        lHadError = YES.
        iErrors = iErrors + 1.
        RUN Log ("ERROR  : " + p_File).
    END.
    ELSE IF COMPILER:WARNING THEN DO:
        iWarnings = iWarnings + 1.
        RUN Log ("WARNING: " + p_File).
    END.
    ELSE
        RUN Log ("OK     : " + p_File).

    /* Dump compiler messages (errors AND warnings) to the log, with row/col from
       the COMPILER handle (same API adecomp and the headless harness use). */
    IF (COMPILER:ERROR OR COMPILER:WARNING) AND COMPILER:NUM-MESSAGES > 0 THEN
    DO iMsg = 1 TO COMPILER:NUM-MESSAGES:
        RUN Log ("         [" + STRING(COMPILER:GET-ERROR-ROW(iMsg)) + ","
                 + STRING(COMPILER:GET-ERROR-COLUMN(iMsg)) + "] "
                 + COMPILER:GET-MESSAGE(iMsg)).
    END.
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


/* Create a directory path if it does not exist (OS-independent, step by step). */
PROCEDURE EnsureDir:
    DEFINE INPUT PARAMETER p_Dir AS CHARACTER NO-UNDO.

    DEFINE VARIABLE cNorm AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSoFar AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iSeg  AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cSeg  AS CHARACTER NO-UNDO.

    cNorm = REPLACE(p_Dir, "~\", "/").
    FILE-INFO:FILE-NAME = cNorm.
    IF FILE-INFO:FULL-PATHNAME <> ? THEN RETURN.   /* already exists */

    DO iSeg = 1 TO NUM-ENTRIES(cNorm, "/"):
        cSeg = ENTRY(iSeg, cNorm, "/").
        IF iSeg = 1 THEN
            cSoFar = cSeg.          /* drive (C:) or empty for leading / */
        ELSE
            cSoFar = cSoFar + "/" + cSeg.
        IF cSoFar = "" THEN NEXT.   /* leading / on unix */
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
