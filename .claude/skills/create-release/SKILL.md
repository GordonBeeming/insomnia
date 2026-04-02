---
name: create-release
description: Create a new draft release for Insomnia. Use when the user says "create a release", "new release", "cut a release", or "ship it".
---

# Create Release

Create a new GitHub release for Insomnia with the correct versioning.

## Steps

1. Pull latest: `but pull`
2. Determine the next version by checking existing releases:
   ```bash
   gh release list --repo gordonbeeming/insomnia --limit 5
   ```
3. Bump the minor version (e.g., v0.2 → v0.3). Never use a patch number in the tag.
4. Create the release:
   ```bash
   gh release create v{major}.{minor} \
     --repo gordonbeeming/insomnia \
     --target main \
     --title "v{major}.{minor} — {short description}" \
     --notes "$(cat <<'EOF'
   # Insomnia v{major}.{minor} — {short description}

   ## What's New

   - {list changes since last release using git log}

   ## Install

   ```bash
   brew upgrade --cask gordonbeeming/tap/insomnia
   ```

   Or download the DMG and CLI binary from the assets below.
   EOF
   )"
   ```
5. The release pipeline will automatically:
   - Build + test
   - Sign with Developer ID
   - Notarize with Apple
   - Create DMG
   - Upload assets to the release
   - Update the Homebrew tap cask
6. Report the release URL and pipeline run to the user

## Version Format

- Tags: `v{major}.{minor}` (e.g., `v0.3`) — NO patch number
- Bundle version: `{major}.{minor}.{runNumber}` — CI adds the run number as patch
- The tag `v0.3` with run number 45 produces bundle version `0.3.45`

## Generating Release Notes

Use git log to find changes since the last release tag:
```bash
LAST_TAG=$(gh release list --repo gordonbeeming/insomnia --limit 1 --json tagName --jq '.[0].tagName')
git log ${LAST_TAG}..HEAD --oneline
```

## Important

- Never reuse or delete existing release tags
- Always bump the minor version for new releases
- Never use `.0` patch in tags (v0.3 not v0.3.0)
- The release triggers the full CI pipeline — wait for it to complete before telling the user to `brew upgrade`
