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
BOT_OWNER="BradleyEvans96"      # e.g. "brad"
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
  statuses: write       # so Brad can post a "Inspector Brad" commit status (the PR check row)
  checks: write         # tolerated by both Statuses API and any future Checks API use

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
      # React with 👀 on the trigger comment so you can see it's working.
      - name: Acknowledge with reaction
        env:
          GH_TOKEN:    \${{ secrets.GITHUB_TOKEN }}
          COMMENT_ID:  \${{ github.event.comment.id }}
          REPO:        \${{ github.repository }}
        run: |
          gh api -X POST \
            "repos/\${REPO}/issues/comments/\${COMMENT_ID}/reactions" \
            -H "Accept: application/vnd.github+json" \
            -f content="eyes"

      - uses: actions/checkout@v4
        with:
          ref: refs/pull/\${{ github.event.issue.number || github.event.pull_request.number }}/head
          fetch-depth: 0

      - id: review
        uses: ${BOT_OWNER}/${BOT_REPO}@${BOT_VERSION}
        with:
          oauth-token:  \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github-token: \${{ secrets.GITHUB_TOKEN }}
          # Optional overrides:
          # model: claude-opus-4-7
          # effort: high
          # extra-instructions: |
          #   This repo is a Django app. Be strict about N+1 queries.

      # If anything above failed, post a visible comment so you don't have
      # to dig into the Actions tab to spot the failure.
      - name: Report failure on PR
        if: failure()
        env:
          GH_TOKEN:   \${{ secrets.GITHUB_TOKEN }}
          REPO:       \${{ github.repository }}
          PR_NUMBER:  \${{ github.event.issue.number || github.event.pull_request.number }}
          RUN_URL:    \${{ github.server_url }}/\${{ github.repository }}/actions/runs/\${{ github.run_id }}
        run: |
          gh pr comment "\${PR_NUMBER}" --repo "\${REPO}" --body "🚨 **Inspector Brad failed to review this PR.** [View logs](\${RUN_URL})"
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

⚠️  GitHub Free plan: org-level Actions secrets are only readable from
   PUBLIC repos. For private repos under a Free org, set the secret at
   the repo level instead:
     gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo OWNER/REPO

Per-repo tuning: drop a .inspector-brad.md file at the repo root with
guidance Brad should apply to every review of that repo. e.g.:

  # .inspector-brad.md
  This is a Django app. Be strict about N+1 queries and missing
  select_related on querysets in views.

  Tests use Pytest. The 'noqa: B008' pattern in tests is intentional
  (DI fixtures) — don't flag it.

To trigger a review, comment "@inspector-brad" or "/inspector-brad" on any PR.
DONE
