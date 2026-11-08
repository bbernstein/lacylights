# Scene to Look Rename Plan

## Overview

This document outlines the comprehensive plan to rename "scene" to "look" throughout the LacyLights codebase. This terminology change aligns with professional theatrical lighting design conventions where "look" refers to a static lighting state, distinct from "scene" which commonly refers to a dramatic unit of a play.

### Terminology Reference

| Current Term | New Term | Definition |
|--------------|----------|------------|
| Scene | Look | A static lighting state - the combination of intensity, color, position across all fixtures |
| Scene Board | Look Board | A visual layout for organizing and triggering looks |
| Cue | Cue | A look with timing/transition information (unchanged) |
| Cue List | Cue List | A sequence of cues (unchanged) |

### Scope Summary

| Category | Files | Occurrences |
|----------|-------|-------------|
| Backend (lacylights-go) | ~35 | ~4,856 |
| Frontend (lacylights-fe) | ~70 | ~2,481 |
| MCP Server (lacylights-mcp) | ~14 | ~1,725 |
| Integration Tests (lacylights-test) | ~10 | ~881 |
| Active Documentation | ~24 | ~245 |
| Archived Documentation | ~15 | ~335 |
| **Total** | **~168 files** | **~10,523 occurrences** |

---

## Phase 1: Preparation and Planning

### 1.1 Create Feature Branches

Create feature branches in all repositories for this refactoring:

```bash
# In each repository
git checkout main
git pull origin main
git checkout -b feature/scene-to-look-rename
```

Repositories requiring branches:
- [ ] lacylights-go
- [ ] lacylights-fe
- [ ] lacylights-mcp
- [ ] lacylights-test
- [ ] lacylights (documentation)
- [ ] lacylights-rpi (minor updates)
- [ ] lacylights-mac (minor updates)

### 1.2 Backup Existing Data

Before any migration, ensure backups exist:

```bash
# Backup SQLite databases
cp ~/.lacylights/lacylights.db ~/.lacylights/lacylights.db.backup-$(date +%Y%m%d)

# On Raspberry Pi deployments
cp /var/lib/lacylights/lacylights.db /var/lib/lacylights/lacylights.db.backup-$(date +%Y%m%d)
```

### 1.3 Document Current Export Format

Save examples of current export format for reference during import compatibility work:

```bash
# Export a project in current format for reference
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "query { exportProject(projectId: \"...\") { data } }"}' \
  > export-format-v1-reference.json
```

---

## Phase 2: Backend Database and Models (lacylights-go)

### 2.1 Database Migration Strategy

Since LacyLights uses GORM AutoMigrate, we need a careful migration approach that:
1. Preserves existing data
2. Handles both fresh installs and upgrades
3. Maintains backwards compatibility during transition

#### Migration Approach: Rename with Data Preservation

Create a new migration system in `internal/database/migrations/`:

```go
// internal/database/migrations/migrations.go
package migrations

import (
    "gorm.io/gorm"
)

type Migration struct {
    ID        string
    Name      string
    Migrate   func(*gorm.DB) error
    Rollback  func(*gorm.DB) error
}

var migrations = []Migration{
    {
        ID:   "001_rename_scenes_to_looks",
        Name: "Rename scenes table to looks",
        Migrate: func(db *gorm.DB) error {
            // Check if migration is needed (scenes table exists)
            if db.Migrator().HasTable("scenes") {
                // Rename tables
                if err := db.Exec("ALTER TABLE scenes RENAME TO looks").Error; err != nil {
                    return err
                }
                if err := db.Exec("ALTER TABLE scene_boards RENAME TO look_boards").Error; err != nil {
                    return err
                }
                if err := db.Exec("ALTER TABLE scene_board_buttons RENAME TO look_board_buttons").Error; err != nil {
                    return err
                }

                // Update foreign key column names (SQLite requires table recreation)
                // See section 2.1.1 for SQLite-specific handling
            }
            return nil
        },
    },
}
```

#### 2.1.1 SQLite Column Rename Strategy

SQLite has limited ALTER TABLE support. For column renames, we need to recreate tables:

```sql
-- Migration script for scene_id -> look_id in fixture_values table
-- Step 1: Create new table with correct column names
CREATE TABLE fixture_values_new (
    id TEXT PRIMARY KEY,
    look_id TEXT NOT NULL,
    fixture_instance_id TEXT NOT NULL,
    channel_values TEXT,
    scene_order INTEGER DEFAULT 0,
    created_at DATETIME,
    updated_at DATETIME,
    FOREIGN KEY (look_id) REFERENCES looks(id) ON DELETE CASCADE,
    FOREIGN KEY (fixture_instance_id) REFERENCES fixture_instances(id) ON DELETE CASCADE
);

-- Step 2: Copy data
INSERT INTO fixture_values_new (id, look_id, fixture_instance_id, channel_values, scene_order, created_at, updated_at)
SELECT id, scene_id, fixture_instance_id, channel_values, scene_order, created_at, updated_at
FROM fixture_values;

-- Step 3: Drop old table
DROP TABLE fixture_values;

-- Step 4: Rename new table
ALTER TABLE fixture_values_new RENAME TO fixture_values;

-- Step 5: Recreate indexes
CREATE INDEX idx_fixture_values_look_id ON fixture_values(look_id);
CREATE INDEX idx_fixture_values_fixture_instance_id ON fixture_values(fixture_instance_id);
```

