# Architecture

## The constraint that decides everything

Modern Hyprland renders through [aquamarine](https://wiki.hypr.land/Hypr-Ecosystem/aquamarine/),
which needs a GBM device obtained from a DRM node — for its `drm` backend and
for its nested `wayland` backend alike. The old wlroots pixman software path
that let people run Hyprland in odd places is gone.

So the question "can Omarchy run here?" reduces to "is there a `/dev/dri`?"

| Environment | DRM node | Hyprland |
|---|---|---|
| WSL2 | none — `/dev/dxg` and Mesa `d3d12` only, `CONFIG_DRM_VKMS` unset | no |
| WSL2 + custom kernel with vkms | yes, software KMS | yes, but a custom kernel for every distro on the machine |
| Hyper-V Gen 2 | yes — `hyperv_drm` | yes |
| QEMU/KVM | yes — virtio-gpu, and accelerated with venus | yes, fastest |

This repo takes the Hyper-V route: a real DRM device on a stock kernel, using
the hypervisor Windows already ships.

## The second constraint: sound

Hyper-V emulates no audio hardware for a Linux guest. There is nothing for
PipeWire to find. Hyper-V's own answer is Enhanced Session Mode, which is xrdp
serving an **X11** session over `hv_sock` — and a Wayland compositor has no X11
session to serve. The two features are mutually exclusive: you can have
Hyprland or you can have Hyper-V's sound, not both through that door.

Options considered:

| Approach | Video | Audio | Works with Hyprland |
|---|---|---|---|
| Hyper-V basic console | yes | no | yes |
| Enhanced Session Mode (xrdp) | yes | yes | **no** |
| wayvnc / VNC | yes | no | yes |
| gnome-remote-desktop | yes | yes | GNOME only |
| **Sunshine → Moonlight** | yes | **yes** | **yes** |

Sunshine captures the live Hyprland session over `wlr-screencopy`, captures a
PipeWire sink monitor for audio, encodes H.264, and Moonlight on Windows plays
both while sending input back. One connection, one window, sound included.

The Hyper-V console stays useful: it is how you install, and it is a silent
fallback when the stream will not start.

## Rendering

There is no GPU. Not by omission — Hyper-V has no path to one for a Linux
guest:

- **GPU-PV** (what WSL2 uses) requires `dxgkrnl` in the guest, which Microsoft
  ships only in the WSL kernel — and it yields `/dev/dxg`, not a DRM node, so
  it would not help Hyprland even if you got it working.
- **DDA** (full device assignment) is a Windows Server feature.
- **RemoteFX vGPU** was removed in 2020.

So Mesa falls back to `llvmpipe` on `hyperv_drm`'s dumb buffers, and every
frame is composited on host CPU cores. `guest/lib/perf.sh` responds to that by
turning off animations, blur, shadows, rounding and hardware cursors, and
enabling VFR so an idle desktop costs nothing.

Sunshine's encode is likewise software x264 at `superfast`/`zerolatency`.
Between compositing and encoding, expect to spend a few host cores while you
are actively using the desktop.

## Display mode

Hyper-V's synthetic display has no EDID and no mode list, so the guest cannot
negotiate a resolution the way it would with a monitor. The mode is fixed at
boot by `video=hyperv_fb:WxH` on the kernel command line, and 1920x1200 is the
ceiling.

Omarchy uses limine with `limine-entry-tool` drop-ins, so we write
`/etc/limine-entry-tool.d/omarchy-on-windows.conf` and run
`sudo limine-mkinitcpio` — the same mechanism `omarchy-hibernation-setup` uses
for its own `resume=` parameters. A reboot applies it.

## Fitting into Omarchy without fighting it

Omarchy 4 ("quattro") configures Hyprland in Lua. Its `~/.config/hypr/hyprland.lua`
loads package defaults from `$OMARCHY_PATH/default/hypr/`, then a fixed list of
user modules: `monitors`, `input`, `bindings`, `looknfeel`, `autostart`. Those
user files are yours; the defaults belong to the package and are replaced on
update.

So:

- **`monitors.lua`** we own outright — its stock content is one `hl.monitor()`
  call and a `GDK_SCALE`, both of which are wrong for a fixed synthetic display.
- **The rendering profile** goes in a sibling module,
  `~/.config/hypr/omarchy-on-windows.lua`, with a single `require` line appended
  to `looknfeel.lua`. That way your own look-and-feel edits survive, and the
  hook is idempotent.

Nothing under `$OMARCHY_PATH` is touched.

## Why this is not an Omarchy plugin

Omarchy has a real plugin system, but it loads **QML plugins inside the running
`omarchy-shell` Quickshell process** — bar widgets, panels, overlays, menus,
headless services. A plugin cannot influence installation, kernel parameters,
bootloader entries, systemd units, or how the compositor starts. Everything
this repo does happens before or below the point where a plugin exists.
