# Copy Fixtures to Other Looks - Implementation Plan

## Overview

This feature allows users to copy fixture channel settings (including enabled/disabled state) from the current look to multiple other looks. The primary use case is maintaining consistency across a series of cues in a scene while allowing other fixtures to vary.

## User Story

As a lighting designer, when I update spot fixtures in one cue's look, I want to easily propagate those changes to other cues in the same scene without manually editing each look.

## Requirements

### Functional Requirements

1. **Entry Point**: "Copy to Other Looks..." button/action in the Look Editor 2D Viewer when fixtures are selected
2. **Selection**: User selects fixtures in the 2D Viewer (existing functionality)
3. **Copy Data**: All channel values + enabled/disabled flags for selected fixtures
4. **Target Selection Dialog**:
   - Show all looks in the project with their associated cues
   - Sort by cue proximity to the source cue (if editing from cue list)
   - Center list on current cue (greyed out, not selectable)
   - Multi-select target looks via checkboxes
   - Search/filter functionality
5. **Execution**: Batch apply fixture values to selected target looks
6. **Feedback**: Toast notification with success/failure count

### Non-Functional Requirements

- Simple UX for common use cases
- MCP server support for AI-driven workflows
- Undo support via existing undo/redo system
- Unit, integration, and E2E tests

---

## Architecture

### Data Flow

```
User selects fixtures in LookEditorLayout
           ↓
User clicks "Copy to Other Looks..."
           ↓
CopyFixturesToLooksModal opens
           ↓
Modal fetches cues with look info (cuesWithLookInfo query)
           ↓
User selects target looks
           ↓
User confirms
           ↓
Frontend calls copyFixturesToLooks mutation
           ↓
Backend captures all target look states for undo
           ↓
Backend updates each look (merging fixture values)
           ↓
Backend records single atomic undo operation
           ↓
Frontend shows success toast with affected cue count
```

---

## Implementation Plan

### Phase 1: Backend - GraphQL Schema & Resolver

**File**: `lacylights-go/internal/graphql/schema/schema.graphql`

#### 1.1 New Query: `cuesWithLookInfo`

Returns all cues in a cue list with their look information, plus orphan looks. This supports the cue-centric modal display.

```graphql
"""
A cue with its associated look information for the copy modal.
"""
type CueWithLookInfo {
  cueId: ID!
  cueNumber: Float!
  cueName: String!
  lookId: ID!
  lookName: String!
  """Other cue numbers that use the same look (excluding this cue)"""
  otherCueNumbers: [Float!]!
}

"""
Response for the cuesWithLookInfo query.
"""
type CuesWithLookInfoResponse {
  """Cues sorted by cue number"""
  cues: [CueWithLookInfo!]!
  """Looks in the project that are not used by any cue in this cue list"""
  orphanLooks: [LookSummary!]!
}

extend type Query {
  """
  Get all cues in a cue list with their look info, plus orphan looks.
  Used for the "Copy Fixtures to Other Looks" modal.
  """
  cuesWithLookInfo(cueListId: ID!): CuesWithLookInfoResponse!
}
```

#### 1.2 Implement Resolver

**File**: `lacylights-go/internal/graphql/resolvers/cue_resolver.go`

Add resolver method:
```go
func (r *queryResolver) CuesWithLookInfo(ctx context.Context, cueListId string) (*model.CuesWithLookInfoResponse, error)
```

Implementation:
1. Fetch all cues for the cue list, sorted by cue number
2. For each look, compute which other cues use the same look
3. Fetch all looks in the project
4. Compute orphan looks (looks not used by any cue in this cue list)
5. Return combined response

#### 1.3 Add Repository Method

**File**: `lacylights-go/internal/database/repositories/cue_repository.go`

```go
func (r *CueRepository) FindCuesWithLookInfoByCueListID(ctx context.Context, cueListID string) ([]CueWithLookInfo, error)
```

Uses SQL to efficiently fetch cues with look info and compute other cue numbers sharing each look.

#### 1.4 New GraphQL Mutation

**File**: `lacylights-go/internal/graphql/schema/schema.graphql`

Add a new mutation that performs the copy operation as a single atomic undo entry:

