<#
The WSL side: GPU-accelerated Linux applications on the Windows desktop.

There is no desktop here and no VM to create, which is why this file is short.
WSL cannot host a Linux desktop -- gnome-remote-desktop needs a DRM device for
its capture pipeline and WSL has none, so it segfaults; see
wsl/lib/remote-desktop.sh for the full measurement. What WSL can do, and the
Hyper-V VM cannot, is run individual applications on the real GPU: Mesa's d3d12
driver renders through /dev/dxg without any DRM node, and WSLg puts each
application in its own Windows window with working audio.
#>

$script:WslDefaults = @{
    DistroName = 'FedoraLinux-44'
}

function Get-WslDistro {
    [CmdletBinding()]
    param([string]$Name = $script:WslDefaults.DistroName)

    # wsl.exe writes UTF-16 with NULs; strip them or every match fails.
    $list = ((& wsl.exe --list --quiet 2>$null) -join "`n") -replace "`0", ''
    $found = $list -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Name }
    [pscustomobject]@{ Name = $Name; Present = [bool]$found }
}

<#
.SYNOPSIS
    Run a Linux application on the discrete GPU, in its own Windows window.

.EXAMPLE
    Start-WslApp firefox

.EXAMPLE
    Start-WslApp glxinfo -Arguments '-B'   # prints the renderer it got
#>
function Start-WslApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Command,
        [string[]]$Arguments = @(),
        [string]$DistroName = $script:WslDefaults.DistroName,
        # Wait and return the output instead of detaching. Useful for checks.
        [switch]$Wait
    )

    $distro = Get-WslDistro -Name $DistroName
    if (-not $distro.Present) {
        throw "No WSL distro named '$DistroName'. Install one with: wsl --install $DistroName"
    }

    # gpu-run is installed by wsl/setup.sh and sets GALLIUM_DRIVER=d3d12 plus
    # the adapter name. Without it Mesa silently uses llvmpipe on Fedora.
    $argv = @('-d', $DistroName, '--', 'gpu-run', $Command) + $Arguments

    if ($Wait) {
        & wsl.exe @argv
    } else {
        Start-Process -FilePath 'wsl.exe' -ArgumentList $argv -WindowStyle Hidden
        Write-Ok "Launched '$Command' in $DistroName on the GPU"
    }
}

<#
Reports which renderer applications in the distro actually get. Use it to
confirm the GPU path rather than assuming it.
#>
function Test-WslGpu {
    [CmdletBinding()]
    param([string]$DistroName = $script:WslDefaults.DistroName)

    $out = & wsl.exe -d $DistroName -- gpu-run glxinfo -B 2>$null
    $renderer = ($out | Select-String 'OpenGL renderer' | Select-Object -First 1) -replace '.*:\s*', ''

    if (-not $renderer) {
        Write-Warn 'Could not read a renderer. Is glxinfo installed, and has wsl/setup.sh been run?'
        return
    }
    if ($renderer -match 'D3D12') {
        Write-Ok "Applications render on: $renderer"
    } else {
        Write-Warn "Software rendering: $renderer"
        Write-Note 'Run: sudo bash wsl/setup.sh --only gpu   inside the distro.'
    }
}
