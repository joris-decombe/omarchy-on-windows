# Desktop detection and per-distro package names.
#
# The kit supports several desktops so they can be compared on the same VM
# shape. They do not have equivalent remote-desktop stories, and the difference
# decides which backend gets used:
#
#   gnome  gnome-remote-desktop in --system mode: a system service that starts
#          a session on demand with a virtual monitor sized by the client.
#          This is the only combination that gives a resizable window with no
#          display of any kind behind it. GNOME 46+.
#
#   kde    KRdp. Real RDP with audio and clipboard, but it attaches to an
#          already-running session, so something must host that session and the
#          geometry follows that surface, not the client. No headless login.
#
#   xrdp   For X11 desktops (XFCE, Cinnamon, MATE). xrdp spawns its own X
#          server through xorgxrdp, so it does not care that GDM has dropped
#          X11 -- but it cannot serve a Wayland-only desktop at all, which is
#          why it is not an escape hatch for GNOME or Plasma-on-Wayland.

# Sets LH_DESKTOP. Honours an explicit choice; otherwise sniffs for what is
# installed. Runs under sudo, where XDG_CURRENT_DESKTOP is not trustworthy, so
# it looks at binaries rather than the environment.
lh_detect_desktop() {
  if [[ -n ${LH_DESKTOP:-} && $LH_DESKTOP != auto ]]; then
    note "desktop: $LH_DESKTOP (explicit)"
    return 0
  fi

  local found=()
  has gnome-shell && found+=(gnome)
  has plasmashell && found+=(kde)
  has xfce4-session && found+=(xfce)
  has cinnamon-session && found+=(cinnamon)
  has mate-session && found+=(mate)

  case ${#found[@]} in
  0) die 'No supported desktop found. Install one, or pass --desktop <gnome|kde|xfce|cinnamon|mate>.' ;;
  1) LH_DESKTOP=${found[0]} ;;
  *)
    LH_DESKTOP=${found[0]}
    warn "Several desktops installed (${found[*]}); using '$LH_DESKTOP'. Pass --desktop to choose."
    ;;
  esac
  note "desktop: $LH_DESKTOP (detected)"
}

# Which remote-desktop backend serves this desktop.
lh_rdp_backend() {
  case $LH_DESKTOP in
  gnome) printf 'gnome' ;;
  kde) printf 'kde' ;;
  xfce | cinnamon | mate) printf 'xrdp' ;;
  *) printf '' ;;
  esac
}

# Package names differ per distro often enough to be worth a table rather than
# conditionals scattered through each module.
lh_packages() {
  local what=$1
  case "$what/$LH_PKG" in
  hyperv/dnf) printf 'hyperv-daemons' ;;
  # Ubuntu/Debian ship the Hyper-V daemons with the kernel tools.
  hyperv/apt) printf 'linux-cloud-tools-virtual' ;;
  hyperv/zypper) printf 'hyper-v' ;;

  audio/dnf) printf 'pipewire pipewire-pulseaudio wireplumber' ;;
  audio/apt) printf 'pipewire pipewire-pulse wireplumber' ;;
  audio/zypper) printf 'pipewire pipewire-pulseaudio wireplumber' ;;

  grd/*) printf 'gnome-remote-desktop' ;;
  krdp/*) printf 'krdp' ;;

  xrdp/dnf) printf 'xrdp xorgxrdp' ;;
  # Debian/Ubuntu bundle xorgxrdp into the xrdp package; the pulseaudio module
  # is what makes xrdp carry sound, and it is packaged separately.
  xrdp/apt) printf 'xrdp pulseaudio-module-xrdp' ;;
  xrdp/zypper) printf 'xrdp' ;;

  openssl/*) printf 'openssl' ;;
  *) printf '' ;;
  esac
}
