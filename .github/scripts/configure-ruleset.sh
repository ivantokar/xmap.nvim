#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
RULESET_ID="${2:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required: https://cli.github.com/"
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

OWNER="${REPO%/*}"
NAME="${REPO#*/}"

if [[ ! -f ".github/rulesets/protect-main.json" ]]; then
  echo "Missing .github/rulesets/protect-main.json"
  exit 1
fi

if [[ -z "$RULESET_ID" ]]; then
  RULESET_ID="$(gh api "/repos/${OWNER}/${NAME}/rulesets" --jq '.[] | select(.name=="Protect main") | .id' | head -n1)"
fi

if [[ -z "$RULESET_ID" ]]; then
  echo "Could not find ruleset id for 'Protect main'"
  exit 1
fi

echo "Updating ruleset ${RULESET_ID} for ${OWNER}/${NAME}"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${NAME}/rulesets/${RULESET_ID}" \
  --input .github/rulesets/protect-main.json >/dev/null

echo "✅ Ruleset updated"
