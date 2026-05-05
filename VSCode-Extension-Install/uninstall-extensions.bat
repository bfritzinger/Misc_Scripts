@echo off
REM uninstall-extensions.bat
REM Wrapper that runs uninstall-extensions.ps1 with -ExecutionPolicy Bypass.
REM See install-extensions.bat for details.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-extensions.ps1" %*
exit /b %ERRORLEVEL%
