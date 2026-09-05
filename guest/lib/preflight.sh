# Refuses to run anywhere this kit would do the wrong thing.

lh_preflight() {
  step 'Preflight'

  [[ $EUID -eq 0 ]] || die 'Run this with sudo: sudo bash guest/setup.sh'
  [[ -n ${SUDO_USER:-} ]] || warn 'No SUDO_USER; RDP will be configured for root, which is probably not what you want.'

  has dnf || die 'This is not a Fedora/RHEL system. The guest kit targets Fedora Workstation.'

  local pretty
  pretty=$(. /etc/os-release 2>/dev/null && printf '%s' "$PRETTY_NAME")
  ok "${pretty:-unknown distribution}"

  # gnome-remote-desktop only grew headless "Remote Login" -- a full RDP
  # session with its own virtual monitor -- in GNOME 46. On older GNOME you get
  # screen sharing of an already-running local session instead, which cannot
  # resize and needs someone logged in at the console first.
  if has gnome-shell; then
    local version major
    version=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    major=${version%%.*}
    if [[ -n $major ]] && ((major >= 46)); then
      ok "GNOME $version (headless Remote Login supported)"
    else
      warn "GNOME ${version:-unknown} is older than 46; headless Remote Login is unavailable."
      note 'You will get screen sharing of the console session instead, without dynamic resolution.'
    fi
  else
    die 'gnome-shell not found. This kit configures GNOME'"'"'s remote desktop.'
  fi

  local virt
  virt=$(systemd-detect-virt 2>/dev/null || echo none)
  case $virt in
  microsoft) ok 'Running under Hyper-V' ;;
  none) die 'Not running in a VM. This kit configures a guest for a Windows host.' ;;
  *) warn "Detected '$virt', not Hyper-V. The RDP parts still apply; the integration services do not." ;;
  esac
}
