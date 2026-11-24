# LacyLights MCP API Refactor Implementation Plan

**Status:** Planning
**Start Date:** 2025-10-23
**Goal:** Refactor MCP API to be context-efficient and follow modern REST-like patterns

## Overview

Refactor the MCP API to handle large projects efficiently by:
- Implementing resource-oriented design patterns
- Adding pagination to all list operations
- Separating lightweight browsing from detailed operations
- Adding search and filtering capabilities
- Removing backward compatibility constraints for clean design

## Architecture Principles

1. **Single Responsibility** - Each tool does one thing well
2. **Resource-Oriented** - Tools organized around resources (projects, fixtures, scenes, etc.)
3. **Consistent Naming** - Predictable patterns: `list_*`, `get_*`, `search_*`, `create_*`, `update_*`, `delete_*`
4. **Paginated by Default** - Always return pages, never "all"
5. **Summary/Detail Separation** - Different tools for browsing vs working
6. **Composable** - Tools can be chained naturally

## Work Breakdown

### Phase 1: Backend GraphQL API Enhancements (lacylights-node)

All backend work happens in `lacylights-node` repository.

#### Task 1.1: Project Queries (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** None
**Estimated Effort:** 2-3 hours
**Branch:** `feature/graphql-project-queries`

**Files to modify:**
- `src/graphql/schema/project.graphql`
- `src/graphql/resolvers/project.ts`
- `src/__tests__/graphql/project.test.ts`

**Changes:**
1. Add simple `project` query that returns metadata only (no nested fixtures/scenes)
2. Ensure existing `projects` query can work without including nested data
3. Add counts to project type: `fixtureCount`, `sceneCount`, `cueListCount`

**GraphQL Schema Changes:**
```graphql
type Project {
  id: ID!
  name: String!
  description: String
  fixtureCount: Int!
  sceneCount: Int!
  cueListCount: Int!
  createdAt: DateTime!
  updatedAt: DateTime!
  # Keep existing fields for backward compat during transition
  fixtures: [FixtureInstance!]
  scenes: [Scene!]
  cueLists: [CueList!]
}

type Query {
  # Simplified query - metadata only
  project(id: ID!): Project

  # Existing query - keep for now
  projects: [Project!]!
}
```

**Acceptance Criteria:**
- [ ] `project(id)` query returns metadata with counts
- [ ] Counts are accurate (use Prisma aggregations)
- [ ] Tests cover all new functionality
- [ ] All existing tests still pass

---

#### Task 1.2: Fixture List/Pagination (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** None
**Estimated Effort:** 4-5 hours
**Branch:** `feature/graphql-fixture-pagination`

**Files to modify:**
- `src/graphql/schema/fixture.graphql`
- `src/graphql/resolvers/fixture.ts`
- `src/__tests__/graphql/fixture.test.ts`

**Changes:**
1. Add pagination types (if not already exist)
2. Add `fixtureInstances` query with pagination and filtering
3. Add `fixtureInstance` query for single fixture details

**GraphQL Schema Changes:**
```graphql
type PaginationInfo {
  total: Int!
  page: Int!
  perPage: Int!
  totalPages: Int!
  hasMore: Boolean!
}

input FixtureFilterInput {
  type: FixtureType
  universe: Int
  tags: [String!]
  manufacturer: String
  model: String
}

type FixtureInstancePage {
  fixtures: [FixtureInstance!]!
  pagination: PaginationInfo!
}

type Query {
  # New paginated query
  fixtureInstances(
    projectId: ID!
    page: Int = 1
    perPage: Int = 50
    filter: FixtureFilterInput
  ): FixtureInstancePage!

  # Single fixture query
  fixtureInstance(id: ID!): FixtureInstance
}
```

**Acceptance Criteria:**
- [ ] Pagination works correctly with default and custom page sizes
- [ ] All filters work independently and in combination
- [ ] Performance is acceptable with 500+ fixtures
- [ ] Tests cover pagination, filtering, edge cases
- [ ] Query is optimized (check with Prisma query logging)

---

