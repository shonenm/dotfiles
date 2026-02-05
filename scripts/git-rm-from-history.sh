#!/bin/bash
# Remove a file completely from git history
# Usage: git-rm-from-history <file-path>
# WARNING: This rewrites history. Force push will be required.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: git-rm-from-history <file-path>"
  echo "WARNING: This rewrites history. Force push will be required."
  exit 1
fi

file="$1"

echo "Removing '$file' from all git history..."
echo ""

if command -v git-filter-repo &>/dev/null; then
  git filter-repo --invert-paths --path "$file" --force
else
  echo "git-filter-repo not found. Falling back to git filter-branch..."
  echo "(Consider installing git-filter-repo for better performance: pip install git-filter-repo)"
  echo ""
  git filter-branch --force --index-filter \
    "git rm --cached --ignore-unmatch '$file'" \
    --prune-empty --tag-name-filter cat -- --all
fi

echo ""
echo "Done. Run 'git push --force --all' to update remote."
