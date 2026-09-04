<#
.SYNOPSIS
    One-shot bootstrap: preflight, create the Hyper-V VM, boot the Omarchy ISO.

.DESCRIPTION
    Run this from an elevated PowerShell. It creates a Generation 2 VM with
    Secure Boot off (the Omarchy ISO will not boot otherwise), attaches the
    installer ISO, and opens the Hyper-V console so you can run the wizard.

    The console is a Hyper-V basic session: it has video but no sound and no
    clipboard. That is only how you install. Once Omarchy is up, run
    guest/install.sh inside it, then Start-OmarchyDesktop here - that is the
    session with sound, and it renders in a window on your Windows desktop.

.EXAMPLE
    .\New-OmarchyVM.ps1 -IsoPath D:\iso\omarchy.iso

.EXAMPLE
    .\New-OmarchyVM.ps1 -IsoPath D:\iso\omarchy.iso -Name Omarchy-Dev `
        -ProcessorCount 12 -MemoryGB 16 -DiskGB 160
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$Name = 'Omarchy',
    [int]$ProcessorCount = 8,
    [int]$MemoryGB = 12,
    [int]$DiskGB = 100,
    [string]$SwitchName = 'Default Switch',
    [string]$VMPath,
    [string]$CidataDir,
    [switch]$NestedVirtualization,
    [switch]$Force,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Omarchy.psd1') -Force

$splat = @{
    Name           = $Name
    IsoPath        = (Resolve-Path -LiteralPath $IsoPath).Path
    ProcessorCount = $ProcessorCount
    MemoryBytes    = [uint64]$MemoryGB * 1GB
    DiskBytes      = [uint64]$DiskGB * 1GB
    SwitchName     = $SwitchName
}
if ($VMPath)               { $splat.VMPath = $VMPath }
if ($CidataDir)            { $splat.CidataDir = (Resolve-Path -LiteralPath $CidataDir).Path }
if ($NestedVirtualization) { $splat.NestedVirtualization = $true }
if ($Force)                { $splat.Force = $true }
if ($NoStart)              { $splat.NoStart = $true }

New-OmarchyVM @splat | Out-Null

Write-Host ''
Write-Host 'Next steps' -ForegroundColor Cyan
Write-Host @"
  1. In the Hyper-V console, run the Omarchy installer.
     Encryption is on by default; Ctrl+C at the disk confirmation turns it off,
     which is the sane choice for a throwaway VM you will boot often.

  2. When Omarchy is up, get this repo's guest kit into it, either by
       git clone <this repo> && bash omarchy-on-windows/guest/install.sh
     or, after enabling sshd in the guest, from here:
       Copy-OmarchyGuestKit -Name '$Name' -UserName <your-guest-user>

  3. Back here:
       Install-OmarchyMoonlight
       Start-OmarchyDesktop -Name '$Name'
     Pair once with the PIN, and the desktop opens with sound.
"@