#### Task 1.3: Scene List/Pagination (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** None
**Estimated Effort:** 4-5 hours
**Branch:** `feature/graphql-scene-pagination`

**Files to modify:**
- `src/graphql/schema/scene.graphql`
- `src/graphql/resolvers/scene.ts`
- `src/__tests__/graphql/scene.test.ts`

**Changes:**
1. Add `scenes` query with pagination (lightweight - no fixture values by default)
2. Modify `scene` query to support `includeFixtureValues` parameter
3. Add `sceneFixtures` query for just fixture list without values

**GraphQL Schema Changes:**
```graphql
input SceneFilterInput {
  nameContains: String
  usesFixture: ID
}

enum SceneSortField {
  NAME
  CREATED_AT
  UPDATED_AT
}

type SceneSummary {
  id: ID!
  name: String!
  description: String
  fixtureCount: Int!
  createdAt: DateTime!
  updatedAt: DateTime!
}

type ScenePage {
  scenes: [SceneSummary!]!
  pagination: PaginationInfo!
}

type SceneFixtureSummary {
  fixtureId: ID!
  fixtureName: String!
  fixtureType: FixtureType!
}

type Query {
  # Paginated lightweight scene list
  scenes(
    projectId: ID!
    page: Int = 1
    perPage: Int = 50
    filter: SceneFilterInput
    sortBy: SceneSortField = CREATED_AT
  ): ScenePage!

  # Full scene details
  scene(id: ID!, includeFixtureValues: Boolean = true): Scene

  # Just which fixtures a scene uses
  sceneFixtures(sceneId: ID!): [SceneFixtureSummary!]!
}
```

**Acceptance Criteria:**
- [ ] Lightweight `scenes` query excludes fixture values
- [ ] `scene` query with `includeFixtureValues=false` is fast
- [ ] `sceneFixtures` query returns just fixture metadata
- [ ] Filtering by `usesFixture` works correctly
- [ ] Tests cover all query variations
- [ ] Performance acceptable with 100+ scenes

---

#### Task 1.4: Cue List Pagination (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** None
**Estimated Effort:** 3-4 hours
**Branch:** `feature/graphql-cuelist-pagination`

**Files to modify:**
- `src/graphql/schema/cueList.graphql`
- `src/graphql/resolvers/cueList.ts`
- `src/__tests__/graphql/cueList.test.ts`

**Changes:**
1. Add `cueLists` query with basic info (already might exist)
2. Modify `cueList` query to support pagination for cues
3. Add `cue` query for single cue details

**GraphQL Schema Changes:**
```graphql
type CueListSummary {
  id: ID!
  name: String!
  description: String
  cueCount: Int!
  totalDuration: Float!  # Sum of all cue times
  loop: Boolean!
  createdAt: DateTime!
}

type CuePage {
  cues: [Cue!]!
  pagination: PaginationInfo!
}

type Query {
  # List all cue lists for a project
  cueLists(projectId: ID!): [CueListSummary!]!

  # Get cue list with paginated cues
  cueList(
    id: ID!
    page: Int = 1
    perPage: Int = 50
    includeSceneDetails: Boolean = false
  ): CueList!

  # Single cue details
  cue(id: ID!): Cue
}

# Modify existing CueList type
type CueList {
  id: ID!
  name: String!
  description: String
  loop: Boolean!
  cues: CuePage!  # Changed from [Cue!]! to paginated
  cueCount: Int!
  totalDuration: Float!
  createdAt: DateTime!
  updatedAt: DateTime!
}
```

**Acceptance Criteria:**
- [ ] `cueLists` query returns lightweight summaries
- [ ] `cueList` query paginates cues correctly
- [ ] `includeSceneDetails=false` improves performance
- [ ] `cue` query works for single cue lookup
- [ ] Tests cover pagination and performance
- [ ] Existing cue mutations still work

---

#### Task 1.5: Search Functionality (P2) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.2, 1.3
**Estimated Effort:** 4-5 hours
**Branch:** `feature/graphql-search`

