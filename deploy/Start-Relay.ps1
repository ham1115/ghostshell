#Requires -Version 5.1
<#
.SYNOPSIS
    Build and start GHOSTSHELL :: Relay Nine on this Windows laptop and make
    it reachable by other machines on the same network.

.DESCRIPTION
    Does the whole venue sequence in one go:

      1. checks Docker is installed and actually running
      2. writes docker-compose.override.yml with the chosen port binding,
         so the committed docker-compose.yml is never edited
      3. builds the image (skip with -NoBuild)
      4. starts the relay and waits for SSH to answer
      5. adds a Windows Firewall rule for the port, if running as admin
      6. prints the exact ssh command to read out to the room

    Run it again any time; every step is idempotent.

.PARAMETER Port
    Host port players connect to. Default 2222. The relay always listens on
    2222 inside the container; this only changes the published port.

.PARAMETER LocalOnly
    Bind to 127.0.0.1 instead of all interfaces. Only this laptop can play.
    No firewall rule is needed or added.

.PARAMETER Name
    Compose project and container name. Default "ghostshell". Give each team
    its own name and port to run several isolated relays on one laptop.

.PARAMETER FirewallProfile
    Which Windows Firewall profiles the rule applies to: Private (default),
    Domain, Public, or Any. Use Any if you cannot set the event Wi-Fi to a
    Private network.

.PARAMETER NoBuild
    Skip the build and start the existing image.

.PARAMETER SkipFirewall
    Do not touch Windows Firewall. Print the command instead.

.EXAMPLE
    .\deploy\Start-Relay.ps1
    Build, start, publish on 2222 to the LAN, print the ssh line.

.EXAMPLE
    .\deploy\Start-Relay.ps1 -Name team-b -Port 2223 -NoBuild
    A second, isolated relay for another team on port 2223.

.EXAMPLE
    .\deploy\Start-Relay.ps1 -LocalOnly
    Solo play on this laptop only.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int]$Port = 2222,
    [switch]$LocalOnly,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$Name = 'ghostshell',
    [ValidateSet('Private', 'Domain', 'Public', 'Any')][string]$FirewallProfile = 'Private',
    [switch]$NoBuild,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------
function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TcpPort {
    param([string]$ComputerName, [int]$ComputerPort, [int]$TimeoutMs = 1000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $ComputerPort, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { $client.Close() }
}

# Writes UTF-8 with no byte-order mark. PowerShell 5.1's -Encoding UTF8 adds a
# BOM, which some YAML parsers reject at the top of a file.
function Write-TextFile {
    param([string]$LiteralPath, [string]$Content)
    [System.IO.File]::WriteAllText(
        $LiteralPath, $Content, (New-Object System.Text.UTF8Encoding $false))
}

# --------------------------------------------------------------------------
# Locate the repository (this script lives in <repo>\deploy)
# --------------------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRoot 'docker-compose.yml'))) {
    Write-Err "Could not find docker-compose.yml above $PSScriptRoot."
    Write-Err 'Run this script from inside a clone of the ghostshell repository.'
    exit 1
}
Push-Location $RepoRoot
try {
    Write-Host ''
    Write-Host '  GHOSTSHELL :: Relay Nine — venue start' -ForegroundColor White
    Write-Host "  repository: $RepoRoot" -ForegroundColor DarkGray

    # ----------------------------------------------------------------------
    # 1. Docker
    # ----------------------------------------------------------------------
    Write-Step 'Checking Docker'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Err 'Docker is not installed, or not on PATH.'
        Write-Err 'Install Docker Desktop: https://www.docker.com/products/docker-desktop/'
        exit 1
    }
    $serverVersion = (& docker info --format '{{.ServerVersion}}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serverVersion)) {
        Write-Err 'Docker is installed but the engine is not responding.'
        Write-Err 'Start Docker Desktop and wait for the whale icon to stop animating, then re-run.'
        exit 1
    }
    Write-Ok "Docker engine $serverVersion"

    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'This Docker has no "docker compose" (v2) command.'
        Write-Err 'Update Docker Desktop — the build needs BuildKit and Compose v2.'
        exit 1
    }

    # ----------------------------------------------------------------------
    # 2. Port binding override
    # ----------------------------------------------------------------------
    Write-Step 'Writing port binding'
    $bindAddress = if ($LocalOnly) { '127.0.0.1' } else { '0.0.0.0' }
    $overridePath = Join-Path $RepoRoot 'docker-compose.override.yml'
    $override = @"
# Generated by deploy\Start-Relay.ps1 — safe to delete.
# Compose merges this over docker-compose.yml, so the committed file stays
# untouched and ``git status`` stays clean.
services:
  ghostshell:
    container_name: $Name
    ports:
      - "${bindAddress}:${Port}:2222"