Similar scripts needed for:
- `cues` table: `scene_id` → `look_id`
- `look_board_buttons` table: `scene_id` → `look_id`, `scene_board_id` → `look_board_id`

### 2.2 Model Updates

#### 2.2.1 Rename Model Files

| Current File | New File |
|--------------|----------|
| `internal/database/models/scene.go` | `internal/database/models/look.go` |
| `internal/database/models/scene_board.go` | `internal/database/models/look_board.go` |

#### 2.2.2 Update Model Definitions

```go
// internal/database/models/look.go (renamed from scene.go)

// Look represents a lighting state (formerly Scene)
type Look struct {
    ID            string         `gorm:"primaryKey;type:text" json:"id"`
    ProjectID     string         `gorm:"type:text;not null" json:"projectId"`
    Name          string         `gorm:"type:text;not null" json:"name"`
    Description   string         `gorm:"type:text" json:"description"`
    FixtureValues []FixtureValue `gorm:"foreignKey:LookID" json:"fixtureValues"`
    CreatedAt     time.Time      `json:"createdAt"`
    UpdatedAt     time.Time      `json:"updatedAt"`

    Project       Project        `gorm:"foreignKey:ProjectID" json:"-"`
}

// TableName specifies the table name for GORM
func (Look) TableName() string {
    return "looks"
}

// LookBoard represents a visual layout for organizing looks (formerly SceneBoard)
type LookBoard struct {
    ID              string            `gorm:"primaryKey;type:text" json:"id"`
    ProjectID       string            `gorm:"type:text;not null" json:"projectId"`
    Name            string            `gorm:"type:text;not null" json:"name"`
    Description     string            `gorm:"type:text" json:"description"`
    GridSize        int               `gorm:"default:50" json:"gridSize"`
    CanvasWidth     int               `gorm:"default:2000" json:"canvasWidth"`
    CanvasHeight    int               `gorm:"default:2000" json:"canvasHeight"`
    DefaultFadeTime float64           `gorm:"default:3.0" json:"defaultFadeTime"`
    Buttons         []LookBoardButton `gorm:"foreignKey:LookBoardID" json:"buttons"`
    CreatedAt       time.Time         `json:"createdAt"`
    UpdatedAt       time.Time         `json:"updatedAt"`

    Project         Project           `gorm:"foreignKey:ProjectID" json:"-"`
}

func (LookBoard) TableName() string {
    return "look_boards"
}

// LookBoardButton represents a button on a look board (formerly SceneBoardButton)
type LookBoardButton struct {
    ID          string    `gorm:"primaryKey;type:text" json:"id"`
    LookBoardID string    `gorm:"type:text;not null" json:"lookBoardId"`
    LookID      string    `gorm:"type:text;not null" json:"lookId"`
    Label       string    `gorm:"type:text" json:"label"`
    Color       string    `gorm:"type:text" json:"color"`
    LayoutX     int       `gorm:"default:0" json:"layoutX"`
    LayoutY     int       `gorm:"default:0" json:"layoutY"`
    Width       int       `gorm:"default:200" json:"width"`
    Height      int       `gorm:"default:120" json:"height"`
    CreatedAt   time.Time `json:"createdAt"`
    UpdatedAt   time.Time `json:"updatedAt"`

    LookBoard   LookBoard `gorm:"foreignKey:LookBoardID" json:"-"`
    Look        Look      `gorm:"foreignKey:LookID" json:"-"`
}

func (LookBoardButton) TableName() string {
    return "look_board_buttons"
}
```

#### 2.2.3 Update Related Models

Update `FixtureValue` model:
```go
type FixtureValue struct {
    ID                string   `gorm:"primaryKey;type:text" json:"id"`
    LookID            string   `gorm:"type:text;not null" json:"lookId"`  // Changed from SceneID
    FixtureInstanceID string   `gorm:"type:text;not null" json:"fixtureInstanceId"`
    ChannelValues     string   `gorm:"type:text" json:"channelValues"`
    SceneOrder        int      `gorm:"default:0" json:"sceneOrder"`  // Keep as sceneOrder for now, or rename to lookOrder
    // ...
}
```

Update `Cue` model:
```go
type Cue struct {
    ID         string  `gorm:"primaryKey;type:text" json:"id"`
    CueListID  string  `gorm:"type:text;not null" json:"cueListId"`
    LookID     string  `gorm:"type:text;not null" json:"lookId"`  // Changed from SceneID
    Name       string  `gorm:"type:text;not null" json:"name"`
    CueNumber  float64 `gorm:"not null" json:"cueNumber"`
    // ...

    Look       Look    `gorm:"foreignKey:LookID" json:"-"`  // Changed from Scene
}
```

### 2.3 Repository Updates

