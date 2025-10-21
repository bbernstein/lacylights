# Release Process

This document describes how to create releases for all LacyLights repositories.

## Overview

All LacyLights repositories use automated GitHub Actions workflows to create releases with consistent version numbering following [Semantic Versioning](https://semver.org/).

## Repositories

- **lacylights-node** - Backend server
- **lacylights-fe** - Frontend web application
- **lacylights-mcp** - MCP server for AI integration
- **lacylights** - Launcher and orchestration scripts

## Semantic Versioning

We follow semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR** - Incompatible API changes
- **MINOR** - New functionality in a backwards-compatible manner
- **PATCH** - Backwards-compatible bug fixes

## How to Create a Release

### Step 1: Navigate to Actions

1. Go to the repository on GitHub
2. Click on the **Actions** tab
3. Select **Create Release** from the workflows list

### Step 2: Run Workflow

1. Click **Run workflow** button
2. Fill in the form:
   - **Version bump type**: Select `patch`, `minor`, or `major`
   - **Release name**: (Optional) Enter a custom release name, or leave blank for auto-generated

### Step 3: Choose Version Bump Type

#### Patch (0.0.X)
- Bug fixes
- Documentation updates
- Minor code refactoring
- Performance improvements without API changes

Example: `0.1.3` → `0.1.4`

#### Minor (0.X.0)
- New features
- New functionality that's backwards-compatible
- Deprecation of features (but not removal)

Example: `0.1.4` → `0.2.0`

#### Major (X.0.0)
- Breaking changes
- Removal of deprecated features
- Major refactoring affecting API
- Incompatible changes

Example: `0.2.0` → `1.0.0`

### Step 4: Review the Release

The workflow will automatically:

1. ✅ Calculate the new version number
2. ✅ Update version in `package.json` (for Node projects) or `VERSION` file
3. ✅ Commit the version bump
4. ✅ Create a git tag (e.g., `v0.2.0`)
5. ✅ Generate AI-powered release notes using GitHub's auto-generation
6. ✅ Create a GitHub Release with the notes
7. ✅ Provide a summary with the release URL

## AI-Generated Release Notes

GitHub automatically generates release notes based on:
- Commit messages since the last release
- Pull request titles and descriptions
- Contributors
- New features, bug fixes, and other changes

The release notes are categorized automatically using conventional commit patterns.

## Best Practices

### Commit Message Format

Use conventional commit format for better release notes:

```
feat: add new lighting effect
fix: resolve DMX channel overflow
docs: update API documentation
chore: bump dependencies
refactor: simplify scene manager
test: add unit tests for fixtures
```

### Release Coordination

When releasing multiple repos together:

1. **Start with dependencies first**: `lacylights-node`, `lacylights-mcp`
2. **Then frontend**: `lacylights-fe`
3. **Finally launcher**: `lacylights`

This ensures the launcher downloads compatible versions.

### Version Alignment

While not strictly required, consider keeping major/minor versions aligned across repos for easier tracking:

```
lacylights-node:  v0.2.0
lacylights-fe:    v0.2.0
lacylights-mcp:   v0.2.0
lacylights:       v0.2.0
```

## Rollback Process

If you need to rollback a release:

1. Delete the release from GitHub (this doesn't delete the tag)
2. Delete the tag: `git tag -d v0.2.0 && git push origin :refs/tags/v0.2.0`
3. Revert the version commit: `git revert <commit-sha>`
4. Create a new patch release with the fix

## Viewing Releases

- **GitHub UI**: Go to the repository → Releases tab
- **API**: `https://api.github.com/repos/bbernstein/[repo]/releases/latest`
- **Download**: The launcher uses these releases for automatic updates

## Troubleshooting

### Workflow Fails

Check the Actions tab for error details. Common issues:
- Permission errors: Ensure `contents: write` permission is set
- Merge conflicts: Ensure main branch is clean
- Network issues: Retry the workflow

### Version Mismatch

If versions get out of sync:
1. Check the current version: `git describe --tags --abbrev=0`
2. Manually create a tag if needed: `git tag v0.2.0 && git push origin v0.2.0`

## Examples

### Creating a Patch Release

```
Scenario: Fixed a bug in DMX output
Action: Run workflow → Select "patch" → v0.1.3 → v0.1.4
```

### Creating a Minor Release

```
Scenario: Added cue list loop mode feature
Action: Run workflow → Select "minor" → v0.1.4 → v0.2.0
```

### Creating a Major Release

```
Scenario: Complete rewrite with breaking API changes
Action: Run workflow → Select "major" → v0.2.0 → v1.0.0
```

## Integration with Launcher

The launcher (`setup.sh` and `update-repos.sh`) automatically:
- Downloads the latest release from each repository
- Extracts the release archive
- Tracks versions using `.lacylights-version` files
- Updates when newer releases are available

This creates a clean deployment without nested git repositories.
