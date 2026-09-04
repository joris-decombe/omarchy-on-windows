# Refuses to run anywhere this kit would do the wrong thing.

ow_preflight() {
  step 'Preflight'

  [[ $EUID -ne 0 ]] || die 'Run this as your normal user, not root. It uses sudo where it needs to.'

  has pacman || die 'This is not an Arch-based system. The guest kit only supports Omarchy.'

  if [[ -z ${OMARCHY_PATH:-} ]] && [[ ! -d /usr/share/omarchy ]]; then
    die 'Omarchy not found (no $OMARCHY_PATH, no /usr/share/omarchy). Install Omarchy first.'
  fi
  local omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
  ok "Omarchy at $omarchy_path$( [[ -f $omarchy_path/version ]] && printf ' (%s)' "$(cat "$omarchy_path/version")" )"

  local virt
  virt=$(systemd-detect-virt 2>/dev/null || echo none)
  case $virt in
  microsoft)
    ok 'Running under Hyper-V'
    ;;
  none)
    die 'Not running in a VM. This kit configures an Omarchy guest for a Windows host; on bare metal it would only make things worse.'
    ;;
  *)
    warn "Detected '$virt', not Hyper-V. The streaming and audio parts still apply, but the display and integration parts assume Hyper-V."
    if [[ ${OW_ASSUME_YES:-0} != 1 ]]; then
      read -rp '    Continue anyway? [y/N] ' reply
      [[ $reply == [yY]* ]] || die 'Stopped.'
    fi
    ;;
  esac

  sudo -v || die 'sudo is required.'

  if ! ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
    warn 'No network reachable. Package installs will fail.'
  fi
}
