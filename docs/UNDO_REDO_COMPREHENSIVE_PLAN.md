# Comprehensive Undo/Redo Implementation Plan

## Overview

This plan extends the existing undo/redo system to cover all relevant project data mutations. The foundation is already in place (FixtureInstance, Look, CuePlayback). This plan adds coverage for Cues, CueLists, LookBoards, Effects, and bulk operations.

**Trigger**: When ready to implement, say "implement history" or "implement undo/redo".

---

## Current State (Already Implemented)

| Entity | Operations | Status |
|--------|-----------|--------|
| FixtureInstance | CREATE, UPDATE, DELETE | ✅ Complete |
| Look | CREATE, UPDATE, DELETE | ✅ Complete |
| CuePlayback | start, next, previous, goTo, stop | ✅ Complete |

**Infrastructure in place:**
- `Operation` and `OperationPointer` database models
- `OperationRepository` with all CRUD methods
- `UndoService` with `RecordOperation`, `Undo`, `Redo`, `JumpToOperation`
- GraphQL schema types and mutations
- Frontend `UndoRedoContext`, `UndoRedoToolbar`, `OperationHistoryPanel`
- MCP tools for undo/redo
- PubSub subscription for real-time updates

---

## Phase 1: Cue Operations (High Priority)

Cues are the most frequently modified entities after looks.

### 1.1 Add State Capture Methods

**File:** `internal/services/undo/service.go`

Add methods:
```go
// CaptureCueState captures the current state of a cue for undo/redo.
func (s *Service) CaptureCueState(ctx context.Context, cueID string) (interface{}, error)

// CaptureCueListState captures the current state of a cue list for undo/redo.
func (s *Service) CaptureCueListState(ctx context.Context, cueListID string) (interface{}, error)

// applyCueSnapshot restores a cue from a snapshot.
func (s *Service) applyCueSnapshot(ctx context.Context, snapshotJSON string, isCreate bool) (string, error)

// applyCueListSnapshot restores a cue list from a snapshot.
func (s *Service) applyCueListSnapshot(ctx context.Context, snapshotJSON string, isCreate bool) (string, error)
```

Update `applySnapshot` switch statement to handle `EntityTypeCue` and `EntityTypeCueList`.

### 1.2 Integrate with Cue Mutations

**File:** `internal/graphql/resolvers/schema.resolvers.go`

Wrap these mutations with state capture:

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `createCue` | CREATE | "Create cue '{name}' (#{cueNumber})" |
| `updateCue` | UPDATE | "Update cue '{name}'" |
| `deleteCue` | DELETE | "Delete cue '{name}'" |
| `toggleCueSkip` | UPDATE | "Toggle skip for cue '{name}'" |
| `reorderCues` | UPDATE | "Reorder cues in '{cueListName}'" |

**Pattern for each mutation:**
```go
func (r *mutationResolver) CreateCue(ctx context.Context, input generated.CreateCueInput) (*models.Cue, error) {
    // 1. Perform the actual creation
    cue, err := r.CueRepo.Create(ctx, ...)
    if err != nil {
        return nil, err
    }

    // 2. Get cue list for project ID
    cueList, _ := r.CueListRepo.FindByID(ctx, input.CueListID)

    // 3. Record operation
    if newState, err := r.UndoService.CaptureCueState(ctx, cue.ID); err == nil {
        _ = r.UndoService.RecordOperation(ctx, cueList.ProjectID, "CREATE", "Cue", cue.ID,
            fmt.Sprintf("Create cue '%s' (#%.1f)", cue.Name, cue.CueNumber), nil, newState, nil)
        r.publishOperationHistoryChanged(ctx, cueList.ProjectID)
    }

    return cue, nil
}
```

### 1.3 Integrate with CueList Mutations

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `createCueList` | CREATE | "Create cue list '{name}'" |
| `updateCueList` | UPDATE | "Update cue list '{name}'" |
| `deleteCueList` | DELETE | "Delete cue list '{name}'" |

