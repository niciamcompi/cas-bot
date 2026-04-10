#!/usr/bin/env bash
set -e

# Use BASH_SOURCE which handles spaces in paths correctly on double-click
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing/updating dependencies..."
cd "$PROJECT_DIR"
uv sync

echo "Starting backend server in the background..."
uv run uvicorn app.main:app > /dev/null 2>&1 &
BACKEND_PID=$!

sleep 1
clear
uv run -m app.cli

echo "CLI exited. Stopping backend server..."
kill "$BACKEND_PID" 2>/dev/null
