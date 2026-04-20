#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"
REPO="${2:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required: https://cli.github.com/"
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

OWNER="${REPO%/*}"
NAME="${REPO#*/}"

if [[ ! -f ".github/branch-protection/main.json" ]]; then
  echo "Missing .github/branch-protection/main.json"
  exit 1
fi

echo "Applying branch protection to ${OWNER}/${NAME}:${BRANCH}"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${NAME}/branches/${BRANCH}/protection" \
  --input .github/branch-protection/main.json >/dev/null

echo "✅ Branch protection applied to ${BRANCH}"