### 1.4 Add resumeCueList to Playback

**File:** `internal/graphql/resolvers/schema.resolvers.go`

The `resumeCueList` mutation should also record a CuePlayback operation.

### 1.5 Verification

```bash
# Run tests
cd lacylights-go && make test

# Manual verification
# 1. Create a cue, verify it appears in operation history
# 2. Undo, verify cue is deleted
# 3. Redo, verify cue is recreated
# 4. Update cue, undo, verify original values restored
```

---

## Phase 2: LookBoard Operations (Medium Priority)

### 2.1 Add State Capture Methods

**File:** `internal/services/undo/service.go`

Add methods:
```go
func (s *Service) CaptureLookBoardState(ctx context.Context, lookBoardID string) (interface{}, error)
func (s *Service) CaptureLookBoardButtonState(ctx context.Context, buttonID string) (interface{}, error)
func (s *Service) applyLookBoardSnapshot(ctx context.Context, snapshotJSON string, isCreate bool) (string, error)
func (s *Service) applyLookBoardButtonSnapshot(ctx context.Context, snapshotJSON string, isCreate bool) (string, error)
```

### 2.2 Integrate with LookBoard Mutations

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `createLookBoard` | CREATE | "Create look board '{name}'" |
| `updateLookBoard` | UPDATE | "Update look board '{name}'" |
| `deleteLookBoard` | DELETE | "Delete look board '{name}'" |

### 2.3 Integrate with LookBoardButton Mutations

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `addLookToBoard` | CREATE | "Add '{lookName}' to board '{boardName}'" |
| `updateLookBoardButton` | UPDATE | "Update button for '{lookName}'" |
| `removeLookFromBoard` | DELETE | "Remove '{lookName}' from board" |
| `updateLookBoardButtonPositions` | UPDATE | "Reposition buttons on '{boardName}'" |

---

## Phase 3: Effect Operations (Medium Priority)

### 3.1 Add State Capture Methods

**File:** `internal/services/undo/service.go`

Add methods for Effect, EffectFixture, EffectChannel, CueEffect entities.

### 3.2 Integrate with Effect Mutations

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `createEffect` | CREATE | "Create effect '{name}'" |
| `updateEffect` | UPDATE | "Update effect '{name}'" |
| `deleteEffect` | DELETE | "Delete effect '{name}'" |
| `addFixtureToEffect` | CREATE | "Add fixture to effect '{name}'" |
| `removeFixtureFromEffect` | DELETE | "Remove fixture from effect" |
| `updateEffectFixture` | UPDATE | "Update fixture settings in effect" |
| `addChannelToEffectFixture` | CREATE | "Add channel to effect fixture" |
| `updateEffectChannel` | UPDATE | "Update effect channel" |
| `removeChannelFromEffectFixture` | DELETE | "Remove channel from effect" |
| `addEffectToCue` | CREATE | "Add effect to cue '{cueName}'" |
| `removeEffectFromCue` | DELETE | "Remove effect from cue" |

---

## Phase 4: Additional Look & Fixture Operations

### 4.1 Safe Look Update Mutations

These mutations already modify looks but bypass the main `updateLook`:

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `addFixturesToLook` | UPDATE | "Add fixtures to look '{name}'" |
| `removeFixturesFromLook` | UPDATE | "Remove fixtures from look '{name}'" |
| `updateLookPartial` | UPDATE | "Update look '{name}'" |
| `duplicateLook` | CREATE | "Duplicate look '{originalName}' as '{newName}'" |
| `cloneLook` | CREATE | "Clone look '{originalName}' as '{newName}'" |

### 4.2 Fixture Ordering & Layout Mutations

