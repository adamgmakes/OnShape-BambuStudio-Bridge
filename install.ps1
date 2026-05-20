# Onshape -> Bambu Studio bridge: interactive installer.
#
# Run from PowerShell in the repo root:
#   .\install.ps1
#
# This will:
#   1. Check for Python 3.10+
#   2. Create a venv and install dependencies
#   3. Prompt for Onshape API access key + secret
#   4. Detect Bambu Studio's install path
#   5. Write config.json (with restrictive ACLs)
#   6. Optionally install the auto-start shortcut

[CmdletBinding()]
param(
    [switch]$SkipAutostart
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerDir = Join-Path $RepoRoot 'server'
$ConfigPath = Join-Path $RepoRoot 'config.json'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# --- 1. Python check ---
Write-Step 'Checking for Python 3.10+'
$pythonCmd = $null
foreach ($candidate in @(@('py', '-3'), @('python'), @('python3'))) {
    try {
        $ver = & $candidate[0] $candidate[1..($candidate.Length - 1)] --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $ver -match 'Python (\d+)\.(\d+)') {
            $major = [int]$Matches[1]; $minor = [int]$Matches[2]
            if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 10)) {
                $pythonCmd = $candidate
                Write-Ok "Found: $ver"
                break
            }
        }
    } catch {}
}
if (-not $pythonCmd) {
    Write-Host 'Python 3.10+ not found. Install from https://www.python.org/downloads/ and re-run.' -ForegroundColor Red
    exit 1
}

# --- 2. venv + deps ---
Write-Step 'Creating virtual environment and installing dependencies'
$venvPath = Join-Path $ServerDir '.venv'
if (-not (Test-Path $venvPath)) {
    & $pythonCmd[0] $pythonCmd[1..($pythonCmd.Length - 1)] -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
}
$venvPip = Join-Path $venvPath 'Scripts\pip.exe'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
& $venvPip install -q -r (Join-Path $ServerDir 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install failed' }
Write-Ok 'Dependencies installed.'

# --- 3. Onshape credentials ---
Write-Step 'Onshape API credentials'
$existingCfg = $null
if (Test-Path $ConfigPath) {
    try { $existingCfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch {}
}
Write-Host '    Get a key pair at: https://dev-portal.onshape.com (API keys section)' -ForegroundColor Gray
$defaultAccess = if ($existingCfg) { $existingCfg.onshape_access_key } else { '' }
$defaultSecret = if ($existingCfg) { $existingCfg.onshape_secret_key } else { '' }

$promptAccess = if ($defaultAccess) { 'Access key [press Enter to keep existing]' } else { 'Access key' }
$access = Read-Host $promptAccess
if (-not $access) { $access = $defaultAccess }
if (-not $access) { Write-Host 'Access key is required.' -ForegroundColor Red; exit 1 }

$promptSecret = if ($defaultSecret) { 'Secret key [press Enter to keep existing]' } else { 'Secret key' }
$secureSecret = Read-Host $promptSecret -AsSecureString
$secret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret))
if (-not $secret) { $secret = $defaultSecret }
if (-not $secret) { Write-Host 'Secret key is required.' -ForegroundColor Red; exit 1 }

# --- 4. Bambu Studio path ---
Write-Step 'Locating Bambu Studio'
$bambuCandidates = @(
    'C:\Program Files\Bambu Studio\bambu-studio.exe',
    'C:\Program Files (x86)\Bambu Studio\bambu-studio.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\Bambu Studio\bambu-studio.exe')
)
$bambuPath = $bambuCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bambuPath -and $existingCfg) { $bambuPath = $existingCfg.bambu_studio_path }
if (-not $bambuPath) {
    $bambuPath = Read-Host 'Could not auto-detect. Full path to bambu-studio.exe'
}
if (-not (Test-Path $bambuPath)) {
    Write-Warn2 "Path '$bambuPath' does not exist. Saving anyway - edit config.json later."
} else {
    Write-Ok "Bambu Studio: $bambuPath"
}

