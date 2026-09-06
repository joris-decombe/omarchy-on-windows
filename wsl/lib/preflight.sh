# Refuses to run anywhere this kit would do the wrong thing.

lw_preflight() {
  step 'Preflight'

  [[ $EUID -eq 0 ]] || die 'Run this with sudo: sudo bash wsl/setup.sh'

  local virt
  virt=$(systemd-detect-virt 2>/dev/null || echo none)
  if [[ $virt != wsl ]] && [[ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    die "This is the WSL kit but the system does not look like WSL (detected '$virt'). For a Hyper-V VM use guest/setup.sh."
  fi
  ok 'Running under WSL'

  # Everything here -- the RDP service, lingering, the user session -- is
  # systemd. WSL only runs it when asked, and the ask is per-distro.
  if [[ ! -d /run/systemd/system ]]; then
    die 'systemd is not running in this distro. Add to /etc/wsl.conf:

    [boot]
    systemd=true

then run "wsl --shutdown" on Windows and start the distro again.'
  fi
  ok 'systemd is running'

  lh_detect_distro
  [[ -n $LH_PKG ]] || die "Unsupported distribution '$LH_DISTRO'."
  ok "$(. /etc/os-release 2>/dev/null && printf '%s' "$PRETTY_NAME") (${LH_PKG})"

  [[ -e /dev/dxg ]] && ok 'GPU device /dev/dxg present' ||
    warn 'No /dev/dxg. Applications will fall back to software rendering.'

  # Worth saying out loud, because it is the whole reason this kit exists in
  # the shape it does.
  if [[ -d /dev/dri ]]; then
    note "/dev/dri exists here, which is new -- a nested compositor may now work."
  else
    note 'No /dev/dri, as expected: the compositor will composite in software'
    note 'while applications render on the GPU through D3D12.'
  fi
}