| Mutation | Operation Type | Description Pattern |
|----------|---------------|---------------------|
| `reorderProjectFixtures` | UPDATE | "Reorder fixtures in project" |
| `reorderLookFixtures` | UPDATE | "Reorder fixtures in look '{name}'" |
| `updateFixturePositions` | UPDATE | "Update fixture positions" |
| `updateInstanceChannelFadeBehavior` | UPDATE | "Update channel fade behavior" |
| `bulkUpdateInstanceChannelsFadeBehavior` | BULK | "Update channel fade behaviors" |

---

## Phase 5: Bulk Operations

Bulk operations should record a single operation with `relatedIds` containing all affected entity IDs.

### 5.1 Bulk State Capture Pattern

```go
func (r *mutationResolver) BulkCreateFixtures(ctx context.Context, input generated.BulkFixtureCreateInput) ([]*models.FixtureInstance, error) {
    fixtures, err := r.performBulkCreate(ctx, input)
    if err != nil {
        return nil, err
    }

    // Collect all created IDs
    var createdIDs []string
    for _, f := range fixtures {
        createdIDs = append(createdIDs, f.ID)
    }

    // Capture bulk state (array of snapshots)
    bulkState := make([]interface{}, len(fixtures))
    for i, f := range fixtures {
        bulkState[i], _ = r.UndoService.CaptureFixtureState(ctx, f.ID)
    }

    // Record single BULK operation
    _ = r.UndoService.RecordOperation(ctx, projectID, "BULK", "FixtureInstance", createdIDs[0],
        fmt.Sprintf("Create %d fixtures", len(fixtures)), nil, bulkState, createdIDs)

    return fixtures, nil
}
```

### 5.2 Bulk Operations to Implement

| Entity | Bulk Mutations |
|--------|----------------|
| FixtureInstance | bulkCreateFixtures, bulkUpdateFixtures, bulkDeleteFixtures |
| Look | bulkCreateLooks, bulkUpdateLooks, bulkDeleteLooks, bulkUpdateLooksPartial, **copyFixturesToLooks** |
| Cue | bulkCreateCues, bulkUpdateCues, bulkDeleteCues |
| CueList | bulkCreateCueLists, bulkUpdateCueLists, bulkDeleteCueLists |
| LookBoard | bulkCreateLookBoards, bulkUpdateLookBoards, bulkDeleteLookBoards |
| LookBoardButton | bulkCreateLookBoardButtons, bulkUpdateLookBoardButtons, bulkDeleteLookBoardButtons |

### 5.2.1 Special Case: copyFixturesToLooks

The `copyFixturesToLooks` mutation copies fixture channel values from one source look to multiple target looks. This is an atomic operation - one "Undo" reverses all changes.

**Mutation signature** (from `docs/COPY_FIXTURES_TO_LOOKS_PLAN.md`):
```graphql
copyFixturesToLooks(input: CopyFixturesToLooksInput!): CopyFixturesToLooksResult!

input CopyFixturesToLooksInput {
  sourceLookId: ID!
  fixtureIds: [ID!]!
  targetLookIds: [ID!]!
}
```

**Undo implementation pattern:**
```go
func (r *mutationResolver) CopyFixturesToLooks(ctx context.Context, input generated.CopyFixturesToLooksInput) (*generated.CopyFixturesToLooksResult, error) {
    // 1. Capture BEFORE state of all target looks (for undo)
    previousStates := make([]interface{}, len(input.TargetLookIds))
    for i, lookID := range input.TargetLookIds {
        previousStates[i], _ = r.UndoService.CaptureLookState(ctx, lookID)
    }

    // 2. Perform the copy operation (in a transaction)
    updatedLooks, err := r.performCopyFixturesToLooks(ctx, input)
    if err != nil {
        return nil, err
    }

    // 3. Capture AFTER state of all target looks (for redo)
    newStates := make([]interface{}, len(updatedLooks))
    for i, look := range updatedLooks {
        newStates[i], _ = r.UndoService.CaptureLookState(ctx, look.ID)
    }

    // 4. Record as single BULK operation
    //    - relatedIds contains ALL target look IDs
    //    - previousState is array of look snapshots (for undo)
    //    - newState is array of look snapshots (for redo)
    _ = r.UndoService.RecordOperation(ctx, projectID, "BULK", "Look", input.TargetLookIds[0],
        fmt.Sprintf("Copy fixtures from '%s' to %d looks", sourceLookName, len(input.TargetLookIds)),
        previousStates, newStates, input.TargetLookIds)

    // 5. Publish updates for each modified look (for real-time UI updates)
    for _, look := range updatedLooks {
        r.pubsub.Publish("lookUpdated", look)
    }

    return &generated.CopyFixturesToLooksResult{
        UpdatedLookCount: len(updatedLooks),
        AffectedCueCount: affectedCueCount,
        UpdatedLooks:     updatedLooks,
        OperationID:      operationID,
    }, nil
}
```

