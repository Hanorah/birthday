@echo off
cd /d "%~dp0web"
echo Starting The Last Promise at http://localhost:8000
echo On your phone (same Wi-Fi): http://YOUR-PC-IP:8000  (find the IP with: ipconfig)
echo Keep this window open while playing. Close it to stop.
start "" http://localhost:8000
where python >nul 2>nul && (python -m http.server 8000 --bind 0.0.0.0) || (npx --yes serve -l 8000 .)
