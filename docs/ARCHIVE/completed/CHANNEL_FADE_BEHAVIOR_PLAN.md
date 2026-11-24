# Channel Fade Behavior Implementation Plan

**Project:** LacyLights Channel Fade Behavior Control
**Status:** Phases 1-4 Complete
**Last Updated:** 2025-12-10
**Branch Name:** `feature/channel-fade-behavior` (all repos)

---

## Overview

This feature enables control over how individual DMX channels behave during scene transitions. Some channels (like intensity, colors, zoom) should fade smoothly, while others (like gobos, color wheels, macros) should snap instantly to avoid unwanted intermediate states.

### FadeBehavior Enum Values

| Value | Description | Use Case |
|-------|-------------|----------|
| `FADE` | Interpolate smoothly between values | Intensity, RGB colors, zoom, focus |
| `SNAP` | Jump to target value at START of transition | Gobos, color wheels, macros, effects |
| `SNAP_END` | Jump to target value at END of transition | Special effects needing old look until fade completes |

### New Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `fadeBehavior` | FadeBehavior | FADE | How the channel transitions between scenes |
| `isDiscrete` | Boolean | false | True if channel has multiple distinct DMX ranges (e.g., gobo wheel positions) |

---

## Repository Information

| Repository | Purpose | Branch |
|------------|---------|--------|
| lacylights-go | Go backend (GraphQL API, database) | `feature/channel-fade-behavior` |
| lacylights-fe | React frontend (UI, fade engine) | `feature/channel-fade-behavior` |
| lacylights-mcp | MCP server (AI integration types) | `feature/channel-fade-behavior` |

**Note:** `lacylights-node` is DEPRECATED. All backend work is on `lacylights-go`.

---

## Phase Summary

| Phase | Description | Status | Commits |
|-------|-------------|--------|---------|
| Phase 1 | Schema/type changes only (safe defaults) | ✅ COMPLETE | See below |
| Phase 2 | Backend fade engine implementation | ✅ COMPLETE | `a071266` |
| Phase 3 | OFL import auto-detection | ✅ COMPLETE | `72e6f54` |
| Phase 4 | UI for editing fadeBehavior per channel | ✅ COMPLETE | `31c588c` (go), `eeefc8a` (fe) |

---

## PHASE 1: Schema & Type Changes ✅ COMPLETE

**Objective:** Add FadeBehavior enum and new fields to all type definitions with safe defaults. No behavior changes.

### 1.1 lacylights-go (Backend) ✅

**Commit:** `20f90fd`
**Status:** Complete, pushed to origin

**Files Changed:**
- `internal/graphql/schema/schema.graphql` - Added FadeBehavior enum, updated types
- `internal/database/models/models.go` - Added fields with GORM defaults
- `internal/graphql/resolvers/schema.resolvers.go` - Implemented resolvers
- `internal/graphql/resolvers/helpers.go` - Added stringToPointer helper

**Tasks:**
- [x] Add FadeBehavior enum to GraphQL schema
- [x] Add fadeBehavior field to ChannelDefinition type
- [x] Add isDiscrete field to ChannelDefinition type
- [x] Add fadeBehavior field to InstanceChannel type
- [x] Add isDiscrete field to InstanceChannel type
- [x] Add optional fields to CreateChannelDefinitionInput
- [x] Update database models with GORM defaults
- [x] Implement resolvers for new fields
- [x] Run `make generate` to regenerate gqlgen code
- [x] Run `make lint` - all checks pass
- [x] Run `make test` - all tests pass
- [x] Commit and push changes

### 1.2 lacylights-fe (Frontend) ✅

**Commit:** `304c7ca`
**Status:** Complete, pushed to origin

**Files Changed:**
- `src/types/index.ts` - Added FadeBehavior enum, updated interfaces
- `src/graphql/fixtures.ts` - Updated all queries with new fields
- Multiple test files updated with new required fields

**Tasks:**
- [x] Add FadeBehavior enum to types/index.ts
- [x] Add fadeBehavior field to ChannelDefinition interface
- [x] Add isDiscrete field to ChannelDefinition interface
- [x] Add fadeBehavior field to InstanceChannel interface
- [x] Add isDiscrete field to InstanceChannel interface
- [x] Update GraphQL queries (IMPORT_OFL_FIXTURE, GET_PROJECT_FIXTURES, etc.)
- [x] Update all test mocks with new required fields
- [x] Run `npm run lint` - all checks pass
- [x] Run `npm test` - all tests pass
- [x] Commit and push changes