**Key requirements:**
- Captures state of ALL target looks BEFORE the copy
- Single operation record with `relatedIds` containing all target look IDs
- Undo restores ALL target looks to their previous state in one action
- PubSub publishes `lookUpdated` for each modified look (real-time UI sync)

### 5.3 Bulk Undo/Redo Logic

Update `applySnapshot` to handle bulk operations:
- For BULK CREATE undo: delete all entities in `relatedIds`
- For BULK UPDATE undo: restore all entities from `previousState` array
- For BULK DELETE undo: recreate all entities from `previousState` array

---

## Phase 6: Testing

### 6.1 Unit Tests

**File:** `internal/services/undo/service_test.go`

Add test cases:
- `TestCaptureCueState`
- `TestCaptureCueListState`
- `TestCaptureLookBoardState`
- `TestCaptureEffectState`
- `TestApplyCueSnapshot`
- `TestApplyBulkSnapshot`
- `TestUndoRedoCue`
- `TestUndoRedoBulkOperation`

### 6.2 Integration Tests

**File:** `lacylights-test/contracts/undo/comprehensive_test.go`

Add test cases:
- `TestUndoRedo_CueCreate`
- `TestUndoRedo_CueListCreate`
- `TestUndoRedo_LookBoardCreate`
- `TestUndoRedo_EffectCreate`
- `TestUndoRedo_BulkFixtureCreate`
- `TestUndoRedo_BulkLookUpdate`
- `TestUndoRedo_CopyFixturesToLooks` (copy fixtures from one look to multiple, undo restores ALL target looks)
- `TestUndoRedo_ComplexWorkflow` (create project, add fixtures, create looks, create cues, undo multiple times)

---

## Implementation Checklist

### Phase 1: Cue Operations
- [ ] Add `CaptureCueState` method
- [ ] Add `CaptureCueListState` method
- [ ] Add `applyCueSnapshot` method
- [ ] Add `applyCueListSnapshot` method
- [ ] Update `applySnapshot` switch for Cue/CueList
- [ ] Wrap `createCue` mutation
- [ ] Wrap `updateCue` mutation
- [ ] Wrap `deleteCue` mutation
- [ ] Wrap `toggleCueSkip` mutation
- [ ] Wrap `reorderCues` mutation
- [ ] Wrap `createCueList` mutation
- [ ] Wrap `updateCueList` mutation
- [ ] Wrap `deleteCueList` mutation
- [ ] Add recording to `resumeCueList`
- [ ] Run tests, verify all pass
- [ ] Manual test: create/undo/redo cue

### Phase 2: LookBoard Operations
- [ ] Add `CaptureLookBoardState` method
- [ ] Add `CaptureLookBoardButtonState` method
- [ ] Add apply snapshot methods
- [ ] Wrap all LookBoard mutations
- [ ] Wrap all LookBoardButton mutations
- [ ] Run tests, verify all pass

