<#
Hyper-V VM lifecycle for an Omarchy guest.

Two Hyper-V facts drive every choice in here:

  * Secure Boot must be off. The Omarchy ISO is not signed for Microsoft's
    UEFI CA, and the manual says as much for bare metal too.
  * Hyper-V gives a Linux guest a KMS display (hyperv_drm) but no sound card
    at all, and its Enhanced Session Mode is xrdp/X11, which cannot host a
    Wayland compositor. So the console here is only for installing; the real
    desktop arrives over Sunshine/Moonlight, set up by guest/install.sh.
#>

function New-OmarchyVM {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name = $script:OmarchyDefaults.VMName,
        [Parameter(Mandatory)][string]$IsoPath,
        [int]$ProcessorCount = $script:OmarchyDefaults.ProcessorCount,
        [uint64]$MemoryBytes = $script:OmarchyDefaults.MemoryBytes,
        [uint64]$DiskBytes = $script:OmarchyDefaults.DiskBytes,
        [string]$SwitchName = $script:OmarchyDefaults.SwitchName,
        [string]$VMPath,
        # Directory of installer config files; when given, the install runs
        # unattended. See lib/Cidata.ps1.
        [string]$CidataDir,
        # Lets the guest run KVM/Docker-in-Docker style nested workloads.
        [switch]$NestedVirtualization,
        [switch]$Force,
        [switch]$NoStart
    )

    Test-OmarchyHost -IsoPath $IsoPath -SwitchName $SwitchName -DiskBytes $DiskBytes -VMPath $VMPath

    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        if (-not $Force) {
            throw "A VM named '$Name' already exists. Pass -Force to remove and recreate it, or -Name to pick another."
        }
        Remove-OmarchyVM -Name $Name -DeleteDisks -Confirm:$false
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

    # Secure Boot off: the ISO will not boot with it on.
    Set-VMFirmware -VM $vm -EnableSecureBoot Off
    Write-Ok 'Secure Boot disabled'

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

    if ($CidataDir) {
        $cidataPath = Join-Path $vmDir 'cidata.vhdx'
        New-OmarchyCidataDisk -SourceDir $CidataDir -Path $cidataPath -Force | Out-Null
        Add-VMHardDiskDrive -VM $vm -Path $cidataPath
        Write-Ok 'Attached cidata disk (unattended install)'
    }

    # Boot the empty disk first: it falls through to the DVD on the first boot
    # and takes over once Omarchy is installed, so nothing has to be unplugged.
    $bootDisk = Get-VMHardDiskDrive -VM $vm | Where-Object Path -eq $vhdPath
    Set-VMFirmware -VM $vm -BootOrder $bootDisk, (Get-VMDvdDrive -VM $vm)

    # HvSocket transport is what Enhanced Session Mode would use. We are not
    # using ESM for the desktop (it is X11-only), but leaving the transport set
    # costs nothing and makes a future xrdp-based console possible.
    Set-VM -VM $vm -EnhancedSessionTransportType HvSocket

    if (-not $NoStart) {
        Start-VM -VM $vm
        Write-Ok 'VM started'
        Write-Note 'Opening the console. Secure Boot is already off; just run the installer.'
        Connect-OmarchyVM -Name $Name
    }

    Get-VM -Name $Name
}

function Connect-OmarchyVM {
    [CmdletBinding()]
    param([string]$Name = $script:OmarchyDefaults.VMName)

    # Basic session only. Enhanced Session Mode negotiates an xrdp X11 session,
    # which a Hyprland guest does not have.
    Start-Process -FilePath "$env:SystemRoot\System32\vmconnect.exe" `
        -ArgumentList 'localhost', $Name
}

function Remove-OmarchyVM {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$Name = $script:OmarchyDefaults.VMName,
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