#### 2.3.1 Rename Repository Files

| Current File | New File |
|--------------|----------|
| `internal/database/repositories/scene_repository.go` | `internal/database/repositories/look_repository.go` |
| `internal/database/repositories/scene_board_repository.go` | `internal/database/repositories/look_board_repository.go` |

#### 2.3.2 Update Repository Interfaces and Implementations

```go
// internal/database/repositories/look_repository.go

type LookRepository interface {
    Create(look *models.Look) error
    GetByID(id string) (*models.Look, error)
    GetByProjectID(projectID string, page, perPage int) ([]models.Look, int64, error)
    Update(look *models.Look) error
    Delete(id string) error
    // ... other methods
}

type lookRepository struct {
    db *gorm.DB
}

func NewLookRepository(db *gorm.DB) LookRepository {
    return &lookRepository{db: db}
}
```

### 2.4 GraphQL Schema Updates

#### 2.4.1 Type Renames

Update `internal/graphql/schema/schema.graphql`:

```graphql
# Types
type Look {
    id: ID!
    projectId: ID!
    name: String!
    description: String
    fixtureValues: [FixtureValue!]!
    fixtureCount: Int!
    createdAt: DateTime!
    updatedAt: DateTime!
}

type LookBoard {
    id: ID!
    projectId: ID!
    name: String!
    description: String
    gridSize: Int!
    canvasWidth: Int!
    canvasHeight: Int!
    defaultFadeTime: Float!
    buttons: [LookBoardButton!]!
    buttonCount: Int!
    createdAt: DateTime!
    updatedAt: DateTime!
}

type LookBoardButton {
    id: ID!
    lookBoardId: ID!
    lookId: ID!
    look: Look!
    label: String
    color: String
    layoutX: Int!
    layoutY: Int!
    width: Int!
    height: Int!
    createdAt: DateTime!
    updatedAt: DateTime!
}

# Input types
input CreateLookInput {
    projectId: ID!
    name: String!
    description: String
    fixtureValues: [FixtureValueInput!]
}

input UpdateLookInput {
    name: String
    description: String
    fixtureValues: [FixtureValueInput!]
}

# ... similar renames for all scene-related inputs

# Queries
type Query {
    # Looks (formerly scenes)
    looks(projectId: ID!, page: Int, perPage: Int, filter: LookFilterInput, sortBy: LookSortField): LookPage!
    look(id: ID!, includeFixtureValues: Boolean): Look
    lookFixtures(lookId: ID!): [LookFixtureSummary!]!
    looksByIds(ids: [ID!]!): [Look!]!
    compareLooks(lookId1: ID!, lookId2: ID!): LookComparison!

    # Look Boards (formerly scene boards)
    lookBoards(projectId: ID!): [LookBoard!]!
    lookBoard(id: ID!): LookBoard
    lookBoardsByIds(ids: [ID!]!): [LookBoard!]!

    # ... etc
}

# Mutations
type Mutation {
    # Looks
    createLook(input: CreateLookInput!): Look!
    updateLook(id: ID!, input: UpdateLookInput!): Look!
    deleteLook(id: ID!): Boolean!
    duplicateLook(id: ID!): Look!
    cloneLook(lookId: ID!, newName: String!): Look!

    # Look activation
    setLookLive(lookId: ID!, fadeTime: Float): Boolean!

    # Bulk operations
    bulkCreateLooks(input: [BulkLookCreateInput!]!): [Look!]!
    bulkUpdateLooks(input: [BulkLookUpdateInput!]!): [Look!]!
    bulkDeleteLooks(lookIds: [ID!]!): BulkDeleteResult!

    # Look fixtures
    addFixturesToLook(lookId: ID!, fixtureValues: [FixtureValueInput!]!, overwriteExisting: Boolean): Look!
    removeFixturesFromLook(lookId: ID!, fixtureIds: [ID!]!): Look!

    # Look Boards
    createLookBoard(input: CreateLookBoardInput!): LookBoard!
    updateLookBoard(id: ID!, input: UpdateLookBoardInput!): LookBoard!
    deleteLookBoard(id: ID!): Boolean!

    # Look Board Buttons
    addLookToBoard(input: CreateLookBoardButtonInput!): LookBoardButton!
    updateLookBoardButton(id: ID!, input: UpdateLookBoardButtonInput!): LookBoardButton!
    removeLookFromBoard(buttonId: ID!): Boolean!
    updateLookBoardButtonPositions(positions: [LookBoardButtonPositionInput!]!): [LookBoardButton!]!

    # Activation from board
    activateLookFromBoard(lookBoardId: ID!, lookId: ID!, fadeTimeOverride: Float): Boolean!

    # ... etc
}

# Subscriptions
type Subscription {
    cueListDataChanged(cueListId: ID!): CueListDataChange!
}

type CueListDataChange {
    type: CueListDataChangeType!
    cueListId: ID!
    affectedCueId: ID
    affectedLookId: ID      # Changed from affectedSceneId
    newLookName: String     # Changed from newSceneName
}

enum CueListDataChangeType {
    CUE_ADDED
    CUE_REMOVED
    CUE_UPDATED
    LOOK_NAME_CHANGED       # Changed from SCENE_NAME_CHANGED
}
```

