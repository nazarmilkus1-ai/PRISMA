[CmdletBinding()]
param(
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Test-RequiredPath([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path $path)) {
        $failures.Add("Missing required path: $RelativePath")
        return $false
    }
    Write-Host "[ok] $RelativePath" -ForegroundColor Green
    return $true
}

Write-Host "PRISMA release verification" -ForegroundColor Cyan
Write-Host "Root: $root"

# Keep the documented PowerShell release command aligned with the CI release gates.
Push-Location $root
try {
    node scripts/verify-release.mjs
    if ($LASTEXITCODE -ne 0) { $failures.Add("Node release preflight failed") }

    node scripts/verify-architecture.mjs
    if ($LASTEXITCODE -ne 0) { $failures.Add("Architecture gate failed") }
} catch {
    $failures.Add("Node release gates could not run: $($_.Exception.Message)")
}
Pop-Location

@(
    "README.md",
    "docs/OPERATIONS.md",
    "bot/main.py",
    "bot/.env.example",
    "panel/package.json",
    "site/package.json",
    "minecraft-plugin/build.gradle.kts",
    "minecraft-plugin/gradlew.bat",
    "supabase/migrations"
) | ForEach-Object { [void](Test-RequiredPath $_) }

$trackedEnv = git -C $root ls-files | Where-Object {
    $_ -match '(^|/)\.env$|(^|/)\.env\.local$' -and (Test-Path (Join-Path $root $_))
}
if ($trackedEnv) {
    $failures.Add("Tracked environment files found: $($trackedEnv -join ', ')")
} else {
    Write-Host "[ok] No tracked .env files" -ForegroundColor Green
}

Push-Location $root
try {
    python -m compileall -q bot
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[ok] Python syntax" -ForegroundColor Green
    } else {
        $failures.Add("Python compileall failed")
    }
} catch {
    $failures.Add("Python is unavailable: $($_.Exception.Message)")
}
Pop-Location

# Runtime regression guards.
$forbidden = @(
    "phone_number",
    "minecraft_uuid",
    "mojang_uuid",
    "/activity_events",
    "/api/whitelist/add",
    "minecraft_nickname=ilike."
)
foreach ($needle in $forbidden) {
    $matches = git -C $root grep -n -I -- $needle -- ':!supabase/migrations/*' ':!docs/archive/*' ':!scripts/verify-release.ps1' 2>$null
    if ($matches) {
        $failures.Add("Forbidden legacy reference '$needle': $($matches -join ' | ')")
    } else {
        Write-Host "[ok] No active legacy reference: $needle" -ForegroundColor Green
    }
}

$nextPaths = @("panel/node_modules/.bin/next")
foreach ($relativePath in $nextPaths) {
    if (Test-Path (Join-Path $root $relativePath)) {
        Write-Host "[ok] $relativePath" -ForegroundColor Green
    } else {
        $warnings.Add("Dependencies are not installed: $relativePath")
    }
}

if (Test-Path (Join-Path $root "panel/node_modules")) {
    Push-Location (Join-Path $root "panel")
    try {
        npm run typecheck
        if ($LASTEXITCODE -eq 0) { Write-Host "[ok] Panel typecheck" -ForegroundColor Green }
        else { $failures.Add("Panel typecheck failed") }

        npm run build
        if ($LASTEXITCODE -eq 0) { Write-Host "[ok] Panel production build" -ForegroundColor Green }
        else { $failures.Add("Panel production build failed") }
    } catch {
        $failures.Add("Panel build error: $($_.Exception.Message)")
    }
    Pop-Location
}


if (Test-Path (Join-Path $root "site/node_modules")) {
    Push-Location (Join-Path $root "site")
    try {
        npm run typecheck
        if ($LASTEXITCODE -eq 0) { Write-Host "[ok] Site typecheck" -ForegroundColor Green }
        else { $failures.Add("Site typecheck failed") }

        npm run build
        if ($LASTEXITCODE -eq 0) { Write-Host "[ok] Site production build" -ForegroundColor Green }
        else { $failures.Add("Site production build failed") }
    } catch {
        $failures.Add("Site build error: $($_.Exception.Message)")
    }
    Pop-Location
} else {
    $warnings.Add("Site dependencies are not installed: site/node_modules")
}

$javaPath = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin/java.exe" } else { $null }
if ($javaPath -and (Test-Path $javaPath)) {
    Write-Host "[ok] Java: $env:JAVA_HOME" -ForegroundColor Green
    if (Test-Path (Join-Path $root "minecraft-plugin/gradlew.bat")) {
        Push-Location (Join-Path $root "minecraft-plugin")
        try {
            & .\gradlew.bat build --no-daemon
            if ($LASTEXITCODE -eq 0) { Write-Host "[ok] Minecraft plugin build" -ForegroundColor Green }
            else { $failures.Add("Minecraft plugin build failed") }
        } catch {
            $failures.Add("Minecraft plugin build error: $($_.Exception.Message)")
        }
        Pop-Location
    }
} else {
    $warnings.Add("Java 21 is not available through JAVA_HOME")
}

if ($failures.Count -gt 0) {
    Write-Host "`nFailures:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
}
if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
}

if ($failures.Count -gt 0 -or ($Strict -and $warnings.Count -gt 0)) {
    exit 1
}

Write-Host "`nRelease verification completed." -ForegroundColor Cyan
