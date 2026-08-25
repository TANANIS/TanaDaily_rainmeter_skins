@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FetchActivityWatch.ps1" -OutputInc "%~dp0..\Data\activitywatch.inc" -CacheJson "%~dp0..\Data\activitywatch_cache.json"
set "AW_EXIT=%errorlevel%"
"%ProgramFiles%\Rainmeter\Rainmeter.exe" !Refresh "MistRainWorkbench\AppUsage"
exit /b %AW_EXIT%
