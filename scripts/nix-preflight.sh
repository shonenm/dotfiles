#!/usr/bin/env bash
# nix-preflight: verify whether a host is ready for the Nix migration.
#
# Usage:
#   ./scripts/nix-preflight.sh           # local host
#   ssh <host> bash -s < scripts/nix-preflight.sh   # remote host (pipe over ssh)
#
# Output: a one-line summary classifying the host as
#   READY-NATIVE   — single-user / multi-user Nix install supported
#   READY-CHROOT   — nix-user-chroot fallback (user namespaces present, /nix unwritable)
#   READY-PORTABLE — nix-portable / proot fallback (no user namespaces)
#   ALREADY        — Nix already installed
#   BLOCKED        — none of the above
#
# The detailed checklist is written to stderr so the summary can be piped.

set -u

OS="$(uname -s)"
SUMMARY=""

note()  { printf '  %s\n' "$*" >&2; }
ok()    { printf '  [ok] %s\n' "$*" >&2; }
warn()  { printf '  [--] %s\n' "$*" >&2; }
fail()  { printf '  [xx] %s\n' "$*" >&2; }

printf '== nix-preflight on %s (%s) ==\n' "$(hostname -s 2>/dev/null || echo unknown)" "$OS" >&2

# 1. Already installed?
if command -v nix >/dev/null 2>&1; then
  ok "nix command found: $(nix --version 2>/dev/null || echo unknown)"
  SUMMARY="ALREADY"
else
  warn "nix command not found"
fi

# 2. macOS path
if [ "$OS" = "Darwin" ]; then
  ok "macOS detected — Determinate Systems installer recommended"
  ok "no user namespaces concept on macOS; nix-darwin used for system layer"
  if [ -z "$SUMMARY" ]; then SUMMARY="READY-NATIVE"; fi
  printf '\nSummary: %s\n' "$SUMMARY"
  exit 0
fi

# 3. Linux path
if [ "$OS" != "Linux" ]; then
  fail "unsupported OS: $OS"
  printf '\nSummary: BLOCKED\n'
  exit 1
fi

# 3a. /nix writability (would need root for multi-user; single-user fine without)
if [ -w / ] || sudo -n true 2>/dev/null; then
  ok "root path available (sudo or root) — multi-user install possible"
  NIX_ROOT_OK=1
else
  warn "no sudo / no root — single-user / nix-user-chroot / nix-portable only"
  NIX_ROOT_OK=0
fi

# 3b. user namespaces
if unshare --user --pid echo ok >/dev/null 2>&1; then
  ok "user namespaces work"
  USERNS_OK=1
else
  warn "user namespaces unavailable (or restricted)"
  USERNS_OK=0
fi

# 3c. kernel version (Nix needs >= 3.10 effectively; modern kernels all qualify)
KREL="$(uname -r 2>/dev/null || echo unknown)"
ok "kernel: $KREL"

# 3d. selinux / apparmor hostility check
if command -v getenforce >/dev/null 2>&1; then
  SE="$(getenforce 2>/dev/null || echo unknown)"
  case "$SE" in
    Enforcing) warn "SELinux Enforcing — may interact with /nix paths" ;;
    *)         ok "SELinux: $SE" ;;
  esac
fi
if command -v aa-status >/dev/null 2>&1 && aa-status --enabled 2>/dev/null; then
  warn "AppArmor enabled — may need profile adjustments"
fi

# 3e. existing /nix directory state
if [ -d /nix ]; then
  if [ -w /nix ]; then
    ok "/nix exists and is writable"
  else
    warn "/nix exists but not writable as $(whoami)"
  fi
else
  note "/nix does not exist (expected pre-install)"
fi

# Classify
if [ -z "$SUMMARY" ]; then
  if [ "$NIX_ROOT_OK" = 1 ]; then
    SUMMARY="READY-NATIVE"
  elif [ "$USERNS_OK" = 1 ]; then
    SUMMARY="READY-CHROOT"
  else
    SUMMARY="READY-PORTABLE"
  fi
fi

printf '\nSummary: %s\n' "$SUMMARY"
