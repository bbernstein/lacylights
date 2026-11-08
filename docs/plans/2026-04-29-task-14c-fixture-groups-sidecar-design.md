# Task 14c — Fixture Groups & Sidecar Application — Design

**Date:** 2026-04-29
**Repo:** `lacylights-go`
**Status:** Design complete, awaiting implementation plan
**Parent project:** Eos ASCII import/export (see `2026-04-28-eos-ascii-importer-exporter-design.md`)

## Context

Phases 1–5 of the Eos ASCII importer/exporter shipped through PR #76, #77, #166, #178, #27, #78, and #167 (all merged). One deferred task remains: **Task 14c**, which closes the round-trip data-loss gap for `$Group` blocks and `$$ LACYLIGHTS:` sidecar records. Today the importer parses both but discards the data with `WarnGroupsSkipped` and `WarnSidecarUnresolved` informational warnings.

This design adds a real `FixtureGroup` model, exposes it as a first-class GraphQL feature, and wires the sidecar's `look_board` and `fade_behavior` records back into the database during import — restoring round-trip integrity for the Eos ASCII format.

## Goals

1. EOS `$Group` blocks → persisted `FixtureGroup` rows with members.
2. Sidecar `look_board` records → reconstructed `LookBoard`s with buttons resolved to `Look` IDs.
3. Sidecar `fade_behavior` records → applied to `InstanceChannel.FadeBehavior` per offset.
4. EOS round-trip preserves group structure, look-board layout, and per-channel fade behavior.
5. `FixtureGroup` is a first-class LacyLights feature with full GraphQL CRUD + bulk mutations.

## Non-goals

