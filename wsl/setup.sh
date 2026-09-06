#!/bin/bash
#
# linux-on-hyperv: WSL side.
#
# Run this inside a WSL distro to get a GNOME desktop you reach from Windows
# over RDP - no virtual machine, sharing the WSL memory you already pay for,
# and with applications rendering on the real GPU.
#
# What this can and cannot do, plainly:
#
#   Applications get the GPU. WSL exposes it as /dev/dxg and Mesa's d3d12
#   driver renders through it with no DRM device involved. Verified: a client
#   in the session reports "D3D12 (NVIDIA GeForce RTX 2070)".
#
#   The compositor does not. Mutter needs a DRM render node to select a GPU;
#   WSL has none, so it composites on the CPU and says so. That is cheap for a
#   shell and irrelevant next to what applications do.
#
# Everything here is idempotent.

set -o pipefail

LW_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LH_REPO=$(dirname "$LW_ROOT")

# Shared with the VM kit so the two cannot drift apart.
# shellcheck source=../guest/lib/common.sh
source "$LH_REPO/guest/lib/common.sh"
# shellcheck source=../guest/lib/desktop.sh
source "$LH_REPO/guest/lib/desktop.sh"
# lh_make_cert lives here and is used by both kits.
# shellcheck source=../guest/lib/remote-desktop.sh
source "$LH_REPO/guest/lib/remote-desktop.sh"

for module in preflight gpu apps remote-desktop; do
  # shellcheck disable=SC1090
  source "$LW_ROOT/lib/$module.sh"
done

LW_MODULES=(gpu apps remote_desktop)

usage() {
  cat <<USAGE
Usage: sudo bash wsl/setup.sh [options]

Options:
  --adapter NAME   GPU to prefer, matched by name (default: ${LW_ADAPTER}).
                   Mesa picks the integrated GPU otherwise.
  --port N         RDP port (default: ${LW_RDP_PORT}). Not 3389, because
                   Windows' own Remote Desktop uses that and WSL forwards
                   guest ports onto Windows' localhost.
  --only MODULE    Run just one module. Repeatable.
  --skip MODULE    Skip a module. Repeatable.
  --dry-run        Print what would change without changing anything.
  -h, --help       This.

Environment:
  LW_RDP_PASSWORD  Password for the RDP session. Headless GNOME authenticates
                   against its own credentials, not a login screen, so without
                   this it will refuse connections.

Modules: ${LW_MODULES[*]}
USAGE
}

only=()
skip=()

while [[ $# -gt 0 ]]; do
  case $1 in
  --adapter) LW_ADAPTER=${2:?--adapter needs a name}; shift 2 ;;
  --port) LW_RDP_PORT=${2:?--port needs a number}; shift 2 ;;
  --only) only+=("${2:?--only needs a module name}"); shift 2 ;;
  --skip) skip+=("${2:?--skip needs a module name}"); shift 2 ;;
  --dry-run) LH_DRY_RUN=1; shift ;;
  -h | --help) usage; exit 0 ;;
  *)
    printf 'unknown option: %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

for name in "${only[@]}" "${skip[@]}"; do
  [[ " ${LW_MODULES[*]} " == *" $name "* ]] || die "unknown module '$name'. Known: ${LW_MODULES[*]}"
done

should_run() {
  local name=$1
  if [[ ${#only[@]} -gt 0 ]]; then
    [[ " ${only[*]} " == *" $name "* ]]
    return
  fi
  [[ " ${skip[*]} " != *" $name "* ]]
}

[[ $LH_DRY_RUN == 1 ]] && printf '\033[33mDry run: nothing will be changed.\033[0m\n'

lw_preflight

for name in "${LW_MODULES[@]}"; do
  should_run "$name" || { note "skipping $name"; continue; }
  "lw_$name"
done

cat <<DONE

$(printf '\033[36mDone.\033[0m')

  Run a graphical app on the GPU:
      wsl.exe -d $(. /etc/os-release; printf '%s' "${NAME// /}") -- gpu-run firefox

  It opens as an ordinary Windows window, with sound, on the discrete GPU.
  Check what it got:
      gpu-run glxinfo -B | grep "OpenGL renderer"

  There is deliberately no desktop shell here: a remote-desktop server needs a
  DRM device and WSL has none, so gnome-remote-desktop segfaults. The evidence
  is in wsl/lib/remote-desktop.sh. For a full desktop, use the VM kit.

  Something wrong? Run: sudo bash $LW_ROOT/doctor.sh
DONE
