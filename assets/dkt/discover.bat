@echo off
setlocal EnableExtensions EnableDelayedExpansion

@REM CommonsBase_Build.Toolchain.Discover.MSVC probe.
@REM
@REM Provider contract (see CommonsBase_Build dk.u, "Toolchain discovery"):
@REM   discover.bat --abi <TARGET_ABI> [--config <path>]
@REM Emits UTF-8 LF KEY=VALUE lines on stdout. On success writes nothing to
@REM stderr. On failure writes the one-line contract error followed by every
@REM location searched and command line tried, then exits nonzero.
@REM
@REM Generalizes CommonsLang_OCaml assets/dkml/detect-vsenv.bat: same
@REM VsDevCmd-shaped and DKML_COMPILE_VS_* emissions, same
@REM -version [16.0,19.0) window, plus a vcvarsall capture of the full
@REM INCLUDE/LIB/LIBPATH/PATH environment and the toolchains.jsonc overrides.
@REM
@REM Requires VSWHERE to point at the packaged
@REM CommonsBase_Build.VSWhere@3.1.7 vswhere.exe (set by the build rule).
@REM
@REM Configuration precedence: --config path, else the project-level
@REM etc\dk\t\toolchains.jsonc under the current directory, else the
@REM user/machine-level %LOCALAPPDATA%\dk\toolchains.jsonc, else the host
@REM probe. Honored keys: "vs_dir" (skips the vswhere search),
@REM "msvs_preference" (re-emitted as MSVS_PREFERENCE for msvs-detect).
@REM
@REM DRAFT limitation (pending section+glob matching, next increment): config
@REM keys are read with a line-oriented scan, blind to which toolchains
@REM section a key sits in. A value beginning with $( is a dk value
@REM expression and must be resolved by
@REM `dk0 dialog CommonsBase_Build.Toolchain.Discover.MSVC` or replaced with
@REM a literal path.

set "CONTRACT_SEE=See "System toolchains (per-ABI contract)" in DK0-REFERENCE."

set "DK_TC_ABI="
set "DK_TC_CONFIG="
:parseargs
if "%~1"=="" goto doneargs
if /i "%~1"=="--abi" (
    set "DK_TC_ABI=%~2"
    shift
    shift
    goto parseargs
)
if /i "%~1"=="--config" (
    set "DK_TC_CONFIG=%~2"
    shift
    shift
    goto parseargs
)
echo dk toolchain: unknown argument %~1 1>&2
exit /b 2
:doneargs
if not defined DK_TC_ABI (
    echo dk toolchain: --abi ^<TARGET_ABI^> is required 1>&2
    exit /b 2
)

@REM Diagnostics accumulate here and are printed to stderr only on failure.
set "DK_TC_DIAG=%TEMP%\dk-tc-diag-%RANDOM%%RANDOM%.txt"
break> "%DK_TC_DIAG%"

@REM Map the target ABI to a vcvarsall architecture. The MSVC probe serves
@REM Windows ABIs only.
set "VCARCH="
if /i "%DK_TC_ABI%"=="Windows_x86_64" set "VCARCH=x64"
if /i "%DK_TC_ABI%"=="Windows_x86" set "VCARCH=x86"
if /i "%DK_TC_ABI%"=="Windows_arm64" set "VCARCH=arm64"
if not defined VCARCH (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: the MSVC probe serves Windows ABIs only. %CONTRACT_SEE%
    goto faildiag
)

set "VSWHERE_EXE=%VSWHERE%"
>> "%DK_TC_DIAG%" echo   vswhere: "%VSWHERE_EXE%"
if not exist "%VSWHERE_EXE%" (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: VSWHERE must point to the packaged CommonsBase_Build.VSWhere vswhere.exe. %CONTRACT_SEE%
    goto faildiag
)

if not defined DK_TC_CONFIG (
    if exist "etc\dk\t\toolchains.jsonc" set "DK_TC_CONFIG=etc\dk\t\toolchains.jsonc"
)
if not defined DK_TC_CONFIG (
    if exist "%LOCALAPPDATA%\dk\toolchains.jsonc" set "DK_TC_CONFIG=%LOCALAPPDATA%\dk\toolchains.jsonc"
)
if defined DK_TC_CONFIG (
    >> "%DK_TC_DIAG%" echo   config: "%DK_TC_CONFIG%"
) else (
    >> "%DK_TC_DIAG%" echo   config: none found ^(etc\dk\t\toolchains.jsonc, %%LOCALAPPDATA%%\dk\toolchains.jsonc^)
)

set "CFG_VS_DIR="
set "CFG_MSVS_PREFERENCE="
if defined DK_TC_CONFIG (
    for /f "usebackq tokens=1,* delims=:" %%A in (`findstr /r /c:"\"vs_dir\"" "%DK_TC_CONFIG%" 2^>nul`) do set "CFG_VS_DIR=%%B"
    for /f "usebackq tokens=1,* delims=:" %%A in (`findstr /r /c:"\"msvs_preference\"" "%DK_TC_CONFIG%" 2^>nul`) do set "CFG_MSVS_PREFERENCE=%%B"
    if defined CFG_VS_DIR call :trimjson CFG_VS_DIR
    if defined CFG_MSVS_PREFERENCE call :trimjson CFG_MSVS_PREFERENCE
)
if defined CFG_VS_DIR if "!CFG_VS_DIR:~0,2!"=="$(" (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: config key "vs_dir" is a dk value expression; run 'dk0 dialog CommonsBase_Build.Toolchain.Discover.MSVC' to resolve it, or replace it with a literal path. %CONTRACT_SEE%
    goto faildiag
)

@REM The vswhere calls stay outside parenthesized blocks: the ) in the
@REM -version [16.0,19.0) range would close a block early.
if defined CFG_VS_DIR goto vsdirprobe