### Phase 3: Effect Operations
- [ ] Add capture methods for Effect, EffectFixture, EffectChannel, CueEffect
- [ ] Add apply snapshot methods
- [ ] Wrap all Effect mutations
- [ ] Wrap all EffectFixture mutations
- [ ] Wrap all EffectChannel mutations
- [ ] Wrap all CueEffect mutations
- [ ] Run tests, verify all pass

### Phase 4: Additional Operations
- [ ] Wrap `addFixturesToLook`
- [ ] Wrap `removeFixturesFromLook`
- [ ] Wrap `updateLookPartial`
- [ ] Wrap `duplicateLook`
- [ ] Wrap `cloneLook`
- [ ] Wrap fixture ordering mutations
- [ ] Wrap fixture layout mutations
- [ ] Wrap channel fade behavior mutations
- [ ] Run tests, verify all pass

### Phase 5: Bulk Operations
- [ ] Implement bulk state capture pattern
- [ ] Update `applySnapshot` for BULK type
- [ ] Wrap all FixtureInstance bulk mutations
- [ ] Wrap all Look bulk mutations
- [ ] Wrap all Cue bulk mutations
- [ ] Wrap all CueList bulk mutations
- [ ] Wrap all LookBoard bulk mutations
- [ ] Wrap all LookBoardButton bulk mutations
- [ ] Implement `copyFixturesToLooks` mutation with atomic undo (see Section 5.2.1)
- [ ] Run tests, verify all pass

### Phase 6: Testing & Documentation
- [ ] Add unit tests for new capture methods
- [ ] Add unit tests for new apply methods
- [ ] Add integration tests for each entity type
- [ ] Add integration test for complex workflow
- [ ] Update CLAUDE.md with coverage notes
- [ ] Run full test suite across all repos

---

## Files to Modify

| Repository | File | Changes |
|------------|------|---------|
| lacylights-go | `internal/services/undo/service.go` | Add capture/apply methods for each entity |
| lacylights-go | `internal/graphql/resolvers/schema.resolvers.go` | Wrap all mutations with undo recording |
| lacylights-go | `internal/services/undo/service_test.go` | Add unit tests |
| lacylights-test | `contracts/undo/comprehensive_test.go` | Add integration tests |

---

## Verification Commands

```bash
# After each phase
cd lacylights-go && make test && make lint

# Full integration test
cd lacylights-test && make test-undo

# Frontend verification (manual)
cd lacylights-fe && npm run dev
# Create entities, verify history panel shows operations
# Test undo/redo buttons and Cmd+Z/Cmd+Shift+Z

# MCP verification
# Use Claude Code to create/undo/redo via MCP tools
```

---

## Notes

