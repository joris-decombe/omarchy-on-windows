#!/bin/bash
#
# omarchy-on-windows: guest side.
#
# Run this inside a freshly installed Omarchy running as a Hyper-V guest. It
# wires the guest up to its Windows host: integration services, a display mode
# the synthetic GPU can actually do, a rendering profile that suits a CPU-only
# compositor, a virtual sound device, and a Sunshine stream that carries the
# whole desktop - picture and sound - into a window on Windows.
#
# Everything here is idempotent. Re-running it is the supported way to change
# the resolution or repair a half-finished run.

set -o pipefail

OW_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$OW_ROOT/lib/common.sh"
for module in preflight integration display perf audio streaming firewall; do
  # shellcheck disable=SC1090
  source "$OW_ROOT/lib/$module.sh"
done

OW_MODULES=(integration display perf audio streaming firewall)

usage() {
  cat <<USAGE
Usage: install.sh [options]

Options:
  --resolution WxH   Guest display mode (default: ${OW_RESOLUTION}).
                     Hyper-V's synthetic display maxes out at 1920x1200.
  --fps N            Stream frame rate offered to Moonlight (default: ${OW_STREAM_FPS}).
  --only MODULE      Run just one module. Repeatable.
  --skip MODULE      Skip a module. Repeatable.
  --dry-run          Print what would change without changing anything.
  --yes              Do not prompt.
  -h, --help         This.

Modules: ${OW_MODULES[*]}
USAGE
}

only=()
skip=()

while [[ $# -gt 0 ]]; do
  case $1 in
  --resolution)
    OW_RESOLUTION=${2:?--resolution needs a value like 1920x1080}
    shift 2
    ;;
  --fps)
    OW_STREAM_FPS=${2:?--fps needs a number}
    shift 2
    ;;
  --only)
    only+=("${2:?--only needs a module name}")
    shift 2
    ;;
  --skip)
    skip+=("${2:?--skip needs a module name}")
    shift 2
    ;;
  --dry-run)
    OW_DRY_RUN=1
    shift
    ;;
  --yes)
    OW_ASSUME_YES=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'unknown option: %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

for name in "${only[@]}" "${skip[@]}"; do
  [[ " ${OW_MODULES[*]} " == *" $name "* ]] || die "unknown module '$name'. Known: ${OW_MODULES[*]}"
done

should_run() {
  local name=$1
  if [[ ${#only[@]} -gt 0 ]]; then
    [[ " ${only[*]} " == *" $name "* ]]
    return
  fi
  [[ " ${skip[*]} " != *" $name "* ]]
}

[[ $OW_DRY_RUN == 1 ]] && printf '\033[33mDry run: nothing will be changed.\033[0m\n'

ow_preflight

for name in "${OW_MODULES[@]}"; do
  should_run "$name" || {
    note "skipping $name"
    continue
  }
  "ow_$name"
done

mkdir -p "$OW_STATE_DIR" 2>/dev/null || true
[[ $OW_DRY_RUN == 1 ]] || date -Is >"$OW_STATE_DIR/last-run" 2>/dev/null || true

address=$(ow_primary_address)

cat <<DONE

$(printf '\033[36mDone.\033[0m')

  This guest is at ${address:-<no address yet>}.

  1. Reboot, so the ${OW_RESOLUTION} display mode takes effect:
       omarchy-system-reboot

  2. On Windows, in an elevated PowerShell in this repo's windows/ directory:
       Import-Module .\Omarchy.psd1
       Install-OmarchyMoonlight
       Start-OmarchyDesktop

  3. Moonlight will show a pairing PIN the first time. Enter it at
       https://${address:-<guest-ip>}:47990
     in a browser inside the guest, under Pin. That is a one-off.

  Sound plays through the "Omarchy Stream (to Windows)" sink and arrives with
  the picture. The Hyper-V console still works as a silent fallback if the
  stream ever will not start.

  Something wrong? Run: bash $OW_ROOT/doctor.sh
DONE
