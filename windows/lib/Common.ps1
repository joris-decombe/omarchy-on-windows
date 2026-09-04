# Shared helpers. Dot-sourced by Omarchy.psm1.

$script:OmarchyDefaults = @{
    VMName        = 'Omarchy'
    ProcessorCount = 8
    MemoryBytes   = 12GB
    DiskBytes     = 100GB
    SwitchName    = 'Default Switch'
    # Hyper-V's synthetic display tops out here for Gen 2 Linux guests.
    Resolution    = '1920x1080'
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  + $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The repo root, so guest/ can be found from any of the host scripts.
function Get-OmarchyRepoRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