```graphql
"""
Input for copying fixtures from one look to multiple target looks.
"""
input CopyFixturesToLooksInput {
  """ID of the look to copy fixtures from"""
  sourceLookId: ID!
  """IDs of fixtures to copy"""
  fixtureIds: [ID!]!
  """IDs of looks to copy fixtures to"""
  targetLookIds: [ID!]!
}

"""
Result of the copy fixtures operation.
"""
type CopyFixturesToLooksResult {
  """Number of looks updated"""
  updatedLookCount: Int!
  """Number of cues affected (for UI feedback)"""
  affectedCueCount: Int!
  """The updated looks"""
  updatedLooks: [Look!]!
  """Operation ID for undo (single atomic operation)"""
  operationId: ID!
}

extend type Mutation {
  """
  Copy fixture values from one look to multiple target looks.
  This is an atomic operation - a single undo reverses all changes.
  """
  copyFixturesToLooks(input: CopyFixturesToLooksInput!): CopyFixturesToLooksResult!
}
```

#### 1.5 Atomic Undo Support - Undo Service Changes

**File**: `lacylights-go/internal/services/undo/service.go`

The undo service already supports bulk operations via the `BulkFixturePositionSnapshot` pattern. We'll follow the same pattern for bulk look updates:

**1.5.1 Add New Entity Type**

```go
const (
    // ... existing entity types ...
    EntityTypeBulkLookUpdate EntityType = "BulkLookUpdate"
)
```

**1.5.2 Add BulkLookUpdateSnapshot**

```go
// BulkLookUpdateSnapshot captures multiple looks' state for atomic undo.
// Used by copyFixturesToLooks to restore all target looks in a single undo operation.
type BulkLookUpdateSnapshot struct {
    Looks []LookSnapshot `json:"looks"`
}
```

**1.5.3 Add CaptureBulkLookState Helper**

```go
// CaptureBulkLookState captures the complete state of multiple looks for undo.
func (s *Service) CaptureBulkLookState(ctx context.Context, lookIDs []string) (*BulkLookUpdateSnapshot, error) {
    var looks []LookSnapshot
    for _, lookID := range lookIDs {
        snapshot, err := s.CaptureLookState(ctx, lookID)
        if err != nil {
            return nil, fmt.Errorf("failed to capture look %s: %w", lookID, err)
        }
        if snapshot != nil {
            looks = append(looks, *snapshot)
        }
    }
    return &BulkLookUpdateSnapshot{Looks: looks}, nil
}
```

**1.5.4 Add applyBulkLookUpdateSnapshot**

```go
// applyBulkLookUpdateSnapshot restores multiple looks from a snapshot.
func (s *Service) applyBulkLookUpdateSnapshot(ctx context.Context, snapshotJSON string) (string, error) {
    if snapshotJSON == "" {
        return "", nil
    }

    var snapshot BulkLookUpdateSnapshot
    if err := json.Unmarshal([]byte(snapshotJSON), &snapshot); err != nil {
        return "", fmt.Errorf("failed to unmarshal bulk look update snapshot: %w", err)
    }

    // Restore each look's state
    var restoredIDs []string
    for _, lookSnapshot := range snapshot.Looks {
        // Use existing applyLookSnapshot logic
        lookJSON, err := json.Marshal(lookSnapshot)
        if err != nil {
            return "", fmt.Errorf("failed to marshal look snapshot: %w", err)
        }
        entityID, err := s.applyLookSnapshot(ctx, string(lookJSON), OperationTypeUpdate, lookSnapshot.Look.ID)
        if err != nil {
            return "", fmt.Errorf("failed to restore look %s: %w", lookSnapshot.Look.ID, err)
        }
        restoredIDs = append(restoredIDs, entityID)
    }

    return strings.Join(restoredIDs, ","), nil
}
```

**1.5.5 Update applySnapshot Switch**

```go
func (s *Service) applySnapshot(ctx context.Context, entityType EntityType, snapshotJSON string, opType OperationType, entityID string) (string, error) {
    switch entityType {
    // ... existing cases ...
    case EntityTypeBulkLookUpdate:
        return s.applyBulkLookUpdateSnapshot(ctx, snapshotJSON)
    // ...
    }
}
```

