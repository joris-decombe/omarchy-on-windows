# Hyper-V guest integration services.
#
# The one that matters is the KVP daemon: it is how the host learns the guest's
# IP address, which is what Get-OmarchyVMAddress on the Windows side reads.
# Without it you are looking up the address by hand every boot.

ow_integration() {
  step 'Hyper-V integration services'

  pacman_install hyperv

  # Arch's hyperv package ships all three; fcopy is optional and absent on some
  # kernels, so a failure there is a warning rather than fatal.
  enable_system_unit hv_kvp_daemon.service
  enable_system_unit hv_vss_daemon.service

  if systemctl list-unit-files hv_fcopy_uio_daemon.service >/dev/null 2>&1; then
    enable_system_unit hv_fcopy_uio_daemon.service
  fi

  # Hyper-V provides a paravirtual clock source; without host time sync a
  # suspended-then-resumed VM drifts and TLS handshakes start failing.
  if systemctl list-unit-files systemd-timesyncd.service >/dev/null 2>&1; then
    enable_system_unit systemd-timesyncd.service
  fi

  ok 'Guest will report its address to the Hyper-V host'
}
