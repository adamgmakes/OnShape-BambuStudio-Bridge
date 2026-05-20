@echo off
cd /d "%~dp0"
echo [%date% %time%] starting bridge > bridge.log
".venv\Scripts\python.exe" main.py >> bridge.log 2>&1
echo [%date% %time%] bridge exited with code %ERRORLEVEL% >> bridge.log