#### 2.4.2 Complete List of GraphQL Renames

**Types (16):**
- `Scene` → `Look`
- `SceneBoard` → `LookBoard`
- `SceneBoardButton` → `LookBoardButton`
- `ScenePage` → `LookPage`
- `SceneSummary` → `LookSummary`
- `SceneFixtureSummary` → `LookFixtureSummary`
- `SceneUsage` → `LookUsage`
- `SceneComparison` → `LookComparison`
- `SceneDifference` → `LookDifference`
- `SceneSortField` → `LookSortField`
- `SceneFilterInput` → `LookFilterInput`
- `CreateSceneInput` → `CreateLookInput`
- `UpdateSceneInput` → `UpdateLookInput`
- `ScenePartialUpdateItem` → `LookPartialUpdateItem`
- `CreateSceneBoardInput` → `CreateLookBoardInput`
- `UpdateSceneBoardInput` → `UpdateLookBoardInput`
- ... (and all bulk operation inputs)

**Queries (10):**
- `scenes` → `looks`
- `scene` → `look`
- `sceneFixtures` → `lookFixtures`
- `searchScenes` → `searchLooks`
- `scenesByIds` → `looksByIds`
- `compareScenes` → `compareLooks`
- `sceneBoards` → `lookBoards`
- `sceneBoard` → `lookBoard`
- `sceneBoardsByIds` → `lookBoardsByIds`
- `sceneBoardButton` → `lookBoardButton`

**Mutations (24):**
- `createScene` → `createLook`
- `updateScene` → `updateLook`
- `deleteScene` → `deleteLook`
- `duplicateScene` → `duplicateLook`
- `cloneScene` → `cloneLook`
- `setSceneLive` → `setLookLive`
- `bulkCreateScenes` → `bulkCreateLooks`
- `bulkUpdateScenes` → `bulkUpdateLooks`
- `bulkDeleteScenes` → `bulkDeleteLooks`
- `addFixturesToScene` → `addFixturesToLook`
- `removeFixturesFromScene` → `removeFixturesFromLook`
- `updateScenePartial` → `updateLookPartial`
- `bulkUpdateScenesPartial` → `bulkUpdateLooksPartial`
- `ensureFixturesInScene` → `ensureFixturesInLook`
- `createSceneBoard` → `createLookBoard`
- `updateSceneBoard` → `updateLookBoard`
- `deleteSceneBoard` → `deleteLookBoard`
- `addSceneToBoard` → `addLookToBoard`
- `updateSceneBoardButton` → `updateLookBoardButton`
- `removeSceneFromBoard` → `removeLookFromBoard`
- `updateSceneBoardButtonPositions` → `updateLookBoardButtonPositions`
- `activateSceneFromBoard` → `activateLookFromBoard`
- `bulkCreateSceneBoards` → `bulkCreateLookBoards`
- ... (and all other bulk operations)

### 2.5 Resolver Updates

After updating the schema, run:
```bash
cd lacylights-go
make generate
```

This will regenerate resolver stubs. Then update all resolver implementations to use new model/repository names.

### 2.6 Service Layer Updates

Update all service files that reference scenes:
- `internal/services/fade/engine.go` - fade transitions reference scenes
- `internal/services/playback/service.go` - cue playback references scenes
- `internal/services/export/export.go` - export format
- `internal/services/import/import.go` - import format (with backwards compatibility)

### 2.7 Export/Import Format Changes

#### 2.7.1 New Export Format

```json
{
  "version": "2.0",
  "exportedAt": "2024-01-15T10:30:00Z",
  "project": {
    "name": "My Show",
    "description": "..."
  },
  "fixtures": [...],
  "looks": [
    {
      "id": "look-1",
      "name": "Morning Light",
      "description": "Warm morning wash",
      "fixtureValues": [...]
    }
  ],
  "lookBoards": [
    {
      "id": "board-1",
      "name": "Main Board",
      "buttons": [
        {
          "lookId": "look-1",
          "label": "Morning",
          "layoutX": 0,
          "layoutY": 0
        }
      ]
    }
  ],
  "cueLists": [
    {
      "name": "Act 1",
      "cues": [
        {
          "name": "Opening",
          "cueNumber": 1,
          "lookId": "look-1",
          "fadeInTime": 3.0
        }
      ]
    }
  ]
}
```

#### 2.7.2 Backwards Compatible Import

The import service must handle both old and new formats:

