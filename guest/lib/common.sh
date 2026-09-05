# Shared helpers for the guest kit. Sourced, never executed.

set -o pipefail

OW_DRY_RUN=${OW_DRY_RUN:-0}
OW_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-on-windows"

# Marks files we write, so an uninstall (or a confused future reader) can tell
# ours from Omarchy's own.
OW_STAMP="# Managed by omarchy-on-windows. Edit freely; re-running install.sh overwrites it."

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok() { printf '  \033[32m+\033[0m %s\n' "$*"; }
note() { printf '    \033[90m%s\033[0m\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die() {
  printf '\n\033[31mfailed:\033[0m %s\n' "$*" >&2
  exit 1
}

# Every side effect goes through run(), so --dry-run is honest rather than
# approximate.
run() {
  if [[ $OW_DRY_RUN == 1 ]]; then
    printf '    \033[90m[dry-run] %s\033[0m\n' "$*"
    return 0
  fi
  "$@"
}

# Writes a file from stdin, creating parents, honouring dry-run, and skipping
# the write when the content already matches so reruns stay quiet.
# Sets OW_WROTE=1 when it actually changed the file, so callers can skip
# expensive follow-up work (rebuilding an initramfs, say) on a no-op re-run.
write_file() {
  local path=$1 sudo_prefix=${2:-}
  local content
  content=$(cat)
  OW_WROTE=0

  if [[ -f $path ]] && [[ $(cat "$path" 2>/dev/null) == "$content" ]]; then
    note "unchanged: $path"
    return 0
  fi

  if [[ $OW_DRY_RUN == 1 ]]; then
    printf '    \033[90m[dry-run] write %s (%d bytes)\033[0m\n' "$path" "${#content}"
    return 0
  fi

  if [[ -n $sudo_prefix ]]; then
    sudo mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" | sudo tee "$path" >/dev/null
  else
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" >"$path"
  fi
  OW_WROTE=1
  ok "wrote $path"
}

has() { command -v "$1" >/dev/null 2>&1; }

pkg_installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# Installs official-repo packages, skipping any already present.
pacman_install() {
  local missing=()
  local pkg
  for pkg in "$@"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    note "already installed: $*"
    return 0
  fi
  run sudo pacman -S --needed --noconfirm "${missing[@]}" || die "pacman failed for: ${missing[*]}"
  ok "installed: ${missing[*]}"
}

# Installs from the AUR with yay, which Omarchy ships.
aur_install() {
  local missing=()
  local pkg
  for pkg in "$@"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    note "already installed: $*"
    return 0
  fi
  has yay || die "yay not found; Omarchy normally ships it. Install ${missing[*]} by hand."
  run yay -S --needed --noconfirm "${missing[@]}" || die "yay failed for: ${missing[*]}"
  ok "installed from AUR: ${missing[*]}"
}

enable_system_unit() {
  local unit=$1
  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    note "already enabled: $unit"
    return 0
  fi
  run sudo systemctl enable --now "$unit" || warn "could not enable $unit"
}

enable_user_unit() {
  local unit=$1

  if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
    note "already enabled: $unit"
    return 0
  fi

  # A unit installed by a package earlier in this same run is invisible to the
  # user manager until it rescans; without this, enabling it fails with
  # "Unit <name> does not exist" even though the file is on disk.
  run systemctl --user daemon-reload 2>/dev/null || true

  if ! systemctl --user list-unit-files "$unit" 2>/dev/null | grep -q "$unit"; then
    warn "user unit $unit not found even after a daemon-reload."
    note "Look for what the package actually shipped:"
    note "  pacman -Qql sunshine sunshine-bin 2>/dev/null | grep -i '\.service$'"
    note "  systemctl --user list-unit-files | grep -i sunshine"
    return 1
  fi

  run systemctl --user enable --now "$unit" || warn "could not enable user unit $unit"
}