# --- 5. Format choice ---
Write-Step 'Export format'
$fmt = Read-Host 'Format (3MF/STL) [3MF]'
if (-not $fmt) { $fmt = '3MF' }
$fmt = $fmt.ToUpper()
if ($fmt -ne '3MF' -and $fmt -ne 'STL') { $fmt = '3MF' }
Write-Ok "Format: $fmt"

# --- 6. Write config.json ---
Write-Step 'Writing config.json'
$cfg = [ordered]@{
    onshape_access_key = $access
    onshape_secret_key = $secret
    onshape_base_url   = 'https://cad.onshape.com'
    bambu_studio_path  = $bambuPath
    export_dir         = ''
    export_format      = $fmt
    port               = 7777
}
$cfg | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding utf8

# Best-effort ACL hardening: disable inheritance, grant only current user.
# Uses icacls (does not need SeSecurityPrivilege). Skipped silently if it fails;
# the parent directory's ACL is usually restrictive enough for a personal machine.
$icaclsOk = $false
try {
    & icacls $ConfigPath /inheritance:r /grant:r "$($env:USERNAME):(R,W)" *>$null
    if ($LASTEXITCODE -eq 0) { $icaclsOk = $true }
} catch {}
if ($icaclsOk) {
    Write-Ok "config.json written (ACL locked to $env:USERNAME)."
} else {
    Write-Ok 'config.json written.'
    Write-Warn2 'Could not lock ACL via icacls. File is still protected by your user profile directory permissions.'
}

# --- 7. Smoke test ---
Write-Step 'Testing Onshape API authentication'
& $venvPython (Join-Path $ServerDir 'smoke_test.py')
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Auth test failed. Check your API keys at https://dev-portal.onshape.com' -ForegroundColor Red
    exit 1
}

# --- 8. Autostart ---
if (-not $SkipAutostart) {
    Write-Step 'Auto-start on login'
    $answer = Read-Host 'Install to Windows Startup folder so the bridge runs at login? (Y/n)'
    if ($answer -eq '' -or $answer -match '^[Yy]') {
        $startup = [Environment]::GetFolderPath('Startup')
        $vbsDst = Join-Path $startup 'OnshapeBambuBridge.vbs'
        $batPath = Join-Path $ServerDir 'start-bridge.bat'
        # Build the launcher line-by-line so PS does not get confused by quoting.
        $lines = @(
            "' Auto-generated by install.ps1. Launches the Onshape -> Bambu bridge silently.",
            'Set sh = CreateObject("WScript.Shell")',
            "sh.CurrentDirectory = `"$ServerDir`"",
            "sh.Run `"`"`"$batPath`"`"`", 0, False"
        )
        $lines | Set-Content -Path $vbsDst -Encoding ascii
        Write-Ok "Installed: $vbsDst"
    }
}

# --- 9. Start now ---
Write-Step 'Starting bridge now'
$vbs = Join-Path $ServerDir 'start-bridge.vbs'
Start-Process wscript -ArgumentList "`"$vbs`"" -WindowStyle Hidden
Start-Sleep -Seconds 3
try {
    $h = Invoke-RestMethod -Uri 'http://127.0.0.1:7777/health' -TimeoutSec 5
    Write-Ok "Bridge is running. Export dir: $($h.export_dir)"
} catch {
    Write-Warn2 'Bridge did not respond. Check server/bridge.log for errors.'
}

Write-Host ''
Write-Host 'Setup complete. Next: install the Tampermonkey userscript.' -ForegroundColor Green
Write-Host '  1. Install Tampermonkey extension in your browser.' -ForegroundColor Gray
Write-Host '  2. Open userscript\onshape-bambu.user.js, copy its contents.' -ForegroundColor Gray
Write-Host '  3. Tampermonkey dashboard -> + (new script) -> paste -> save.' -ForegroundColor Gray
Write-Host '  4. Open a Part Studio on cad.onshape.com. Green button = bottom right.' -ForegroundColor Gray
