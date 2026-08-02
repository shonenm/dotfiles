#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

assert_eq() {
  [[ "$1" == "$2" ]] || { echo "expected '$2', got '$1'" >&2; exit 1; }
}

assert_eq "$(npm_package_name foo)" "foo"
assert_eq "$(npm_package_name foo@1.2.3)" "foo"
assert_eq "$(npm_package_name @scope/foo)" "@scope/foo"
assert_eq "$(npm_package_name @scope/foo@latest)" "@scope/foo"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/src"
touch "$tmpdir/src/input" "$tmpdir/target"
chmod +x "$tmpdir/target"
target_needs_rebuild "$tmpdir/missing" "$tmpdir/src"
if target_needs_rebuild "$tmpdir/target" "$tmpdir/src"; then
  echo "unchanged input unexpectedly requires rebuild" >&2
  exit 1
fi
sleep 1
touch "$tmpdir/src/input"
target_needs_rebuild "$tmpdir/target" "$tmpdir/src"

list_contains_line $'foo\n@scope/bar' '@scope/bar'
if list_contains_line $'foobar\nbar' 'foo'; then
  echo "list_contains_line accepted a partial match" >&2
  exit 1
fi

export XDG_CACHE_HOME="$tmpdir/cache"
fp=$(install_fingerprint alpha beta)
assert_eq "$fp" "$(install_fingerprint alpha beta)"
if install_state_is_current test "$fp"; then
  echo "missing install state unexpectedly matched" >&2
  exit 1
fi
record_install_state test "$fp"
install_state_is_current test "$fp"
UPDATE_INSTALL=true
if install_state_is_current test "$fp"; then
  echo "--update did not invalidate install state" >&2
  exit 1
fi
export UPDATE_INSTALL=false

HOME="$tmpdir/home"
mkdir -p "$HOME" "$tmpdir/templates"
printf 'home=__HOME__\n' > "$tmpdir/templates/input"
render_home_template "$tmpdir/templates/input" "$HOME/output"
if render_home_template "$tmpdir/templates/input" "$HOME/output"; then
  echo "unchanged template was rewritten" >&2
  exit 1
fi

echo "install fast-path tests: OK"
