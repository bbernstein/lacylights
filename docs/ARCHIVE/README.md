# Archived Documentation

This directory contains documentation for completed or obsolete initiatives. These documents are preserved for historical reference but are no longer actively maintained.

---

## Directory Structure

```
ARCHIVE/
├── completed/     # Successfully completed features
├── go-rewrite/    # Node.js to Go backend migration (complete)
└── obsolete/      # Plans that were superseded or abandoned
```

---

## Completed Features (`completed/`)

Documentation for features that were successfully implemented and deployed.

| Document | Feature | Completed |
|----------|---------|-----------|
| `CHANNEL_FADE_BEHAVIOR_PLAN.md` | DMX channel fade/snap behavior control | 2025-12-10 |
| `MOBILE_SCENE_BOARD_PLAN.md` | Pixel-based scene board with zoom/pan | 2025-11-22 |
| `MOBILE_SCENE_BOARD_TODO.md` | Task checklist for scene board implementation | 2025-11-22 |
| `CONTRACT_TESTING_PLAN.md` | GraphQL contract testing infrastructure | 2025-10-31 |
| `CONTRACT_TESTING_PROGRESS.md` | Contract testing implementation progress | 2025-10-31 |
| `WIFI_CONFIGURATION_DESIGN.md` | Initial WiFi network configuration | 2025-10-26 |
| `WIFI_IMPLEMENTATION_SUMMARY.md` | WiFi feature implementation summary | 2025-10-26 |
| `WIFI_AVAILABILITY_CHECK.md` | WiFi availability detection | 2025-10-26 |

---

## Go Backend Rewrite (`go-rewrite/`)

Complete documentation of the migration from lacylights-node (Node.js/Prisma) to lacylights-go (Go/GORM). This migration was completed in November 2025.

| Document | Description |
|----------|-------------|
| `LACYLIGHTS_GO_REWRITE_PLAN.md` | Comprehensive rewrite plan with all phases |
| `LACYLIGHTS_GO_REWRITE_PROGRESS.md` | Phase-by-phase progress tracking |
| `MIGRATION_PLAYBOOK.md` | Step-by-step migration procedures |
| `MIGRATION_README.md` | Migration overview and instructions |
| `MIGRATION_STATUS.txt` | Final migration status |
| `SCHEMA_COMPARISON_MATRIX.md` | Prisma vs GORM schema comparison |
| `SCHEMA_COMPATIBILITY_REPORT.md` | API compatibility analysis |

**Key Outcomes:**
- All 79 GraphQL resolvers implemented
- 24/24 contract tests passing
- Full API compatibility maintained
- lacylights-node is now deprecated

---

## Obsolete Documentation (`obsolete/`)

Plans that were superseded by other work or are no longer relevant.

| Document | Reason for Obsolescence |
|----------|------------------------|
| `MCP_API_REFACTOR_PLAN.md` | Was for lacylights-node; superseded by Go rewrite |
| `MCP_API_REFACTOR_STATUS.md` | Was for lacylights-node; superseded by Go rewrite |
| `MCP_API_REFACTOR_AGENT_GUIDE.md` | Was for lacylights-node; superseded by Go rewrite |
| `LACYLIGHTS_RPI_REPO_PROPOSAL.md` | Proposal complete; lacylights-rpi repo now exists |

---

## Notes

- These documents may contain outdated information
- Reference active docs in `docs/` for current plans
- See `docs/STATUS.md` for current project status
