# Windows-Ersatz für das Makefile (PowerShell).
# Aufruf aus dem Ordner marktradar:   .\tasks.ps1 pipeline
# Falls Skripte blockiert sind:        powershell -ExecutionPolicy Bypass -File .\tasks.ps1 pipeline
param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "lint", "test", "pipeline", "serve", "docker")]
    [string]$Task = "pipeline"
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Run([string]$cmd) {
    Write-Host ">> $cmd" -ForegroundColor Cyan
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) { throw "Fehlgeschlagen: $cmd" }
}

switch ($Task) {
    "install"  { Run "uv sync" }
    "lint"     { Run "uv run ruff format --check ."; Run "uv run ruff check ."; Run "uv run mypy src" }
    "test"     { Run "uv run pytest" }
    "pipeline" { Run "uv sync"; Run "uv run marktradar download"; Run "uv run marktradar build"; Run "uv run marktradar train" }
    "serve"    { Run "uv run marktradar serve --host 127.0.0.1" }
    "docker"   { Run "docker build -t marktradar ."; Run "docker run --rm -p 8000:8000 marktradar" }
}