"@
    Write-TextFile -LiteralPath $overridePath -Content $override
    if ($LocalOnly) {
        Write-Ok "127.0.0.1:$Port — this laptop only"
    } else {
        Write-Ok "0.0.0.0:$Port — reachable from the network"
    }

    # ----------------------------------------------------------------------
    # 3. Build
    # ----------------------------------------------------------------------
    if ($NoBuild) {
        Write-Step 'Skipping build (-NoBuild)'
    } else {
        Write-Step 'Building the relay image (first run takes a few minutes)'
        & docker compose --project-name $Name build
        if ($LASTEXITCODE -ne 0) {
            Write-Err 'Build failed. Scroll up for the first error.'
            Write-Err 'If it mentions "bad interpreter" or line endings, see RUNNING.md.'
            exit 1
        }
        Write-Ok 'Image built'
    }

    # ----------------------------------------------------------------------
    # 4. Start and wait
    # ----------------------------------------------------------------------
    Write-Step 'Starting the relay'
    & docker compose --project-name $Name up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'Failed to start.'
        Write-Err "If the port is taken, re-run with a different -Port (e.g. -Port 2322)."
        exit 1
    }

    $ready = $false
    foreach ($attempt in 1..30) {
        if (Test-TcpPort -ComputerName '127.0.0.1' -ComputerPort $Port) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if ($ready) {
        Write-Ok "SSH is answering on port $Port"
    } else {
        Write-Warn "Port $Port is not answering yet. Check the logs:"
        Write-Warn "  docker compose --project-name $Name logs"
    }

    # ----------------------------------------------------------------------
    # 5. Firewall
    # ----------------------------------------------------------------------
    if ($LocalOnly) {
        Write-Step 'Skipping firewall (local-only binding needs no rule)'
    } elseif ($SkipFirewall) {
        Write-Step 'Skipping firewall (-SkipFirewall)'
    } else {
        Write-Step 'Windows Firewall'
        $ruleName = "GHOSTSHELL CTF ($Name, port $Port)"
        $profileValue = if ($FirewallProfile -eq 'Any') { 'Any' } else { $FirewallProfile }
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Ok "Rule already present: $ruleName"
        } elseif (Test-Admin) {
            try {
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound `
                    -Protocol TCP -LocalPort $Port -Action Allow `
                    -Profile $profileValue -ErrorAction Stop | Out-Null
                Write-Ok "Added inbound rule for TCP $Port (profile: $profileValue)"
            } catch {
                Write-Warn "Could not add the rule: $($_.Exception.Message)"
            }
        } else {
            Write-Warn 'Not running as Administrator, so no firewall rule was added.'
            Write-Warn 'If players cannot connect, run this in an elevated PowerShell:'
            Write-Host ''
            Write-Host "  New-NetFirewallRule -DisplayName `"$ruleName`" -Direction Inbound ``" -ForegroundColor White
            Write-Host "    -Protocol TCP -LocalPort $Port -Action Allow -Profile $profileValue" -ForegroundColor White
        }

        $publicActive = (Get-NetConnectionProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.NetworkCategory -eq 'Public' })
        if ($publicActive -and $FirewallProfile -eq 'Private') {
            Write-Host ''
            Write-Warn 'This machine is on a network marked Public, but the rule covers Private.'
            Write-Warn 'Either set the network to Private in Settings > Network, or re-run with:'
            Write-Warn '  -FirewallProfile Any'
        }
    }

    # ----------------------------------------------------------------------
    # 6. Tell the room where to connect
    # ----------------------------------------------------------------------
    Write-Step 'Ready'

    if (-not $LocalOnly) {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InterfaceAlias -notmatch 'Loopback|WSL|vEthernet|Docker' -and
                $_.IPAddress -notmatch '^(127\.|169\.254\.)'
            })

        Write-Host ''
        if ($addresses.Count -eq 0) {
            Write-Warn 'No usable network address found. Is Wi-Fi connected?'
            Write-Warn "Players on this laptop can still use:  ssh level0@127.0.0.1 -p $Port"
        } else {
            Write-Host '  Players connect with:' -ForegroundColor White
            foreach ($a in $addresses) {
                Write-Host "    ssh level0@$($a.IPAddress) -p $Port" -ForegroundColor Green -NoNewline
                Write-Host "   ($($a.InterfaceAlias))" -ForegroundColor DarkGray
            }
            if ($addresses.Count -gt 1) {
                Write-Host ''
                Write-Host '  More than one address listed — give out the one for the' -ForegroundColor DarkGray
                Write-Host '  network the players are actually on (usually Wi-Fi).' -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host ''
        Write-Host '  Play with:' -ForegroundColor White
        Write-Host "    ssh level0@127.0.0.1 -p $Port" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Entry password: ' -ForegroundColor White -NoNewline
    Write-Host 'ghostshell' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Stop it with:   ' -ForegroundColor DarkGray -NoNewline
    Write-Host ".\deploy\Stop-Relay.ps1 -Name $Name" -ForegroundColor DarkGray
    Write-Host '  Watch logs:     ' -ForegroundColor DarkGray -NoNewline
    Write-Host "docker compose --project-name $Name logs -f" -ForegroundColor DarkGray

    # ----------------------------------------------------------------------
    # Sleep warning — deliberately not changed automatically
    # ----------------------------------------------------------------------
    $standby = $null
    try {
        $acLine = (& powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null |
            Select-String 'Current AC Power Setting Index' | Select-Object -First 1)
        if ($acLine) { $standby = [Convert]::ToInt32(($acLine.ToString() -split ':')[-1].Trim(), 16) }
    } catch { }

    if ($null -ne $standby -and $standby -gt 0) {
        Write-Host ''
        Write-Warn "This laptop sleeps after $([math]::Round($standby / 60)) minutes on AC power."
        Write-Warn 'If it sleeps, the relay goes down and every player is disconnected.'
        Write-Warn 'To keep it awake while plugged in (this changes a system setting):'
        Write-Warn '  powercfg /change standby-timeout-ac 0'
        Write-Warn 'Restore it afterwards with your previous value, e.g.:'
        Write-Warn "  powercfg /change standby-timeout-ac $([math]::Round($standby / 60))"
    }
    Write-Host ''
} finally {
    Pop-Location
}