**Files to modify:**
- `src/graphql/schema/search.graphql` (new)
- `src/graphql/resolvers/search.ts` (new)
- `src/__tests__/graphql/search.test.ts` (new)

**Changes:**
1. Add search queries for fixtures, scenes, and cues
2. Implement text search using database capabilities
3. Support combined filters and search

**GraphQL Schema Changes:**
```graphql
type Query {
  # Search fixtures by name, manufacturer, model
  searchFixtures(
    projectId: ID!
    query: String!
    filter: FixtureFilterInput
    page: Int = 1
    perPage: Int = 50
  ): FixtureInstancePage!

  # Search scenes by name, description
  searchScenes(
    projectId: ID!
    query: String!
    filter: SceneFilterInput
    page: Int = 1
    perPage: Int = 50
  ): ScenePage!

  # Search cues by name, notes
  searchCues(
    cueListId: ID!
    query: String!
    page: Int = 1
    perPage: Int = 50
  ): CuePage!
}
```

**Acceptance Criteria:**
- [ ] Search is case-insensitive
- [ ] Search works across multiple fields
- [ ] Can combine search with filters
- [ ] Performance acceptable with large datasets
- [ ] Tests cover various search scenarios

---

#### Task 1.6: Relationship Queries (P3) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.2, 1.3, 1.4
**Estimated Effort:** 3-4 hours
**Branch:** `feature/graphql-relationships`

**Files to modify:**
- `src/graphql/schema/relationships.graphql` (new)
- `src/graphql/resolvers/relationships.ts` (new)
- `src/__tests__/graphql/relationships.test.ts` (new)

**Changes:**
1. Add queries to find where fixtures/scenes are used
2. Add scene comparison functionality
3. Optimize queries for performance

**GraphQL Schema Changes:**
```graphql
type FixtureUsage {
  fixtureId: ID!
  fixtureName: String!
  scenes: [SceneSummary!]!
  cues: [CueUsageSummary!]!
}

type CueUsageSummary {
  cueId: ID!
  cueNumber: Float!
  cueName: String!
  cueListId: ID!
  cueListName: String!
}

type SceneUsage {
  sceneId: ID!
  sceneName: String!
  cues: [CueUsageSummary!]!
}

type SceneDifference {
  fixtureId: ID!
  fixtureName: String!
  scene1Values: [Int!]!
  scene2Values: [Int!]!
  differenceType: DifferenceType!
}

enum DifferenceType {
  VALUES_CHANGED
  ONLY_IN_SCENE1
  ONLY_IN_SCENE2
}

type SceneComparison {
  scene1: SceneSummary!
  scene2: SceneSummary!
  differences: [SceneDifference!]!
  identicalFixtureCount: Int!
  differentFixtureCount: Int!
}

type Query {
  # Find where a fixture is used
  fixtureUsage(fixtureId: ID!): FixtureUsage!

  # Find where a scene is used
  sceneUsage(sceneId: ID!): SceneUsage!

  # Compare two scenes
  compareScenes(sceneId1: ID!, sceneId2: ID!): SceneComparison!
}
```

**Acceptance Criteria:**
- [ ] Usage queries are performant
- [ ] Scene comparison accurately identifies differences
- [ ] Tests cover various scenarios
- [ ] Edge cases handled (deleted scenes, etc.)

---

#### Task 1.7: Clone/Utility Mutations (P3) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Task 1.3
**Estimated Effort:** 2-3 hours
**Branch:** `feature/graphql-utilities`

**Files to modify:**
- `src/graphql/schema/scene.graphql`
- `src/graphql/resolvers/scene.ts`
- `src/__tests__/graphql/scene.test.ts`

**Changes:**
1. Add `cloneScene` mutation
2. Ensure it copies all fixture values correctly

**GraphQL Schema Changes:**
```graphql
type Mutation {
  # Clone an existing scene
  cloneScene(sceneId: ID!, newName: String!): Scene!
}
```

**Acceptance Criteria:**
- [ ] Cloned scene has all fixture values from original
- [ ] New scene has unique ID and specified name
- [ ] Tests verify complete cloning
- [ ] Performance acceptable with large scenes

