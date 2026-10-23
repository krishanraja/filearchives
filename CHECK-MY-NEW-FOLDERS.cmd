@echo off
rem Run this week's folder check-in now: it asks about any new folder.
rem Nothing on your drives is moved, renamed or deleted.
setlocal
set "REPO=%~dp0"
if not exist "%REPO%.git" set "REPO=C:\Users\krish\dev\krishanraja\filearchives\"
if not exist "%REPO%.git" (
  echo Could not find the filearchives folder. Expected it at %REPO%
  pause
  exit /b 1
)
where pwsh >nul 2>nul || (
  echo PowerShell 7 is not installed on this PC, so this cannot run yet.
  pause
  exit /b 1
)
for /f %%b in ('git -C "%REPO%." rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"
if not "%BRANCH%"=="main" (
  rem Switch to main only when nothing can be lost: no unsaved changes, and
  rem everything on this branch is already in main on GitHub.
  git -C "%REPO%." fetch origin main
  git -C "%REPO%." diff --quiet HEAD
  if errorlevel 1 goto notmain
  git -C "%REPO%." merge-base --is-ancestor HEAD origin/main
  if errorlevel 1 goto notmain
  echo Switching the filearchives folder from %BRANCH% to main. Its work is already in main.
  git -C "%REPO%." checkout main
  if errorlevel 1 goto notmain
)
echo Getting the latest filearchives from GitHub...
git -C "%REPO%." pull --ff-only origin main
if errorlevel 1 (
  echo Could not update filearchives from GitHub. Nothing was changed.
  pause
  exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%REPO%chains\chain_weekly_folder_checkin.ps1"
pause
exit /b 0

:notmain
echo The filearchives folder is on branch %BRANCH%, not main, and switching could lose work. Nothing was changed.
pause
exit /b 1
