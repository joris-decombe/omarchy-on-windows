#!/bin/bash
#
# Reports the state of the WSL setup. Read-only; never prompts.

set -o pipefail
LW_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LH_REPO=$(dirname "$LW_ROOT")
# shellcheck source=../guest/lib/common.sh
source "$LH_REPO/guest/lib/common.sh"
lh_detect_distro

LW_ADAPTER=${LW_ADAPTER:-NVIDIA}
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

step 'Environment'
printf '    distro:  %s\n' "$(. /etc/os-release 2>/dev/null && printf '%s' "$PRETTY_NAME")"
printf '    virt:    %s\n' "$(systemd-detect-virt 2>/dev/null || echo unknown)"
printf '    user:    %s\n' "$(target_user)"

step 'GPU for applications'
check '/dev/dxg present' \
  'No GPU access in this distro. Check the WSL version and the host driver.' \
  test -e /dev/dxg
check 'gpu-run installed' \
  'sudo bash wsl/setup.sh --only apps' \
  test -x /usr/local/bin/gpu-run

if has glxinfo; then
  r=$(GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME="$LW_ADAPTER" \
    glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | cut -d: -f2- | sed 's/^ *//')
  if [[ $r == *D3D12* ]]; then
    printf '  \033[32mok  \033[0m applications render on: %s\n' "$r"
  else
    printf '  \033[31mbad \033[0m expected D3D12, got: %s\n' "${r:-nothing}"
    printf '        \033[90msudo bash wsl/setup.sh --only gpu\033[0m\n'
    fails=$((fails + 1))
  fi
else
  printf '    glxinfo not installed; cannot verify the renderer\n'
fi

step 'WSLg'
# The X socket must stay a symlink into WSLg's own mount. Replacing it with a
# real directory (which an earlier revision of this kit did, to satisfy
# Xwayland) cuts every X11 application off from WSLg.
check '/tmp/.X11-unix still points at WSLg' \
  'ln -sfn /mnt/wslg/.X11-unix /tmp/.X11-unix' \
  test -L /tmp/.X11-unix
check 'WSLg audio socket present' \
  'Restart the distro; WSLg provides this.' \
  test -S /mnt/wslg/PulseServer

step 'Remote desktop'
printf '    Not available in WSL, by measurement rather than omission:\n'
printf '    gnome-remote-desktop needs an EGL device for its capture pipeline\n'
printf '    and segfaults without a DRM node. Use the VM kit for a full\n'
printf '    desktop. Evidence: wsl/lib/remote-desktop.sh\n'

printf '\n'
if [[ $fails -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m Run apps with: gpu-run <command>\n'
else
  printf '\033[31m%d check(s) failed.\033[0m See the fix under each.\n' "$fails"
  exit 1
fi