**Resolver Implementation Notes**:
- The resolver captures all target looks' states BEFORE making any changes
- Performs all look updates (can be in a transaction for atomicity)
- Records ONE operation using `EntityTypeBulkLookUpdate` with the pre-update snapshot
- A single "Undo" restores all looks to their previous state

#### 1.5 PubSub for Real-time Updates

The existing `lookUpdated` subscription will be triggered for each updated look. No new subscriptions needed, but ensure the mutation publishes updates:

```go
// In the resolver, after updating each look:
for _, look := range updatedLooks {
    r.pubsub.Publish("lookUpdated", look)
}
```

### Phase 2: Frontend - GraphQL Query

**File**: `lacylights-fe/src/graphql/cueLists.ts`

#### 2.1 New Query

```typescript
export const GET_CUES_WITH_LOOK_INFO = gql`
  query GetCuesWithLookInfo($cueListId: ID!) {
    cuesWithLookInfo(cueListId: $cueListId) {
      cues {
        cueId
        cueNumber
        cueName
        lookId
        lookName
        otherCueNumbers
      }
      orphanLooks {
        id
        name
        description
      }
    }
  }
`;
```

#### 2.2 New Mutation

Add the atomic copy mutation:

```typescript
export const COPY_FIXTURES_TO_LOOKS = gql`
  mutation CopyFixturesToLooks($input: CopyFixturesToLooksInput!) {
    copyFixturesToLooks(input: $input) {
      updatedLookCount
      affectedCueCount
      operationId
      updatedLooks {
        id
        name
        updatedAt
        fixtureValues {
          fixture {
            id
            name
          }
          channels {
            offset
            value
          }
        }
      }
    }
  }
`;
```

#### 2.3 Query for Preview (optional enhancement)

To show whether fixtures exist in target looks for the preview:

```typescript
export const GET_LOOK_FIXTURE_IDS = gql`
  query GetLookFixtureIds($lookId: ID!) {
    look(id: $lookId) {
      id
      fixtureValues {
        fixture {
          id
        }
      }
    }
  }
`;
```

This can be batched for multiple target looks to populate the preview.

### Phase 3: Frontend - CopyFixturesToLooksModal Component

**File**: `lacylights-fe/src/components/CopyFixturesToLooksModal.tsx`

#### 3.1 Component Props

```typescript
interface CopyFixturesToLooksModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** Project ID (needed when no cue list context) */
  projectId: string;
  /** Look ID we're copying FROM (used to disable its rows) */
  sourceLookId: string;
  /** Fixture IDs to copy */
  fixtureIds: string[];
  /** Fixture names for display */
  fixtureNames: Map<string, string>;
  /** Channel values for each fixture (fixtureId -> dense array) */
  fixtureValues: Map<string, number[]>;
  /** Active channels for each fixture (fixtureId -> Set of offsets) */
  activeChannels: Map<string, Set<number>>;
  /** Cue list ID - OPTIONAL, enables cue-centric display */
  cueListId?: string;
  /** Cue number we're editing from (for centering the list) */
  returnCueNumber?: string;
  /** Callback on successful copy */
  onSuccess: (result: { lookCount: number; cueCount: number }) => void;
}
```

**Behavior based on `cueListId`**:
- **With cueListId**: Cue-centric display sorted by cue number, centered on current cue
- **Without cueListId**: Look-centric display sorted alphabetically by look name, no cue info shown

#### 3.2 Component Structure

The modal displays a **cue-centric list** where each cue is a row, with its associated look shown. This allows users to navigate by cue order (their mental model during rehearsal) while still selecting looks as the target.

