#!/usr/bin/env bash
# check-package-duplication.sh — ensure sudo (apt) and no-sudo (pixi) paths
# stay in sync for packages that live in both install modes.
#
# Rationale:
#   A handful of tools are installed via apt (sudo) AND via pixi (no-sudo).
#   If someone adds a new one to packages.linux.apt.txt but forgets
#   pixi-packages.txt (or vice versa), one environment will silently miss it.
#
# This check enforces: any package that appears in the apt list AND is known
# to need user-scope equivalence must also appear in pixi-packages.txt.
#
# The "must mirror" set below is curated: it is the intersection of packages
# we install via apt that are also available on conda-forge (where pixi pulls
# from). If the apt list stays inside this set, the check is useful; if we
# adopt truly sudo-only packages (e.g., kernel tools), add them to the
# APT_SUDO_ONLY set at the bottom to mark them as intentionally-missing.
#
# Exit status: 0 if in sync, 1 otherwise.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
APT_FILE="$REPO_ROOT/config/packages.linux.apt.txt"
PIXI_FILE="$REPO_ROOT/config/pixi-packages.txt"

if [[ ! -f "$APT_FILE" ]] || [[ ! -f "$PIXI_FILE" ]]; then
  echo "error: expected $APT_FILE and $PIXI_FILE to exist" >&2
  exit 2
fi

# Normalize: strip comments + blanks, sort unique.
apt_pkgs=$(grep -vE '^\s*#|^\s*$' "$APT_FILE" | sort -u)
pixi_pkgs=$(grep -vE '^\s*#|^\s*$' "$PIXI_FILE" | sort -u)

# Packages we *knowingly* install via apt that MUST also be in pixi for
# no-sudo parity. Keep this list curated.
declare -a MUST_MIRROR=(
  zsh
  stow
  jq
  unzip
  rsync
  ripgrep
  fd-find
  imagemagick
)

# Packages intentionally sudo-only (no pixi equivalent expected).
declare -a APT_SUDO_ONLY=(
  build-essential
  pkg-config
  libssl-dev
  luarocks
  tmux  # tmux comes from install_tmux_source in no-sudo mode, not pixi
)

missing=()
for pkg in "${MUST_MIRROR[@]}"; do
  if ! printf '%s\n' "$apt_pkgs" | grep -qxF "$pkg"; then
    echo "warn: '$pkg' listed as MUST_MIRROR but missing from $APT_FILE"
    continue
  fi
  if ! printf '%s\n' "$pixi_pkgs" | grep -qxF "$pkg"; then
    missing+=("$pkg")
  fi
done

# Also detect packages added to apt that aren't in MUST_MIRROR or APT_SUDO_ONLY
# — these probably need a decision.
declare -A known=()
for p in "${MUST_MIRROR[@]}" "${APT_SUDO_ONLY[@]}"; do known[$p]=1; done

unclassified=()
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  if [[ -z "${known[$pkg]:-}" ]]; then
    unclassified+=("$pkg")
  fi
done <<< "$apt_pkgs"

fail=0
if (( ${#missing[@]} > 0 )); then
  echo "ERROR: packages in $APT_FILE missing from $PIXI_FILE:"
  printf '  - %s\n' "${missing[@]}"
  fail=1
fi

if (( ${#unclassified[@]} > 0 )); then
  echo "WARN: packages in $APT_FILE not classified as MUST_MIRROR or APT_SUDO_ONLY:"
  printf '  - %s\n' "${unclassified[@]}"
  echo "  (update MUST_MIRROR or APT_SUDO_ONLY in $(basename "$0"))"
  # Don't fail on unclassified — treat as warning so brand-new tools don't
  # block CI before the classification is updated.
fi

if (( fail == 0 )); then
  echo "OK: apt/pixi package lists are in sync."
fi
exit $fail
