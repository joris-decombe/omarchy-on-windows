# Remote desktop in WSL: measured, and it does not work. This module exists to
# say why, once, with evidence, so nobody re-treads the path.
#
# What was tried, on Fedora 44 / GNOME 50.4 under WSL2 (kernel 6.18):
#
#   1. Nested GNOME (gnome-shell inside WSLg).
#      WSLg's Weston advertises neither zwp_linux_dmabuf_v1 nor wl_drm -- there
#      is no DRM device to back them. Mutter's nested backend needs one of the
#      two to allocate its output buffers, so it abandons nested mode, falls
#      back to running as a display server, and dies on logind:
#         Failed to setup: Failed to find any matching session
#
#   2. Headless GNOME + gnome-remote-desktop, per-user ("--headless") mode.
#      Configuration applies correctly -- dconf shows rdp/headless enable=true,
#      the port set, valid TLS paths, credentials stored -- and the daemon runs
#      without complaint. It never binds a port.
#
#   3. Headless GNOME + gnome-remote-desktop sharing that session (user mode).
#      This one names the cause outright:
#         libEGL warning: MESA-LOADER: failed to retrieve device information
#         libEGL warning: failed to get driver name for fd -1
#         gnome-remote-desktop.service: Main process exited, status=11/SEGV
#      gnome-remote-desktop needs an EGL device for its capture and encode
#      pipeline. With no DRM node it gets fd -1 and segfaults.
#
# The common cause is the one constant of WSL: /dev/dxg, no /dev/dri. Mesa's
# d3d12 driver renders *applications* through /dev/dxg without DRM, which is
# why GPU acceleration works for apps -- but a compositor's display and capture
# paths want a DRM device, and nothing substitutes for it.
#
# So: for a full desktop, use the Hyper-V VM (guest/setup.sh); it is software
# rendered but complete. For GPU-accelerated applications, use this kit and run
# them as WSLg apps -- they appear as ordinary Windows windows.

lw_remote_desktop() {
  step 'Remote desktop'

  warn 'Not supported in WSL, and not for want of configuration.'
  note 'gnome-remote-desktop segfaults here: it needs an EGL device for its'
  note 'capture pipeline and WSL has no DRM node to provide one. The full'
  note 'investigation, with the three approaches tried and the errors each'
  note 'produced, is in the comment at the top of wsl/lib/remote-desktop.sh.'
  note ''
  note 'For a complete desktop use the VM:      guest/setup.sh'
  note 'For GPU-accelerated apps use this kit:  they run as WSLg windows.'
  return 0
}
