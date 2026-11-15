@echo off
cd /d "%~dp0"
if not exist ".godot\imported" engine\godot.exe --headless --path . --import
start "" engine\godot.exe --path . --rendering-method gl_compatibility
