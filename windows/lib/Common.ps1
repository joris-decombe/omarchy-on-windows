# Shared helpers. Dot-sourced by HyperVLinux.psm1.

$script:VMDefaults = @{
    VMName         = 'Fedora'
    ProcessorCount = 8
    MemoryBytes    = 12GB
    DiskBytes      = 100GB
    SwitchName     = 'Default Switch'
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

# Hyper-V cmdlets also work unelevated for members of this group, which is the
# saner way to live than a UAC prompt per command.
function Test-HyperVAccess {
    if (Test-Elevated) { return $true }
    try {
        $sid = (Get-LocalGroup 'Hyper-V Administrators' -ErrorAction Stop).SID.Value
        return [Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -contains $sid
    } catch { return $false }
}

function Get-RepoRoot {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
