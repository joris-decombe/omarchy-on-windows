#!/bin/bash
#
# Reports the state of every piece install.sh sets up, and says what to do
# about each one that is wrong. Read-only: it changes nothing.

set -o pipefail
OW_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$OW_ROOT/lib/common.sh"

fails=0

check() {
  local label=$1 fix=$2
  shift 2
  if "$@" >/dev/null 2>&1; then
    printf '  \033[32mok  \033[0m %s\n' "$label"
  else
    printf '  \033[31mbad \033[0m %s\n' "$label"
    printf '        \033[90m%s\033[0m\n' "$fix"
    fails=$((fails + 1))
  fi
}

step 'Host and virtualization'
printf '    virt: %s\n' "$(systemd-detect-virt 2>/dev/null || echo unknown)"
printf '    omarchy: %s\n' "$(cat "${OMARCHY_PATH:-/usr/share/omarchy}/version" 2>/dev/null || echo 'not found')"
printf '    address: %s\n' "$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -1)"

step 'Display'
# hyperv_drm is not always card0 (card1 is common) and exposes no renderD*
# node, so check for the family rather than a fixed path.
check 'DRM device /dev/dri/card*' \
  'Gen 2 VM required. Check with: lsmod | grep hyperv_drm' \
  bash -c 'compgen -G "/dev/dri/card*" >/dev/null'
check 'hyperv_drm loaded' \
  'sudo modprobe hyperv_drm' \
  bash -c 'lsmod | grep -q "^hyperv_drm"'
check 'video= mode pinned on the kernel command line' \
  'Re-run install.sh, then sudo limine-mkinitcpio, then reboot.' \
  bash -c 'grep -q "video=hyperv_fb:" /proc/cmdline'
check 'Hyprland running' \
  'Log in to the Hyper-V console first; the stream captures a live session.' \
  pgrep -x Hyprland

step 'Hyper-V integration'
check 'hv_kvp_daemon active (host can see the guest IP)' \
  'sudo systemctl enable --now hv_kvp_daemon.service' \
  systemctl is-active --quiet hv_kvp_daemon.service

step 'Audio'
check "sink ${OW_SINK_NAME:-omarchy-stream} exists" \
  'Re-run: bash install.sh --only audio' \
  bash -c "pactl list short sinks | grep -q '${OW_SINK_NAME:-omarchy-stream}'"
check "sink ${OW_SINK_NAME:-omarchy-stream} is the default" \
  'wpctl status, then wpctl set-default <id>' \
  bash -c "pactl get-default-sink 2>/dev/null | grep -q '${OW_SINK_NAME:-omarchy-stream}'"

step 'Streaming'
check 'sunshine installed' \
  'yay -S sunshine-bin' \
  bash -c 'pacman -Qq sunshine >/dev/null 2>&1 || pacman -Qq sunshine-bin >/dev/null 2>&1'
check 'sunshine user service active' \
  'systemctl --user status sunshine  (and: journalctl --user -u sunshine -n50)' \
  systemctl --user is-active --quiet sunshine.service
check 'sunshine listening on 47989' \
  'The service is up but not bound. Check its log for a capture backend error.' \
  bash -c 'ss -tlnp 2>/dev/null | grep -q ":47989"'
check 'web UI listening on 47990' \
  'Needed to enter the Moonlight pairing PIN.' \
  bash -c 'ss -tlnp 2>/dev/null | grep -q ":47990"'

step 'Firewall'
if has ufw; then
  if sudo ufw status 2>/dev/null | grep -q '47989'; then
    printf '  \033[32mok  \033[0m sunshine ports allowed\n'
  else
    printf '  \033[31mbad \033[0m sunshine ports not in ufw\n'
    printf '        \033[90mRe-run: bash install.sh --only firewall\033[0m\n'
    fails=$((fails + 1))
  fi
else
  printf '    ufw not installed; nothing to check\n'
fi

printf '\n'
if [[ $fails -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%d check(s) failed.\033[0m See the fix under each.\n' "$fails"
  exit 1
fi
