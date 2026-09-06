<#
The WSL route: a GNOME session inside a WSL distro, reached over RDP on
localhost.

There is no VM to create here, so this file is much smaller than Vm.ps1. WSL
forwards a guest's listening ports onto Windows' own localhost, so the desktop
is at 127.0.0.1 and nothing has to be routed or firewalled.
#>

$script:WslDefaults = @{
    DistroName = 'FedoraLinux-44'
    Port       = 3390
}

function Get-WslDistro {
    [CmdletBinding()]
    param([string]$Name = $script:WslDefaults.DistroName)

    # wsl.exe writes UTF-16 with NULs; strip them or every match fails.
    $list = (& wsl.exe --list --quiet 2>$null) -join "`n"
    $list = $list -replace "`0", ''
    $found = $list -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Name }
    [pscustomobject]@{
        Name    = $Name
        Present = [bool]$found
    }
}

<#
Opens the WSL desktop over RDP.

Headless GNOME authenticates against credentials set with grdctl, not against a
login screen - so the username and password here are the ones wsl/setup.sh
configured, which are usually your Linux user's.
#>
function Start-WslDesktop {
    [CmdletBinding()]
    param(
        [string]$DistroName = $script:WslDefaults.DistroName,
        [int]$Port = $script:WslDefaults.Port,
        [switch]$FullScreen
    )

    $distro = Get-WslDistro -Name $DistroName
    if (-not $distro.Present) {
        throw "No WSL distro named '$DistroName'. Install one with: wsl --install $DistroName"
    }

    # Fail early and clearly rather than handing mstsc a dead port.
    $probe = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
    if (-not $probe) {
        throw @"
Nothing is listening on 127.0.0.1:$Port.

The RDP server runs inside '$DistroName'. Check it there with:
    sudo bash wsl/doctor.sh

The usual cause is that no RDP password has been set - headless GNOME refuses
connections until one exists:
    grdctl --headless rdp set-credentials <user> <password>
"@
    }

    $rdpPath = Join-Path $env:LOCALAPPDATA "HyperVLinux\$DistroName.rdp"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rdpPath) | Out-Null

    $lines = @(
        "full address:s:127.0.0.1:$Port"
        'audiomode:i:0'
        'audiocapturemode:i:1'
        'dynamic resolution:i:1'
        'smart sizing:i:0'
        'redirectclipboard:i:1'
        'redirectprinters:i:0'
        'session bpp:i:32'
        # grdctl issues its own certificate, so the issuer is untrusted.
        'authentication level:i:0'
        'prompt for credentials:i:1'
        "screen mode id:i:$(if ($FullScreen) { 2 } else { 1 })"
    )
    Set-Content -LiteralPath $rdpPath -Value $lines -Encoding ASCII

    Start-Process mstsc.exe -ArgumentList "`"$rdpPath`""
    Write-Ok "Opened the $DistroName desktop on 127.0.0.1:$Port"
    Write-Note 'Applications in this session render on the GPU; the shell composites on the CPU.'
}
