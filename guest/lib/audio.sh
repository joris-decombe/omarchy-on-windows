# Audio.
#
# Hyper-V emulates no sound card, so a stock guest has no output device at all
# and applications fall back to a null device or refuse to start.
#
# gnome-remote-desktop creates its own PipeWire node for the RDP session and
# routes it to the client, so on a Remote Login session sound Just Works. This
# module exists for the gap around that: making sure PipeWire is actually
# installed and running, and reporting what the session will use.

lh_audio() {
  step 'Audio'

  pkg_install $(lh_packages audio)

  local user
  user=$(target_user)

  if [[ $LH_DRY_RUN == 1 ]]; then
    note '[dry-run] skipping PipeWire inspection'
    return 0
  fi

  # PipeWire is a user service; inspect it as the real user, not as root.
  if runuser -u "$user" -- systemctl --user is-active --quiet pipewire 2>/dev/null; then
    ok "PipeWire running for $user"
  else
    note "PipeWire is not running for $user yet; it starts with their session."
  fi

  case $(lh_rdp_backend) in
  gnome)
    note 'gnome-remote-desktop publishes its own sink for the remote session and'
    note 'sends it to the client. Nothing else to configure - just keep'
    note 'audiomode:i:0 in the .rdp profile, which Start-LinuxDesktop sets.'
    ;;
  kde)
    note 'KRdp carries audio from the session it is attached to.'
    ;;
  xrdp)
    note 'xrdp needs pulseaudio-module-xrdp for sound; without it the session is'
    note 'silent. It is packaged on Debian/Ubuntu and not on Fedora.'
    ;;
  esac
}
