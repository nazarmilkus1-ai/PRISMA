[CmdletBinding()]
param(
    [switch]$InstallDependencies
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bot = Join-Path $root "bot"
$envFile = Join-Path $bot ".env"
$envExample = Join-Path $bot ".env.example"

Write-Host "PRISMA bot bootstrap" -ForegroundColor Cyan

foreach ($path in @(
    (Join-Path $bot "main.py"),
    (Join-Path $bot "requirements.txt"),
    $envExample
)) {
    if (-not (Test-Path $path)) {
        throw "Required bot file is missing: $path"
    }
}

if (-not (Test-Path $envFile)) {
    Copy-Item $envExample $envFile
    Write-Host "Created bot/.env from bot/.env.example. Fill in credentials before starting." -ForegroundColor Yellow
} else {
    Write-Host "Keeping existing bot/.env; source files are never overwritten." -ForegroundColor Green
}

if ($InstallDependencies) {
    $venv = Join-Path $bot "venv"
    if (-not (Test-Path (Join-Path $venv "Scripts/python.exe"))) {
        python -m venv $venv
    }
    & (Join-Path $venv "Scripts/python.exe") -m pip install --upgrade pip
    & (Join-Path $venv "Scripts/python.exe") -m pip install -r (Join-Path $bot "requirements.txt")
    Write-Host "Bot dependencies installed." -ForegroundColor Green
}

Write-Host "Bootstrap complete. Start with: python bot/main.py" -ForegroundColor Cyan