---

### Phase 2: MCP Server Implementation (lacylights-mcp)

All MCP work happens in `lacylights-mcp` repository.

#### Task 2.1: MCP Pagination Helpers (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Task 1.2 (as reference)
**Estimated Effort:** 2 hours
**Branch:** `feature/mcp-pagination-helpers`

**Files to create/modify:**
- `src/utils/pagination.ts` (new)
- `src/types/pagination.ts` (new)

**Changes:**
1. Create reusable pagination types
2. Create helper functions for formatting pagination responses
3. Add validation for page parameters

**Code Structure:**
```typescript
// src/types/pagination.ts
export interface PaginationParams {
  page?: number;
  perPage?: number;
}

export interface PaginationInfo {
  total: number;
  page: number;
  perPage: number;
  totalPages: number;
  hasMore: boolean;
}

export interface PaginatedResponse<T> {
  items: T[];
  pagination: PaginationInfo;
}

// src/utils/pagination.ts
export function normalizePaginationParams(
  page?: number,
  perPage?: number
): { page: number; perPage: number } {
  return {
    page: Math.max(1, page || 1),
    perPage: Math.min(100, Math.max(1, perPage || 50))
  };
}

export function formatPaginationInfo(
  total: number,
  page: number,
  perPage: number
): PaginationInfo {
  const totalPages = Math.ceil(total / perPage);
  return {
    total,
    page,
    perPage,
    totalPages,
    hasMore: page < totalPages
  };
}
```

**Acceptance Criteria:**
- [ ] Pagination helpers handle edge cases
- [ ] Page/perPage validation works correctly
- [ ] Unit tests cover all helper functions
- [ ] TypeScript types are exported correctly

---

#### Task 2.2: Project Tools (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.1, 2.1
**Estimated Effort:** 3 hours
**Branch:** `feature/mcp-project-tools`

**Files to create/modify:**
- `src/tools/project.ts` (modify existing or create)
- `src/__tests__/tools/project.test.ts`

**Changes:**
1. Implement `get_project` tool (lightweight metadata only)
2. Implement `list_projects` tool
3. Update tool descriptions with usage guidance
4. Add tests

**Tool Definitions:**
```typescript
{
  name: "get_project",
  description: `Get high-level project information including metadata and counts.

  Returns:
  - Project metadata (id, name, description)
  - Resource counts (fixtureCount, sceneCount, cueListCount)
  - Universe count
  - Timestamps

  Does NOT include:
  - Fixture details (use list_fixtures)
  - Scene details (use list_scenes)
  - Cue list details (use list_cue_lists)

  Use this tool first to understand project scope before drilling down.`,
  inputSchema: {
    type: "object",
    properties: {
      projectId: {
        type: "string",
        description: "Project ID to retrieve"
      }
    },
    required: ["projectId"]
  }
}

{
  name: "list_projects",
  description: `List all projects with optional detail level.

  Parameters:
  - includeDetails: When true, includes counts for each project. Default false.

  Use includeDetails=false for quick project listing.
  Use includeDetails=true when you need to understand project sizes.`,
  inputSchema: {
    type: "object",
    properties: {
      includeDetails: {
        type: "boolean",
        description: "Include fixture/scene/cue counts",
        default: false
      }
    }
  }
}
```

**Acceptance Criteria:**
- [ ] Tools call correct GraphQL queries
- [ ] Error handling is robust
- [ ] Tool descriptions clearly guide LLM usage
- [ ] Tests cover success and error cases
- [ ] Response format matches documentation

---

#### Task 2.3: Fixture Tools (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.2, 2.1
**Estimated Effort:** 4-5 hours
**Branch:** `feature/mcp-fixture-tools`

**Files to create/modify:**
- `src/tools/fixtures.ts` (modify existing)
- `src/__tests__/tools/fixtures.test.ts`

**Changes:**
1. Implement `list_fixtures` tool with pagination
2. Implement `get_fixture` tool for single fixture
3. Keep existing mutation tools (create/update/delete/bulk)
4. Update tool descriptions

