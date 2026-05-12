#!/usr/bin/env bash
# install.sh — push the Inspector Brad workflow file into many of your repos at once.
#
# Usage:
#   ./install.sh OWNER/repo1 OWNER/repo2 OWNER/repo3
#   ./install.sh $(gh repo list YOUR_USERNAME --limit 100 --json nameWithOwner -q '.[].nameWithOwner')
#
# Requires: gh CLI authenticated (`gh auth login`).

set -euo pipefail

if [ $# -eq 0 ]; then
  cat <<USAGE
Usage:
  $0 OWNER/repo [OWNER/repo ...]

Examples:
  # Install on a single repo
  $0 brad/my-side-project

  # Install on every repo you own (be careful!)
  $0 \$(gh repo list YOUR_USERNAME --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

  # Install on repos in an org
  $0 \$(gh repo list YOUR_ORG --limit 100 --json nameWithOwner -q '.[].nameWithOwner')

Before running, edit the BOT_OWNER variable at the top of this script
to point at YOUR inspector-brad repo (e.g. "brad").
USAGE
  exit 1
fi

# ---- EDIT THIS ----
BOT_OWNER="YOUR_GH_USERNAME"      # e.g. "brad"
BOT_REPO="inspector-brad"           # the action repo name
BOT_VERSION="v1"                  # tag to pin to
# -------------------

WORKFLOW_PATH=".github/workflows/claude-review.yml"
TMP_FILE=$(mktemp)

cat > "$TMP_FILE" <<WFEOF
name: Claude PR Review

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

permissions:
  contents: read
  pull-requests: write
  issues: write
  id-token: write

jobs:
  review:
    if: >-
      (github.event.issue.pull_request != null || github.event.pull_request != null) &&
      (
        contains(github.event.comment.body, '@inspector-brad') ||
        contains(github.event.comment.body, '/inspector-brad')
      )
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: refs/pull/\${{ github.event.issue.number || github.event.pull_request.number }}/head
          fetch-depth: 0

      - uses: ${BOT_OWNER}/${BOT_REPO}@${BOT_VERSION}
        with:
          oauth-token:  \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github-token: \${{ secrets.GITHUB_TOKEN }}
WFEOF

for repo in "$@"; do
  echo "→ Installing in $repo..."

  # Check if the file already exists
  if gh api "repos/$repo/contents/$WORKFLOW_PATH" >/dev/null 2>&1; then
    echo "  ⚠️  $WORKFLOW_PATH already exists — skipping. Delete manually if you want to overwrite."
    continue
  fi

  # Push via the contents API (single-file commit, no clone needed)
  SHA=""
  CONTENT=$(base64 < "$TMP_FILE" | tr -d '\n')
  gh api -X PUT "repos/$repo/contents/$WORKFLOW_PATH" \
    -f message="Install Inspector Brad" \
    -f content="$CONTENT" >/dev/null

  echo "  ✅ Installed"
done

rm -f "$TMP_FILE"

cat <<DONE

All done. Make sure each repo has CLAUDE_CODE_OAUTH_TOKEN as a secret —
if you set it at the org level, every repo inherits it for free.

To trigger a review, comment "@inspector-brad" or "/inspector-brad" on any PR.
DONE
