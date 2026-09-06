# GPU: make applications in the session use the real GPU.
#
# WSL exposes the host GPU as /dev/dxg, and Mesa's d3d12 driver renders through
# it -- with no DRM device and no /dev/dri involved. Two things stop that
# happening by default:
#
#   * Fedora ships stock Mesa, which does not auto-select d3d12 on WSL the way
#     Ubuntu's patched build does. Left alone it silently uses llvmpipe: no
#     warning, no error, just software rendering.
#   * When it does select d3d12 it picks the first adapter, which on a machine
#     with both is the integrated GPU rather than the discrete one.
#
# This does NOT accelerate the compositor. Mutter needs a DRM render node to
# pick a GPU and there is none, so it says "surfaceless renderer without GPU"
# and composites on the CPU. Compositing a shell is cheap; the applications
# are what needed the GPU, and they get it.

LW_GPU_PROFILE=/etc/profile.d/10-linux-on-hyperv-gpu.sh
LW_ADAPTER=${LW_ADAPTER:-NVIDIA}

lw_gpu() {
  step "GPU (preferring adapter: $LW_ADAPTER)"

  if [[ ! -e /dev/dxg ]]; then
    warn 'No /dev/dxg; skipping. Nothing here would take effect.'
    return 0
  fi

  write_file "$LW_GPU_PROFILE" <<PROFILE
$LH_STAMP
#
# See wsl/lib/gpu.sh for why both of these are needed.
export GALLIUM_DRIVER=d3d12
export MESA_D3D12_DEFAULT_ADAPTER_NAME=$LW_ADAPTER
PROFILE
  [[ $LH_DRY_RUN == 1 ]] || chmod 0644 "$LW_GPU_PROFILE"

  # A profile.d file only reaches login shells. The RDP session's processes are
  # started by systemd --user, which reads its own environment, so set it there
  # too or every graphical app misses the GPU.
  local user home
  user=$(target_user)
  home=$(getent passwd "$user" | cut -d: -f6)
  if [[ -n $home && -d $home ]]; then
    write_file "$home/.config/environment.d/10-linux-on-hyperv-gpu.conf" <<ENVD
$LH_STAMP
GALLIUM_DRIVER=d3d12
MESA_D3D12_DEFAULT_ADAPTER_NAME=$LW_ADAPTER
ENVD
    [[ $LH_DRY_RUN == 1 ]] || chown -R "$user:$user" "$home/.config/environment.d" 2>/dev/null || true
  fi

  lw_gpu_verify
}

lw_gpu_verify() {
  [[ $LH_DRY_RUN == 1 ]] && return 0
  has glxinfo || pkg_install glx-utils >/dev/null 2>&1 || true
  has glxinfo || { note 'glxinfo not available; skipping verification'; return 0; }

  local renderer
  renderer=$(GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME="$LW_ADAPTER" \
    glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | cut -d: -f2- | sed 's/^ *//')

  if [[ $renderer == *D3D12* ]]; then
    ok "applications will render on: $renderer"
  else
    warn "expected a D3D12 renderer, got: ${renderer:-nothing}"
    note 'Check that mesa-dri-drivers (Fedora) or mesa-utils (Debian) is installed.'
  fi
}
