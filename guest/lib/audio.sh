# Audio.
#
# Hyper-V emulates no sound device whatsoever - there is no card for PipeWire
# to find, and Hyper-V's own answer (RDP audio over Enhanced Session Mode)
# needs an xrdp X11 session, which a Hyprland guest does not have.
#
# So the guest gets a null sink instead: a real, selectable output device that
# discards its samples locally, and whose monitor Sunshine captures and ships
# to Moonlight on Windows. Applications see an ordinary sink; the sound comes
# out of the Windows speakers.

OW_SINK_NAME=${OW_SINK_NAME:-omarchy-stream}

ow_audio() {
  step 'Audio (virtual sink for streaming)'

  pacman_install pipewire pipewire-pulse wireplumber

  if pactl list short sinks 2>/dev/null | grep -q 'alsa_output'; then
    warn 'A hardware sink exists, which is unexpected under Hyper-V. Adding the stream sink alongside it.'
  fi

  # A PipeWire config drop-in rather than a runtime `pactl load-module`, so the
  # sink survives reboots and PipeWire restarts.
  write_file "$HOME/.config/pipewire/pipewire.conf.d/50-omarchy-stream-sink.conf" <<CONF
# $OW_STAMP
#
# A null sink that Sunshine captures. object.linger keeps it alive even when
# nothing is playing, so Moonlight does not lose the audio stream between
# sounds.
context.objects = [
  { factory = adapter
    args = {
      factory.name              = support.null-audio-sink
      node.name                 = "$OW_SINK_NAME"
      node.description          = "Omarchy Stream (to Windows)"
      media.class               = Audio/Sink
      audio.position            = [ FL FR ]
      monitor.channel-volumes   = true
      object.linger             = true
    }
  }
]
CONF

  if [[ $OW_DRY_RUN != 1 ]]; then
    run systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null ||
      warn 'Could not restart PipeWire. Log out and back in to pick up the new sink.'

    # PipeWire republishes its nodes asynchronously; a fixed sleep either wastes
    # time or loses the race. Poll instead.
    local waited=0
    while ((waited < 15)); do
      pactl list short sinks 2>/dev/null | grep -q "$OW_SINK_NAME" && break
      sleep 1
      ((waited++))
    done

    if pactl list short sinks 2>/dev/null | grep -q "$OW_SINK_NAME"; then
      ok "sink $OW_SINK_NAME is up (after ${waited}s)"
      if run pactl set-default-sink "$OW_SINK_NAME"; then
        ok "default sink is now $OW_SINK_NAME"
      else
        warn "could not set $OW_SINK_NAME as default; do it in Omarchy's audio menu"
      fi
    else
      warn "Sink $OW_SINK_NAME did not appear within ${waited}s. Check after a reboot with: wpctl status"
    fi
  fi
}
