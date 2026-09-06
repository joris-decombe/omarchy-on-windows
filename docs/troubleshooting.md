# Troubleshooting

Start with `sudo bash guest/doctor.sh` inside the guest. It checks each piece
and prints the fix under any that fails, and it never blocks on a password
prompt.

## Hyper-V cmdlets say "You do not have the required permission"

Run PowerShell elevated, or add yourself to the group once:

```powershell
Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member $env:USERNAME
```

Then **sign out and back in**. Group membership only takes effect on a new
logon token, so it will keep failing in your current session.

## The VM will not boot the ISO

Secure Boot. Generation 2 VMs default to the Windows template, which rejects a
Linux bootloader:

```powershell
Set-VMFirmware -VMName Fedora -EnableSecureBoot Off
```

Or, for a signed distro like Fedora, use the right template instead:

```powershell
Set-VMFirmware -VMName Fedora -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
```

## Caps Lock is out of sync in the Hyper-V console

The basic session does not propagate lock-key state to the guest: the guest
tracks its own Caps Lock, so the two drift apart and your host keyboard LED is
reporting Windows, not the VM. You get inverted case with nothing on screen to
explain it.

During an install this matters most for the password, because you will not find
out it went in inverted until the login screen rejects it. Use Shift rather
than Caps Lock -- modifiers pass through correctly -- and reveal the password
field before committing to it. Pressing Caps Lock once inside the VM window
resyncs the two.

This is a console-only problem. `mstsc` synchronizes lock keys when it
connects, so it disappears once you are on RDP.

## Get-LinuxVMAddress finds nothing

The host learns the address from the KVP daemon, in the `hyperv-daemons`
package:

```bash
sudo systemctl enable --now hypervkvpd.service
```

Until then, read it in the guest with `ip -4 addr`.

## mstsc cannot connect

Check the guest is actually listening:

```bash
ss -tlnp | grep 3389
systemctl status gnome-remote-desktop
journalctl -u gnome-remote-desktop -n 50
```

A service that is up but not bound is nearly always the TLS certificate: it is
missing, or `gnome-remote-desktop` cannot read it. Re-run
`sudo bash guest/setup.sh --only remote_desktop`.

If it is listening but Windows still cannot reach it, check firewalld
(`sudo firewall-cmd --list-all`) and confirm the allowed subnet still matches
the guest's current address — the Hyper-V Default Switch renumbers on host
reboot. Refresh with `sudo bash guest/setup.sh --only firewall`.

## mstsc refuses because of the certificate

The certificate is self-signed, so `mstsc` will not accept it under the default
authentication level. `Start-LinuxDesktop` writes a profile with
`authentication level:i:0` for that reason. If you are connecting by hand with
`mstsc /v:<ip>`, you will hit this — use `Start-LinuxDesktop` instead, or add
the setting to your own `.rdp` file.

## I get a login screen but the session never starts

That is Remote Login working and the session failing behind it. Check the
journal for `gnome-remote-desktop` and for GDM:

```bash
journalctl -u gnome-remote-desktop -b
journalctl -u gdm -b | tail -50
```

On a CPU-only guest a session can simply be slow to appear the first time,
while `llvmpipe` warms up.

## No sound

Audio rides the RDP connection, so it is a client-side setting as often as a
guest one. Confirm the profile has `audiomode:i:0` — "play on this computer".
`Start-LinuxDesktop` sets it; a hand-made connection may not.

In the guest, the RDP session gets its own PipeWire sink from
`gnome-remote-desktop`. A missing sink on the *console* session is normal and
not a fault — there is no sound card for it to find.

## The window will not resize the desktop

Dynamic resolution needs three things: GNOME 46+, Remote **Login** (not the
per-user Remote Desktop mode), and `dynamic resolution:i:1` in the profile.
Check the first two with:

```bash
gnome-shell --version
grdctl --system status
```

If GNOME is older than 46, headless Remote Login does not exist and no client
setting will produce it.

## Everything is slow

Expected to a point — this is `llvmpipe` on host CPU cores, with no GPU
available to a Hyper-V Linux guest at all. What helps, in order:

1. More vCPUs: `Set-VMProcessor -VMName Fedora -Count 12` with the VM off.
2. Turn off GNOME animations (`gsettings set org.gnome.desktop.interface enable-animations false`).
3. A smaller window — every pixel is composited and encoded on the CPU.

## Starting over

```powershell
Remove-LinuxVM -Name Fedora -DeleteDisks
```
