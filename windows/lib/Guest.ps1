<#
Host-side plumbing for a running Linux guest: finding its address and opening
the desktop.

The desktop arrives over RDP, served by gnome-remote-desktop inside the guest.
That is the whole reason this project moved off a capture-and-stream approach:
RDP already carries video, audio, clipboard and -- the part that matters most
in a VM -- a resolution that follows the client window as you resize it. The
Windows client is mstsc.exe, which is already installed.
#>

function Get-LinuxVMAddress {
    [CmdletBinding()]
    param(
        [string]$Name = $script:VMDefaults.VMName,
        # Wait for the guest to report an address. It only does so once the
        # Hyper-V KVP daemon is running (the hyperv-daemons package).
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

Hyper-V learns it from the guest's KVP daemon, which comes from the Fedora
'hyperv-daemons' package. Either the VM is still booting, or guest/setup.sh has
not run yet. Inside the guest, read it with 'ip -4 addr'.
"@
}

<#
Opens the guest desktop in the Windows Remote Desktop client.

Dynamic resolution is the default in mstsc for servers that advertise it, and
gnome-remote-desktop does -- so resizing the window resizes the guest desktop,
with no fixed mode anywhere in the chain.
#>
function Start-LinuxDesktop {
    [CmdletBinding()]
    param(
        [string]$Name = $script:VMDefaults.VMName,
        [string]$Address,
        # Start full screen instead of in a window.
        [switch]$FullScreen,
        # Skip writing an .rdp file and just hand the address to mstsc.
        [switch]$NoProfile
    )

    if (-not $Address) { $Address = Get-LinuxVMAddress -Name $Name -TimeoutSeconds 120 }

    if ($NoProfile) {
        Start-Process mstsc.exe -ArgumentList "/v:$Address"
        Write-Ok "Opened Remote Desktop to $Address"
        return
    }

    # An .rdp file is the only way to set several of these; mstsc's command line
    # cannot express audio redirection or dynamic resolution.
    $rdpPath = Join-Path $env:LOCALAPPDATA "HyperVLinux\$Name.rdp"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rdpPath) | Out-Null

    $lines = @(
        "full address:s:$Address"
        # Play the guest's audio on this machine. Without this RDP renders it
        # on the "remote" side, which in a VM with no sound card means nowhere.
        'audiomode:i:0'
        # Send this machine's microphone the other way.
        'audiocapturemode:i:1'
        # Let the session resize with the window rather than pinning a mode.
        'dynamic resolution:i:1'
        'smart sizing:i:0'
        'redirectclipboard:i:1'
        'redirectprinters:i:0'
        'session bpp:i:32'
        # The guest's certificate is self-signed by grdctl; without this mstsc
        # refuses outright rather than warning.
        'authentication level:i:0'
        'prompt for credentials:i:1'
        "screen mode id:i:$(if ($FullScreen) { 2 } else { 1 })"
    )
    Set-Content -LiteralPath $rdpPath -Value $lines -Encoding ASCII

    Start-Process mstsc.exe -ArgumentList "`"$rdpPath`""
    Write-Ok "Opened Remote Desktop to $Address"
    Write-Note "Profile: $rdpPath"
    Write-Note 'Log in with your guest username and password.'
}

<#
Copies guest/ into the VM over SSH. Fedora Workstation does not enable sshd by
default either, so this only works once you have turned it on in the guest.
#>
function Copy-GuestKit {
    [CmdletBinding()]
    param(
        [string]$Name = $script:VMDefaults.VMName,
        [Parameter(Mandatory)][string]$UserName,
        [string]$Address
    )

    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
        throw 'scp not found. Install the Windows OpenSSH client, or clone this repo inside the guest instead.'
    }
    if (-not $Address) { $Address = Get-LinuxVMAddress -Name $Name -TimeoutSeconds 60 }

    $guestDir = Join-Path (Get-RepoRoot) 'guest'
    Write-Step "Copying guest kit to ${UserName}@${Address}"
    & scp -r -o StrictHostKeyChecking=accept-new $guestDir "${UserName}@${Address}:~/linux-on-hyperv-guest"
    if ($LASTEXITCODE -ne 0) { throw "scp failed with exit code $LASTEXITCODE" }

    Write-Ok 'Copied'
    Write-Note 'Now run in the guest:  bash ~/linux-on-hyperv-guest/setup.sh'
}
