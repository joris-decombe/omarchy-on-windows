# linux-on-hyperv

Run a Linux desktop on Windows in a Hyper-V VM, with display, **sound**,
clipboard and a resolution that follows the window — over the Remote Desktop
client Windows already ships.

Two halves:

- **`windows/`** — a PowerShell module that builds the Hyper-V VM correctly the
  first time and opens the desktop.
- **`guest/`** — a shell kit you run once inside Fedora that turns on GNOME's
  own RDP server and wires up the Hyper-V integration services.

## Why RDP, and not screen capture

Hyper-V gives a Linux guest a KMS display but **no sound card of any kind**,
and its Enhanced Session Mode is xrdp serving X11. So the built-in console can
show you a desktop but can never give you audio, a clipboard, or a resizable
window.

The obvious fix is to capture the desktop and stream it (Sunshine → Moonlight).
That works, but on a GPU-less VM it means software capture *and* software H.264
encode, plus a pairing dance, plus a capture backend that has to match your
compositor — and the resolution is still pinned by a kernel argument.

GNOME already solves all of this. `gnome-remote-desktop` **is** an RDP server,
and since GNOME 46 it offers **Remote Login**: a headless session created on
demand, with a virtual monitor sized by whatever client connects. So:

| | Sunshine/Moonlight | GNOME Remote Login |
|---|---|---|
| Video | yes | yes |
| Audio | yes, via a null sink you build | yes, built in |
| Clipboard | no | yes |
| Resize with the window | no (fixed mode) | **yes** |
| Client | install Moonlight | `mstsc.exe`, already present |
| Setup | pair by PIN, `setcap`, pick a capture backend | one command |

There is still no GPU in a Hyper-V Linux guest — GPU-PV is WSL-kernel only, DDA
is Windows Server only — so GNOME renders on `llvmpipe`. It is perfectly usable
for everything except 3D.

## Requirements

- Windows 10/11 Pro, Enterprise or Education with Hyper-V enabled
- A [Fedora Workstation](https://fedoraproject.org/workstation/) ISO (**GNOME 46
  or newer** — Remote Login does not exist before that)
- ~30 GB free for the VM disk to grow into; 8 vCPU and 12 GB RAM by default

Give yourself Hyper-V access once, instead of a UAC prompt per command:

```powershell
Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member $env:USERNAME
```

Then sign out and back in — group membership only applies to a new logon token.

## Install

### 1. Create the VM

```powershell
cd windows
.\New-LinuxVM.ps1 -IsoPath D:\iso\Fedora-Workstation-Live-x86_64.iso
```

Runs preflight, creates a Generation 2 VM with pinned memory and no automatic
checkpoints, and opens the Hyper-V console. Install Fedora there and reboot.

Fedora is signed for Microsoft's third-party UEFI CA, so `-SecureBoot` works —
but only under the `MicrosoftUEFICertificateAuthority` template, which is not
the one Hyper-V picks by default. The script handles that; Secure Boot is off
unless you ask for it.

Other switches: `-Name`, `-ProcessorCount`, `-MemoryGB`, `-DiskGB`,
`-SwitchName`, `-VMPath`, `-NestedVirtualization`.

### 2. Set up the guest

Inside Fedora:

```bash
sudo dnf install -y git
git clone https://github.com/joris-decombe/linux-on-hyperv.git
sudo bash linux-on-hyperv/guest/setup.sh
```

`--dry-run` shows every change without making one. `--only`/`--skip` narrow it
to a module.

### 3. Open the desktop

```powershell
Import-Module .\windows\HyperVLinux.psd1
Start-LinuxDesktop
```

You get a GDM login screen over RDP. Log in with the guest's own username and
password — Remote Login has no separate RDP credentials.

## Commands

### Windows

| Command | What it does |
|---|---|
| `Test-HyperVHost` | Preflight only: access, Hyper-V, switch, ISO, disk space |
| `New-LinuxVM` | Create and start the VM |
| `Connect-LinuxVM` | Open the Hyper-V console (basic session, no sound) |
| `Remove-LinuxVM` | Delete the VM, optionally its disks |
| `Get-LinuxVMAddress` | Guest IP, as reported by the KVP daemon |
| `Start-LinuxDesktop` | Open the desktop over RDP |
| `Copy-GuestKit` | scp `guest/` into the VM |

### Guest

| Command | What it does |
|---|---|
| `guest/setup.sh` | Set everything up; idempotent, re-runnable |
| `guest/doctor.sh` | Check every piece and print the fix for each failure |

## What gets changed in the guest

| Path | Why |
|---|---|
| `hyperv-daemons` package + units | So the host can read the guest's IP |
| `/var/lib/gnome-remote-desktop/certificates/` | Self-signed TLS cert; `grdctl` will not enable RDP without one |
| `grdctl --system rdp` settings | Turns on Remote Login |
| `gnome-remote-desktop.service` | The system (not per-user) unit |
| firewalld | TCP+UDP 3389, scoped to the guest's own subnet |

## Troubleshooting

Start with `sudo bash guest/doctor.sh`. More in
[docs/troubleshooting.md](docs/troubleshooting.md); the reasoning behind the
design is in [docs/architecture.md](docs/architecture.md).

## History

This started as an Omarchy project — Hyprland on Arch — and the git history
shows it. I dropped it once I learned who its creator is and read what he
posts. I don't want anything to do with him or his software, and that came
first; the technical case for leaving happened to be just as strong.

Omarchy was fine software. The problem was never Omarchy — it was the
combination of a tiling Wayland compositor with a hypervisor that offers no
GPU and no sound card, which forced a capture-and-stream design where every
piece had to be built by hand. Moving to GNOME replaced that whole stack with
an RDP server the desktop already ships, and made the window resizable as a
side effect. [docs/architecture.md](docs/architecture.md) has the reasoning.

Four real bugs turned up along the way, all of them found by running the thing
rather than reading it: a hardcoded `/dev/dri/card0` that misses `hyperv_drm`'s
`card1`, a Hyprland config key that silently voided the entire config file, a
systemd unit the Sunshine package does not actually ship, and a capture backend
Hyprland cannot feed. The Hyper-V half of that work carried over unchanged; the
guest half was replaced.

## License

MIT.
