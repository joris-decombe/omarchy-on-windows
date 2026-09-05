# Firewall.
#
# Fedora runs firewalld with a default-deny inbound zone, so RDP needs an
# explicit rule. Scope it to the subnet the guest is actually on rather than
# opening 3389 to everything the host can route to.

lh_firewall() {
  step 'Firewall (RDP)'

  if ! has firewall-cmd; then
    warn 'firewalld not installed; skipping. Open TCP/UDP 3389 yourself if something blocks it.'
    return 0
  fi

  if ! systemctl is-active --quiet firewalld 2>/dev/null; then
    note 'firewalld installed but not running; nothing to open.'
    return 0
  fi

  local subnet
  subnet=$(lh_guest_subnet)

  if [[ -z $subnet ]]; then
    warn 'Could not determine the guest subnet; allowing the rdp service in the default zone instead.'
    run firewall-cmd --permanent --add-service=rdp >/dev/null || warn 'could not add the rdp service'
  else
    ok "Allowing RDP from $subnet"
    run firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=\"$subnet\" port port=\"$LH_RDP_PORT\" protocol=\"tcp\" accept" >/dev/null ||
      warn 'could not add the TCP rule'
    # RDP can use UDP for a lower-latency transport; mstsc falls back to TCP
    # without it, so this is an improvement rather than a requirement.
    run firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=\"$subnet\" port port=\"$LH_RDP_PORT\" protocol=\"udp\" accept" >/dev/null ||
      warn 'could not add the UDP rule'
  fi

  run firewall-cmd --reload >/dev/null || warn 'firewall-cmd --reload failed'
  ok 'Rules applied'
}

# Derive the subnet from the address the guest actually holds, so this works on
# the Hyper-V Default Switch (NAT, renumbered every host reboot) and on an
# external switch (a real LAN address) without being told which.
lh_guest_subnet() {
  local cidr
  cidr=$(ip -4 -o addr show scope global 2>/dev/null | awk '{ print $4 }' | head -1)
  [[ -n $cidr ]] || return 0
  python3 - "$cidr" <<'PY' 2>/dev/null
import ipaddress, sys
print(ipaddress.ip_network(sys.argv[1], strict=False))
PY
}

lh_primary_address() {
  ip -4 -o addr show scope global 2>/dev/null | awk '{ print $4 }' | cut -d/ -f1 | head -1
}
