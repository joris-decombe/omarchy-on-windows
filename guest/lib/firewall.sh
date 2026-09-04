# Firewall.
#
# Omarchy ships ufw denying everything inbound. Sunshine needs a handful of
# ports open, and only ever to the Windows host - the Hyper-V switch subnet -
# never to the wider network the host is on.

ow_firewall() {
  step 'Firewall (ufw rules for Sunshine)'

  if ! has ufw; then
    warn 'ufw not installed; skipping. Omarchy normally ships it.'
    return 0
  fi

  local subnet
  subnet=$(ow_host_subnet)
  if [[ -z $subnet ]]; then
    warn 'Could not work out the Hyper-V switch subnet; falling back to private ranges.'
    subnet='192.168.0.0/16'
  fi
  ok "Allowing Sunshine from $subnet"

  # Sunshine's fixed port block: 47984/47989/48010 TCP and 47998-48000/48002
  # UDP, plus 47990 for the web UI where the pairing PIN goes in.
  local rule
  for rule in \
    '47984/tcp' '47989/tcp' '47990/tcp' '48010/tcp' \
    '47998:48000/udp' '48002/udp' '48010/udp'; do
    run sudo ufw allow from "$subnet" to any port "${rule%/*}" proto "${rule#*/}" \
      comment 'omarchy-on-windows sunshine' >/dev/null || warn "could not add rule $rule"
  done

  run sudo ufw reload >/dev/null 2>&1 || true
  ok 'Rules applied'
}

# The Hyper-V Default Switch hands out a NAT'd /28-ish range that changes every
# host reboot, so derive the subnet from whatever the guest actually has rather
# than hardcoding one.
ow_host_subnet() {
  ip -4 -o addr show scope global 2>/dev/null |
    awk '{ print $4 }' |
    head -1 |
    while IFS=/ read -r addr prefix; do
      [[ -n $addr ]] || continue
      # Normalize to the network address so ufw takes it as a subnet.
      python3 - "$addr" "$prefix" <<'PY' 2>/dev/null || printf '%s/%s\n' "${addr%.*}.0" "$prefix"
import ipaddress, sys
print(ipaddress.ip_network(f"{sys.argv[1]}/{sys.argv[2]}", strict=False))
PY
    done
}
