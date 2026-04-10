@echo off
cd /d "%~dp0"

echo Installing/updating dependencies...
uv sync

echo Starting backend server in the background...
start /b uv run uvicorn app.main:app > nul 2>&1

timeout /t 1 /nobreak > nul
cls
uv run -m app.cli

echo CLI exited. Stopping backend server...
taskkill /f /im uvicorn.exe > nul 2>&1
