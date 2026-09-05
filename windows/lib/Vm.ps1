<#
Hyper-V VM lifecycle for a Linux desktop guest.

Two Hyper-V facts drive the choices in here:

  * Secure Boot defaults to a Microsoft template that most Linux installers
    will not boot. Fedora is signed for the Microsoft UEFI CA, so it can boot
    with Secure Boot on -- but only under the "MicrosoftUEFICertificateAuthority"
    template, not the Windows one Hyper-V picks by default.
  * Hyper-V emulates no sound card for a Linux guest, and its Enhanced Session
    Mode is xrdp serving X11. Both are irrelevant here: the desktop arrives
    over the guest's own RDP server (gnome-remote-desktop), which carries
    video, audio, clipboard and dynamic resolution on one connection. The
    Hyper-V console is only for installing.
#>

function New-LinuxVM {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name = $script:VMDefaults.VMName,
        [Parameter(Mandatory)][string]$IsoPath,
        [int]$ProcessorCount = $script:VMDefaults.ProcessorCount,
        [uint64]$MemoryBytes = $script:VMDefaults.MemoryBytes,
        [uint64]$DiskBytes = $script:VMDefaults.DiskBytes,
        [string]$SwitchName = $script:VMDefaults.SwitchName,
        [string]$VMPath,
        # Fedora boots fine with Secure Boot on under the right template;
        # leave it off for installers that are not signed for it.
        [switch]$SecureBoot,
        # Lets the guest run KVM/Docker-in-Docker style nested workloads.
        [switch]$NestedVirtualization,
        [switch]$Force,
        [switch]$NoStart
    )

    Test-HyperVHost -IsoPath $IsoPath -SwitchName $SwitchName -DiskBytes $DiskBytes -VMPath $VMPath

    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        if (-not $Force) {
            throw "A VM named '$Name' already exists. Pass -Force to remove and recreate it, or -Name to pick another."
        }
        Remove-LinuxVM -Name $Name -DeleteDisks -Confirm:$false
    }

    if (-not $VMPath) { $VMPath = (Get-VMHost).VirtualHardDiskPath }
    $vmDir = Join-Path $VMPath $Name
    $vhdPath = Join-Path $vmDir "$Name.vhdx"

    if (-not $PSCmdlet.ShouldProcess($Name, 'Create Hyper-V VM')) { return }

    Write-Step "Creating VM '$Name'"
    New-Item -ItemType Directory -Force -Path $vmDir | Out-Null

    $vm = New-VM -Name $Name -Generation 2 `
        -MemoryStartupBytes $MemoryBytes `
        -NewVHDPath $vhdPath -NewVHDSizeBytes $DiskBytes `
        -SwitchName $SwitchName -Path $VMPath
    Write-Ok ("{0} vCPU, {1:N0} GB RAM, {2:N0} GB disk on '{3}'" -f $ProcessorCount, ($MemoryBytes/1GB), ($DiskBytes/1GB), $SwitchName)

    if ($SecureBoot) {
        # Fedora's shim is signed for Microsoft's third-party UEFI CA, which is
        # a different template from the Windows one Hyper-V defaults to.
        Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
        Write-Ok 'Secure Boot on (Microsoft UEFI CA template)'
    } else {
        Set-VMFirmware -VM $vm -EnableSecureBoot Off
        Write-Ok 'Secure Boot disabled'
    }

    Set-VMProcessor -VM $vm -Count $ProcessorCount
    if ($NestedVirtualization) {
        Set-VMProcessor -VM $vm -ExposeVirtualizationExtensions $true
        Write-Ok 'Nested virtualization exposed'
    }

    # Dynamic memory makes a desktop guest stutter under memory pressure, and
    # llvmpipe rendering is already the tight resource here. Pin it.
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $false

    # Automatic checkpoints silently snapshot on every start, which doubles the
    # disk footprint of a 100 GB desktop image for no benefit.
    Set-VM -VM $vm -AutomaticCheckpointsEnabled $false -CheckpointType Production `
        -AutomaticStartAction Nothing -AutomaticStopAction ShutDown

    Add-VMDvdDrive -VM $vm -Path $IsoPath
    Write-Ok "Attached installer ISO"


    # Boot the empty disk first: it falls through to the DVD on the first boot
    # and takes over once the distro is installed, so nothing has to be unplugged.
    $bootDisk = Get-VMHardDiskDrive -VM $vm | Where-Object Path -eq $vhdPath
    Set-VMFirmware -VM $vm -BootOrder $bootDisk, (Get-VMDvdDrive -VM $vm)

    # HvSocket transport is what Enhanced Session Mode would use. We are not
    # using ESM for the desktop (it is X11-only), but leaving the transport set
    # costs nothing and makes a future xrdp-based console possible.
    Set-VM -VM $vm -EnhancedSessionTransportType HvSocket

    if (-not $NoStart) {
        Start-VM -VM $vm
        Write-Ok 'VM started'
        Write-Note 'Opening the console. Run the installer, then see guest/setup.sh.'
        Connect-LinuxVM -Name $Name
    }

    Get-VM -Name $Name
}

function Connect-LinuxVM {
    [CmdletBinding()]
    param([string]$Name = $script:VMDefaults.VMName)

    # Basic session only. Enhanced Session Mode negotiates an xrdp X11 session,
    # which a Hyprland guest does not have.
    Start-Process -FilePath "$env:SystemRoot\System32\vmconnect.exe" `
        -ArgumentList 'localhost', $Name
}

function Remove-LinuxVM {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$Name = $script:VMDefaults.VMName,
        [switch]$DeleteDisks
    )

    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if (-not $vm) { Write-Warn "No VM named '$Name'"; return }

    $disks = @(Get-VMHardDiskDrive -VM $vm | Select-Object -ExpandProperty Path)

    if (-not $PSCmdlet.ShouldProcess($Name, "Remove VM$(if ($DeleteDisks) { ' and delete its disks' })")) { return }

    if ($vm.State -ne 'Off') { Stop-VM -VM $vm -TurnOff -Force }
    Remove-VM -VM $vm -Force

    if ($DeleteDisks) {
        foreach ($disk in $disks) {
            if (Test-Path -LiteralPath $disk) {
                Remove-Item -LiteralPath $disk -Force
                Write-Ok "Deleted $disk"
            }
        }
    } else {
        foreach ($disk in $disks) { Write-Note "Left behind: $disk" }
    }
}