### 1.3 lacylights-mcp (MCP Server) ✅

**Commit:** `6677988`
**Status:** Complete, pushed to origin

**Files Changed:**
- `src/types/lighting.ts` - Added FadeBehavior enum, updated interfaces
- `src/generated/graphql.ts` - Updated generated types

**Tasks:**
- [x] Add FadeBehavior enum to types/lighting.ts
- [x] Add fadeBehavior/isDiscrete to ChannelDefinition interface
- [x] Add fadeBehavior/isDiscrete to InstanceChannel interface
- [x] Update generated/graphql.ts with new types
- [x] Run `npm run lint` - all checks pass
- [x] Run `npm run build` - builds successfully
- [x] Commit and push changes

**Note:** MCP tests have a pre-existing Jest environment issue unrelated to these changes.

---

## PHASE 2: Backend Fade Engine Implementation ✅ COMPLETE

**Objective:** Implement the actual fade behavior logic in the lacylights-go backend fade engine.

**Commit:** `a071266`
**Status:** Complete, pushed to origin

**Key Finding:** The fade interpolation happens on the **backend**, not the frontend. The frontend only visualizes fade progress. The Go backend calculates interpolated DMX values and sends them to Art-Net.

**Files Changed:**
- `internal/services/fade/engine.go` - Added FadeBehavior constants, updated structs, modified processFades()
- `internal/services/fade/engine_test.go` - Added 6 comprehensive fade behavior tests
- `internal/services/playback/service.go` - Load fixture channels, pass fadeBehavior to fade engine

### 2.1 Identify Fade Engine Location ✅

**Finding:** The fade engine is in `lacylights-go`. Key files:
- `internal/services/fade/engine.go` - Core fade/interpolation logic
- `internal/services/playback/service.go` - Cue execution, builds scene channels

The frontend (`lacylights-fe`) only:
- Receives `fadeProgress` (0-100) via GraphQL subscription
- Visualizes fade with `FadeProgressChart` component
- Uses `easing.ts` for UI animation only

### 2.2 Find Backend Interpolation Code ✅

- [x] Locate interpolation logic in lacylights-go (`internal/services/fade/engine.go:processFades()`)
- [x] Understand how scene values are faded between cues
- [x] Document the playback engine flow

### 2.3 Implement Channel-Level Fade Behavior ✅

- [x] Modify interpolation function to check channel's fadeBehavior
- [x] For FADE channels: Use existing smooth interpolation (unchanged)
- [x] For SNAP channels: Return target value immediately when progress > 0
- [x] For SNAP_END channels: Return source value until progress = 1.0

### 2.4 Update Playback Engine ✅

- [x] Pass fadeBehavior from channel definitions to interpolation
- [x] Ensure each channel is interpolated according to its behavior
- [x] Handle mixed behaviors within same scene
- [x] Preload fixture Channels in ExecuteCueDmx for behavior lookup

### 2.5 Create Unit Tests (Go) ✅

- [x] Test FADE behavior (smooth interpolation) - `TestFadeBehavior_FADE`
- [x] Test SNAP behavior (immediate at start) - `TestFadeBehavior_SNAP`
- [x] Test SNAP_END behavior (immediate at end) - `TestFadeBehavior_SNAP_END`
- [x] Test mixed channels in same scene - `TestFadeBehavior_Mixed`
- [x] Test default behavior - `TestFadeBehavior_Default`
- [x] Test FadeToScene with behavior - `TestFadeToScene_WithBehavior`

### 2.6 Manual Testing ⏳

- [ ] Test with actual DMX fixtures
- [ ] Verify gobo channels snap correctly
- [ ] Verify color channels fade smoothly
- [ ] Test cue list playback with mixed behaviors

### 2.7 Commit and Push ✅

- [x] Run `make lint` - all checks pass
- [x] Run `make test` - all tests pass
- [x] Commit with descriptive message
- [x] Push to feature branch

---

## PHASE 3: OFL Import Auto-Detection ✅ COMPLETE

**Objective:** Automatically set fadeBehavior based on channel type when importing from Open Fixture Library.

**Commit:** `72e6f54`
**Status:** Complete, pushed to origin

