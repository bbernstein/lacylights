# LacyLights Project Instructions

This file provides guidance to Claude Code when working with the LacyLights multi-repository project.

## Quick Reference

- **Rules**: See [.claude/RULES.md](.claude/RULES.md) for coding standards and workflow rules
- **Architecture**: See [.claude/ARCHITECTURE.md](.claude/ARCHITECTURE.md) for system design
- **Multi-Repo**: See [.claude/CROSS_REPO.md](.claude/CROSS_REPO.md) for cross-repository workflows

## Repository Overview

### Application Components
| Repository | Purpose | Tech Stack |
|------------|---------|------------|
| [lacylights-go](lacylights-go/) | Backend API server | Go, GraphQL, SQLite, Art-Net |
| [lacylights-fe](lacylights-fe/) | Web frontend | Next.js, React, TypeScript |
| [lacylights-mcp](lacylights-mcp/) | AI integration server | TypeScript, MCP SDK, OpenAI |

### Production Deployment Platforms
| Repository | Purpose | Hosts |
|------------|---------|-------|
| [lacylights-mac](lacylights-mac/) | macOS production platform | Frontend + Backend + MCP |
| [lacylights-rpi](lacylights-rpi/) | Raspberry Pi production platform | Frontend + Backend |

Both platforms download releases from dist.lacylights.com and run the applications in production.

### Infrastructure & Testing
| Repository | Purpose | Tech Stack |
|------------|---------|------------|
| [lacylights-terraform](lacylights-terraform/) | Release distribution infrastructure | AWS S3, CloudFront, DynamoDB |
| [lacylights-test](lacylights-test/) | Integration & contract tests | Go |

Each repository has its own CLAUDE.md with specific guidance. Read the relevant one when working in a subdirectory.

## Current Implementation Project

**Raspberry Pi Hardware Product**: We are implementing LacyLights as a turnkey hardware product for Raspberry Pi. See `docs/RASPBERRY_PI_PRODUCT_PLAN.md` for the complete implementation plan, architecture, and progress tracking.

## Important Search Warning

**CRITICAL**: The `lacylights/lacylights/` subdirectory contains symlinks/copies to other repos. When searching recursively, **always exclude this directory** to avoid duplicate results:

```bash
# Correct approach
grep -r "pattern" lacylights-go/ lacylights-fe/

# Wrong - will find duplicates
grep -r "pattern" .
```

## Services and Ports

| Service | Port | Protocol |
|---------|------|----------|
| GraphQL API | 4000 (dev) / 4001 (test) | HTTP |
| WebSocket | 4000 | WS |
| Art-Net DMX | 6454 | UDP |
| Web Frontend | 3000 | HTTP |

## Integration Testing Hub: lacylights-test

The `lacylights-test` repository is **NOT a unit test repo**. It's the central integration testing hub that validates cross-repository behavior.

**When working in lacylights-test:**
1. Read `docs/TESTING_PLAN.md` first
2. Use Explore agent to read code from other repos
3. Tests here validate contracts between components, not internal logic

**Key Principle**: "Does this test cross repository boundaries?"
- **YES** → Belongs in lacylights-test
- **NO** → Belongs in the component's own repo

## GitHub Repositories

- https://github.com/bbernstein/lacylights (documentation)
- https://github.com/bbernstein/lacylights-go
- https://github.com/bbernstein/lacylights-fe
- https://github.com/bbernstein/lacylights-mcp
- https://github.com/bbernstein/lacylights-test
- https://github.com/bbernstein/lacylights-terraform
- https://github.com/bbernstein/lacylights-rpi
- https://github.com/bbernstein/lacylights-mac

## Key Documentation

| Document | Location | Purpose |
|----------|----------|---------|
| RPi Product Plan | `docs/RASPBERRY_PI_PRODUCT_PLAN.md` | Hardware product implementation |
| Testing Plan | `lacylights-test/docs/TESTING_PLAN.md` | Integration testing strategy |
| Go Distribution | `docs/GO_DISTRIBUTION_PLAN.md` | Binary releases |
| Contract Testing | `docs/CONTRACT_TESTING_PLAN.md` | API contract validation |

## Completed Features

### Channel Fade Behavior (2025-12-10)
Added per-channel control over DMX fade behavior during scene transitions. See `docs/CHANNEL_FADE_BEHAVIOR_PLAN.md`.

### Mobile Scene Board Optimization (2025-11-22)
Converted Scene Board to pixel-based coordinates with touch gesture support. See `docs/MOBILE_SCENE_BOARD_PLAN.md`.
