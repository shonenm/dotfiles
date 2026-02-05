#!/bin/bash
# Remove a git submodule completely
# Usage: git-rm-submodule <submodule-path>

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: git-rm-submodule <submodule-path>"
  exit 1
fi

submodule="$1"

# Remove trailing slash if present
submodule="${submodule%/}"

if [[ ! -f .gitmodules ]] || ! grep -q "path = $submodule" .gitmodules 2>/dev/null; then
  echo "Error: '$submodule' is not a registered submodule."
  exit 1
fi

echo "Removing submodule '$submodule'..."

git submodule deinit -f "$submodule"
git rm -f "$submodule"
rm -rf ".git/modules/$submodule"

echo "Done. Submodule '$submodule' removed. Commit the changes to complete."