**Files Created:**
- `internal/services/ofl/types.go` - OFL JSON structure types
- `internal/services/ofl/service.go` - OFL import service with auto-detection
- `internal/services/ofl/service_test.go` - Comprehensive test suite (13 tests)

**Files Modified:**
- `internal/graphql/resolvers/resolver.go` - Added OFLService
- `internal/graphql/resolvers/schema.resolvers.go` - Implemented ImportOFLFixture resolver

### 3.1 Channel Type Mappings ✅

**SNAP Channels (instant change):**
- `GOBO` - Gobo wheel positions
- `COLOR_WHEEL` - Color wheel positions
- `MACRO` - Program/macro selection
- `STROBE` - Strobe effects (often has distinct modes)

**FADE Channels (smooth interpolation):**
- `INTENSITY`, `RED`, `GREEN`, `BLUE`, `WHITE`, `AMBER`, `UV`
- `PAN`, `TILT`, `ZOOM`, `FOCUS`, `IRIS`
- `EFFECT`, `OTHER`

### 3.2 OFL Capability Type Mappings ✅

| OFL Type | Color | LacyLights Type |
|----------|-------|-----------------|
| Intensity | - | INTENSITY |
| ColorIntensity | red | RED |
| ColorIntensity | green | GREEN |
| ColorIntensity | blue | BLUE |
| ColorIntensity | white | WHITE |
| ColorIntensity | amber | AMBER |
| ColorIntensity | uv | UV |
| Pan | - | PAN |
| Tilt | - | TILT |
| Zoom | - | ZOOM |
| Focus | - | FOCUS |
| Iris | - | IRIS |
| Gobo | - | GOBO |
| WheelSlot | - | GOBO |
| ColorWheel | - | COLOR_WHEEL |
| ColorPreset | - | COLOR_WHEEL |
| ShutterStrobe | - | STROBE |
| Maintenance | - | MACRO |
| Effect/Speed/Rotation | - | EFFECT |
| * (anything else) | - | OTHER |

### 3.3 IsDiscrete Auto-Detection ✅

Channels with multiple `capabilities[]` (vs single `capability`) are automatically marked as discrete.

### 3.4 Tasks ✅

- [x] Create OFL types (`internal/services/ofl/types.go`)
- [x] Port OFL import from Node.js to Go (`internal/services/ofl/service.go`)
- [x] Implement channel type mapping from OFL capabilities
- [x] Add fadeBehavior auto-detection based on channel type
- [x] Add isDiscrete auto-detection based on capabilities count
- [x] Handle fine channel aliases (inherit parent type/behavior)
- [x] Handle switched channels (split on " / ")
- [x] Integrate with ImportOFLFixture resolver
- [x] Create comprehensive test suite (13 tests)
- [x] Run `make lint` - all checks pass
- [x] Run `make test` - all tests pass
- [x] Commit and push changes

### 3.5 Database Migration

**Note:** GORM AutoMigrate handles schema changes automatically on server start. No custom migration needed. New columns get default values (FadeBehavior=FADE, IsDiscrete=false) for existing data.

---

## PHASE 4: UI for Editing fadeBehavior ✅ COMPLETE

**Objective:** Allow users to manually override fadeBehavior per channel.

**Backend Commit:** `31c588c`
**Frontend Commit:** `eeefc8a`
**Status:** Complete, pushed to origin

### 4.1 Backend Mutations (lacylights-go) ✅

**Files Modified:**
- `internal/graphql/schema/schema.graphql` - Added mutations and input types
- `internal/graphql/resolvers/schema.resolvers.go` - Implemented resolvers
- `internal/graphql/generated/*` - Auto-generated code

**New GraphQL Mutations:**
```graphql
updateInstanceChannelFadeBehavior(channelId: ID!, fadeBehavior: FadeBehavior!): InstanceChannel!
bulkUpdateInstanceChannelsFadeBehavior(updates: [ChannelFadeBehaviorInput!]!): [InstanceChannel!]!

input ChannelFadeBehaviorInput {
  channelId: ID!
  fadeBehavior: FadeBehavior!
}
```

### 4.2 Frontend Components (lacylights-fe) ✅

**Files Created:**
- `src/components/FadeBehaviorBadge.tsx` - Visual indicator component
- `src/components/FadeBehaviorEditModal.tsx` - Modal for editing channel fade behavior
- `src/components/__tests__/FadeBehaviorBadge.test.tsx` - 18 tests
- `src/components/__tests__/FadeBehaviorEditModal.test.tsx` - 20 tests

