# Display and sound on Windows, via Sunshine -> Moonlight.
#
# Why not something simpler:
#
#   Hyper-V basic console  video, but no sound and no clipboard. Fine for the
#                          installer, not for a desktop.
#   Enhanced Session Mode  gives sound and clipboard, but it is xrdp serving an
#                          X11 session. Hyprland is Wayland-only, so there is
#                          nothing for it to serve.
#   VNC (wayvnc)           works with Hyprland, carries no audio at all.
#
# Sunshine captures the running Hyprland session through wlr-screencopy,
# encodes H.264 in software (there is no GPU to encode with), captures the
# null sink from lib/audio.sh, and Moonlight on Windows plays both with input
# going back the other way. One connection, video plus sound plus keyboard and
# mouse, in a resizable window on the Windows desktop.

OW_SINK_NAME=${OW_SINK_NAME:-omarchy-stream}
OW_STREAM_FPS=${OW_STREAM_FPS:-60}

ow_streaming() {
  step 'Sunshine (desktop streaming to Windows)'

  # Prefer the prebuilt package: building Sunshine from source inside a
  # CPU-only VM takes the better part of an hour.
  if pkg_installed sunshine || pkg_installed sunshine-bin; then
    note 'already installed: sunshine'
  elif ! aur_install sunshine-bin; then
    warn 'sunshine-bin unavailable; falling back to a source build (this takes a while).'
    aur_install sunshine
  fi

  local config_dir="$HOME/.config/sunshine"

  write_file "$config_dir/sunshine.conf" <<CONF
# $OW_STAMP

# Capture the live Hyprland session over wlr-screencopy. The kms backend would
# need cap_sys_admin and buys nothing here, since hyperv_drm has no scanout we
# could grab more cheaply.
capture = wlr

# No GPU in a Hyper-V guest, so x264 on the host CPU it is. On a modern
# many-core host this encodes 1080p60 without breaking a sweat; the guest's
# vCPU count is what to raise if the stream stutters.
encoder = software
sw_preset = superfast
sw_tune = zerolatency

# Matching the guest's fixed hyperv_fb mode avoids a scale on both ends.
fps = [$OW_STREAM_FPS]

# Capture the null sink's monitor. Without an explicit sink Sunshine picks the
# first device it finds, which on a machine with no sound card is nothing.
audio_sink = ${OW_SINK_NAME}.monitor

# The web UI is how you enter Moonlight's pairing PIN. Keep it on the LAN
# (here, the Hyper-V switch subnet) rather than exposed further.
origin_web_ui_allowed = lan

# Sunshine's own resolution changing has nothing to change: the guest's mode is
# pinned by the kernel command line.
min_log_level = warning
CONF

  # A single "Desktop" app: we want the whole session, not a launcher.
  write_file "$config_dir/apps.json" <<'JSON'
{
  "env": {},
  "apps": [
    {
      "name": "Desktop",
      "image-path": "desktop.png"
    }
  ]
}
JSON

  ow_streaming_autostart

  ok 'Sunshine configured'
  note "Web UI: https://$(ow_primary_address):47990 (self-signed certificate; accept it)"
  note 'First connection from Moonlight shows a PIN. Enter it there once.'
}

# Sunshine has to run *inside* the graphical session -- it captures a live
# compositor -- and the Arch package does not ship a systemd user unit. Prefer
# a packaged unit if some future version adds one; otherwise hook Hyprland's
# own autostart, which is where Omarchy expects session services to live and
# which guarantees WAYLAND_DISPLAY is already set when Sunshine starts.
ow_streaming_autostart() {
  if systemctl --user list-unit-files sunshine.service 2>/dev/null | grep -q '^sunshine\.service'; then
    enable_user_unit sunshine.service
    return
  fi

  note 'No packaged systemd user unit; using Hyprland autostart instead.'

  local autostart="$HOME/.config/hypr/autostart.lua"
  local line='o.launch_on_start("sunshine")'

  if [[ -f $autostart ]] && grep -qF "$line" "$autostart"; then
    note "already in $autostart"
  elif [[ $OW_DRY_RUN == 1 ]]; then
    note "[dry-run] append $line to $autostart"
  else
    mkdir -p "$(dirname "$autostart")"
    [[ -f $autostart ]] || printf -- '-- Extra autostart processes.\n' >"$autostart"
    printf '\n-- %s\n%s\n' "$OW_STAMP" "$line" >>"$autostart"
    ok "added Sunshine to $autostart"
  fi

  # Start it for the session that is running right now, so there is no need to
  # log out to test. Hyprland's dispatcher gives it the session environment.
  if [[ $OW_DRY_RUN != 1 ]] && has hyprctl && pgrep -x Hyprland >/dev/null 2>&1; then
    if pgrep -x sunshine >/dev/null 2>&1; then
      note 'Sunshine already running.'
    else
      run hyprctl dispatch exec sunshine >/dev/null 2>&1 || warn 'could not start Sunshine now; it will start at next login'
      sleep 3
      if pgrep -x sunshine >/dev/null 2>&1; then
        ok 'Sunshine started'
      else
        warn 'Sunshine did not stay up. Check: sunshine 2>&1 | head -40'
      fi
    fi
  fi
}

ow_primary_address() {
  ip -4 -o addr show scope global 2>/dev/null | awk '{ print $4 }' | cut -d/ -f1 | head -1
}
