# Software-rendering profile.
#
# There is no GPU in a Hyper-V Linux guest - no passthrough, no GPU-PV, no DDA
# outside Windows Server - so every pixel Hyprland and Quickshell draw goes
# through Mesa's llvmpipe on host CPU cores. That is fine for a tiling desktop
# and terrible for the effects Omarchy turns on by default.
#
# Rather than overwrite Omarchy's own ~/.config/hypr/looknfeel.lua (yours to
# edit), we write a sibling module and make sure looknfeel.lua requires it.

OW_HYPR_MODULE="$HOME/.config/hypr/omarchy-on-windows.lua"
OW_HYPR_LOOKNFEEL="$HOME/.config/hypr/looknfeel.lua"
OW_HYPR_REQUIRE='require("hypr.omarchy-on-windows")'

ow_perf() {
  step 'Software-rendering profile'

  write_file "$OW_HYPR_MODULE" <<LUA
-- $OW_STAMP
--
-- Hyper-V gives the guest no GPU, so Hyprland renders through llvmpipe on the
-- host CPU. Everything below trades an effect for frames.

hl.config({
  animations = {
    -- Every animated frame is a full CPU composite. At 1080p that is the
    -- difference between a desktop that feels instant and one that smears.
    enabled = false,
  },

  decoration = {
    rounding = 0,
    dim_inactive = false,
    blur = { enabled = false },
    shadow = { enabled = false },
  },

  cursor = {
    -- hyperv_drm exposes no hardware cursor plane. Without these the pointer
    -- is invisible or leaves trails.
    no_hardware_cursors = true,
    use_cpu_buffer = true,
  },
})

-- Not set here: VFR. Hyprland idles the refresh rate on its own (vfr defaults
-- to on), and 0.55 moved the key to debug: precisely because it is not meant
-- to be set in a real config. Setting misc.vfr made Hyprland refuse the whole
-- file with "unknown config key".

-- Mesa picks llvmpipe here anyway; saying so explicitly keeps it from probing
-- for a hardware driver on every client start.
hl.env("LIBGL_ALWAYS_SOFTWARE", "1")

-- Quickshell (omarchy-shell) is Qt Quick. Its threaded render loop costs more
-- than it saves when the "GPU" is the same CPU running the scene graph.
hl.env("QSG_RENDER_LOOP", "basic")
LUA

  # Omarchy's hyprland.lua requires a fixed list of user modules, and ours is
  # not on it. Hook in from looknfeel.lua, which is on the list.
  if [[ ! -f $OW_HYPR_LOOKNFEEL ]]; then
    write_file "$OW_HYPR_LOOKNFEEL" <<LUA
-- Change the default Omarchy look'n'feel.

$OW_HYPR_REQUIRE
LUA
  elif grep -qF "$OW_HYPR_REQUIRE" "$OW_HYPR_LOOKNFEEL"; then
    note "already hooked into $OW_HYPR_LOOKNFEEL"
  else
    if [[ $OW_DRY_RUN == 1 ]]; then
      note "[dry-run] append require to $OW_HYPR_LOOKNFEEL"
    else
      printf '\n-- %s\n%s\n' "$OW_STAMP" "$OW_HYPR_REQUIRE" >>"$OW_HYPR_LOOKNFEEL"
      ok "hooked into $OW_HYPR_LOOKNFEEL"
    fi
  fi

  note 'Reload with: hyprctl reload'
}
