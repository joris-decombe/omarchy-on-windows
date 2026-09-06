# Remote desktop: dispatches to whichever backend the chosen desktop supports.
#
# These are not equivalent. See lib/desktop.sh for the reasoning; the short
# version is that only the GNOME backend gives a session whose monitor is
# sized by the connecting client, which is what makes the window resizable.

LH_TLS_DIR=/var/lib/gnome-remote-desktop/certificates
LH_RDP_PORT=${LH_RDP_PORT:-3389}

lh_remote_desktop() {
  local backend
  backend=$(lh_rdp_backend)
  [[ -n $backend ]] || die "no remote-desktop backend known for desktop '$LH_DESKTOP'"

  step "Remote desktop (backend: $backend)"
  "lh_rdp_$backend"
}

# --- shared ---------------------------------------------------------------

# A self-signed certificate is fine here: the connection is host-to-guest, and
# the .rdp profile written by Start-LinuxDesktop tells mstsc not to fail on an
# untrusted issuer. It is still real TLS on the wire.
lh_make_cert() {
  local dir=$1 owner=${2:-}
  local key="$dir/rdp-tls.key" crt="$dir/rdp-tls.crt"

  if [[ -f $key && -f $crt ]]; then
    note 'TLS certificate already present'
    return 0
  fi

  has openssl || pkg_install "$(lh_packages openssl)"

  run mkdir -p "$dir"
  run openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=NZ/ST=NA/L=NA/O=linux-on-hyperv/CN=$(hostname)" \
    -out "$crt" -keyout "$key" 2>/dev/null || die 'could not generate the RDP TLS certificate'

  [[ -n $owner ]] && run chown -R "$owner" "$dir" 2>/dev/null
  run chmod 600 "$key"
  ok "generated $crt"
}

# --- GNOME ----------------------------------------------------------------

lh_rdp_gnome() {
  pkg_install "$(lh_packages grd)"
  lh_make_cert "$LH_TLS_DIR" gnome-remote-desktop:gnome-remote-desktop

  has grdctl || die 'grdctl not found even though gnome-remote-desktop is installed.'

  # --system is Remote Login: a system service that puts GDM on the far end,
  # creating a session on demand with a virtual monitor sized by the client.
  # The per-user service is a different thing and is deliberately left alone.
  run grdctl --system rdp set-tls-cert "$LH_TLS_DIR/rdp-tls.crt"
  run grdctl --system rdp set-tls-key "$LH_TLS_DIR/rdp-tls.key"
  run grdctl --system rdp enable
  enable_unit gnome-remote-desktop.service

  if [[ $LH_DRY_RUN != 1 ]]; then
    printf '\n'
    grdctl --system status 2>/dev/null || warn 'grdctl --system status failed'
  fi

  ok 'Remote Login enabled'
  note "Log in over RDP with the guest's own username and password."
}

# --- KDE ------------------------------------------------------------------

lh_rdp_kde() {
  pkg_install "$(lh_packages krdp)"

  warn 'KRdp cannot do headless login.'
  note 'It attaches to a session that is already running, so something has to be'
  note 'hosting one -- here, the Hyper-V console session. Consequences:'
  note '  * the resolution follows that session, not your RDP window, so'
  note '    resizing scales rather than reflows;'
  note '  * you must be logged in at the console before connecting.'
  note 'Audio and clipboard do work. This backend is here for comparison.'

  lh_make_cert /var/lib/krdp

  # KRdp is configured per-user through System Settings and stores its password
  # in KWallet, which is not scriptable from a root shell in any honest way.
  note ''
  note 'Finish in the guest, as your user:'
  note '  System Settings -> Remote Desktop -> enable, set a username/password'
  note 'or: krdpserver --port '"$LH_RDP_PORT"' --username <u> --password <p>'
}

# --- xrdp (X11 desktops) --------------------------------------------------

lh_rdp_xrdp() {
  pkg_install "$(lh_packages xrdp)"

  # xrdp starts its own X server via xorgxrdp, so it is unaffected by display
  # managers dropping X11 -- but it cannot serve a Wayland-only desktop, which
  # is why this backend is only offered for XFCE/Cinnamon/MATE.
  local session
  case $LH_DESKTOP in
  xfce) session='startxfce4' ;;
  cinnamon) session='cinnamon-session' ;;
  mate) session='mate-session' ;;
  *) die "xrdp backend does not know how to start '$LH_DESKTOP'" ;;
  esac

  # xrdp reads ~/.xsession for what to launch. Write it for the real user, not
  # for root, or every RDP login lands in a grey void with no window manager.
  local user home
  user=$(target_user)
  home=$(getent passwd "$user" | cut -d: -f6)
  if [[ -n $home && -d $home ]]; then
    write_file "$home/.xsession" <<XSESSION
$LH_STAMP
exec $session
XSESSION
    [[ $LH_DRY_RUN == 1 ]] || run chown "$user:$user" "$home/.xsession"
  else
    warn "could not resolve a home directory for $user; skipping .xsession"
  fi

  enable_unit xrdp.service
  ok "xrdp will start '$session'"

  if [[ $LH_PKG == dnf ]]; then
    note 'Sound over xrdp needs pulseaudio-module-xrdp, which Fedora does not'
    note 'package; on Fedora this backend is silent. Debian/Ubuntu have it.'
  fi
}
