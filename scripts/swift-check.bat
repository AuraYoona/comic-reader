@echo off
setlocal enabledelayedexpansion
rem Local type gate for the iOS port on Windows (no Mac needed). ASCII-only on purpose:
rem cmd.exe parses .bat bytes with the OEM codepage, so non-ASCII comments can corrupt parsing.
rem   Step 1: typecheck all ComicCore sources as one module.
rem   Step 2: emit the module (-enable-testing) and typecheck the XCTest files against it.
rem   Step 3: parse-check the App layer (UIKit/SwiftUI cannot typecheck on Windows, but syntax errors can be caught).
rem XCTest cannot RUN on Windows; running the tests is CI's job (macOS runner).
rem Usage: scripts\swift-check.bat  -> prints ALL_TYPECHECK_OK on success.

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set "SW=C:\Users\AuraYoona\AppData\Local\Programs\Swift"
set "PATH=%SW%\Runtimes\6.4.1\usr\bin;%SW%\Toolchains\6.4.1+Asserts\usr\bin;%PATH%"
set "SDK=%SW%\Platforms\6.4.1\Windows.platform\Developer\SDKs\Windows.sdk"
set "XCT=%SW%\Platforms\6.4.1\Windows.platform\Developer\Library\XCTest-6.4.1\usr\lib\swift\windows"
set "TST=%SW%\Platforms\6.4.1\Windows.platform\Developer\Library\Testing-6.4.1\usr\lib\swift\windows"

set "REPO=%~dp0.."
pushd "%REPO%\ios\ComicCore" || exit /b 1

set "SRC_FILES="
for /R "Sources\ComicReaderCore" %%f in (*.swift) do set SRC_FILES=!SRC_FILES! "%%f"
set "TEST_FILES="
for /R "Tests\ComicReaderCoreTests" %%f in (*.swift) do set TEST_FILES=!TEST_FILES! "%%f"

echo [1/3] typecheck sources...
swiftc -typecheck -module-name ComicReaderCore -sdk "%SDK%" !SRC_FILES!
if %ERRORLEVEL% NEQ 0 (
  echo TYPECHECK_FAILED: sources
  popd
  exit /b 1
)

echo [2/3] emit module and typecheck tests...
if exist build-tc rmdir /s /q build-tc
mkdir build-tc
swiftc -emit-module -enable-testing -module-name ComicReaderCore -sdk "%SDK%" !SRC_FILES! -emit-module-path build-tc\ComicReaderCore.swiftmodule
if %ERRORLEVEL% NEQ 0 (
  echo TYPECHECK_FAILED: module emit
  popd
  exit /b 1
)
swiftc -typecheck -module-name ComicReaderCoreTests -sdk "%SDK%" !TEST_FILES! -I build-tc -I "%XCT%" -I "%XCT%\x86_64" -I "%TST%"
if %ERRORLEVEL% NEQ 0 (
  echo TYPECHECK_FAILED: tests
  popd
  exit /b 1
)

echo [3/3] parse-check App layer...
set "APP_FAIL=0"
for /R "%REPO%\ios\App" %%f in (*.swift) do (
  swiftc -parse -sdk "%SDK%" "%%f" 2>&1 | findstr /C:"error" >nul
  if !ERRORLEVEL! == 0 (
    echo PARSE_FAIL: %%f
    swiftc -parse -sdk "%SDK%" "%%f" 2>&1 | findstr /C:"error"
    set APP_FAIL=1
  )
)
if !APP_FAIL! == 1 (
  echo TYPECHECK_FAILED: app parse
  popd
  exit /b 1
)

popd
echo ALL_TYPECHECK_OK
exit /b 0