>> "%DK_TC_DIAG%" echo   ran: "%VSWHERE_EXE%" -latest -version [16.0,19.0) -products * -requires ...VC.Tools.x86.x64 -property installationPath
set "VSW_TMP=%TEMP%\dk-tc-vswhere-%RANDOM%.txt"
"%VSWHERE_EXE%" -latest -version [16.0,19.0) -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%VSW_TMP%" 2>nul
if exist "%VSW_TMP%" set /p INSTALLPATH=<"%VSW_TMP%"
del "%VSW_TMP%" >nul 2>nul
set "VSW_TMP=%TEMP%\dk-tc-vswhere-%RANDOM%.txt"
"%VSWHERE_EXE%" -latest -version [16.0,19.0) -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion > "%VSW_TMP%" 2>nul
if exist "%VSW_TMP%" set /p INSTALLVERSION=<"%VSW_TMP%"
del "%VSW_TMP%" >nul 2>nul
goto haveinstall

:vsdirprobe
>> "%DK_TC_DIAG%" echo   ran: "%VSWHERE_EXE%" -path "%CFG_VS_DIR%" -property installationVersion  ^(vs_dir override^)
set "INSTALLPATH=%CFG_VS_DIR%"
set "VSW_TMP=%TEMP%\dk-tc-vswhere-%RANDOM%.txt"
"%VSWHERE_EXE%" -path "%CFG_VS_DIR%" -property installationVersion > "%VSW_TMP%" 2>nul
if exist "%VSW_TMP%" set /p INSTALLVERSION=<"%VSW_TMP%"
del "%VSW_TMP%" >nul 2>nul

:haveinstall

if not defined INSTALLPATH (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: no Visual Studio installation with the C++ workload was found; install Visual Studio Build Tools with the C++ workload. %CONTRACT_SEE%
    goto faildiag
)
>> "%DK_TC_DIAG%" echo   installationPath: "%INSTALLPATH%"
if not defined INSTALLVERSION (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: found "%INSTALLPATH%" but could not read its installation version. %CONTRACT_SEE%
    goto faildiag
)

set "DKML_COMPILE_VS_DIR=%INSTALLPATH%"

>> "%DK_TC_DIAG%" echo   searched: "%INSTALLPATH%\VC\Tools\MSVC" for the toolset version
set "VCTOOLSVERSION="
if exist "%INSTALLPATH%\VC\Tools\MSVC" (
    for /f "delims=" %%I in ('dir /b /ad /o-n "%INSTALLPATH%\VC\Tools\MSVC" 2^>nul') do if not defined VCTOOLSVERSION set "VCTOOLSVERSION=%%I"
)

>> "%DK_TC_DIAG%" echo   searched: "%ProgramFiles(x86)%\Windows Kits\10\Include" for the SDK version
set "WINDOWSSDKVERSION="
if exist "%ProgramFiles(x86)%\Windows Kits\10\Include" (
    for /f "delims=" %%I in ('dir /b /ad /o-n "%ProgramFiles(x86)%\Windows Kits\10\Include" 2^>nul') do if not defined WINDOWSSDKVERSION set "WINDOWSSDKVERSION=%%I"
)

