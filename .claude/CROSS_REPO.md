# Multi-Repository Workflow Guide

## When Working from Root Directory

When Claude Code is invoked from `/Users/bernard/src/lacylights/`:
- Changes may span multiple repositories
- Consider impact on all affected repos
- Create branches in each affected repo
- Coordinate commits across repos
- PRs may need to be merged in specific order

## When Working from Subdirectory

When Claude Code is invoked from a specific repo (e.g., `lacylights-go/`):
- Focus on that single repository
- Check the repo's own CLAUDE.md for specific guidance
- Consider how changes affect consumers

## Cross-Repository Changes

### Schema Changes (lacylights-go)
When GraphQL schema changes:
1. Update schema in `lacylights-go/internal/graph/schema.graphqls`
2. Run `make generate` in lacylights-go
3. Update `lacylights-fe`: Run `npm run codegen`
4. Update `lacylights-mcp`: Manually update queries
5. Update `lacylights-test`: Update test queries

### API Contract Changes
1. Update lacylights-go first (source of truth)
2. Update consumers (lacylights-fe, lacylights-mcp)
3. Add contract tests in lacylights-test
4. Update documentation

### Release Coordination
When releasing new versions:
1. Ensure all repos are on compatible versions
2. Update lacylights-go first (backend)
3. Update lacylights-fe (frontend must match backend)
4. Update lacylights-mcp (must match backend API)
5. Update lacylights-rpi/mac deployment scripts if needed

## Search Guidelines

**CRITICAL**: When searching across all repos, exclude the `lacylights/lacylights/` subdirectory to avoid duplicates (it contains symlinks to other repos).

```bash
# Correct: Search specific repos
grep -r "pattern" lacylights-go/ lacylights-fe/

# Wrong: Will find duplicates
grep -r "pattern" .
```

## Repository Dependencies

```
APPLICATION COMPONENTS:
lacylights-go (backend) ─── SOURCE OF TRUTH for API
    ↓
    ├── lacylights-fe (frontend) - consumes API
    ├── lacylights-mcp (AI server) - consumes API
    └── lacylights-test (tests) - validates API contracts

DISTRIBUTION INFRASTRUCTURE:
lacylights-terraform ─── ACTIVE production distribution
    ↓                    (S3/CloudFront at dist.lacylights.com)
    └── All component repos upload releases here via CI/CD

PRODUCTION DEPLOYMENT PLATFORMS:
lacylights-mac ─── macOS production platform
    └── Downloads and hosts: frontend + backend + MCP

lacylights-rpi ─── Raspberry Pi production platform
    └── Downloads and hosts: frontend + backend (no MCP)

Both platforms download releases from lacylights-terraform infrastructure
```

## Testing Cross-Repo Changes

For changes affecting multiple repos:
1. Run unit tests in each affected repo
2. Run integration tests in lacylights-test
3. Test manually on target platform (RPi or Mac)

## Coordinated Branch Strategy

When making cross-repo changes:
1. Use the same branch name in all affected repos
2. Example: `feature/new-api-field` in:
   - lacylights-go
   - lacylights-fe
   - lacylights-mcp
   - lacylights-test (if needed)

## Communication Between Repos

| From | To | Method |
|------|----|--------|
| lacylights-fe | lacylights-go | GraphQL HTTP/WS |
| lacylights-mcp | lacylights-go | GraphQL HTTP |
| lacylights-test | lacylights-go | GraphQL HTTP + Art-Net UDP |
| lacylights-mac | All | Process management |
| lacylights-rpi | All | systemd services |

## Common Multi-Repo Tasks

### Adding a New Field
1. `lacylights-go`: Add to schema, regenerate, implement resolver
2. `lacylights-fe`: Regenerate types, update queries/UI
3. `lacylights-mcp`: Update queries if MCP tools use the field
4. `lacylights-test`: Add contract tests

### Adding a New Feature
1. Design in `lacylights-go` (API first)
2. Implement backend
3. Implement frontend
4. Add MCP tools if AI-relevant
5. Add integration tests
6. Update deployment scripts if needed

### Fixing a Bug
1. Identify which repo owns the bug
2. Fix in source repo
3. Update tests
4. Consider if fix affects other repos
