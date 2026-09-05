# The whole point of the project: display, sound, clipboard and a resolution
# that follows the client window, over one RDP connection.
#
# gnome-remote-desktop runs in two very different modes and the distinction
# matters more than anything else in this file:
#
#   Remote Desktop (per-user, --headless)
#       Shares or creates a session for one already-logged-in user. Needs that
#       user to have an active session, and the service runs in their bus.
#
#   Remote Login (--system)
#       A system service that puts GDM itself on the far end of RDP. You get a
#       login screen, log in as anyone, and the session is created with a
#       virtual monitor sized by the client -- which is what makes the window
#       resizable. This is what we configure. GNOME 46+.
#
# Both need a TLS certificate; grdctl will not enable RDP without one.

LH_TLS_DIR=/var/lib/gnome-remote-desktop/certificates
LH_RDP_PORT=${LH_RDP_PORT:-3389}

lh_remote_desktop() {
  step 'Remote desktop (GNOME over RDP)'

  dnf_install gnome-remote-desktop

  lh_rdp_certificate
  lh_rdp_enable
}

# A self-signed certificate is fine here: the connection is host-to-guest on a
# virtual switch, and mstsc is told not to fail on an untrusted issuer. It is
# still real TLS on the wire.
lh_rdp_certificate() {
  local key="$LH_TLS_DIR/rdp-tls.key"
  local crt="$LH_TLS_DIR/rdp-tls.crt"

  if [[ -f $key && -f $crt ]]; then
    note 'TLS certificate already present'
    return 0
  fi

  has openssl || dnf_install openssl

  run mkdir -p "$LH_TLS_DIR"
  run openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=NZ/ST=NA/L=NA/O=linux-on-hyperv/CN=$(hostname)" \
    -out "$crt" -keyout "$key" 2>/dev/null ||
    die 'could not generate the RDP TLS certificate'

  # gnome-remote-desktop runs as its own system user and must be able to read
  # the key; nothing else should.
  run chown -R gnome-remote-desktop:gnome-remote-desktop "$LH_TLS_DIR" 2>/dev/null || true
  run chmod 600 "$key"
  ok "generated $crt"
}

lh_rdp_enable() {
  has grdctl || die 'grdctl not found even though gnome-remote-desktop is installed.'

  run grdctl --system rdp set-tls-cert "$LH_TLS_DIR/rdp-tls.crt"
  run grdctl --system rdp set-tls-key "$LH_TLS_DIR/rdp-tls.key"
  run grdctl --system rdp enable
  ok 'Remote Login enabled system-wide'

  # This is the unit for Remote Login. The per-user one
  # (gnome-remote-desktop.service in the user bus) is a different thing and is
  # deliberately left alone.
  enable_unit gnome-remote-desktop.service

  if [[ $LH_DRY_RUN != 1 ]]; then
    printf '\n'
    grdctl --system status 2>/dev/null || warn 'grdctl --system status failed'
  fi

  note "Log in over RDP with the guest's own username and password."
  note 'No separate RDP credentials: Remote Login shows you GDM.'
}