```go
// internal/services/import/import.go

type ImportData struct {
    Version     string          `json:"version"`

    // New format (v2.0+)
    Looks       []LookData      `json:"looks,omitempty"`
    LookBoards  []LookBoardData `json:"lookBoards,omitempty"`

    // Legacy format (v1.x) - for backwards compatibility
    Scenes      []LookData      `json:"scenes,omitempty"`
    SceneBoards []LookBoardData `json:"sceneBoards,omitempty"`
}

func (s *ImportService) Import(data []byte) (*models.Project, error) {
    var importData ImportData
    if err := json.Unmarshal(data, &importData); err != nil {
        return nil, err
    }

    // Handle legacy format
    if len(importData.Scenes) > 0 && len(importData.Looks) == 0 {
        importData.Looks = importData.Scenes
    }
    if len(importData.SceneBoards) > 0 && len(importData.LookBoards) == 0 {
        importData.LookBoards = importData.SceneBoards
    }

    // Also handle legacy field names within objects
    for i := range importData.Looks {
        // Handle sceneId -> lookId in nested structures
        s.migrateLegacyLookData(&importData.Looks[i])
    }

    // Continue with import...
}
```

### 2.8 Backend Test Updates

Update all test files in:
- `internal/graphql/resolvers/*_test.go`
- `internal/database/repositories/*_test.go`
- `internal/services/**/*_test.go`
- `test/integration/*_test.go`

---

## Phase 3: Frontend Updates (lacylights-fe)

### 3.1 Route Structure Changes

#### 3.1.1 Directory Renames

```bash
# Rename route directories
mv src/app/(main)/scenes src/app/(main)/looks
mv src/app/(main)/scene-board src/app/(main)/look-board
```

#### 3.1.2 URL Path Updates

| Old Route | New Route |
|-----------|-----------|
| `/scenes` | `/looks` |
| `/scenes/[sceneId]/edit` | `/looks/[lookId]/edit` |
| `/scene-board` | `/look-board` |
| `/scene-board/[id]` | `/look-board/[id]` |

#### 3.1.3 Update Dynamic Route Parameters

Rename `[sceneId]` directory to `[lookId]` and update all references.

### 3.2 Component Renames

#### 3.2.1 File Renames

| Current File | New File |
|--------------|----------|
| `src/components/scenes/SceneEditorLayout.tsx` | `src/components/looks/LookEditorLayout.tsx` |
| `src/components/scenes/SceneEditorBottomActions.tsx` | `src/components/looks/LookEditorBottomActions.tsx` |
| `src/components/scenes/SceneEditorMobileToolbar.tsx` | `src/components/looks/LookEditorMobileToolbar.tsx` |
| `src/components/scenes/SceneEditorPageClient.tsx` | `src/components/looks/LookEditorPageClient.tsx` |
| `src/components/scenes/CreateSceneModal.tsx` | `src/components/looks/CreateLookModal.tsx` |
| `src/components/scene-board/SceneBoardClient.tsx` | `src/components/look-board/LookBoardClient.tsx` |

#### 3.2.2 Update Component Names

```tsx
// Before
export function SceneEditorLayout({ ... }) { ... }

// After
export function LookEditorLayout({ ... }) { ... }
```

### 3.3 GraphQL Query Updates

#### 3.3.1 Rename Query Files

| Current File | New File |
|--------------|----------|
| `src/graphql/scenes.ts` | `src/graphql/looks.ts` |
| `src/graphql/sceneBoards.ts` | `src/graphql/lookBoards.ts` |

#### 3.3.2 Update Query Definitions

```typescript
// src/graphql/looks.ts (renamed from scenes.ts)

export const GET_LOOKS = gql`
  query GetLooks($projectId: ID!, $page: Int, $perPage: Int) {
    looks(projectId: $projectId, page: $page, perPage: $perPage) {
      items {
        id
        name
        description
        fixtureCount
        createdAt
        updatedAt
      }
      pagination {
        page
        perPage
        total
        hasMore
      }
    }
  }
`;

export const GET_LOOK = gql`
  query GetLook($id: ID!, $includeFixtureValues: Boolean) {
    look(id: $id, includeFixtureValues: $includeFixtureValues) {
      id
      name
      description
      fixtureValues {
        fixtureId
        channels {
          offset
          value
        }
      }
    }
  }
`;

export const CREATE_LOOK = gql`
  mutation CreateLook($input: CreateLookInput!) {
    createLook(input: $input) {
      id
      name
    }
  }
`;

// ... etc
```

### 3.4 Hook Updates

#### 3.4.1 Rename Hook Files

| Current File | New File |
|--------------|----------|
| `src/hooks/useCurrentActiveScene.ts` | `src/hooks/useCurrentActiveLook.ts` |

#### 3.4.2 Update Hook Implementations

```typescript
// src/hooks/useCurrentActiveLook.ts

export function useCurrentActiveLook() {
  const { data, loading, error } = useQuery(GET_CURRENT_ACTIVE_LOOK);

  return {
    activeLook: data?.currentActiveLook,
    loading,
    error,
  };
}
```

### 3.5 Type Updates

Update `src/types/index.ts`:

```typescript
export interface Look {
  id: string;
  projectId: string;
  name: string;
  description?: string;
  fixtureValues?: FixtureValue[];
  fixtureCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface LookBoard {
  id: string;
  projectId: string;
  name: string;
  description?: string;
  gridSize: number;
  canvasWidth: number;
  canvasHeight: number;
  defaultFadeTime: number;
  buttons: LookBoardButton[];
  buttonCount: number;
}

export interface LookBoardButton {
  id: string;
  lookBoardId: string;
  lookId: string;
  look?: Look;
  label?: string;
  color?: string;
  layoutX: number;
  layoutY: number;
  width: number;
  height: number;
}
```