```
┌─────────────────────────────────────────────────────────────────┐
│  Copy Fixtures to Other Looks                                   │
│─────────────────────────────────────────────────────────────────│
│  Copying: 3 fixtures (Spot 1, Spot 2, Spot 3)                   │
│  • 12 active channels will be copied                            │
│                                                                 │
│  [🔍 Search cues or looks...]                                   │
│                                                                 │
│  [ ] Select All                                                 │
│─────────────────────────────────────────────────────────────────│
│  [ ] #1: Opening: Blackout                                      │
│  [ ] #2: Lights Up: Full Stage Wash                             │
│  [—] #3: Scene Start: Blue Spots (#5)        ← source, disabled │
│  [ ] #4: Transition: Dim Wash                                   │
│  [—] #5: Scene Continue: Blue Spots (#3)     ← source, disabled │
│  [✓] #6: Finale Prep: Warm Glow (#8)         ← selected         │
│  [ ] #7: Finale Build: Bright Wash                              │
│  [✓] #8: Finale Peak: Warm Glow (#6)         ← auto-selected    │
│                                                                 │
│  ——— Looks not in any cue ———                                   │
│  [ ] Test Look A                                                │
│  [ ] Rehearsal Look B                                           │
│─────────────────────────────────────────────────────────────────│
│  ⚠️ "Warm Glow" is used by 2 cues (#6, #8) - all will be updated│
│─────────────────────────────────────────────────────────────────│
│                        PREVIEW                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Target: "Warm Glow" (cues #6, #8)                         │  │
│  │ ─────────────────────────────────────────────────────────│  │
│  │ Spot 1: RGB 30,80,210 → will overwrite existing          │  │
│  │ Spot 2: RGB 30,80,210, Dim 100% → will overwrite         │  │
│  │ Spot 3: RGB 30,80,210 → will add (not in target)         │  │
│  └───────────────────────────────────────────────────────────┘  │
│─────────────────────────────────────────────────────────────────│
│  [Cancel]                            [Copy to 1 Look (2 cues)]  │
└─────────────────────────────────────────────────────────────────┘
```

**Without cue list context** (direct look editor access):
```
┌─────────────────────────────────────────────────────────────────┐
│  Copy Fixtures to Other Looks                                   │
│─────────────────────────────────────────────────────────────────│
│  Copying: 3 fixtures (Spot 1, Spot 2, Spot 3)                   │
│  • 12 active channels will be copied                            │
│                                                                 │
│  [🔍 Search looks...]                                           │
│                                                                 │
│  [ ] Select All                                                 │
│─────────────────────────────────────────────────────────────────│
│  [—] Blue Spots                              ← source, disabled │
│  [ ] Blackout                                                   │
│  [ ] Bright Wash                                                │
│  [ ] Dim Wash                                                   │
│  [ ] Full Stage Wash                                            │
│  [✓] Warm Glow                               ← selected         │
│─────────────────────────────────────────────────────────────────│
│                        PREVIEW                                  │
│  ... (same preview section as above)                            │
│─────────────────────────────────────────────────────────────────│
│  [Cancel]                                    [Copy to 1 Look]   │
└─────────────────────────────────────────────────────────────────┘
```

**Row Format**: `#<cueNumber>: <cueName>: <lookName> (<otherCueNumbers>)`

- `#3: Scene Start: Blue Spots (#5)` means cue #3 named "Scene Start" uses look "Blue Spots", which is also used by cue #5

#### 3.3 Key Features

1. **Cue-Centric Sorting**:
   - Primary list: All cues sorted by cue number
   - Centered on current cue (if `returnCueNumber` is provided)
   - Secondary section: Orphan looks (not in any cue) appear below a divider

