# Hyper-V guest integration services.
#
# The one that matters is the KVP daemon: it is how the host learns the guest's
# IP address, which is what Get-LinuxVMAddress on the Windows side reads. On
# Fedora these live in the hyperv-daemons package.

lh_integration() {
  step 'Hyper-V integration services'

  if [[ $(systemd-detect-virt 2>/dev/null) != microsoft ]]; then
    note 'Not a Hyper-V guest; skipping.'
    return 0
  fi

  pkg_install $(lh_packages hyperv)

  # The package ships all three; fcopy is optional and absent on some kernels,
  # so a failure there is a warning rather than fatal.
  # Unit names differ between distros: Fedora ships hypervkvpd, Debian and
  # Ubuntu ship hv-kvp-daemon. Enable whichever exists rather than guessing
  # from the distro id, which gets stale.
  local unit found=0
  for unit in hypervkvpd.service hv-kvp-daemon.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1 &&
      systemctl list-unit-files "$unit" 2>/dev/null | grep -q "^$unit"; then
      enable_unit "$unit"
      found=1
    fi
  done
  ((found)) || warn 'no KVP daemon unit found; the host will not see the guest IP'

  for unit in hypervvssd.service hv-vss-daemon.service hypervfcopyd.service hv-fcopy-daemon.service; do
    if systemctl list-unit-files "$unit" 2>/dev/null | grep -q "^$unit"; then
      enable_unit "$unit"
    fi
  done

  ok 'Guest will report its address to the Hyper-V host'
}