### 3.6 Regenerate Types

After backend GraphQL schema is updated:

```bash
cd lacylights-fe
npm run codegen
```

### 3.7 UI Text Updates

Update all user-facing text:
- "Scene" → "Look"
- "Scene Board" → "Look Board"
- "Create Scene" → "Create Look"
- "Edit Scene" → "Edit Look"
- "Delete Scene" → "Delete Look"
- etc.

### 3.8 Navigation Updates

Update navigation menus and links:

```tsx
// Before
<Link href="/scenes">Scenes</Link>

// After
<Link href="/looks">Looks</Link>
```

### 3.9 Frontend Test Updates

Update all test files:
- `src/components/__tests__/CreateSceneModal.test.tsx` → `CreateLookModal.test.tsx`
- `src/components/__tests__/SceneEditorLayout.test.tsx` → `LookEditorLayout.test.tsx`
- etc.

---

## Phase 4: MCP Server Updates (lacylights-mcp)

### 4.1 Tool Renames

#### 4.1.1 File Renames

| Current File | New File |
|--------------|----------|
| `src/tools/scene-tools.ts` | `src/tools/look-tools.ts` |
| `src/tools/scene-board-tools.ts` | `src/tools/look-board-tools.ts` |

#### 4.1.2 Tool Name Updates

| Current Tool | New Tool |
|--------------|----------|
| `generate_scene` | `generate_look` |
| `list_scenes` | `list_looks` |
| `get_scene` | `get_look` |
| `activate_scene` | `activate_look` |
| `update_scene` | `update_look` |
| `optimize_scene` | `optimize_look` |
| `add_fixtures_to_scene` | `add_fixtures_to_look` |
| `remove_fixtures_from_scene` | `remove_fixtures_from_look` |
| `ensure_fixtures_in_scene` | `ensure_fixtures_in_look` |
| `get_scene_fixture_values` | `get_look_fixture_values` |
| `create_scene_board` | `create_look_board` |
| `list_scene_boards` | `list_look_boards` |
| `get_scene_board` | `get_look_board` |
| `add_scene_to_board` | `add_look_to_board` |
| `remove_scene_from_board` | `remove_look_from_board` |
| `activate_scene_from_board` | `activate_look_from_board` |
| `update_scene_board` | `update_look_board` |
| `delete_scene_board` | `delete_look_board` |
| `update_scene_board_button` | `update_look_board_button` |
| `update_scene_board_button_positions` | `update_look_board_button_positions` |
| `bulk_*_scenes` | `bulk_*_looks` |
| `bulk_*_scene_boards` | `bulk_*_look_boards` |
| `bulk_*_scene_board_buttons` | `bulk_*_look_board_buttons` |

#### 4.1.3 Update Tool Descriptions

```typescript
// src/tools/look-tools.ts

export const generateLookTool = {
  name: "generate_look",
  description: "Generate a lighting look based on script context and design preferences",
  inputSchema: {
    type: "object",
    properties: {
      projectId: {
        type: "string",
        description: "Project ID to create look in"
      },
      lookDescription: {  // Changed from sceneDescription
        type: "string",
        description: "Description of the look to create"
      },
      // ... etc
    }
  }
};
```

### 4.2 Update GraphQL Queries in MCP

Update all GraphQL queries in MCP tool implementations to use new field names.

### 4.3 Regenerate Types

```bash
cd lacylights-mcp
npm run codegen
```

### 4.4 MCP Test Updates

Update all test files in `src/__tests__/`.

---

## Phase 5: Integration Tests (lacylights-test)

### 5.1 Contract Test Updates

#### 5.1.1 File Renames

| Current File | New File |
|--------------|----------|
| `contracts/crud/scene_test.go` | `contracts/crud/look_test.go` |

#### 5.1.2 Update Test Cases

```go
// contracts/crud/look_test.go (renamed from scene_test.go)

func TestLookCRUD(t *testing.T) {
    t.Run("Create Look", func(t *testing.T) {
        query := `
            mutation CreateLook($input: CreateLookInput!) {
                createLook(input: $input) {
                    id
                    name
                    description
                }
            }
        `
        // ...
    })

    t.Run("Get Look", func(t *testing.T) {
        query := `
            query GetLook($id: ID!) {
                look(id: $id) {
                    id
                    name
                    fixtureValues {
                        fixtureId
                        channels {
                            offset
                            value
                        }
                    }
                }
            }
        `
        // ...
    })
}
```

### 5.2 Update All Test Assertions

Update any assertions that check for "scene" in response data.

---

## Phase 6: Documentation Updates

### 6.1 Files Requiring Filename Changes

