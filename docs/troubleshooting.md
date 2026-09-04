# Troubleshooting

Run `bash guest/doctor.sh` inside the guest first. It checks each piece and
prints the fix under any that fails.

## The VM will not boot the ISO

Secure Boot. `New-OmarchyVM` disables it, but if you built the VM by hand:

```powershell
Set-VMFirmware -VMName Omarchy -EnableSecureBoot Off
```

The Omarchy ISO is not signed for Microsoft's UEFI CA — the manual says the
same for bare metal.

## Hyper-V cmdlets say "You do not have the required permission"

Run PowerShell elevated, or add yourself to the group once and sign out:

```powershell
Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member $env:USERNAME
```

## Hyprland will not start in the guest

```bash
ls /dev/dri
```

Expect `card0`. No device means the VM is Generation 1 — Hyper-V cannot convert
a VM's generation, so recreate it. If the device is there but Hyprland still
dies, check that the driver loaded with `lsmod | grep hyperv_drm`.

## Get-OmarchyVMAddress finds nothing

The host learns the guest's address from the KVP daemon, which is in the Arch
`hyperv` package:

```bash
sudo systemctl enable --now hv_kvp_daemon.service
```

Until then, read it in the guest with `ip -4 addr`.

## Moonlight cannot find the host

Sunshine has to be running in a **logged-in graphical session** — it is a user
service capturing a live compositor, not a system daemon.

```bash
systemctl --user status sunshine
journalctl --user -u sunshine -n 50
ss -tlnp | grep 4798
```

If it is listening but Moonlight still cannot reach it, check ufw
(`sudo ufw status`) and that the Hyper-V switch subnet in those rules still
matches the guest's current address — the Default Switch renumbers on host
reboot. Refresh them with:

```bash
bash guest/install.sh --only firewall
```

## Pairing PIN never appears

Moonlight shows the PIN; you type it into **Sunshine's** web UI, which runs in
the guest at `https://<guest-ip>:47990`. Its certificate is self-signed, so
accept the warning. Open it from a browser inside the guest — the `lan` origin
policy will not accept it from elsewhere.

## No sound

```bash
pactl list short sinks
pactl get-default-sink
```

Expect `omarchy-stream` in both. There is no hardware sink under Hyper-V, so if
it is missing then nothing has anywhere to play:

```bash
bash guest/install.sh --only audio
```

If the sink exists but Moonlight is silent, check that `audio_sink` in
`~/.config/sunshine/sunshine.conf` reads `omarchy-stream.monitor` — the
monitor, not the sink.

## The desktop is sluggish

Expected to a point: this is CPU rendering plus CPU encoding. Things that help,
in order of effect:

1. More vCPUs. `Set-VMProcessor -VMName Omarchy -Count 12` with the VM off.
2. A lower resolution: `bash guest/install.sh --resolution 1600x900`, reboot.
3. `--fps 30` if the encoder rather than the compositor is the bottleneck.
4. Confirm the perf profile actually loaded:
   `grep -n omarchy-on-windows ~/.config/hypr/looknfeel.lua`

`htop` in the guest during a stream tells you which half is saturated: Hyprland
means compositing, `sunshine` means encoding.

## Resolution changes did nothing

The mode is a kernel parameter and needs a reboot after
`sudo limine-mkinitcpio`. Verify it landed:

```bash
grep -o 'video=hyperv_fb:[^ ]*' /proc/cmdline
```

Nothing there means `limine-mkinitcpio` did not rerun. Run it by hand and
reboot.

## Starting over

```powershell
Remove-OmarchyVM -Name Omarchy -DeleteDisks
```