set "VSMAJOR="
set "VSMINOR=0"
for /f "tokens=1,2 delims=." %%A in ("%INSTALLVERSION%") do (
    if not defined VSMAJOR set "VSMAJOR=%%A"
    if not "%%B"=="" set "VSMINOR=%%B"
)
if not defined VSMAJOR (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: failed to parse the Visual Studio major version from "%INSTALLVERSION%". %CONTRACT_SEE%
    goto faildiag
)

set "VISUALSTUDIOMAJOR=%VSMAJOR%"
set /a VSMAJOR_INT=%VSMAJOR% >nul 2>nul
if not errorlevel 1 if %VSMAJOR_INT% GTR 18 set "VISUALSTUDIOMAJOR=18"

echo VSINSTALLDIR=%INSTALLPATH%\
echo DKML_COMPILE_VS_DIR=%DKML_COMPILE_VS_DIR%
if defined VCTOOLSVERSION (
    echo VCToolsVersion=%VCTOOLSVERSION%
    for /f "tokens=1,2 delims=." %%A in ("%VCTOOLSVERSION%") do if not "%%A"=="" if not "%%B"=="" echo DKML_COMPILE_VS_VCVARSVER=%%A.%%B
)
if defined WINDOWSSDKVERSION (
    echo WindowsSDKVersion=%WINDOWSSDKVERSION%\
    echo DKML_COMPILE_VS_WINSDKVER=%WINDOWSSDKVERSION%
)
echo VSCMD_VER=%VSMAJOR%.%VSMINOR%
echo VisualStudioVersion=%VISUALSTUDIOMAJOR%.0
echo DKML_COMPILE_VS_MSVSPREFERENCE=VS%VSMAJOR%.%VSMINOR%
if defined CFG_MSVS_PREFERENCE echo MSVS_PREFERENCE=!CFG_MSVS_PREFERENCE!

if "%VISUALSTUDIOMAJOR%"=="11" (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 11 2012
) else if "%VISUALSTUDIOMAJOR%"=="12" (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 13 2013
) else if "%VISUALSTUDIOMAJOR%"=="14" (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 14 2015
) else if "%VISUALSTUDIOMAJOR%"=="15" (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 15 2017
) else if "%VISUALSTUDIOMAJOR%"=="16" (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 16 2019
) else if "%VISUALSTUDIOMAJOR%"=="17" (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 17 2022
) else (
    echo DKML_COMPILE_VS_CMAKEGENERATOR=Visual Studio 18 2026
)

@REM Full environment capture: run vcvarsall for the target architecture and
@REM emit INCLUDE/LIB/LIBPATH/PATH so a build task consumes them and skips
@REM vcvarsall itself. This is the environment the dialog caches into
@REM resolved.jsonc.
set "VCVARSALL=%INSTALLPATH%\VC\Auxiliary\Build\vcvarsall.bat"
>> "%DK_TC_DIAG%" echo   ran: "%VCVARSALL%" %VCARCH%
if not exist "%VCVARSALL%" (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: vcvarsall.bat not found under "%INSTALLPATH%". %CONTRACT_SEE%
    goto faildiag
)
call "%VCVARSALL%" %VCARCH% >nul 2>nul
if errorlevel 1 (
    >&2 echo dk toolchain: Release.%DK_TC_ABI%: vcvarsall.bat %VCARCH% failed; the %VCARCH% toolset may not be installed. %CONTRACT_SEE%
    goto faildiag
)
echo INCLUDE=%INCLUDE%
echo LIB=%LIB%
echo LIBPATH=%LIBPATH%
echo PATH=%PATH%

del "%DK_TC_DIAG%" >nul 2>nul
exit /b 0

:faildiag
if exist "%DK_TC_DIAG%" >&2 type "%DK_TC_DIAG%"
del "%DK_TC_DIAG%" >nul 2>nul
exit /b 1

:trimjson
@REM Strip a JSONC line remainder in-place: leading/trailing spaces, a
@REM trailing comma, all double quotes, and JSON \\ escapes.
set "V=!%~1!"
:trimlead
if "!V:~0,1!"==" " set "V=!V:~1!" & goto trimlead
:trimtail
if "!V:~-1!"==" " set "V=!V:~0,-1!" & goto trimtail
if "!V:~-1!"=="," set "V=!V:~0,-1!" & goto trimtail
set V=!V:"=!
set "V=!V:\\=\!"
set "%~1=!V!"
exit /b 0
