@echo off
REM install-extensions.bat
REM Wrapper that runs install-extensions.ps1 with -ExecutionPolicy Bypass so
REM team members don't have to deal with PowerShell signing/MOTW errors.
REM
REM %~dp0 resolves to this script's directory, so this works regardless of
REM the caller's current working directory. %* forwards all arguments.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-extensions.ps1" %*
exit /b %ERRORLEVEL%
