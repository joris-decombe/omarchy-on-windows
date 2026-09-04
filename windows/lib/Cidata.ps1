<#
Unattended-install support.

The Omarchy ISO skips its setup wizard when it finds a second drive labeled
`cidata` carrying the installer's own configuration files (see the Omarchy
manual, "Unattended Installs"). Rather than build an ISO - Windows has no
genisoimage, and the IMAPI COM path uppercases the volume ID anyway - we hand
Hyper-V a tiny FAT32 VHDX with that label. Any filesystem with the right label
works, and a VHDX is something Hyper-V and PowerShell can both make natively.

The files themselves are whatever the interactive wizard wrote to /root on a
previous install. We do not invent them: the schema belongs to Omarchy's
installer and changes with it. Run one interactive install, copy /root off it,
and point -SourceDir here.
#>

$script:CidataRequired = @('user_configuration.json')
$script:CidataKnown = @(
    'user_configuration.json'
    'user_credentials.json'
    'user_full_name.txt'
    'user_email_address.txt'
    'user_encrypt_installation.txt'
    'authorized_keys'
    'tailscale_authkey'
    'defer-provisioning'
)

function New-OmarchyCidataDisk {
    [CmdletBinding()]
    param(
        # Directory holding the installer config files copied from /root of a
        # previous interactive Omarchy install.
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "cidata source directory not found: $SourceDir"
    }

    $files = Get-ChildItem -LiteralPath $SourceDir -File
    if ($files.Count -eq 0) { throw "cidata source directory is empty: $SourceDir" }

    foreach ($required in $script:CidataRequired) {
        if ($files.Name -notcontains $required) {
            throw "cidata source is missing the required file '$required'. Copy /root from an interactive Omarchy install."
        }
    }
    # Either credentials or an explicit "let the first boot ask" marker.
    if ($files.Name -notcontains 'user_credentials.json' -and $files.Name -notcontains 'defer-provisioning') {
        throw "cidata source needs either 'user_credentials.json' or an empty 'defer-provisioning' file."
    }
    foreach ($file in $files) {
        if ($script:CidataKnown -notcontains $file.Name) {
            Write-Warn "Unrecognized file in cidata source, copying anyway: $($file.Name)"
        }
    }

    if (Test-Path -LiteralPath $Path) {
        if (-not $Force) { throw "cidata disk already exists: $Path (pass -Force to replace it)" }
        Dismount-VHD -Path $Path -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Path -Force
    }

    Write-Step 'Building cidata disk'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null

    # 64 MB is far more than the handful of small text files need, and is above
    # the floor where Windows will still hand us a FAT32 volume.
    New-VHD -Path $Path -SizeBytes 64MB -Fixed | Out-Null

    $mounted = $null
    try {
        $mounted = Mount-VHD -Path $Path -Passthru | Get-Disk
        Initialize-Disk -Number $mounted.Number -PartitionStyle MBR -Confirm:$false | Out-Null
        $partition = New-Partition -DiskNumber $mounted.Number -UseMaximumSize -AssignDriveLetter
        # FAT32 uppercases the label to CIDATA. cloud-init's NoCloud datasource
        # - which is where the `cidata` name comes from - matches it
        # case-insensitively, and so does blkid's LABEL lookup.
        Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Confirm:$false | Out-Null

        $drive = "$($partition.DriveLetter):"
        foreach ($file in $files) {
            Copy-Item -LiteralPath $file.FullName -Destination $drive -Force
            Write-Ok "  $($file.Name)"
        }
    } finally {
        if ($mounted) { Dismount-VHD -Path $Path -ErrorAction SilentlyContinue }
    }

    Write-Ok "cidata disk at $Path"
    $Path
}

<#
Hashes a password the way Omarchy's user_credentials.json wants it (SHA-512
crypt, i.e. `openssl passwd -6`). Windows has no crypt(3), so we borrow one:
openssl if it is on PATH, else any WSL distro. Neither present means the user
generates the hash themselves - we will not silently write a weaker one.
#>
function New-OmarchyPasswordHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][securestring]$Password)

    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))

    try {
        if (Get-Command openssl -ErrorAction SilentlyContinue) {
            return (& openssl passwd -6 $plain).Trim()
        }
        if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
            $hash = (& wsl.exe -e openssl passwd -6 $plain 2>$null)
            if ($LASTEXITCODE -eq 0 -and $hash) { return ($hash -join '').Trim() }
        }
        throw 'No openssl available (tried PATH and wsl.exe). Generate the hash yourself with: openssl passwd -6 "yourpassword"'
    } finally {
        $plain = $null
        [GC]::Collect()
    }
}