**Tool Definitions:**
```typescript
{
  name: "list_fixtures",
  description: `List fixtures in a project with pagination and filtering.

  Returns lightweight fixture information:
  - Basic metadata (id, name, manufacturer, model, type)
  - DMX addressing (universe, startChannel, channelCount)
  - Tags

  Does NOT include:
  - Full channel definitions (use get_fixture for that)
  - Scene usage (use get_fixture_usage)

  Pagination:
  - Default: 50 items per page
  - Max: 100 items per page
  - Use pagination.hasMore to check if more results exist

  Filtering:
  - type: Filter by fixture type (LED_PAR, MOVING_HEAD, etc.)
  - universe: Filter by DMX universe
  - tags: Filter by tags (array)
  - manufacturer: Filter by manufacturer name
  - model: Filter by model name

  Example workflow:
  1. list_fixtures(projectId, page=1) - Get first page
  2. If pagination.hasMore, call with page=2, etc.`,
  inputSchema: {
    type: "object",
    properties: {
      projectId: { type: "string" },
      page: { type: "number", default: 1 },
      perPage: { type: "number", default: 50 },
      filter: {
        type: "object",
        properties: {
          type: { type: "string" },
          universe: { type: "number" },
          tags: { type: "array", items: { type: "string" } },
          manufacturer: { type: "string" },
          model: { type: "string" }
        }
      }
    },
    required: ["projectId"]
  }
}
```

**Acceptance Criteria:**
- [ ] Pagination works correctly
- [ ] All filters work independently and combined
- [ ] Error messages are clear
- [ ] Tool descriptions guide LLM usage patterns
- [ ] Tests cover pagination, filtering, errors

---

#### Task 2.4: Scene Tools (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.3, 2.1
**Estimated Effort:** 4-5 hours
**Branch:** `feature/mcp-scene-tools`

**Files to create/modify:**
- `src/tools/scenes.ts` (modify existing)
- `src/__tests__/tools/scenes.test.ts`

**Changes:**
1. Implement `list_scenes` tool with pagination
2. Implement `get_scene` tool with optional fixture values
3. Implement `get_scene_fixtures` tool for fixture summary
4. Keep existing mutation tools
5. Update tool descriptions

**Tool Definitions:**
```typescript
{
  name: "list_scenes",
  description: `List scenes in a project with pagination and filtering.

  Returns lightweight scene summaries:
  - Metadata (id, name, description)
  - Fixture count
  - Timestamps

  Does NOT include:
  - Fixture values (use get_scene for that)
  - Usage information (use get_scene_usage)

  This is the most efficient way to browse available scenes.

  Filtering:
  - nameContains: Filter by scene name (case-insensitive)
  - usesFixture: Filter to scenes using specific fixture ID

  Sorting:
  - name: Alphabetical by name
  - createdAt: Oldest first (default)
  - updatedAt: Recently modified first`,
  inputSchema: { /* ... */ }
}

{
  name: "get_scene",
  description: `Get full details for a specific scene.

  Parameters:
  - sceneId: Scene to retrieve
  - includeFixtureValues: Include all DMX channel values (default: true)

  Set includeFixtureValues=false if you only need to know which fixtures
  are in the scene, not their specific values. This is much faster for
  large scenes.

  Use get_scene_fixtures instead if you only need fixture metadata.`,
  inputSchema: { /* ... */ }
}

{
  name: "get_scene_fixtures",
  description: `Get just the fixtures used in a scene without their values.

  Returns:
  - Fixture IDs, names, and types

  This is the fastest way to understand scene composition without
  loading full DMX channel data.

  Use cases:
  - "Which fixtures does this scene use?"
  - "What type of fixtures are in this scene?"
  - Quick scene composition analysis`,
  inputSchema: { /* ... */ }
}
```

**Acceptance Criteria:**
- [ ] All three tools work correctly
- [ ] `includeFixtureValues` parameter improves performance
- [ ] Pagination and filtering work
- [ ] Tool descriptions guide correct usage
- [ ] Tests cover all scenarios

