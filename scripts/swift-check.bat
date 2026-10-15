@echo off
rem Swift 语法检查入口：加载 MSVC 环境后对 ios/ComicCore 全部源文件跑 swiftc -parse
rem 用法: scripts\swift-check.bat
rem 注意: 完整 swift build/test 需要能链接的运行时环境；本机目前只有 -parse 级别，
rem       完整测试由 CI (macos runner) 的 `swift test` 保证。

setlocal enabledelayedexpansion
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set "SW=C:\Users\AuraYoona\AppData\Local\Programs\Swift"
set "PATH=%SW%\Runtimes\6.4.1\usr\bin;%SW%\Toolchains\6.4.1+Asserts\usr\bin;%PATH%"
set "SDKROOT=%SW%\Platforms\6.4.1\Windows.platform\Developer\SDKs\Windows.sdk"

set "ROOT=%~dp0..\ios\ComicCore"
set FAIL=0
for /R "%ROOT%" %%f in (*.swift) do (
  swiftc -parse "%%f" 2>&1 | findstr /C:"error" >nul
  if !ERRORLEVEL! == 0 (
    echo PARSE_FAIL: %%f
    swiftc -parse "%%f" 2>&1 | findstr /C:"error"
    set FAIL=1
  )
)
if %FAIL% == 0 (
  echo ALL_PARSE_OK
  exit /b 0
) else (
  exit /b 1
)
