@echo off
rem Lance Arena LAN avec Godot 4.7 (Godot.exe dans ce dossier, sinon l'installation winget).
set "PROJ=%~dp0."
if exist "%~dp0Godot.exe" (
  start "" "%~dp0Godot.exe" --path "%PROJ%"
  exit /b
)
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
  for %%E in ("%%D\Godot_v*_win64.exe") do (
    echo %%~nxE | findstr /i /v "console" >nul && (
      start "" "%%E" --path "%PROJ%"
      exit /b
    )
  )
)
echo Godot introuvable. Copie Godot_v4.7.2-stable_win64.exe dans ce dossier et renomme-le Godot.exe
pause
