<#
.SYNOPSIS
    One-shot bootstrap: preflight, create the Hyper-V VM, boot a Linux ISO.

.DESCRIPTION
    Creates a Generation 2 VM sized for a desktop, attaches the installer ISO,
    and opens the Hyper-V console so you can run the installer.

    That console is a Hyper-V basic session: video, but no sound and no
    clipboard. It exists only to install. Once the desktop is up, run
    guest/setup.sh inside it to turn on the guest's own RDP server, then
    Start-LinuxDesktop here - that session has sound, clipboard, and a
    resolution that follows the window.

.EXAMPLE
    .\New-LinuxVM.ps1 -IsoPath D:\iso\Fedora-Workstation-Live-x86_64.iso

.EXAMPLE
    .\New-LinuxVM.ps1 -IsoPath D:\iso\fedora.iso -Name Fedora -SecureBoot `
        -ProcessorCount 12 -MemoryGB 16 -DiskGB 160
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$Name = 'Fedora',
    [int]$ProcessorCount = 8,
    [int]$MemoryGB = 12,
    [int]$DiskGB = 100,
    [string]$SwitchName = 'Default Switch',
    [string]$VMPath,
    [switch]$SecureBoot,
    [switch]$StaticMemory,
    [int]$MinMemoryGB = 2,
    [switch]$NestedVirtualization,
    [switch]$Force,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'HyperVLinux.psd1') -Force

$splat = @{
    Name           = $Name
    IsoPath        = (Resolve-Path -LiteralPath $IsoPath).Path
    ProcessorCount = $ProcessorCount
    MemoryBytes    = [uint64]$MemoryGB * 1GB
    DiskBytes      = [uint64]$DiskGB * 1GB
    SwitchName     = $SwitchName
}
if ($VMPath)               { $splat.VMPath = $VMPath }
if ($SecureBoot)           { $splat.SecureBoot = $true }
if ($StaticMemory)         { $splat.StaticMemory = $true }
$splat.MinimumMemoryBytes = [uint64]$MinMemoryGB * 1GB
if ($NestedVirtualization) { $splat.NestedVirtualization = $true }
if ($Force)                { $splat.Force = $true }
if ($NoStart)              { $splat.NoStart = $true }

New-LinuxVM @splat | Out-Null

Write-Host ''
Write-Host 'Next steps' -ForegroundColor Cyan
Write-Host @"
  1. In the Hyper-V console, run the installer and reboot into the new system.

  2. Inside the guest:
       sudo dnf install -y git
       git clone https://github.com/joris-decombe/linux-on-hyperv.git
       sudo bash linux-on-hyperv/guest/setup.sh

  3. Back here:
       Import-Module .\HyperVLinux.psd1
       Start-LinuxDesktop -Name '$Name'

     Log in with your guest username and password. Sound, clipboard and
     resize-with-the-window all come over that one connection.
"@