| Current Name | New Name |
|--------------|----------|
| `lacylights-fe/docs/SCENE_BOARD_INTERACTION_SPEC.md` | `LOOK_BOARD_INTERACTION_SPEC.md` |
| `lacylights-fe/docs/SCENE_EDITOR_2D_LAYOUT_PLAN.md` | `LOOK_EDITOR_2D_LAYOUT_PLAN.md` |
| `lacylights-fe/docs/SCENE_BOARD_REFACTOR_PROGRESS.md` | `LOOK_BOARD_REFACTOR_PROGRESS.md` |
| `lacylights-mcp/docs/SCENE_TYPES.md` | `LOOK_TYPES.md` |

### 6.2 Active Documentation Updates

Update content in these files (24 files, ~245 occurrences):

**High Priority (API/User-facing):**
- `lacylights-mcp/README.md` (58 occurrences)
- `lacylights-fe/docs/SCENE_BOARD_INTERACTION_SPEC.md` (25 occurrences)
- `lacylights-fe/docs/SCENE_EDITOR_2D_LAYOUT_PLAN.md` (35 occurrences)
- `lacylights-mcp/docs/SCENE_TYPES.md` (17 occurrences)
- `lacylights-test/docs/TESTING_PLAN.md` (28 occurrences)

**Medium Priority (Developer docs):**
- `lacylights-mcp/CLAUDE.md` (17 occurrences)
- `lacylights-fe/docs/USER_MODE_SYSTEM_PLAN.md` (10 occurrences)
- `lacylights-test/README.md` (7 occurrences)
- Various other CLAUDE.md and README.md files

### 6.3 Archived Documentation (Optional)

Consider updating for historical consistency:
- `docs/ARCHIVE/completed/MOBILE_SCENE_BOARD_PLAN.md` (85 occurrences)
- `docs/ARCHIVE/go-rewrite/LACYLIGHTS_GO_REWRITE_PLAN.md` (72 occurrences)

### 6.4 Files to NOT Update

These contain theatrical scene references (not lighting data structure):
- `ourtown_scenes_report.md`
- `ourtown_scenes_01.md`

---

## Phase 7: Deployment Platform Updates

### 7.1 lacylights-rpi Updates

Minor documentation updates:
- `README.md`
- `docs/GO_BACKEND_MIGRATION.md`
- `docs/DEPLOYMENT.md`

### 7.2 lacylights-mac Updates

Minor documentation updates:
- `README.md`
- `docs/USAGE.md`

---

## Phase 8: Migration Tooling

### 8.1 Database Migration Script

Create a standalone migration tool for existing installations:

```go
// cmd/migrate-scene-to-look/main.go

package main

import (
    "database/sql"
    "fmt"
    "log"
    "os"

    _ "github.com/mattn/go-sqlite3"
)

func main() {
    dbPath := os.Args[1]
    if dbPath == "" {
        log.Fatal("Usage: migrate-scene-to-look <database-path>")
    }

    db, err := sql.Open("sqlite3", dbPath)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    // Check if migration is needed
    var tableName string
    err = db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='scenes'").Scan(&tableName)
    if err == sql.ErrNoRows {
        fmt.Println("Migration not needed - 'scenes' table does not exist")
        return
    }

    // Perform migration
    migrations := []string{
        "ALTER TABLE scenes RENAME TO looks",
        "ALTER TABLE scene_boards RENAME TO look_boards",
        "ALTER TABLE scene_board_buttons RENAME TO look_board_buttons",
        // ... column renames via table recreation
    }

    for _, migration := range migrations {
        _, err := db.Exec(migration)
        if err != nil {
            log.Printf("Warning: %v", err)
        }
    }

    fmt.Println("Migration completed successfully")
}
```

### 8.2 Export Format Migration Tool

Create a tool to convert old export files to new format:

```go
// cmd/migrate-export/main.go

package main

import (
    "encoding/json"
    "io/ioutil"
    "log"
    "os"
    "strings"
)

func main() {
    inputPath := os.Args[1]
    outputPath := os.Args[2]

    data, err := ioutil.ReadFile(inputPath)
    if err != nil {
        log.Fatal(err)
    }

    // Parse and transform
    var oldFormat map[string]interface{}
    json.Unmarshal(data, &oldFormat)

    // Rename keys
    if scenes, ok := oldFormat["scenes"]; ok {
        oldFormat["looks"] = scenes
        delete(oldFormat, "scenes")
    }
    if sceneBoards, ok := oldFormat["sceneBoards"]; ok {
        oldFormat["lookBoards"] = sceneBoards
        delete(oldFormat, "sceneBoards")
    }

    // Update nested references
    // ... (recursive transformation)

    // Update version
    oldFormat["version"] = "2.0"

    // Write output
    output, _ := json.MarshalIndent(oldFormat, "", "  ")
    ioutil.WriteFile(outputPath, output, 0644)
}
```

---

## Phase 9: Testing and Validation

### 9.1 Unit Test Execution

```bash
# Backend
cd lacylights-go
make test

# Frontend
cd lacylights-fe
npm test

# MCP
cd lacylights-mcp
npm test
```

### 9.2 Integration Test Execution

```bash
cd lacylights-test
make test
```

### 9.3 Manual Testing Checklist