---

#### Task 2.5: Cue List Tools (P1) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.4, 2.1
**Estimated Effort:** 3-4 hours
**Branch:** `feature/mcp-cuelist-tools`

**Files to create/modify:**
- `src/tools/cueLists.ts` (modify existing)
- `src/__tests__/tools/cueLists.test.ts`

**Changes:**
1. Implement `list_cue_lists` tool
2. Modify `get_cue_list_details` to support pagination
3. Implement `get_cue` tool
4. Keep existing mutation/playback tools
5. Update tool descriptions

**Tool Definitions:**
```typescript
{
  name: "list_cue_lists",
  description: `List all cue lists in a project.

  Returns lightweight summaries:
  - Metadata (id, name, description)
  - Cue count
  - Total duration
  - Loop setting

  Does NOT include:
  - Individual cues (use get_cue_list_details)
  - Scene details (use get_scene)

  Note: Projects typically have < 10 cue lists, so no pagination needed.`,
  inputSchema: { /* ... */ }
}

{
  name: "get_cue_list_details",
  description: `Get cue list with its cues, optionally paginated.

  Parameters:
  - cueListId: Cue list to retrieve
  - page: Page number (default: 1)
  - perPage: Items per page (default: 50)
  - includeSceneDetails: Include full scene data for each cue (default: false)

  By default, each cue includes sceneId and sceneName but not full scene
  fixture values. Set includeSceneDetails=true only if you need full scene
  data for every cue (this can be very large).

  For large cue lists (50+ cues), use pagination to avoid context overflow.`,
  inputSchema: { /* ... */ }
}
```

**Acceptance Criteria:**
- [ ] Pagination works for large cue lists
- [ ] `includeSceneDetails` parameter works correctly
- [ ] All existing cue mutations still work
- [ ] Tool descriptions are clear
- [ ] Tests cover pagination and options

---

#### Task 2.6: Search Tools (P2) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.5, 2.3, 2.4
**Estimated Effort:** 3 hours
**Branch:** `feature/mcp-search-tools`

**Files to create/modify:**
- `src/tools/search.ts` (new)
- `src/__tests__/tools/search.test.ts`

**Changes:**
1. Implement `search_fixtures` tool
2. Implement `search_scenes` tool
3. Implement `search_cues` tool
4. Add comprehensive tool descriptions

**Acceptance Criteria:**
- [ ] All search tools work correctly
- [ ] Can combine search with filters
- [ ] Tool descriptions explain when to use search vs list
- [ ] Tests cover various search scenarios

---

#### Task 2.7: Relationship Tools (P3) 🔴 Not Started
**Owner:** TBD
**Dependencies:** Tasks 1.6, 2.3, 2.4
**Estimated Effort:** 3 hours
**Branch:** `feature/mcp-relationship-tools`

**Files to create/modify:**
- `src/tools/relationships.ts` (new)
- `src/__tests__/tools/relationships.test.ts`

**Changes:**
1. Implement `get_fixture_usage` tool
2. Implement `get_scene_usage` tool
3. Implement `compare_scenes` tool
4. Add comprehensive tool descriptions

**Acceptance Criteria:**
- [ ] All relationship tools work correctly
- [ ] Tool descriptions explain use cases
- [ ] Tests cover various scenarios
- [ ] Error handling for missing resources

---

#### Task 2.8: Deprecate Old Tools (P4) 🔴 Not Started
**Owner:** TBD
**Dependencies:** All Phase 2 tasks
**Estimated Effort:** 2 hours
**Branch:** `feature/mcp-deprecate-old-tools`

**Files to modify:**
- `src/tools/project.ts`
- `src/tools/fixtures.ts`
- `src/index.ts`

**Changes:**
1. Remove `get_project_details` tool completely
2. Remove `get_fixture_inventory` tool completely
3. Update any other tools that returned too much data
4. Update index to reflect new tool exports
5. Update README with migration guide

