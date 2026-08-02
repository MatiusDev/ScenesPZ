@echo off
REM Copy mods from this repo into %USERPROFILE%\Zomboid\mods for testing.
REM
REM Do NOT use mklink instead. On Linux, Project Zomboid resolves a symlinked mod
REM directory to its absolute target and then re-appends it to the mods folder,
REM producing paths like  Zomboid\mods\c\dev\scenespz\...  -- mod.info is still
REM found, so the mod REPORTS AS LOADED while every script silently fails.
REM Copying costs a second and removes the whole class of problem.
setlocal
set REPO=%~dp0..
set DEST=%USERPROFILE%\Zomboid\mods

for /d %%P in ("%REPO%\mods\*") do (
    for /d %%M in ("%%P\Contents\mods\*") do (
        echo syncing %%~nxM
        robocopy "%%M" "%DEST%\%%~nxM" /MIR /NFL /NDL /NJH /NJS /NP >nul
    )
)
echo.
echo Done. Restart Project Zomboid -- there is no hot reload.
endlocal
