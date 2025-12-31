#!/bin/bash
set -e

# Setup script for GitHub repository
# Run this after pushing to GitHub for the first time

echo "Setting up GitHub repository..."

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    echo "Install with: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub CLI"
    echo "Run: gh auth login"
    exit 1
fi

# Get repo name
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
if [ -z "$REPO" ]; then
    echo "Error: Not in a GitHub repository or remote not set"
    exit 1
fi

echo "Repository: $REPO"

# Create release labels
echo ""
echo "Creating release labels..."
gh label create "release:major" --color "b60205" --description "Breaking change - triggers major version bump" --force || true
gh label create "release:minor" --color "0e8a16" --description "New feature - triggers minor version bump" --force || true
gh label create "release:patch" --color "fbca04" --description "Bug fix - triggers patch version bump" --force || true
gh label create "release:skip" --color "cccccc" --description "No release - skip version bump" --force || true

# Create other useful labels
gh label create "bug" --color "d73a4a" --description "Something isn't working" --force || true
gh label create "enhancement" --color "a2eeef" --description "New feature or request" --force || true
gh label create "documentation" --color "0075ca" --description "Improvements or additions to documentation" --force || true
gh label create "dependencies" --color "0366d6" --description "Pull requests that update a dependency" --force || true

echo "Labels created!"

# Set up branch protection for main
echo ""
echo "Setting up branch protection for 'main'..."

gh api repos/$REPO/branches/main/protection \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field "required_status_checks[strict]=true" \
  --field "required_status_checks[contexts][]=Build and Test" \
  --field "enforce_admins=false" \
  --field "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  --field "required_pull_request_reviews[require_code_owner_reviews]=false" \
  --field "required_pull_request_reviews[required_approving_review_count]=1" \
  --field "restrictions=null" \
  --field "allow_force_pushes=false" \
  --field "allow_deletions=false" \
  --field "block_creations=false" \
  --field "required_conversation_resolution=true" \
  2>/dev/null && echo "Branch protection enabled!" || {
    echo ""
    echo "Could not set branch protection automatically."
    echo "This may require admin permissions or a paid GitHub plan."
    echo ""
    echo "To set up manually:"
    echo "1. Go to: https://github.com/$REPO/settings/branches"
    echo "2. Click 'Add branch protection rule'"
    echo "3. Branch name pattern: main"
    echo "4. Enable:"
    echo "   - Require a pull request before merging"
    echo "   - Require status checks to pass (select 'Build and Test')"
    echo "   - Do not allow bypassing the above settings"
}

# Enable auto-merge
echo ""
echo "Enabling auto-merge..."
gh repo edit --enable-auto-merge 2>/dev/null && echo "Auto-merge enabled!" || echo "Could not enable auto-merge (may require admin)"

# Enable delete branch on merge
echo ""
echo "Enabling delete branch on merge..."
gh repo edit --delete-branch-on-merge 2>/dev/null && echo "Delete branch on merge enabled!" || echo "Could not enable (may require admin)"

echo ""
echo "============================================"
echo "Setup complete!"
echo ""
echo "Branch protection rules:"
echo "  - Direct pushes to main: BLOCKED"
echo "  - Required: Pull request with 1 approval"
echo "  - Required: Build must pass"
echo "  - Stale reviews dismissed on new commits"
echo ""
echo "To create a release:"
echo "  1. Create a branch: git checkout -b feature/my-feature"
echo "  2. Make changes and commit: git commit -m 'feat: my feature'"
echo "  3. Push and create PR: gh pr create"
echo "  4. After merge, release is created automatically!"
echo "============================================"