**Files Modified:**
- `src/components/ChannelSlider.tsx` - Added optional fade behavior badge
- `src/graphql/fixtures.ts` - Added mutation definitions
- `src/types/index.ts` - Added ChannelFadeBehaviorInput type

### 4.3 Component Features ✅

**FadeBehaviorBadge:**
- Visual indicator for FADE (~), SNAP (⚡), SNAP_END (⏹)
- Color-coded: green (FADE), amber (SNAP), purple (SNAP_END)
- Shows discrete channel indicator
- Clickable to open edit modal
- Two sizes: sm, md

**FadeBehaviorEditModal:**
- Radio button selection for fade behavior
- Descriptions for each option
- Warning message for discrete channels
- Disabled save until change is made
- Loading state support

**ChannelSlider Enhancement:**
- New `showFadeBehavior` prop to display badge
- New `onFadeBehaviorClick` callback for opening edit modal
- Extended `SliderChannel` interface with `fadeBehavior` and `isDiscrete`

### 4.4 Tasks ✅

- [x] Add `updateInstanceChannelFadeBehavior` mutation to backend
- [x] Add `bulkUpdateInstanceChannelsFadeBehavior` mutation to backend
- [x] Add `ChannelFadeBehaviorInput` type to schema
- [x] Implement resolvers with transaction support
- [x] Create FadeBehaviorBadge component
- [x] Create FadeBehaviorEditModal component
- [x] Update ChannelSlider with optional badge
- [x] Add GraphQL mutations to frontend
- [x] Add comprehensive test suite (38 tests)
- [x] Run linting and type checks - all pass
- [x] Run tests - all 1246 tests pass
- [x] Commit and push changes

---

## Orchestration Strategy

When continuing this work across sessions, use this orchestration approach:

### For Multi-Repository Changes

1. **Create orchestrator agent** to coordinate changes
2. **Spawn sub-agents** for each repository:
   - Agent 1: lacylights-go (backend changes)
   - Agent 2: lacylights-fe (frontend changes)
   - Agent 3: lacylights-mcp (type updates)
3. **Synchronize** - Ensure backend changes complete before frontend

### For Single-Repository Phases

1. **Read this document first** to understand current status
2. **Check git branch** - Should be `feature/channel-fade-behavior`
3. **Resume from last completed task**
4. **Update this document** after completing tasks

### Command to Check Status

```bash
# Check status across all repos
for repo in lacylights-go lacylights-fe lacylights-mcp; do
  echo "=== $repo ==="
  cd ~/src/lacylights/$repo
  git branch --show-current
  git log -1 --oneline
  cd ..
done
```

---

## Technical Notes

### Default Values

- `fadeBehavior` defaults to `FADE` for backward compatibility
- `isDiscrete` defaults to `false`
- Existing fixtures/channels will use defaults until updated

### Database Schema (lacylights-go)

```go
// ChannelDefinition
FadeBehavior string `gorm:"column:fade_behavior;default:FADE"`
IsDiscrete   bool   `gorm:"column:is_discrete;default:false"`

// InstanceChannel
FadeBehavior string `gorm:"column:fade_behavior;default:FADE"`
IsDiscrete   bool   `gorm:"column:is_discrete;default:false"`
```

### GraphQL Schema

```graphql
enum FadeBehavior {
  FADE
  SNAP
  SNAP_END
}

type ChannelDefinition {
  # ... existing fields ...
  fadeBehavior: FadeBehavior!
  isDiscrete: Boolean!
}

type InstanceChannel {
  # ... existing fields ...
  fadeBehavior: FadeBehavior!
  isDiscrete: Boolean!
}
```

---

## References

- Branch: `feature/channel-fade-behavior` (all repos)
- Related: Raspberry Pi Product Plan (`RASPBERRY_PI_PRODUCT_PLAN.md`)
- Related: Mobile Scene Board (`MOBILE_SCENE_BOARD_PLAN.md`)

---

## Change Log

| Date | Phase | Action | Details |
|------|-------|--------|---------|
| 2025-12-10 | 1 | Complete | Schema/types added to all repos |
| 2025-12-10 | 2 | Complete | Fade engine in lacylights-go updated to respect fadeBehavior |
| 2025-12-10 | 3 | Complete | OFL import ported from Node.js to Go with FadeBehavior auto-detection |
