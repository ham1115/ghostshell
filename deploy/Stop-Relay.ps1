#Requires -Version 5.1
<#
.SYNOPSIS
    Stop GHOSTSHELL :: Relay Nine and optionally clean up what Start-Relay
    left behind.

.DESCRIPTION
    Stops and removes the relay container. By default it leaves the firewall
    rule and the generated docker-compose.override.yml in place, so the next
    Start-Relay run is quick. Pass -Clean at the end of an event to remove
    both, and -RemoveImage to reclaim the disk as well.

.PARAMETER Name
    Compose project and container name to stop. Default "ghostshell". Must
    match the -Name you started with.

.PARAMETER Clean
    Also remove the firewall rule (needs Administrator) and delete the
    generated docker-compose.override.yml.

.PARAMETER RemoveImage
    Also delete the ghostshell image. The next start will rebuild it, which
    needs internet access.

.EXAMPLE
    .\deploy\Stop-Relay.ps1
    Stop the relay, keep the override and firewall rule for next time.

.EXAMPLE
    .\deploy\Stop-Relay.ps1 -Clean
    Stop and tidy up after the event.

.EXAMPLE
    .\deploy\Stop-Relay.ps1 -Name team-b -Clean
    Stop the team B relay and remove its rule.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$Name = 'ghostshell',
    [switch]$Clean,
    [switch]$RemoveImage
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRoot 'docker-compose.yml'))) {
    Write-Err "Could not find docker-compose.yml above $PSScriptRoot."
    exit 1
}
Push-Location $RepoRoot
try {
    Write-Host ''
    Write-Host '  GHOSTSHELL :: Relay Nine — shutting down' -ForegroundColor White

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Err 'Docker is not installed, or not on PATH. Nothing to stop.'
        exit 1
    }

    Write-Step "Stopping the relay ($Name)"
    & docker compose --project-name $Name down
    if ($LASTEXITCODE -ne 0) {
        # Compose can fail if the override is gone; fall back to the container.
        Write-Warn 'Compose could not stop it. Trying the container directly.'
        & docker rm -f $Name *> $null
        if ($LASTEXITCODE -eq 0) { Write-Ok "Removed container $Name" }
        else { Write-Warn "No running container named $Name." }
    } else {
        Write-Ok 'Relay stopped and removed'
    }

    if ($Clean) {
        Write-Step 'Cleaning up'

        $overridePath = Join-Path $RepoRoot 'docker-compose.override.yml'
        if (Test-Path $overridePath) {
            Remove-Item $overridePath -Force
            Write-Ok 'Deleted docker-compose.override.yml'
        } else {
            Write-Ok 'No override file to delete'
        }

        $rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "GHOSTSHELL CTF ($Name,*" })
        if ($rules.Count -eq 0) {
            Write-Ok 'No firewall rule to remove'
        } elseif (Test-Admin) {
            foreach ($r in $rules) {
                Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
                Write-Ok "Removed firewall rule: $($r.DisplayName)"
            }
        } else {
            Write-Warn 'Not running as Administrator, so the firewall rule was left in place.'
            foreach ($r in $rules) {
                Write-Warn "Remove it later with:  Remove-NetFirewallRule -DisplayName `"$($r.DisplayName)`""
            }
        }
    }

    if ($RemoveImage) {
        Write-Step 'Removing the image'
        & docker rmi ghostshell:1.0 *> $null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'Deleted ghostshell:1.0' }
        else { Write-Warn 'Image not found, or still in use by another relay.' }
    }

    Write-Host ''
    Write-Host '  Done. Start again with:  ' -ForegroundColor DarkGray -NoNewline
    Write-Host ".\deploy\Start-Relay.ps1 -Name $Name" -ForegroundColor DarkGray
    if (-not $Clean) {
        Write-Host '  End of the event? Run:   ' -ForegroundColor DarkGray -NoNewline
        Write-Host ".\deploy\Stop-Relay.ps1 -Name $Name -Clean" -ForegroundColor DarkGray
    }
    Write-Host ''
} finally {
    Pop-Location
}
