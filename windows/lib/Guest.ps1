<#
Host-side plumbing that talks to a running Omarchy guest: finding its address,
pushing the guest kit onto it, and opening the desktop stream.
#>

function Get-OmarchyVMAddress {
    [CmdletBinding()]
    param(
        [string]$Name = $script:OmarchyDefaults.VMName,
        # Wait for the guest to report an address (it only does so once the
        # Hyper-V KVP daemon is running, which guest/install.sh enables).
        [int]$TimeoutSeconds = 0
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $addresses = @(Get-VMNetworkAdapter -VMName $Name -ErrorAction Stop |
            Select-Object -ExpandProperty IPAddresses |
            Where-Object { $_ -and $_ -notmatch ':' -and $_ -ne '127.0.0.1' })

        if ($addresses.Count -gt 0) { return $addresses[0] }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 2
    } while ($true)

    throw @"
The guest is not reporting an IP address.

Hyper-V learns it from the guest's KVP daemon, which comes from the Arch
'hyperv' package. Either the VM is still booting, or guest/install.sh has not
run yet. Inside the guest you can read the address with 'ip -4 addr'.
"@
}

<#
Copies guest/ into the VM over SSH. Omarchy ships openssh with the service
disabled, so either enable it in the guest first (systemctl enable --now sshd)
or skip this and clone the repo from inside the guest instead.
#>
function Copy-OmarchyGuestKit {
    [CmdletBinding()]
    param(
        [string]$Name = $script:OmarchyDefaults.VMName,
        [Parameter(Mandatory)][string]$UserName,
        [string]$Address
    )

    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
        throw 'scp not found. Install the Windows OpenSSH client, or clone this repo inside the guest instead.'
    }
    if (-not $Address) { $Address = Get-OmarchyVMAddress -Name $Name -TimeoutSeconds 60 }

    $guestDir = Join-Path (Get-OmarchyRepoRoot) 'guest'
    Write-Step "Copying guest kit to ${UserName}@${Address}"
    & scp -r -o StrictHostKeyChecking=accept-new $guestDir "${UserName}@${Address}:~/omarchy-on-windows-guest"
    if ($LASTEXITCODE -ne 0) { throw "scp failed with exit code $LASTEXITCODE" }

    Write-Ok 'Copied'
    Write-Note "Now run in the guest:  bash ~/omarchy-on-windows-guest/install.sh"
}

function Install-OmarchyMoonlight {
    [CmdletBinding()]
    param()

    if (Get-OmarchyMoonlightPath) { Write-Ok 'Moonlight already installed'; return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Install Moonlight manually from https://moonlight-stream.org/'
    }

    Write-Step 'Installing Moonlight'
    & winget install --id MoonlightGameStreamingProject.Moonlight --accept-package-agreements --accept-source-agreements
    if (-not (Get-OmarchyMoonlightPath)) {
        throw 'Moonlight install did not produce an executable where expected. Install it manually from https://moonlight-stream.org/'
    }
    Write-Ok 'Moonlight installed'
}

function Get-OmarchyMoonlightPath {
    $candidates = @(
        "$env:ProgramFiles\Moonlight Game Streaming\Moonlight.exe"
        "${env:ProgramFiles(x86)}\Moonlight Game Streaming\Moonlight.exe"
        "$env:LOCALAPPDATA\Programs\Moonlight Game Streaming\Moonlight.exe"
    )
    $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

<#
Opens the Omarchy desktop. Moonlight pairs with Sunshine once, by PIN: the
first run prints a PIN that you type into Sunshine's web UI in the guest
(https://<guest>:47990). After that it connects straight through.
#>
function Start-OmarchyDesktop {
    [CmdletBinding()]
    param(
        [string]$Name = $script:OmarchyDefaults.VMName,
        [string]$Address,
        [string]$AppName = 'Desktop'
    )

    $moonlight = Get-OmarchyMoonlightPath
    if (-not $moonlight) { throw 'Moonlight is not installed. Run Install-OmarchyMoonlight first.' }

    if (-not $Address) { $Address = Get-OmarchyVMAddress -Name $Name -TimeoutSeconds 120 }
    Write-Step "Streaming '$AppName' from $Address"
    Write-Note "Not paired yet? Open https://${Address}:47990 in the guest and enter the PIN Moonlight shows."

    Start-Process -FilePath $moonlight -ArgumentList 'stream', $Address, $AppName
}
