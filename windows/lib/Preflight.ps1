<#
Checks that must pass before we touch Hyper-V. Every failure here is something
the user has to fix themselves (elevation, a Windows feature, disk space), so
we collect them all and report once instead of dying on the first one.
#>

function Test-HyperVHost {
    [CmdletBinding()]
    param(
        [string]$IsoPath,
        [string]$SwitchName = $script:VMDefaults.SwitchName,
        [uint64]$DiskBytes = $script:VMDefaults.DiskBytes,
        [string]$VMPath
    )

    $problems = [System.Collections.Generic.List[string]]::new()

    Write-Step 'Preflight'

    if (Test-HyperVAccess) {
        Write-Ok $(if (Test-Elevated) { 'Running elevated' } else { 'Member of Hyper-V Administrators' })
    } else {
        $problems.Add('No Hyper-V access. Either run PowerShell as Administrator, or add yourself once with: Add-LocalGroupMember -Group "Hyper-V Administrators" -Member $env:USERNAME  (then sign out and back in).')
    }

    # Get-WindowsOptionalFeature itself needs elevation, so only trust it when we have it.
    if (Test-Elevated) {
        $hv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
        if (-not $hv) {
            $problems.Add('Could not query the Microsoft-Hyper-V-All feature. Is this a Windows edition that has Hyper-V (Pro/Enterprise/Education)?')
        } elseif ($hv.State -ne 'Enabled') {
            $problems.Add('Hyper-V is not enabled. Enable it with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All  (then reboot)')
        } else {
            Write-Ok 'Hyper-V feature enabled'
        }
    }

    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        $problems.Add('The Hyper-V PowerShell module is not installed. Add it with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell')
    }

    if ($IsoPath) {
        if (Test-Path -LiteralPath $IsoPath) {
            $size = (Get-Item -LiteralPath $IsoPath).Length
            if ($size -lt 500MB) {
                $problems.Add("The ISO at $IsoPath is only $([math]::Round($size/1MB)) MB. A desktop ISO is a few GB - did the download finish?")
            } else {
                Write-Ok ("ISO found ({0:N1} GB)" -f ($size / 1GB))
            }
        } else {
            $problems.Add("ISO not found at $IsoPath. Download a Fedora Workstation ISO from https://fedoraproject.org/workstation/ first.")
        }
    }

    # Switch and free-space checks need Hyper-V access, which needs elevation.
    if ((Test-HyperVAccess) -and (Get-Module -ListAvailable -Name Hyper-V)) {
        if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
            $available = (Get-VMSwitch -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', '
            $problems.Add("No virtual switch named '$SwitchName'. Available: ${available}. Pass -SwitchName, or create one in Hyper-V Manager.")
        } else {
            Write-Ok "Virtual switch '$SwitchName' present"
        }

        if (-not $VMPath) { $VMPath = (Get-VMHost).VirtualHardDiskPath }
    }

    if ($VMPath) {
        # A dynamic VHDX starts small, but the install plus a few snapshots will
        # grow it, so insist on real headroom rather than the current footprint.
        $needed = [math]::Max($DiskBytes * 0.35, 30GB)
        $qualifier = Split-Path -Qualifier $VMPath -ErrorAction SilentlyContinue
        if ($qualifier) {
            $drive = Get-PSDrive -Name $qualifier.TrimEnd(':') -ErrorAction SilentlyContinue
            if ($drive -and $drive.Free -lt $needed) {
                $problems.Add(("Only {0:N0} GB free on {1} but the VM wants at least {2:N0} GB of headroom. Pass -VMPath to put it on another drive." -f ($drive.Free/1GB), $qualifier, ($needed/1GB)))
            } elseif ($drive) {
                Write-Ok ("{0:N0} GB free on {1}" -f ($drive.Free/1GB), $qualifier)
            }
        }
    }

    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Host 'Preflight failed:' -ForegroundColor Red
        foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Red }
        throw 'Preflight failed. Fix the problems above and run again.'
    }

    Write-Ok 'Preflight passed'
}
