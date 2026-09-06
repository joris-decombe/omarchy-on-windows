<#
.SYNOPSIS
    Install Fedora into a Hyper-V VM with no keystrokes in the VM console.

.DESCRIPTION
    Builds an OEMDRV kickstart disk, attaches it to the VM alongside the
    installer ISO, and starts it. Anaconda finds the kickstart, installs
    unattended, and reboots into the finished system.

    This exists because the Hyper-V basic console is a poor place to type: it
    does not propagate lock-key state, so Caps Lock silently inverts case, and
    a password mistyped that way is only discovered later at the login screen.
    An install nobody types into cannot be mistyped into. It also makes the VMs
    reproducible, which matters when comparing desktops on machines that are
    supposed to be identical.

    Run this from an ELEVATED PowerShell: attaching a VHD to the host needs
    Administrator, which membership of Hyper-V Administrators does not cover.

    You are prompted once for the new Linux user's password. It is hashed
    locally with openssl and only the hash is written to the disk.

.EXAMPLE
    .\Install-FedoraUnattended.ps1 -IsoPath D:\Downloads\Fedora-Workstation-Live-44-1.7.x86_64.iso

.EXAMPLE
    .\Install-FedoraUnattended.ps1 -IsoPath D:\iso\fedora.iso -Name Fedora-KDE `
        -UserName joris -Hostname fedora-kde -SwitchName HA-External
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$Name = 'Fedora',
    [string]$UserName = $env:USERNAME.ToLower(),
    [string]$FullName,
    [string]$Hostname,
    [string]$Timezone = 'Pacific/Auckland',
    [string]$KeyboardLayout = 'us',
    [string]$Locale = 'en_NZ.UTF-8',
    # Reuse an existing VM instead of creating one. The VM is stopped, wiped by
    # the kickstart's clearpart, and reinstalled.
    [switch]$UseExistingVM,
    [string]$SwitchName = 'Default Switch',
    [int]$ProcessorCount = 8,
    [int]$MemoryGB = 12,
    [int]$DiskGB = 100,
    [switch]$SecureBoot
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'HyperVLinux.psd1') -Force

if (-not $FullName) { $FullName = $UserName }
if (-not $Hostname) { $Hostname = $Name.ToLower() }

if (-not (Test-Elevated)) {
    throw @'
Run this from an elevated PowerShell.

Building the kickstart disk calls Mount-VHD, which attaches a disk to Windows
itself and needs Administrator. Membership of Hyper-V Administrators is enough
for everything else here, but not for that.
'@
}

$IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path

# --- the VM -----------------------------------------------------------------

$vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

if ($vm -and -not $UseExistingVM) {
    throw "A VM named '$Name' already exists. Pass -UseExistingVM to reinstall into it, or -Name for a new one."
}
if (-not $vm) {
    Write-Step "Creating VM '$Name'"
    $splat = @{
        Name           = $Name
        IsoPath        = $IsoPath
        ProcessorCount = $ProcessorCount
        MemoryBytes    = [uint64]$MemoryGB * 1GB
        DiskBytes      = [uint64]$DiskGB * 1GB
        SwitchName     = $SwitchName
        NoStart        = $true
    }
    if ($SecureBoot) { $splat.SecureBoot = $true }
    $vm = New-LinuxVM @splat
}

if ($vm.State -ne 'Off') {
    Write-Step "Stopping '$Name'"
    Stop-VM -Name $Name -TurnOff -Force
}

# --- the kickstart disk -----------------------------------------------------

Write-Host ''
Write-Host 'The password below is for the Linux user the installer will create.' -ForegroundColor Cyan
Write-Host 'It is hashed locally; only the hash reaches the disk.' -ForegroundColor DarkGray
$hash = New-LinuxPasswordHash

$vmDir = Split-Path -Parent (Get-VMHardDiskDrive -VMName $Name | Select-Object -First 1 -ExpandProperty Path)
$ksPath = Join-Path $vmDir "$Name-kickstart.vhdx"

New-KickstartDisk -Path $ksPath -UserName $UserName -FullName $FullName `
    -Hostname $Hostname -PasswordHash $hash `
    -Timezone $Timezone -KeyboardLayout $KeyboardLayout -Locale $Locale -Force | Out-Null

Add-KickstartDisk -VMName $Name -Path $ksPath

# The ISO must still be attached, and the empty system disk boots first so that
# once Fedora is installed the machine stops returning to the installer.
if (-not (Get-VMDvdDrive -VMName $Name | Where-Object Path -eq $IsoPath)) {
    Write-Step 'Attaching the installer ISO'
    $dvd = Get-VMDvdDrive -VMName $Name | Select-Object -First 1
    if ($dvd) { Set-VMDvdDrive -VMName $Name -Path $IsoPath } else { Add-VMDvdDrive -VMName $Name -Path $IsoPath }
}

Write-Step "Starting '$Name'"
Start-VM -Name $Name -ErrorAction Continue
if ((Get-VM -Name $Name).State -ne 'Running') {
    throw "The VM did not start. Free memory is the usual cause; see docs/troubleshooting.md."
}

Write-Host ''
Write-Host 'Installing.' -ForegroundColor Cyan
Write-Host @"
  Anaconda will find the OEMDRV disk, install without asking anything, and
  reboot into the finished system. Watch it if you like:
      vmconnect.exe localhost $Name

  Nothing needs typing in that window. When the guest comes back up, the host
  will start seeing its address once the Hyper-V daemons are installed:
      Get-LinuxVMAddress -Name $Name

  Then, in the guest:
      sudo dnf install -y git
      git clone https://github.com/joris-decombe/linux-on-hyperv.git
      sudo bash linux-on-hyperv/guest/setup.sh

  And back here:
      Start-LinuxDesktop -Name $Name

  Log in as '$UserName' with the password you just set.
"@

Write-Warn "The kickstart disk stays attached at $ksPath."
Write-Note 'It is harmless once installed, but it will reinstall if the VM ever boots the ISO again.'
Write-Note "Remove it when you are happy:  Remove-VMHardDiskDrive -VMName $Name -ControllerType SCSI -ControllerNumber 0 -ControllerLocation <n>"
