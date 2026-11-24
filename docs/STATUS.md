# LacyLights Project Status

**Last Updated:** 2026-10-14 (Import/Export follow-ups; go v0.4.1, Mac v1.3.6)

This document provides a high-level overview of active initiatives and recent completions.

---

## Active Initiatives

| Initiative | Plan Document | Status | Priority | Notes |
|------------|---------------|--------|----------|-------|
| WiFi AP Mode | [WIFI_AP_MODE_PLAN.md](WIFI_AP_MODE_PLAN.md) | Not Started | High | Enable RPi to create its own WiFi network |
| Remove MCP from RPi | [REMOVE_MCP_FROM_RPI_PLAN.md](REMOVE_MCP_FROM_RPI_PLAN.md) | Not Started | Medium | Simplify RPi deployment |

### WiFi AP Mode
**Goal:** Allow Raspberry Pi to create its own WiFi access point when no network is available, enabling initial setup and standalone operation.

**Key Tasks:**
- [ ] Backend WiFi service with nmcli integration
- [ ] GraphQL schema extensions for AP configuration
- [ ] Frontend WiFi mode indicator and controls
- [ ] SSID generation from MAC address

### Remove MCP from RPi
**Goal:** Simplify Raspberry Pi deployment by removing MCP server (AI integration not needed on private lighting networks).

**Changes Required:**
- lacylights-rpi: Remove MCP installation/update code
- lacylights-go: Make MCP optional in version service
- lacylights-fe: Handle dynamic repo list from backend

---

## Reference Documentation

| Document | Purpose |
|----------|---------|
| [RASPBERRY_PI_PRODUCT_PLAN.md](RASPBERRY_PI_PRODUCT_PLAN.md) | Main product architecture and deployment reference |

---

## Recently Completed

| Feature | Completed | Plan / Archive Location |
|---------|-----------|------------------------|
| Import/Export screen + CSV/XLSX export (fe#175) and follow-ups: OFL import fixes, MCP data-export tools, Mac `.asc` picker | 2026-10-14 | [plans/2026-10-12-import-export-followups.md](plans/2026-10-12-import-export-followups.md) — open follow-ups: go#91, fe#180, fe#179, go#88, go#87 |
| Go Distribution: versioned URLs, raw binaries, downgrade-safe | 2026-04-30 (audited) | [ARCHIVE/completed/GO_DISTRIBUTION_PLAN.md](ARCHIVE/completed/GO_DISTRIBUTION_PLAN.md) — shipped progressively in lacylights-go (commit `5ea42e4` and follow-ups); verified live with checksum match on v0.2.30 |
| Eos ASCII Import/Export (incl. Task 14c FixtureGroup) | 2026-04-30 | [plans/2026-04-28-eos-ascii-importer-exporter-implementation.md](plans/2026-04-28-eos-ascii-importer-exporter-implementation.md), [plans/2026-04-29-task-14c-fixture-groups-sidecar-implementation.md](plans/2026-04-29-task-14c-fixture-groups-sidecar-implementation.md) |
| Multi-Tenant Group Ownership (Phases 1-9) | 2026-02-18 | [plans/2026-02-09-multi-tenant-phases-7-8.md](plans/2026-02-09-multi-tenant-phases-7-8.md) |
| Scene to Look Rename | 2026-01 | [SCENE_TO_LOOK_RENAME_PLAN.md](SCENE_TO_LOOK_RENAME_PLAN.md) |
| Channel Fade Behavior | 2025-12-10 | [ARCHIVE/completed/](ARCHIVE/completed/) |
| Mobile Look Board | 2025-11-22 | [ARCHIVE/completed/](ARCHIVE/completed/) |
| Go Backend Rewrite | 2025-11-27 | [ARCHIVE/go-rewrite/](ARCHIVE/go-rewrite/) |
| Contract Testing | 2025-10-31 | [ARCHIVE/completed/](ARCHIVE/completed/) |
| Initial WiFi Config | 2025-10-26 | [ARCHIVE/completed/](ARCHIVE/completed/) |

---

## Repository Status

| Repository | Purpose | Status |
|------------|---------|--------|
| lacylights-go | Go backend (GraphQL, DMX, SQLite) | Active |
| lacylights-fe | Next.js frontend | Active |
| lacylights-mcp | MCP server for AI integration | Active |
| lacylights-rpi | Raspberry Pi deployment | Active |
| lacylights-mac | macOS application | Active |
| lacylights-terraform | AWS distribution infrastructure | Active |
| lacylights-test | Integration/contract tests | Active |
| ~~lacylights-node~~ | ~~Node.js backend~~ | Deprecated |

---

## How to Use This Document

1. **Starting new work:** Check "Active Initiatives" for current priorities
2. **Understanding history:** Check "Recently Completed" and browse [ARCHIVE/](ARCHIVE/)
3. **Finding plans:** Each initiative links to its detailed plan document
4. **Updating status:** Update this file when initiatives start, complete, or change priority

---

## Notes

- Keep this document concise - details belong in individual plan files
- Move completed initiatives to "Recently Completed" with archive links
- Archive plan documents when work is complete (see [ARCHIVE/README.md](ARCHIVE/README.md))