**Acceptance Criteria:**
- [ ] Old tools are completely removed
- [ ] No references to old tools in codebase
- [ ] Migration guide explains what replaced what
- [ ] All tests pass with old tools removed

---

### Phase 3: Documentation & Testing

#### Task 3.1: Update Documentation (P4) 🔴 Not Started
**Owner:** TBD
**Dependencies:** All Phase 2 tasks
**Estimated Effort:** 3-4 hours
**Branch:** `feature/update-documentation`

**Files to create/modify:**
- `lacylights-mcp/README.md`
- `lacylights-mcp/docs/TOOL_USAGE_GUIDE.md` (new)
- `lacylights-mcp/docs/MIGRATION_GUIDE.md` (new)
- `lacylights/README.md`

**Changes:**
1. Update main README with new API overview
2. Create comprehensive tool usage guide with examples
3. Create migration guide explaining old → new tool mappings
4. Add performance tips for large projects
5. Add example workflows for common tasks

**Acceptance Criteria:**
- [ ] README clearly explains new API structure
- [ ] Usage guide has examples for all major workflows
- [ ] Migration guide covers all replaced tools
- [ ] Documentation is accurate and up-to-date

---

#### Task 3.2: Integration Testing (P4) 🔴 Not Started
**Owner:** TBD
**Dependencies:** All Phase 2 tasks
**Estimated Effort:** 4-5 hours
**Branch:** `feature/integration-tests`

**Files to create/modify:**
- `lacylights-mcp/src/__tests__/integration/large-project.test.ts` (new)
- `lacylights-mcp/src/__tests__/integration/workflows.test.ts` (new)

**Changes:**
1. Create test with large project (500 fixtures, 100 scenes)
2. Test pagination across all list tools
3. Test common workflows end-to-end
4. Measure and document performance improvements
5. Test context window usage with large projects

**Test Scenarios:**
```typescript
describe('Large Project Performance', () => {
  // Setup project with 500 fixtures, 100 scenes

  test('list_fixtures uses <1000 tokens', async () => {
    // Measure token usage of list_fixtures response
  });

  test('get_project + list_scenes uses <2000 tokens', async () => {
    // Measure combined token usage
  });

  test('can page through all fixtures efficiently', async () => {
    // Test pagination through 500 fixtures
  });
});

describe('Common Workflows', () => {
  test('add cue to cue list', async () => {
    // 1. list_cue_lists
    // 2. search_scenes
    // 3. get_cue_list_details
    // 4. add_cue_to_list
  });

  test('find where fixture is used', async () => {
    // 1. search_fixtures
    // 2. get_fixture_usage
  });

  test('clone and modify scene', async () => {
    // 1. search_scenes
    // 2. clone_scene
    // 3. update_scene
  });
});
```

**Acceptance Criteria:**
- [ ] Large project tests pass with acceptable performance
- [ ] Token usage is significantly reduced vs old API
- [ ] Common workflows are documented and tested
- [ ] Performance metrics are documented

---

#### Task 3.3: Performance Benchmarking (P4) 🔴 Not Started
**Owner:** TBD
**Dependencies:** All Phase 2 tasks
**Estimated Effort:** 2-3 hours
**Branch:** `feature/performance-benchmarks`

**Files to create/modify:**
- `scripts/benchmark-api.ts` (new, in lacylights-node)
- `scripts/measure-token-usage.ts` (new, in lacylights-mcp)
- `PERFORMANCE.md` (new, in root)

**Changes:**
1. Create benchmark script for GraphQL queries
2. Create token measurement script for MCP tools
3. Document performance characteristics
4. Compare old vs new API

**Metrics to Capture:**
- Query response time (ms)
- Response size (KB)
- Token count (for MCP responses)
- Database query count
- Context window usage percentage

**Acceptance Criteria:**
- [ ] Benchmarks show performance improvements
- [ ] Token usage significantly reduced
- [ ] Performance metrics documented
- [ ] Regression tests in place

---

## Work Assignment Strategy

### Parallel Work Streams

The following tasks can be done in parallel with NO dependencies on each other:

