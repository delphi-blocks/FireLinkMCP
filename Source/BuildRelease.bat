@ECHO OFF
SETLOCAL

:: Delphi 13.0 Florence
set "BDSVER=37.0"

:: IDE root: the user hive first (custom -r profiles), then the machine-wide one
for /f "tokens=2,*" %%A in (
    'reg query "HKCU\SOFTWARE\Embarcadero\BDS\%BDSVER%" /v RootDir 2^>nul'
) do set "BDS=%%B"

if not defined BDS (
    for /f "tokens=2,*" %%A in (
        'reg query "HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\%BDSVER%" /v RootDir 2^>nul'
    ) do set "BDS=%%B"
)

if not defined BDS (
    echo ERROR: RAD Studio %BDSVER% not found in the registry.
    exit /b 1
)

REM remove any trailing backslash
if "%BDS:~-1%"=="\" set "BDS=%BDS:~0,-1%"

CALL "%BDS%\bin\rsvars.bat"
::::::::::::::::::::::::::::::::

:: Set Target, config and platform
SET "_TARGET=%~1"
IF "%_TARGET%"=="" SET "_TARGET=Rebuild"

SET "_CONFIG=%~2"
IF "%_CONFIG%"=="" SET "_CONFIG=Release"

SET "_PLATFORM=%~3"
IF "%_PLATFORM%"=="" SET "_PLATFORM=Win32"

:: Same folder seen from here, used to sign the executables below
SET "OUTDIR=%~dp0..\Bin\%_PLATFORM%"

:: Script used to sign executables; called only if it exists
SET "SIGNSCRIPT=%~dp0SignFile.bat"

SET "ERRORCOUNT=0"

ECHO ========================================================
ECHO ===  FireLink MCP - %_CONFIG% / %_PLATFORM% (%_TARGET%)
ECHO ========================================================

:: Build FIRELINKMCP.EXE - stdio transport, the one an MCP client launches
msbuild "%~dp0Stdio\FireLinkMCP.dproj" /t:%_TARGET% /p:config=%_CONFIG% /p:platform=%_PLATFORM%
IF ERRORLEVEL 1 (
  set /a ERRORCOUNT+=1
) ELSE (
  IF EXIST "%SIGNSCRIPT%" CALL "%SIGNSCRIPT%" "%OUTDIR%\FireLinkMCP.exe"
)

:: Build FIRELINKMCPINDY.EXE - HTTP transport (VCL GUI)
msbuild "%~dp0Indy\FireLinkMCPIndy.dproj" /t:%_TARGET% /p:config=%_CONFIG% /p:platform=%_PLATFORM%
IF ERRORLEVEL 1 (
  set /a ERRORCOUNT+=1
) ELSE (
  IF EXIST "%SIGNSCRIPT%" CALL "%SIGNSCRIPT%" "%OUTDIR%\FireLinkMCPIndy.exe"
)

IF %ERRORCOUNT% NEQ 0 (

  ECHO =============================================
  ECHO ===  %ERRORCOUNT% FireLink project^(s^) failed to compile
  ECHO =============================================
  EXIT /B 1

) ELSE (

  ECHO =============================================
  ECHO ===  FireLink MCP compiled successfully
  ECHO ===  Output: %OUTDIR%
  ECHO =============================================

)
