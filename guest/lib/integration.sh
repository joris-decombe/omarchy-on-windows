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

  dnf_install hyperv-daemons

  # The package ships all three; fcopy is optional and absent on some kernels,
  # so a failure there is a warning rather than fatal.
  enable_unit hypervkvpd.service
  enable_unit hypervvssd.service
  if systemctl list-unit-files hypervfcopyd.service >/dev/null 2>&1; then
    enable_unit hypervfcopyd.service
  fi

  ok 'Guest will report its address to the Hyper-V host'
}
