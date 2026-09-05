# Shared helpers for the guest kit. Sourced, never executed.

set -o pipefail

LH_DRY_RUN=${LH_DRY_RUN:-0}
LH_STAMP="# Managed by linux-on-hyperv. Re-running setup.sh overwrites this."

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
  if [[ $LH_DRY_RUN == 1 ]]; then
    printf '    \033[90m[dry-run] %s\033[0m\n' "$*"
    return 0
  fi
  "$@"
}

# Writes a file from stdin, skipping the write when the content already
# matches. Sets LH_WROTE=1 when it actually changed something.
write_file() {
  local path=$1
  local content
  content=$(cat)
  LH_WROTE=0

  if [[ -f $path ]] && [[ $(cat "$path" 2>/dev/null) == "$content" ]]; then
    note "unchanged: $path"
    return 0
  fi

  if [[ $LH_DRY_RUN == 1 ]]; then
    printf '    \033[90m[dry-run] write %s (%d bytes)\033[0m\n' "$path" "${#content}"
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
  LH_WROTE=1
  ok "wrote $path"
}

has() { command -v "$1" >/dev/null 2>&1; }

pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }

dnf_install() {
  local missing=()
  local pkg
  for pkg in "$@"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    note "already installed: $*"
    return 0
  fi
  run dnf install -y "${missing[@]}" || die "dnf failed for: ${missing[*]}"
  ok "installed: ${missing[*]}"
}

enable_unit() {
  local unit=$1
  if systemctl is-enabled --quiet "$unit" 2>/dev/null && systemctl is-active --quiet "$unit" 2>/dev/null; then
    note "already enabled and running: $unit"
    return 0
  fi
  run systemctl enable --now "$unit" || warn "could not enable $unit"
}

# The invoking user, even though the script runs under sudo. Almost everything
# here is system-level, but the RDP login is per-user and needs the real name.
target_user() {
  printf '%s' "${SUDO_USER:-$(id -un)}"
}