- MCP tools for `FixtureGroup` (follow-up).
- Frontend UI for managing groups or look boards (follow-up).
- `synth_def` sidecar emission on the writer side (reader tolerates it; v1 writer skips).
- User-editable `RefID`s (frozen post-creation by design).
- Reverse migrations / rollback (codebase doesn't have these).

## Architecture

Four pieces, all in one PR against `lacylights-go`:

1. **`FixtureGroup` model + repository + GraphQL.** Two new tables (`fixture_groups`, `fixture_group_members`), a new repository, full CRUD + bulk + membership ops in GraphQL.
2. **`RefID` column** on `FixtureInstance`, `FixtureDefinition`, `Look`, `LookBoard`. Project-scoped unique (global for `FixtureDefinition`, since defs are shared). Defaults to row ID at create; importer can override to enable round-trip resolution. Read-only via GraphQL.
3. **Mapper integration.** `applyGroups` resolves EOS channel numbers → fixture IDs and persists groups. `applySidecar` reconstructs `LookBoard`s and applies `fade_behavior` overrides.
4. **Writer integration.** Emits `$Group` blocks (using persisted `EosNumber`, auto-assigning when missing). Emits sidecar `look_board` and `fade_behavior` records using `RefID`s.

## Data model

### `FixtureGroup`

```go
type FixtureGroup struct {
    ID           string    `gorm:"column:id;primaryKey"`
    ProjectID    string    `gorm:"column:project_id;index;not null"`
    Name         string    `gorm:"column:name;not null"`
    Description  *string   `gorm:"column:description"`
    EosNumber    *int      `gorm:"column:eos_number"`
    RefID        string    `gorm:"column:ref_id;not null"`
    ProjectOrder *int      `gorm:"column:project_order"`

    CreatedAt time.Time `gorm:"column:created_at;autoCreateTime"`
    UpdatedAt time.Time `gorm:"column:updated_at;autoUpdateTime"`

    Members []FixtureGroupMember `gorm:"foreignKey:GroupID;constraint:OnDelete:CASCADE"`
}
```

Indexes:
- Unique `(project_id, ref_id)`.
- Partial unique `(project_id, eos_number) WHERE eos_number IS NOT NULL` (SQLite supports partial indexes).

### `FixtureGroupMember`

```go
type FixtureGroupMember struct {
    GroupID   string `gorm:"column:group_id;primaryKey"`
    FixtureID string `gorm:"column:fixture_id;primaryKey"`
    Order     int    `gorm:"column:order;not null"`
}
```

Composite PK `(GroupID, FixtureID)`. `FixtureID` FK cascades on fixture delete.

### `RefID` column on existing models

Added to `FixtureInstance`, `FixtureDefinition`, `Look`, `LookBoard`:

```go
RefID string `gorm:"column:ref_id;not null"`
```

Uniqueness:
- `FixtureInstance`, `Look`, `LookBoard`: project-scoped — unique `(project_id, ref_id)`.
- `FixtureDefinition`: globally unique `ref_id` (definitions are shared across projects).

Lifecycle:
- Default at row creation = the row's `ID` (CUID). Repository helpers set this in `Create*` if caller leaves blank.
- Importer overrides with deterministic, EOS-derived values for re-importable entities (see Mapper section).
- Read-only after creation. No mutation path exposed.
- Backfill on first deploy: `UPDATE … SET ref_id = id WHERE ref_id IS NULL OR ref_id = ''` for each table.

## Repository surface

### `FixtureGroupRepository` (new)

```go
Create(ctx, group)
CreateWithMembers(ctx, group, fixtureIDs)
FindByID(ctx, id)
FindByProjectID(ctx, projectID)
FindByRefID(ctx, projectID, refID)
FindByEosNumber(ctx, projectID, eosNumber)
Update(ctx, group)
Delete(ctx, id)
GetMembers(ctx, groupID)
SetMembers(ctx, groupID, fixtureIDs)             // transactional replace
AddMembers(ctx, groupID, fixtureIDs)
RemoveMembers(ctx, groupID, fixtureIDs)
ReorderMembers(ctx, groupID, fixtureIDs)
AssignNextEosNumber(ctx, projectID) → int        // MAX(eos_number)+1
```

### `FixtureRepository` additions

```go
FindInstanceByRefID(ctx, projectID, refID) → (*FixtureInstance, error)   // ErrNotFound on miss
UpdateInstanceChannelFadeBehavior(ctx, instanceID, offset, behavior)     // ErrChannelOffsetNotFound on miss
FindDefinitionByRefID(ctx, refID) → (*FixtureDefinition, error)          // global lookup
```

### `LookRepository` additions

```go
MapByRefID(ctx, projectID, refIDs []string) → map[string]string          // present-only map
FindByRefID(ctx, projectID, refID) → (*Look, error)
```

### `LookBoardRepository` additions

```go
FindByRefID(ctx, projectID, refID) → (*LookBoard, error)
```

### Test helpers

```go
(d *testDeps) MustListGroupsByProject(t, projectID) []FixtureGroup
(d *testDeps) MustListLookBoardsByProject(t, projectID) []LookBoard
(d *testDeps) MustGetInstanceChannel(t, instanceID, offset) InstanceChannel
```

## Mapper changes (importer)

### `applyGroups`

```go
func (m *Mapper) applyGroups(ctx, projectID, show *Show, chToFix map[int]string,
                              groupsCount *int, warn *Collector) error
```

Logic:
1. For each `g := show.Groups`, resolve members from `g.Channels` via `chToFix`. Channels missing from the map → `WarnGroupChannelUnresolved` (severity Warning), continue with remaining channels.
2. Determine name: `g.Label` → deref `g.UnicodeText` → `fmt.Sprintf("Group %s", g.Number)`.
3. Parse `g.Number` as int; on parse error leave `EosNumber = nil`.
4. Build `FixtureGroup{ProjectID, Name, EosNumber, RefID: <auto = ID>}` and call `CreateWithMembers`.
5. Increment `*groupsCount` on success.

Idempotency: re-importing the same `.asc` into the same project finds an existing group via `FindByEosNumber`; if present, `SetMembers` and `Update(name)` instead of creating a duplicate.

### `applySidecar`

```go
func (m *Mapper) applySidecar(ctx, projectID, sc Sidecar, warn *Collector) error
```

Order:

1. **Look boards.** Collect all `LookRefID`s across all boards' buttons; one `MapByRefID` call. For each board:
   - Build `[]LookBoardButton` from `lb.Buttons`. Missing `LookRefID` → `WarnSidecarUnresolved {kind:"look_board_button", lookRefId, boardRefId}`, skip the button.
   - `FindByRefID(projectID, lb.RefID)` for idempotency: update if present, else `Create` with `RefID = lb.RefID`.

2. **Fade behaviors.** For each record:
   - `FindInstanceByRefID(projectID, fb.InstanceRefID)`; missing → `WarnSidecarUnresolved {kind:"fade_behavior", instanceRefId}`.
   - For each `(offset, behavior)`: validate `behavior ∈ {"FADE","SNAP","SNAP_END"}`; invalid → warn and skip. Call `UpdateInstanceChannelFadeBehavior`; `ErrChannelOffsetNotFound` → `WarnSidecarUnresolved {kind:"fade_behavior_offset", instanceRefId, offset}` and continue.

3. **Synth defs.** Advisory only. `FindDefinitionByRefID` for log-only validation; missing → informational `WarnSidecarUnresolved {kind:"synth_def", defRefId}`.

### Apply() callsites

Existing call sites at lines 169 and 172 of `mapper.go` updated to pass the existing `eosChannelToInstanceID` map (built at line 93) into `applyGroups`.

### Warning code additions

- New: `WarnGroupChannelUnresolved`.
- Existing `WarnSidecarUnresolved` extended with structured `kind` field for FE grouping.

### Deterministic RefID derivation

This is the key change that makes round-trips work.

When the importer creates entities from EOS data, it sets `RefID` deterministically:

- `FixtureInstance.RefID = fmt.Sprintf("ch-%d", eosChannel)`
- `Look.RefID = fmt.Sprintf("cue-%s-%s", cueListNumber, cueNumber)` for cue-derived looks, where `cueListNumber` is the EOS cue list integer (the same value emitted as `$CueList <n>` in the file) and `cueNumber` is the EOS cue number string (e.g. `"1.5"`). For palette-derived looks: `fmt.Sprintf("palette-%s-%s", paletteKind, paletteNumber)` where `paletteKind ∈ {"color","beam","focus","intensity","preset"}`.
- `FixtureDefinition.RefID = fmt.Sprintf("def-%s-%s", manufacturer, model)` for matched defs; for synthesized defs derive from channel fingerprint.
- `LookBoard.RefID` = the row's CUID (LookBoards have no EOS analog; sidecar carries the LacyLights-side stable ID as authored — round-trip resolves only when re-importing into the same project, which is the documented limitation).

`CueList` does **not** get a RefID column — it isn't referenced from the sidecar, and its EOS-native identifier (the cue list number) is already carried in `CueList.Number`. Look RefIDs use that number directly rather than introducing a sympathetic chain of refIds.

The exporter writes the same `RefID` values it reads back. Same input → same RefID, regardless of CUID churn. This is what makes the sidecar resolve cleanly when re-importing into a fresh project.

## Writer changes (exporter)

### `$Group` block emission

1. `groups, _ := fixtureGroupRepo.FindByProjectID(ctx, projectID)`.
2. Sort by `(EosNumber NULLS LAST, Name, ID)` for determinism.
3. Walk sorted groups; for any with `EosNumber == nil`, assign `MAX(existing) + 1` and persist via `Update`. *This mutates DB state during export* — intentional, so EOS numbers stay stable across exports. Comment in writer explains why.
4. For each group: skip if empty (`WarnExportEmptyGroupSkipped`, severity Info). Otherwise emit:

   ```
   $Group <eosNumber>
   Text <name>
   [$$UText <utf16le-hex if non-ASCII>]
   <chan> [<chan> ...]
   ```

   Channels in member-`Order` order, mapped to EOS channel numbers via the existing instance→channel map.

### Sidecar emission

1. **`fade_behavior`.** For each `FixtureInstance`, load `InstanceChannel`s, filter to `FadeBehavior != "FADE"`. If any non-default, emit one record. Channels sorted by offset.
2. **`look_board`.** For each `LookBoard`, emit one record. Buttons sorted by `(y, x, lookRefId)`.
3. **`synth_def`.** Skipped in v1; documented as a known limitation in `IMPORT_EXPORT_FORMATS.md`.
4. All sidecar records sorted by `kind`, then primary refId. `TestExport_Deterministic` covers this.

## GraphQL surface

### `FixtureGroup` type

```graphql
type FixtureGroup {
  id: ID!
  refId: String!
  name: String!
  description: String
  eosNumber: Int
  projectOrder: Int
  project: Project!
  fixtures: [FixtureInstance!]!         # ordered by membership.Order
  createdAt: DateTime!
  updatedAt: DateTime!
}
```

### Inputs

```graphql
input CreateFixtureGroupInput {
  projectId: ID!
  name: String!
  description: String
  fixtureIds: [ID!]!
  eosNumber: Int
}

input UpdateFixtureGroupInput {
  id: ID!
  name: String
  description: String
  eosNumber: Int
  projectOrder: Int
}

input ReorderFixturesInGroupInput {
  groupId: ID!
  fixtureIds: [ID!]!
}
```

### Queries

```graphql
extend type Query {
  fixtureGroup(id: ID!): FixtureGroup
  fixtureGroups(projectId: ID!): [FixtureGroup!]!
}
```

### Mutations

```graphql
extend type Mutation {
  createFixtureGroup(input: CreateFixtureGroupInput!): FixtureGroup!
  updateFixtureGroup(input: UpdateFixtureGroupInput!): FixtureGroup!
  deleteFixtureGroup(id: ID!): Boolean!

  addFixturesToGroup(groupId: ID!, fixtureIds: [ID!]!): FixtureGroup!
  removeFixturesFromGroup(groupId: ID!, fixtureIds: [ID!]!): FixtureGroup!
  reorderFixturesInGroup(input: ReorderFixturesInGroupInput!): FixtureGroup!

  bulkCreateFixtureGroups(inputs: [CreateFixtureGroupInput!]!): [FixtureGroup!]!
  bulkUpdateFixtureGroups(inputs: [UpdateFixtureGroupInput!]!): [FixtureGroup!]!
  bulkDeleteFixtureGroups(ids: [ID!]!): Int!
}
```

### `RefID` exposure on existing types (read-only)

```graphql
extend type FixtureInstance       { refId: String! }
extend type FixtureDefinition     { refId: String! }
extend type Look                  { refId: String! }
extend type LookBoard             { refId: String! }
```

### Auth

Every group query/mutation gates via `ensureProjectAccess(projectID)` (existing helper from the multi-tenant work). For mutations referencing a group by `id`, load the group first to get its `ProjectID`.

### Resolver layout

- gqlgen-generated stubs land in `schema.resolvers.go` as usual.
- Helper implementations in a new `fixture_group_resolvers.go` (matches the `auth_resolvers.go` / `group_admin_resolvers.go` separation pattern).

### Dataloaders

v1 uses straight per-resolution loads on `FixtureGroup.fixtures`. Revisit if perf becomes an issue; the codebase doesn't yet use dataloaders consistently.

## Migration & backfill

In `cmd/server/main.go`:

1. **Phase 1** (existing, unchanged): auth tables without FK.
2. **Phase 2** (existing FK list): adds `&FixtureGroup{}` after `FixtureInstance`, then `&FixtureGroupMember{}` after `FixtureGroup`.
3. **Phase 2.5** (new): `backfillRefIDs(db)` runs four idempotent `UPDATE … SET ref_id = id WHERE ref_id IS NULL OR ref_id = ''` statements (one per affected table).
4. **Phase 3** (new): `db.Migrator().CreateIndex(...)` for the new unique indexes — idempotent in SQLite via `CREATE UNIQUE INDEX IF NOT EXISTS`.

Test setup additions:
- `internal/services/import_eos/testdeps_test.go` AutoMigrate adds `&FixtureGroup{}`, `&FixtureGroupMember{}`.
- `internal/database/repositories/repositories_test.go` AutoMigrate adds the same (per existing pattern documented in MEMORY).

Rollback: same posture as every prior migration — manual SQL if needed. Documented as a known limitation.

## Testing strategy

### Repository tests

- New: `fixture_group_repository_test.go` — `Create*`, `FindBy*`, `SetMembers`, `Add/RemoveMembers`, `ReorderMembers`, `AssignNextEosNumber`, cascade-on-fixture-delete, unique-constraint enforcement.
- Additions to `fixture_repository_test.go` — `FindInstanceByRefID`, `UpdateInstanceChannelFadeBehavior` (success + `ErrChannelOffsetNotFound`), `FindDefinitionByRefID`.
- Additions to `look_repository_test.go` — `MapByRefID`, `FindByRefID`.
- Additions to `look_board_repository_test.go` — `FindByRefID`.

### Mapper tests (in `mapper_test.go`)

- `TestMapper_GroupsCreated` — happy path (fixture: `presets_groups.asc`).
- `TestMapper_GroupChannelUnresolvedWarn` — group references an unpatched channel.
- `TestMapper_SidecarLookBoardRebuilt` — happy path (fixture: `sidecar_roundtrip.asc`).
- `TestMapper_SidecarLookBoardUnresolvedButton` — sidecar references missing `lookRefId`.
- `TestMapper_SidecarFadeBehaviorApplied` — happy path.
- `TestMapper_SidecarFadeBehaviorOffsetMissing` — sidecar references a non-existent channel offset.
- `TestMapper_SidecarSynthDefAdvisory` — unknown `defRefId`.
- `TestMapper_RefIDsDeterministic` — same input → same RefIDs across two fresh projects.
- `TestMapper_GroupsIdempotentReimport` — re-import same `.asc` into the same project.

### Writer tests

- `TestExport_GroupsEmitted`, `TestExport_EmptyGroupSkipped`, `TestExport_SidecarFadeBehavior`, `TestExport_SidecarLookBoard`, extended `TestExport_Deterministic`.

### Round-trip tests (`eos_roundtrip_test.go`)

- `TestEosRoundtrip_GroupsPreserved`, `TestEosRoundtrip_FadeBehaviorsPreserved`, `TestEosRoundtrip_LookBoardsPreserved`. Update `TestEosRoundtrip_OTBPA` to assert group count.

### GraphQL resolver tests

- New: `internal/graphql/fixture_group_resolvers_test.go` — smoke per query/mutation, auth gate, bulk variants.

### New testdata

- `testdata/groups_only.asc` — minimal patch + 3 groups, no cues.
- `testdata/sidecar_full.asc` — patch + minimal cues + sidecar with all four record types.

## Open questions resolved during brainstorming

1. **`FixtureGroup` scope.** First-class feature with full GraphQL — not just internal plumbing.
2. **RefID strategy.** New `RefID` column on four models, project-scoped unique (global for `FixtureDefinition`).
3. **Membership shape.** Junction table with `Order` column.
4. **Fade-behavior application.** Strict overwrite of listed offsets; non-listed channels untouched.
5. **Group export numbering.** Persisted `EosNumber`, auto-assigned and persisted on first export. Empty groups skipped with warning.
6. **GraphQL surface.** Full CRUD + dedicated membership ops + bulk variants. MCP tools deferred.
7. **RefID details.** Project-scoped unique; default = ID at creation; backfill via migration; read-only via GraphQL; frozen post-creation.

## Out of scope / follow-ups

1. MCP tools for `FixtureGroup` (separate PR in `lacylights-mcp`).
2. Frontend UI for managing groups.
3. Friendly-name additions in `EosImportWarningsList` for new warning codes.
4. `synth_def` sidecar emission on the writer side.
5. Dataloader-based batching for `FixtureGroup.fixtures`.
6. User-editable RefIDs.
7. Reverse-migration tooling.
8. Group-aware Look operations (model supports it; UX deferred).

## Spec / plan documents referenced

- `docs/plans/2026-04-28-eos-ascii-importer-exporter-design.md` (parent design)
- `docs/plans/2026-04-28-eos-ascii-importer-exporter-implementation.md` (parent plan; Task 14c at lines 3476–3616)
- `lacylights-go/docs/EOS_ASCII_FORMAT.md` (format reference)
- `docs/IMPORT_EXPORT_FORMATS.md` (user-facing format docs)
