@echo off
setlocal enabledelayedexpansion
rem Full local type gate for ios/ComicCore on Windows (no Mac needed).
rem   Step 1: typecheck all Core sources as one module.
rem   Step 2: emit the module (-enable-testing) and typecheck the XCTest files against it.
rem Tests cannot RUN on Windows (no simulator); running them is CI's job (macos runner).
rem Usage: scripts\swift-check.bat   -> prints ALL_TYPECHECK_OK on success.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set "SW=C:\Users\AuraYoona\AppData\Local\Programs\Swift"
set "PATH=%SW%\Runtimes\6.4.1\usr\bin;%SW%\Toolchains\6.4.1+Asserts\usr\bin;%PATH%"
set "SDK=%SW%\Platforms\6.4.1\Windows.platform\Developer\SDKs\Windows.sdk"
set "XCT=%SW%\Platforms\6.4.1\Windows.platform\Developer\Library\XCTest-6.4.1\usr\lib\swift\windows"
set "TST=%SW%\Platforms\6.4.1\Windows.platform\Developer\Library\Testing-6.4.1\usr\lib\swift\windows"

cd /d "%~dp0..\ios\ComicCore"

set "SRC_FILES="
for /R "Sources\ComicReaderCore" %%f in (*.swift) do set SRC_FILES=!SRC_FILES! "%%f"
set "TEST_FILES="
for /R "Tests\ComicReaderCoreTests" %%f in (*.swift) do set TEST_FILES=!TEST_FILES! "%%f"

echo [1/2] typecheck sources...
swiftc -typecheck -module-name ComicReaderCore -sdk "%SDK%" !SRC_FILES!
if %ERRORLEVEL% NEQ 0 (
  echo TYPECHECK_FAILED: sources
  exit /b 1
)

echo [2/2] emit module and typecheck tests...
if exist build-tc rmdir /s /q build-tc
mkdir build-tc
swiftc -emit-module -enable-testing -module-name ComicReaderCore -sdk "%SDK%" !SRC_FILES! -emit-module-path build-tc\ComicReaderCore.swiftmodule
if %ERRORLEVEL% NEQ 0 (
  echo TYPECHECK_FAILED: module emit
  exit /b 1
)
swiftc -typecheck -module-name ComicReaderCoreTests -sdk "%SDK%" !TEST_FILES! -I build-tc -I "%XCT%" -I "%XCT%\x86_64" -I "%TST%"
if %ERRORLEVEL% NEQ 0 (
  echo TYPECHECK_FAILED: tests
  exit /b 1
)

echo ALL_TYPECHECK_OK
exit /b 0