2. **Source Look Handling**:
   - ALL cues using the source look are disabled (greyed out, not checkable)
   - Cannot copy a look to itself
   - Example: If copying from "Blue Spots" (used by cues #3 and #5), both rows are disabled

3. **Shared Look Display**:
   - Parentheses show other cue numbers using the same look
   - Format: `(#3, #7, #12)` for multiple cues
   - Rows sharing the same look have subtle background highlighting (grouped visually)

4. **Selection Behavior**:
   - Checking one cue row selects its LOOK
   - All other cue rows using the same look are automatically checked
   - Visual indicator (auto-selected rows slightly dimmed or marked)
   - Warning banner appears when selection affects multiple cues:
     `⚠️ "Warm Glow" is used by 2 cues (#6, #8) - all will be updated`

5. **Button Label**:
   - Shows both look count and affected cue count
   - `[Copy to 1 Look (2 cues)]` or `[Copy to 3 Looks]`

6. **Search/Filter**:
   - Filter by cue name (case-insensitive)
   - Filter by look name (case-insensitive)
   - Filter by cue number

7. **Multi-Select**:
   - "Select All" selects all non-disabled looks
   - Badge shows: "3 looks selected (affecting 5 cues)"

8. **Preview Section**:
   - Appears when at least one target is selected
   - Shows each target look with its affected cues
   - For each fixture being copied:
     - Shows fixture name and channel summary (e.g., "RGB 30,80,210")
     - Indicates action: "will overwrite existing" or "will add (not in target)"
   - Collapsible if many fixtures/targets (show first 3, expand for more)
   - Helps user verify changes before committing

#### 3.4 Modal Actions

**On Confirm**:
1. Build fixture values array for mutation:
   ```typescript
   const fixtureValuesInput = Array.from(fixtureIds).map(fixtureId => ({
     fixtureId,
     channels: buildSparseChannels(fixtureValues.get(fixtureId), activeChannels.get(fixtureId))
   }));
   ```

2. Call `bulkUpdateLooksPartial` mutation with `mergeFixtures: true`

3. Handle success/error feedback

### Phase 4: Frontend - Integration into LookEditorLayout

**File**: `lacylights-fe/src/components/LookEditorLayout.tsx`

#### 4.1 Add Modal State

```typescript
const [showCopyToLooksModal, setShowCopyToLooksModal] = useState(false);
```

#### 4.2 Add Handler

```typescript
const handleCopyToOtherLooks = useCallback(() => {
  if (selectedFixtureIds.size === 0) {
    // Show toast: "Select fixtures first"
    return;
  }
  setShowCopyToLooksModal(true);
}, [selectedFixtureIds]);
```

#### 4.3 Add Button to Toolbar

In `LookEditorMobileToolbar.tsx` or main toolbar area:
- Button appears when fixtures are selected
- Icon: `DocumentDuplicateIcon` or similar
- Label: "Copy to Other Looks..."
- Keyboard shortcut: `Ctrl/Cmd + Shift + C`

#### 4.4 Pass Required Props to Modal

```tsx
<CopyFixturesToLooksModal
  isOpen={showCopyToLooksModal}
  onClose={() => setShowCopyToLooksModal(false)}
  projectId={look?.project?.id || ""}
  sourceLookId={lookId}
  fixtureIds={Array.from(selectedFixtureIds)}
  fixtureValues={localFixtureValues}
  activeChannels={activeChannels}
  returnCueNumber={returnCueNumber}
  cueListId={cueListId}
  onSuccess={(count) => {
    setShowCopyToLooksModal(false);
    // Show success toast
  }}
/>
```

### Phase 5: MCP Server - New Tool

**File**: `lacylights-mcp/src/tools/look-tools.ts`

#### 5.1 Add Tool: `copy_fixtures_to_looks`

```typescript
const CopyFixturesToLooksSchema = z.object({
  sourceLookId: z.string().describe("ID of the look to copy fixtures from"),
  fixtureIds: z.array(z.string()).describe("IDs of fixtures to copy"),
  targetLookIds: z.array(z.string()).describe("IDs of looks to copy fixtures to"),
  overwriteExisting: z.boolean().default(true).describe("Whether to overwrite existing fixture values in target looks")
});
```

#### 5.2 Implementation

```typescript
async copyFixturesToLooks(args: z.infer<typeof CopyFixturesToLooksSchema>) {
  const { sourceLookId, fixtureIds, targetLookIds, overwriteExisting } = args;

  // 1. Get source look with fixture values
  const sourceLook = await this.graphqlClient.getLook(sourceLookId);

  // 2. Filter to requested fixtures
  const fixtureValues = sourceLook.fixtureValues
    .filter(fv => fixtureIds.includes(fv.fixture.id))
    .map(fv => ({
      fixtureId: fv.fixture.id,
      channels: fv.channels
    }));

  // 3. Apply to each target look
  const updates = targetLookIds.map(lookId => ({
    lookId,
    fixtureValues,
    mergeFixtures: !overwriteExisting
  }));

  const result = await this.graphqlClient.bulkUpdateLooksPartial(updates);

  return {
    sourceFixturesCount: fixtureValues.length,
    targetLooksUpdated: result.length,
    message: `Copied ${fixtureValues.length} fixtures to ${result.length} looks`
  };
}
```

#### 5.3 Register Tool

Add to tool list in `index.ts`:
```typescript
{
  name: "copy_fixtures_to_looks",
  description: "Copy fixture channel values from one look to multiple other looks. Use this to propagate fixture settings across a series of cues in a scene.",
  inputSchema: {
    type: "object",
    properties: {
      sourceLookId: { type: "string", description: "ID of the look to copy fixtures from" },
      fixtureIds: {
        type: "array",
        items: { type: "string" },
        description: "IDs of fixtures to copy"
      },
      targetLookIds: {
        type: "array",
        items: { type: "string" },
        description: "IDs of looks to copy fixtures to"
      },
      overwriteExisting: {
        type: "boolean",
        description: "Whether to overwrite existing fixture values in target looks (default: true)"
      }
    },
    required: ["sourceLookId", "fixtureIds", "targetLookIds"]
  }
}
```

---

## Testing Plan

### Phase 6: Unit Tests

#### 6.1 Backend Tests

**File**: `lacylights-go/internal/graphql/resolvers/look_resolver_test.go`

- Test `LooksWithCueUsage` returns looks with cue associations
- Test looks without cues are included with empty cue array
- Test fixture count is accurate
- Test project scoping (only returns looks for requested project)

**File**: `lacylights-go/internal/database/repositories/look_repository_test.go`

- Test `FindLooksWithCueUsageByProjectID` query efficiency
- Test cue sorting by cue number
- Test handling of looks in multiple cues

#### 6.2 Frontend Unit Tests

**File**: `lacylights-fe/src/components/__tests__/CopyFixturesToLooksModal.test.tsx`

- Test modal renders correctly with fixture summary
- Test search/filter functionality
- Test checkbox selection logic
- Test current look is disabled and greyed
- Test sorting by cue proximity
- Test "Select All" behavior
- Test confirm button enabled only when selection exists
- Test mutation call with correct parameters
- Test error handling

**File**: `lacylights-fe/src/components/__tests__/LookEditorLayout.test.tsx`

- Test "Copy to Other Looks" button appears when fixtures selected
- Test button disabled when no fixtures selected
- Test modal opens on button click
- Test keyboard shortcut triggers modal

#### 6.3 MCP Server Tests

**File**: `lacylights-mcp/tests/tools/look-tools.test.ts`

- Test `copy_fixtures_to_looks` validates inputs
- Test copies correct fixtures to correct looks
- Test handles empty fixture list
- Test handles empty target list
- Test `overwriteExisting` flag behavior

### Phase 7: Integration Tests (lacylights-test)

**File**: `lacylights-test/tests/copy_fixtures_integration_test.go`

Test end-to-end scenarios:

1. **Basic Copy Flow**:
   - Create project with fixtures
   - Create source look with fixture values
   - Create target looks
   - Call `bulkUpdateLooksPartial` mutation
   - Verify target looks have copied values

2. **Merge vs Replace**:
   - Target look has fixtures A, B
   - Copy fixtures B, C from source
   - With merge: A retained, B updated, C added
   - Without merge: Only B, C present

3. **Active Channel Handling**:
   - Source has 5-channel fixture with only channels 0, 2, 4 active
   - Copy to target
   - Verify only active channels are copied
   - Non-active channels in target retain original values

4. **Cross-Cue-List Copy**:
   - Copy fixtures between looks in different cue lists
   - Verify no side effects

### Phase 8: E2E Tests (lacylights-test)

**File**: `lacylights-test/e2e/copy_fixtures_e2e_test.go`

Full user workflow tests:

1. **Happy Path**:
   - Start cue list playback
   - Right-click cue → Edit Look
   - Select 2 fixtures in 2D viewer
   - Click "Copy to Other Looks..."
   - Verify modal shows looks sorted by cue proximity
   - Select 3 target looks
   - Confirm copy
   - Verify success toast
   - Navigate to target looks and verify values

2. **Empty Selection**:
   - Open look editor
   - Click "Copy to Other Looks..." with no selection
   - Verify appropriate error/disabled state

3. **Single Target**:
   - Select fixtures
   - Copy to just one look
   - Verify works correctly

4. **Keyboard Shortcut**:
   - Select fixtures
   - Press Ctrl+Shift+C
   - Verify modal opens

---

## File Changes Summary

### New Files

| File | Purpose |
|------|---------|
| `lacylights-fe/src/components/CopyFixturesToLooksModal.tsx` | Modal component |
| `lacylights-fe/src/components/__tests__/CopyFixturesToLooksModal.test.tsx` | Modal unit tests |
| `lacylights-test/tests/copy_fixtures_integration_test.go` | Integration tests |
| `lacylights-test/e2e/copy_fixtures_e2e_test.go` | E2E tests |

### Modified Files

| File | Changes |
|------|---------|
| `lacylights-go/internal/graphql/schema/schema.graphql` | Add `CueWithLookInfo`, `CuesWithLookInfoResponse`, `CopyFixturesToLooksInput`, `CopyFixturesToLooksResult` types; add `cuesWithLookInfo` query and `copyFixturesToLooks` mutation |
| `lacylights-go/internal/services/undo/service.go` | Add `EntityTypeBulkLookUpdate`, `BulkLookUpdateSnapshot`, `CaptureBulkLookState()`, `applyBulkLookUpdateSnapshot()` |
| `lacylights-go/internal/graphql/resolvers/cue_resolver.go` | Implement `CuesWithLookInfo` resolver |
| `lacylights-go/internal/graphql/resolvers/look_resolver.go` | Implement `CopyFixturesToLooks` resolver with atomic undo support |
| `lacylights-go/internal/database/repositories/cue_repository.go` | Add `FindCuesWithLookInfoByCueListID` method |
| `lacylights-fe/src/graphql/cueLists.ts` | Add `GET_CUES_WITH_LOOK_INFO` query |
| `lacylights-fe/src/graphql/looks.ts` | Add `COPY_FIXTURES_TO_LOOKS` mutation |
| `lacylights-fe/src/components/LookEditorLayout.tsx` | Add modal state, handler, button |
| `lacylights-fe/src/components/LookEditorMobileToolbar.tsx` | Add "Copy to Other Looks" button |
| `lacylights-mcp/src/tools/look-tools.ts` | Add `copyFixturesToLooks` method |
| `lacylights-mcp/src/index.ts` | Register `copy_fixtures_to_looks` tool |

---

## Implementation Order

1. **Phase 1**: Backend GraphQL schema and resolver (lacylights-go)
2. **Phase 2**: Frontend GraphQL queries (lacylights-fe)
3. **Phase 3**: CopyFixturesToLooksModal component (lacylights-fe)
4. **Phase 4**: Integration into LookEditorLayout (lacylights-fe)
5. **Phase 5**: MCP server tool (lacylights-mcp)
6. **Phase 6**: Unit tests (all repos)
7. **Phase 7**: Integration tests (lacylights-test)
8. **Phase 8**: E2E tests (lacylights-test)

---

## Design Decisions

1. **Undo Support**: ✅ **Atomic operation** - The entire copy operation (across all target looks) is a single undo/redo entry. One "Undo" reverses all changes. Implemented using the existing `BulkLookUpdateSnapshot` pattern in the undo service (see Phase 1.5).

2. **Preview**: ✅ **Yes** - Show a summary of changes before confirming (which fixtures, how many channels, target looks affected).

3. **Direct Look Editor Access**: ✅ **Allowed without cue list** - User can still copy to other looks, but there's no "current" cue to center on. The list shows looks alphabetically or by last modified.

4. **Multi-user Notification**: ✅ **PubSub updates** - Use existing subscription system to push look changes to any open views. If another user has the look open, their view updates automatically.

---

## Estimated Effort

| Phase | Estimate |
|-------|----------|
| Phase 1: Backend | Medium |
| Phase 2: Frontend GraphQL | Small |
| Phase 3: Modal Component | Medium-Large |
| Phase 4: Integration | Small |
| Phase 5: MCP Tool | Small |
| Phase 6: Unit Tests | Medium |
| Phase 7-8: Integration/E2E | Medium |

---

## Success Criteria

1. User can copy selected fixtures from one look to multiple other looks in under 30 seconds
2. Modal correctly sorts looks by cue proximity
3. All channel values AND enabled/disabled flags are preserved
4. MCP server can perform the same operation
5. Operation is covered by unit, integration, and E2E tests
6. No regressions in existing look editing functionality
