# omarchy-on-windows

Run [Omarchy](https://omarchy.org) on Windows — the real desktop, with its
Hyprland session, its bar, its menu and its themes — in a Hyper-V VM, showing
up in a window on the Windows desktop with working sound.

Two halves:

- **`windows/`** — a PowerShell module that builds the Hyper-V VM correctly the
  first time and opens the desktop stream.
- **`guest/`** — a shell kit you run once inside Omarchy that wires the guest to
  its Windows host: integration services, display mode, a rendering profile for
  a GPU-less VM, a virtual sound device, and the stream.

## Why not WSL?

Because Hyprland cannot start there, and the reason is structural rather than a
missing package. WSL2 gives a distro `/dev/dxg` and Mesa's `d3d12` driver, but
**no DRM render node** — there is no `/dev/dri` at all, and the WSL kernel ships
with `CONFIG_DRM_VKMS` unset. Modern Hyprland (via aquamarine) needs a GBM
device from a DRM node for both its `drm` and its nested `wayland` backend, and
it dropped the old software/pixman path that once made this work. No render
node, no compositor.

Hyper-V does not have that problem. A Generation 2 Linux guest gets
`hyperv_drm`, a genuine KMS device, so Hyprland's DRM backend has something to
run on.

You can check the WSL side yourself:

```bash
ls /dev/dri            # No such file or directory
zcat /proc/config.gz | grep VKMS   # CONFIG_DRM_VKMS is not set
```

## Why Sunshine and not the Hyper-V window?

Hyper-V gives a Linux guest video but **no sound device of any kind**, and its
answer to that — Enhanced Session Mode — is xrdp serving an X11 session, which
a Wayland compositor cannot provide. VNC works with Hyprland but carries no
audio.

So the console is for installing, and the desktop arrives over
[Sunshine](https://github.com/LizardByte/Sunshine) →
[Moonlight](https://moonlight-stream.org/): one connection carrying video,
audio, keyboard and mouse, in a resizable window on Windows. The guest gets a
PipeWire null sink as its default output and Sunshine captures its monitor, so
applications see an ordinary sound card and you hear it on Windows.

## The catch, stated plainly

There is no GPU in a Hyper-V Linux guest. Not GPU-PV (WSL-kernel only), not DDA
(Windows Server only), not passthrough. Hyprland and Quickshell render through
Mesa's **llvmpipe on host CPU cores**, and Sunshine encodes H.264 in software.

On a many-core desktop that is genuinely usable — the guest kit turns off
animations, blur, shadows and hardware cursors, and enables VFR so an idle
desktop costs nothing. It is not what Omarchy feels like on bare metal, and it
never will be inside Hyper-V. If you want acceleration, that is a different
hypervisor (virtio-gpu venus under QEMU) or a real partition.

## Requirements

- Windows 10/11 Pro, Enterprise or Education, with Hyper-V enabled
- An elevated PowerShell (or membership of **Hyper-V Administrators**)
- The Omarchy ISO from <https://omarchy.org/>
- ~30 GB free for the VM disk to grow into, 8 vCPU and 12 GB RAM by default

## Install

### 1. Create the VM

From an **elevated** PowerShell:

```powershell
cd windows
.\New-OmarchyVM.ps1 -IsoPath D:\iso\omarchy.iso
```

That runs preflight, creates a Generation 2 VM with **Secure Boot off** (the
ISO will not boot otherwise), pins the memory, turns off automatic checkpoints,
and opens the Hyper-V console. Run the Omarchy installer there.

For a throwaway VM, hit `Ctrl+C` at the disk confirmation to skip full-disk
encryption — otherwise you type a LUKS passphrase into the console on every
boot, before any of this repo's plumbing exists.

Useful switches: `-Name`, `-ProcessorCount`, `-MemoryGB`, `-DiskGB`,
`-SwitchName`, `-VMPath`, `-NestedVirtualization`, `-CidataDir`.

### 2. Set up the guest

Inside Omarchy:

```bash
git clone https://github.com/joris-decombe/omarchy-on-windows.git
bash omarchy-on-windows/guest/install.sh
```

Then reboot, so the display mode takes effect.

`--dry-run` shows every change without making one. `--only`/`--skip` narrow it
to a module. `--resolution WxH` picks the mode (Hyper-V's synthetic display
tops out at 1920x1200).

### 3. Open the desktop

Back on Windows:

```powershell
Import-Module .\windows\Omarchy.psd1
Install-OmarchyMoonlight
Start-OmarchyDesktop
```

Moonlight shows a pairing PIN the first time. Enter it at
`https://<guest-ip>:47990` in a browser **inside the guest**. One-off.

## Commands

### Windows

| Command | What it does |
|---|---|
| `Test-OmarchyHost` | Preflight only: elevation, Hyper-V, switch, ISO, disk space |
| `New-OmarchyVM` | Create and start the VM |
| `Connect-OmarchyVM` | Open the Hyper-V console (basic session, no sound) |
| `Remove-OmarchyVM` | Delete the VM, optionally its disks |
| `Get-OmarchyVMAddress` | Guest IP, as reported by the KVP daemon |
| `Copy-OmarchyGuestKit` | scp `guest/` into the VM |
| `Install-OmarchyMoonlight` | Install Moonlight via winget |
| `Start-OmarchyDesktop` | Stream the desktop |
| `New-OmarchyCidataDisk` | Build an unattended-install drive |
| `New-OmarchyPasswordHash` | SHA-512 crypt hash for `user_credentials.json` |

### Guest

| Command | What it does |
|---|---|
| `guest/install.sh` | Set everything up; idempotent, re-runnable |
| `guest/doctor.sh` | Check every piece and print the fix for each failure |

## Unattended installs

The Omarchy ISO skips its wizard when it finds a second drive labeled `cidata`
carrying the installer's config files. Get those files by running one
interactive install and copying `/root` off it, then:

```powershell
.\New-OmarchyVM.ps1 -IsoPath D:\iso\omarchy.iso -CidataDir C:\omarchy\cidata
```

We build a FAT32 VHDX rather than an ISO — Windows has no `genisoimage`, and a
VHDX is something PowerShell can make natively. The files' schema belongs to
Omarchy's installer, so this repo does not invent them; see
[the Omarchy manual on unattended installs](https://github.com/omacom/omarchy/blob/quattro/manual/51-unattended-installs.md).

## What gets changed in the guest

| Path | Why |
|---|---|
| `/etc/limine-entry-tool.d/omarchy-on-windows.conf` | `video=hyperv_fb:WxH` — the synthetic display has no EDID, so the mode comes from the kernel command line |
| `~/.config/hypr/monitors.lua` | Single output at that mode, scale 1 |
| `~/.config/hypr/omarchy-on-windows.lua` | Software-rendering profile |
| `~/.config/hypr/looknfeel.lua` | One `require` line appended to load the above |
| `~/.config/pipewire/pipewire.conf.d/50-omarchy-stream-sink.conf` | The null sink Sunshine captures |
| `~/.config/sunshine/{sunshine.conf,apps.json}` | Software encode, wlr capture, that sink |
| ufw | Sunshine's ports, from the Hyper-V switch subnet only |

Everything lands in Omarchy's own override locations, so package updates do not
fight it and removing these files restores stock behaviour.

## Troubleshooting

Start with `bash guest/doctor.sh` — it checks each piece and prints the fix.
More in [docs/troubleshooting.md](docs/troubleshooting.md), and the reasoning
behind the design in [docs/architecture.md](docs/architecture.md).

## Status

Early. The host side is exercised on Windows 11 26200 with WSL 2.7.12 present;
the guest side targets Omarchy 4.x ("quattro"), whose Lua Hyprland config and
limine drop-ins this depends on.

## License

MIT.