- [ ] Create new project
- [ ] Create new look
- [ ] Edit look fixture values
- [ ] Duplicate look
- [ ] Delete look
- [ ] Create look board
- [ ] Add looks to look board
- [ ] Activate look from board
- [ ] Create cue list with looks
- [ ] Play cue list
- [ ] Export project
- [ ] Import project (new format)
- [ ] Import project (old format - backwards compatibility)
- [ ] MCP tool: generate_look
- [ ] MCP tool: list_looks
- [ ] MCP tool: activate_look

### 9.4 Migration Testing

- [ ] Fresh install creates correct table names
- [ ] Existing database migrates successfully
- [ ] Migrated data is accessible
- [ ] Old export files import correctly
- [ ] New export files have correct format

---

## Phase 10: Release and Deployment

### 10.1 Version Bump

This is a breaking change for the API. Bump major version:
- `v1.x.x` → `v2.0.0`

### 10.2 Release Notes

```markdown
# LacyLights v2.0.0

## Breaking Changes

### Terminology Update: "Scene" → "Look"

We've renamed "scene" to "look" throughout the application to align with
professional theatrical lighting terminology. A "look" refers to a static
lighting state, which is distinct from a theatrical "scene" (a dramatic
unit of a play).

#### API Changes

All GraphQL queries and mutations have been renamed:
- `scenes` → `looks`
- `scene` → `look`
- `createScene` → `createLook`
- `updateScene` → `updateLook`
- (etc.)

#### Database Migration

Existing databases will be automatically migrated on first startup.
Backup your database before upgrading.

#### Import Compatibility

The new version can import both old (scene-based) and new (look-based)
export files. New exports will use the look-based format.

### Migration Guide

1. Backup your database
2. Update to v2.0.0
3. Restart the server (migration runs automatically)
4. Verify your projects are accessible
```

### 10.3 Deployment Order

1. Deploy backend (lacylights-go) - includes migration
2. Deploy frontend (lacylights-fe)
3. Deploy MCP server (lacylights-mcp)
4. Update deployment platforms (lacylights-rpi, lacylights-mac)

---

## Rollback Plan

### If Issues Occur

1. **Database Rollback:**
   ```bash
   # Restore from backup
   cp ~/.lacylights/lacylights.db.backup-YYYYMMDD ~/.lacylights/lacylights.db
   ```

2. **Code Rollback:**
   ```bash
   # In each repository
   git checkout main
   ```

3. **Re-deploy Previous Version:**
   Deploy the previous release from dist.lacylights.com

---

## Timeline Estimate

| Phase | Description | Dependencies |
|-------|-------------|--------------|
| 1 | Preparation | None |
| 2 | Backend | Phase 1 |
| 3 | Frontend | Phase 2 (schema must be ready) |
| 4 | MCP Server | Phase 2 (schema must be ready) |
| 5 | Integration Tests | Phases 2-4 |
| 6 | Documentation | Phases 2-4 |
| 7 | Deployment Platforms | Phase 6 |
| 8 | Migration Tooling | Phase 2 |
| 9 | Testing | Phases 2-8 |
| 10 | Release | Phase 9 |

Phases 3, 4, and 6 can run in parallel after Phase 2 completes.

---

## Checklist Summary

### Pre-Migration
- [ ] Create feature branches in all repos
- [ ] Backup all databases
- [ ] Document current export format
- [ ] Notify users of upcoming breaking change

### Backend (Phase 2)
- [ ] Create database migration
- [ ] Update models
- [ ] Update repositories
- [ ] Update GraphQL schema
- [ ] Regenerate resolvers
- [ ] Update services
- [ ] Update export format
- [ ] Add import backwards compatibility
- [ ] Update tests
- [ ] All tests pass

### Frontend (Phase 3)
- [ ] Rename route directories
- [ ] Update route parameters
- [ ] Rename component files
- [ ] Update component implementations
- [ ] Update GraphQL queries
- [ ] Regenerate types
- [ ] Update hooks
- [ ] Update types
- [ ] Update UI text
- [ ] Update navigation
- [ ] Update tests
- [ ] All tests pass

### MCP Server (Phase 4)
- [ ] Rename tool files
- [ ] Update tool names
- [ ] Update tool descriptions
- [ ] Update GraphQL queries
- [ ] Regenerate types
- [ ] Update tests
- [ ] All tests pass

### Integration Tests (Phase 5)
- [ ] Update contract tests
- [ ] All tests pass

### Documentation (Phase 6)
- [ ] Rename documentation files
- [ ] Update active documentation content
- [ ] Update CLAUDE.md files
- [ ] Update README files

### Migration Tooling (Phase 8)
- [ ] Database migration script
- [ ] Export format migration tool
- [ ] Test migration tools

### Final Validation (Phase 9)
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing complete
- [ ] Migration testing complete

### Release (Phase 10)
- [ ] Version bumped to v2.0.0
- [ ] Release notes written
- [ ] Deploy backend
- [ ] Deploy frontend
- [ ] Deploy MCP server
- [ ] Update deployment platforms
- [ ] Verify production systems
