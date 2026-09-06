# GPU-accelerated Linux applications on the Windows desktop.
#
# This is what WSL can genuinely do that the VM cannot. WSLg already puts each
# graphical application in its own Windows window with working audio; the only
# missing piece is that Fedora's Mesa needs telling to use the GPU (see gpu.sh).
#
# There is no desktop shell here on purpose: no compositor, no panel, no
# launcher. Applications are the unit.

lw_apps() {
  step 'GPU-accelerated applications'

  if [[ ! -e /dev/dxg ]]; then
    warn 'No /dev/dxg; applications will render in software.'
    return 0
  fi

  # A launcher that guarantees the GPU environment, so an app started from
  # anywhere -- a Windows shortcut, another shell -- gets it.
  write_file /usr/local/bin/gpu-run <<'LAUNCH'
#!/bin/bash
# Run a graphical application on the GPU under WSLg.
#
# Fedora's stock Mesa does not auto-select the WSL d3d12 driver and picks the
# integrated GPU when it does; both have to be said explicitly. Without this
# the app silently renders on llvmpipe.
export GALLIUM_DRIVER=${GALLIUM_DRIVER:-d3d12}
export MESA_D3D12_DEFAULT_ADAPTER_NAME=${MESA_D3D12_DEFAULT_ADAPTER_NAME:-NVIDIA}
exec "$@"
LAUNCH
  [[ $LH_DRY_RUN == 1 ]] || chmod 0755 /usr/local/bin/gpu-run
  ok 'installed /usr/local/bin/gpu-run'

  note 'Use it like:  gpu-run firefox        (from a WSL shell, or wsl.exe -d ... -- gpu-run ...)'
  note 'Check what an app gets with:  gpu-run glxinfo -B | grep "OpenGL renderer"'
}