- Always capture state BEFORE performing mutations for updates/deletes
- Always capture state AFTER performing mutations for creates
- Use non-blocking error handling for recording (don't fail mutations if recording fails)
- Call `publishOperationHistoryChanged` after each recording
- Get projectID from the entity or related entity (cue → cueList → project)
- Use consistent description patterns for user-friendly history display

---

## Known Issues & Technical Debt (from PR #60 Claude Review)

These critical issues were identified during the PR review and should be addressed before expanding undo/redo coverage.

### Issue 1: Transaction Atomicity in Undo/Redo Operations (CRITICAL)

**Location:** `internal/services/undo/service.go:227-235` (Undo) and similar for Redo

**Problem:** When `applySnapshot` fails during undo, the operation pointer has already been decremented in the database transaction by `opRepo.Undo()`. The code logs a warning but doesn't actually rollback the pointer change. This leaves the system in an inconsistent state where the pointer position doesn't match the actual entity state.

**Current code:**
```go
entityID, err := s.applySnapshot(ctx, EntityType(op.EntityType), op.PreviousState, ...)
if err != nil {
    // Rollback the pointer change
    // Note: In a more robust implementation, we'd want to handle this atomically
    log.Printf("Warning: failed to apply undo, attempting rollback: %v", err)
    return &UndoRedoResult{Success: false, ...}, err  // Pointer already changed!
}
```

**Impact:**
- Users may see "Undo" available but clicking it puts the system in an inconsistent state
- Subsequent undos may fail or produce unexpected results
- Database integrity is compromised

**Required Fix:** Wrap the entire undo/redo operation in a single database transaction:
1. Start transaction
2. Update pointer within transaction
3. Apply snapshot within same transaction
4. Commit only if ALL steps succeed
5. Rollback entire transaction if any step fails

**Implementation options:**
- Option A: Have repository return the operation WITHOUT modifying pointer; service updates pointer after successful apply
- Option B: Wrap the entire operation (pointer update + snapshot application) in a single transaction
- Option C: Implement a compensating transaction that restores the pointer on failure

### Issue 2: Missing Undo Recording for Many Mutations (HIGH PRIORITY)

**Problem:** The current implementation only records undo operations for:
- FixtureInstance (CREATE, UPDATE, DELETE)
- Look (CREATE, UPDATE, DELETE)
- CuePlayback (start, next, previous, goTo, stop)

**Missing coverage (these mutations modify state but cannot be undone):**

| Category | Missing Mutations |
|----------|-------------------|
| Cue | `createCue`, `updateCue`, `deleteCue`, `toggleCueSkip`, `reorderCues` |
| CueList | `createCueList`, `updateCueList`, `deleteCueList` |
| Effect | `createEffect`, `updateEffect`, `deleteEffect`, effect fixture/channel mutations |
| LookBoard | `createLookBoard`, `updateLookBoard`, `deleteLookBoard` |
| LookBoardButton | `addLookToBoard`, `updateLookBoardButton`, `removeLookFromBoard`, `updateLookBoardButtonPositions` |
| Bulk Operations | All bulk create/update/delete mutations |
| Project | `updateProject`, `deleteProject` |
| Additional Look | `addFixturesToLook`, `removeFixturesFromLook`, `updateLookPartial`, `duplicateLook`, `cloneLook` |
| Fixture Layout | `reorderProjectFixtures`, `reorderLookFixtures`, `updateFixturePositions` |
| Channel Behavior | `updateInstanceChannelFadeBehavior`, `bulkUpdateInstanceChannelsFadeBehavior` |

**Impact:** Users have inconsistent undo/redo behavior - some operations can be undone, others cannot. This creates a confusing UX.

**Required Fix:** Add `RecordOperation` calls to ALL state-modifying mutations (covered in Phases 1-5 above).

### Issue 3: Additional Issues from Review (Lower Priority)

These issues should be addressed as part of ongoing maintenance:

1. **Race condition in playback state capture** - Playback state is captured outside transactions; between capturing and recording, state could change
2. **Unbounded JSON state storage** - No size limits on snapshot JSON; large entities could create very large database rows
3. **JumpToOperation performance** - Calls Undo/Redo in a loop; large jumps could be slow
4. **Missing composite index** - Add `(project_id, sequence)` composite index for query optimization
5. **Hard-coded history limit** - 100-operation limit should be configurable via environment variable
6. **No user/session tracking** - Operations don't track which user/session created them (audit trail)
7. **CueList snapshot partial failure** - Cue recreation during undo could leave orphaned cues on partial failure

### Checklist: Pre-requisites Before Expanding Coverage

Before implementing Phases 1-5 (adding more mutations), fix these foundational issues:

- [ ] **Fix Issue 1**: Implement atomic transactions for Undo/Redo operations
- [ ] Add tests that verify Undo behavior when `applySnapshot` fails
- [ ] Add tests that verify Redo behavior when `applySnapshot` fails
- [ ] **Document limitation**: Clearly document which operations support undo/redo until full coverage is complete
- [ ] Consider adding composite index on `(project_id, sequence)`

### References

- PR #60 Claude Review: https://github.com/bbernstein/lacylights-go/pull/60
- Review comments identify these as "Must Fix Before Merge" for production readiness
