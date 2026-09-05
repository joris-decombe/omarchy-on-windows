# Display.
#
# Hyper-V hands a Gen 2 Linux guest a synthetic KMS display driven by the
# in-kernel hyperv_drm module. That matters more than it sounds: it is a real
# DRM device, so Hyprland's DRM backend has something to run on. (This is
# exactly what WSL2 cannot offer - no /dev/dri there at all, which is why
# Hyprland cannot run under WSL and can run here.)
#
# There is no GPU behind it. Rendering is Mesa's llvmpipe on the host CPU, so
# the perf module turns off everything expensive. See lib/perf.sh.
#
# Resolution is fixed at boot by the hyperv_fb kernel parameter; the guest
# cannot renegotiate it the way a normal monitor would.

OW_RESOLUTION=${OW_RESOLUTION:-1920x1080}
OW_LIMINE_DROP_IN=/etc/limine-entry-tool.d/omarchy-on-windows.conf

ow_display() {
  step "Display (${OW_RESOLUTION})"

  # The node is not always card0 -- hyperv_drm lands on whatever minor is
  # free, commonly card1 -- and it is KMS-only, so there is no renderD*
  # node beside it. Match the family, not a fixed name.
  local cards=(/dev/dri/card*)
  if [[ -e ${cards[0]} ]]; then
    ok "DRM device present: ${cards[*]}"
  else
    warn 'No /dev/dri/card* device. Hyprland cannot start without one.'
    note 'Check that the guest is Generation 2 and that hyperv_drm loaded: lsmod | grep hyperv_drm'
  fi

  if ! lsmod | grep -q '^hyperv_drm'; then
    warn 'hyperv_drm is not loaded. On a Gen 2 VM it should autoload.'
  fi

  # Pin the framebuffer mode. Hyper-V's synthetic video tops out at 1920x1200
  # for Linux guests, so anything larger silently falls back.
  write_file "$OW_LIMINE_DROP_IN" sudo <<CONF
$OW_STAMP
#
# Hyper-V's synthetic display has no EDID and no mode list, so the resolution
# is whatever the kernel is told at boot. Change it here and re-run
# 'sudo limine-mkinitcpio', or just re-run install.sh with OW_RESOLUTION set.
KERNEL_CMDLINE[default]+=" video=hyperv_fb:${OW_RESOLUTION}"
CONF

  if [[ $OW_WROTE == 1 && $OW_DRY_RUN != 1 ]]; then
    # limine-mkinitcpio rebuilds the initramfs and UKI for every kernel, which
    # takes minutes. Only worth it when the command line actually changed.
    step 'Rebuilding boot entries (limine-mkinitcpio)'
    run sudo limine-mkinitcpio || warn 'limine-mkinitcpio failed; the resolution change will not take effect until it succeeds.'
    note 'The resolution change needs a reboot.'
  else
    note 'Kernel command line unchanged; skipping the initramfs rebuild.'
  fi

  # Omarchy loads ~/.config/hypr/monitors.lua after its own defaults, which is
  # the supported place to override without fighting package updates.
  write_file "$HOME/.config/hypr/monitors.lua" <<LUA
-- $OW_STAMP
--
-- Hyper-V exposes a single synthetic output. Its mode is fixed by the
-- video=hyperv_fb= kernel parameter (see $OW_LIMINE_DROP_IN),
-- so "preferred" is the only mode there is and scaling stays at 1: a
-- fractional scale would cost llvmpipe another full-frame resample.
hl.monitor({ output = "", mode = "${OW_RESOLUTION}@60", position = "auto", scale = 1 })

-- GDK_SCALE of 1 to match. Omarchy's default of 2 assumes a HiDPI laptop panel.
hl.env("GDK_SCALE", "1")
LUA

  ok 'Monitor configured'
}
