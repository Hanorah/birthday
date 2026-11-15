@echo off
cd /d "%~dp0"
echo The Last Promise (drive) running at http://localhost:8080 - keep this window open
start "" http://localhost:8080
where python >nul 2>nul && (python -m http.server 8080 --bind 0.0.0.0) || (npx --yes serve -l 8080 .)