**Stream A - Backend Core:**
- Task 1.1 (Project Queries)
- Task 1.2 (Fixture Pagination)
- Task 1.3 (Scene Pagination)
- Task 1.4 (Cue List Pagination)

**Stream B - Backend Advanced:**
- Task 1.5 (Search) - depends on Stream A
- Task 1.6 (Relationships) - depends on Stream A
- Task 1.7 (Clone/Utilities) - depends on Task 1.3

**Stream C - MCP Core:**
- Task 2.1 (Pagination Helpers) - independent
- Task 2.2 (Project Tools) - depends on Task 1.1
- Task 2.3 (Fixture Tools) - depends on Tasks 1.2, 2.1
- Task 2.4 (Scene Tools) - depends on Tasks 1.3, 2.1
- Task 2.5 (Cue List Tools) - depends on Tasks 1.4, 2.1

**Stream D - MCP Advanced:**
- Task 2.6 (Search Tools) - depends on Task 1.5 and Stream C
- Task 2.7 (Relationship Tools) - depends on Task 1.6 and Stream C

**Stream E - Cleanup:**
- Task 2.8 (Deprecate Old Tools) - depends on all Phase 2
- Task 3.1 (Documentation) - depends on all Phase 2
- Task 3.2 (Integration Testing) - depends on all Phase 2
- Task 3.3 (Performance Benchmarking) - depends on all Phase 2

### Recommended Agent Assignment

**4 Agents Working in Parallel:**

1. **Agent A - Backend Core:** Tasks 1.1, 1.2, 1.3, 1.4 (sequential within agent)
2. **Agent B - Backend Advanced:** Tasks 1.5, 1.6, 1.7 (sequential, waits for Agent A)
3. **Agent C - MCP Core:** Tasks 2.1, 2.2, 2.3, 2.4, 2.5 (sequential within agent, waits for Agent A)
4. **Agent D - MCP Advanced:** Tasks 2.6, 2.7 (sequential, waits for Agents B and C)

Then sequentially:
5. **Agent E - Cleanup:** Tasks 2.8, 3.1, 3.2, 3.3 (sequential, waits for all)

**2 Agents Working in Parallel:**

1. **Agent A - All Backend:** Tasks 1.1→1.7 (sequential)
2. **Agent B - All MCP:** Tasks 2.1→2.7 (sequential, waits for Agent A tasks as needed)

Then sequentially:
3. **Agent C - Cleanup:** Tasks 2.8→3.3

## Status Tracking

Update this section as work progresses:

### Completed Tasks
- [ ] None yet

### In Progress Tasks
- [ ] None yet

### Blocked Tasks
- [ ] None yet

## Testing Strategy

### Unit Tests
- Each GraphQL resolver must have unit tests
- Each MCP tool must have unit tests
- Target: >80% code coverage

### Integration Tests
- Test complete workflows across backend and MCP
- Test with realistic large projects
- Measure token usage and performance

### Performance Tests
- Benchmark query response times
- Measure token usage for various operations
- Compare against old API

## Success Criteria

- [ ] All Phase 1 backend tasks complete with tests passing
- [ ] All Phase 2 MCP tasks complete with tests passing
- [ ] Documentation is comprehensive and accurate
- [ ] Performance benchmarks show improvement
- [ ] Token usage reduced by >80% for large projects
- [ ] All existing functionality still works
- [ ] No regressions in existing tests

## Notes

- Each agent should create a feature branch from main
- All tests must pass before merging
- Code reviews should focus on API consistency and documentation
- Performance should be measured at each step
- Context window usage is the primary metric to optimize

## Communication

Each agent working on a task should:
1. Update the task status in this document when starting
2. Create detailed commit messages referencing this plan
3. Document any deviations or issues encountered
4. Update task status when complete
5. Note any blocked dependencies

## References

- [GraphQL Best Practices](https://graphql.org/learn/best-practices/)
- [Pagination Patterns](https://www.apollographql.com/docs/apollo-server/data/resolvers/#pagination)
- [MCP Server Documentation](https://modelcontextprotocol.io/)
