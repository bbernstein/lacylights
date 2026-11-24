# Task 14c — Fixture Groups & Sidecar Application — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Task 14c — wire `$Group` blocks and `$$ LACYLIGHTS:` sidecar records back into LacyLights data via a new `FixtureGroup` model, a `RefID` column on four existing models, and full GraphQL CRUD for fixture groups. Closes the EOS round-trip data-loss gap.

**Architecture:** New `FixtureGroup` + `FixtureGroupMember` models with a junction table. New `RefID` column on `FixtureInstance`, `FixtureDefinition`, `Look`, `LookBoard` (project-scoped unique, except `FixtureDefinition` which is global). Importer assigns deterministic, EOS-derived `RefID`s so the sidecar resolves cleanly across round-trips. Exporter emits `$Group` blocks and sidecar `look_board` / `fade_behavior` records via `RefID`s.

**Tech Stack:** Go 1.21+, GORM (SQLite), gqlgen, `cuid` for IDs.

**Working directory:** `~/src/lacylights/lacylights-go`

**Spec:** `~/src/lacylights/docs/plans/2026-04-29-task-14c-fixture-groups-sidecar-design.md`

**Branch:** `feature/eos-task-14c-fixture-groups`

---

## Pre-flight

- [ ] **P1: Confirm clean working tree, then create branch off main**

```bash
cd ~/src/lacylights/lacylights-go
git status
git fetch origin
git checkout main
git pull --ff-only
git checkout -b feature/eos-task-14c-fixture-groups
```

Expected: `nothing to commit, working tree clean` after `git status`. The pre-existing `stash@{*}` from earlier sessions does **not** need to be touched (per resumption-state memory).

- [ ] **P2: Verify build + tests pass on main before starting**

```bash
make generate
ARTNET_ENABLED=false go test ./...
make lint
```

Expected: all tests pass, no lint errors. If `make generate` produces a diff, commit it before starting (it means the schema and generated code drifted — but on `main` this should be a no-op).

---

## Phase 1 — RefID column + repository foundation

Adds the `RefID` column to four existing models, idempotent backfill, unique indexes, and the new repository helper methods that the mapper and resolvers will call.

### Task 1: Add `RefID` field to four existing models

**Files:**
- Modify: `internal/database/models/models.go`

- [ ] **Step 1: Add `RefID` to `FixtureInstance`**

Find the `FixtureInstance` struct (around line 348). Add the field after `Tags`:

```go
type FixtureInstance struct {
	ID           string  `gorm:"column:id;primaryKey"`
	// ... existing fields ...
	Tags         *string `gorm:"column:tags;default:[]"`
	RefID        string  `gorm:"column:ref_id;not null;default:''"` // stable cross-roundtrip identifier; project-scoped unique via runtime index

	ProjectOrder   *int     `gorm:"column:project_order"`
	// ... rest unchanged ...
}
```

- [ ] **Step 2: Add `RefID` to `FixtureDefinition`**

Find `FixtureDefinition` (around line 290). Add the field after `IsBuiltIn`:

```go
type FixtureDefinition struct {
	ID           string `gorm:"column:id;primaryKey"`
	// ... existing fields ...
	IsBuiltIn    bool   `gorm:"column:is_built_in"`
	RefID        string `gorm:"column:ref_id;not null;default:''"` // global unique identifier for round-trip definition matching
	// ... rest unchanged ...
}
```

- [ ] **Step 3: Add `RefID` to `Look`**

Find `Look` (around line 398). Add the field after the existing `ProjectID`:

```go
type Look struct {
	ID          string  `gorm:"column:id;primaryKey"`
	// ... existing fields ...
	ProjectID   string  `gorm:"column:project_id;index;not null"`
	RefID       string  `gorm:"column:ref_id;not null;default:''"` // project-scoped stable identifier for sidecar references
	// ... rest unchanged ...
}
```

- [ ] **Step 4: Add `RefID` to `LookBoard`**

Find `LookBoard` (around line 498). Add the field after `ProjectID`:

```go
type LookBoard struct {
	ID          string  `gorm:"column:id;primaryKey"`
	// ... existing fields ...
	ProjectID   string  `gorm:"column:project_id;index;not null"`
	RefID       string  `gorm:"column:ref_id;not null;default:''"` // project-scoped stable identifier for sidecar references
	// ... rest unchanged ...
}
```

- [ ] **Step 5: Verify the file compiles**

```bash
go build ./internal/database/models/...
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add internal/database/models/models.go
git commit -m "feat(models): add RefID column to FixtureInstance, FixtureDefinition, Look, LookBoard

Adds stable, project-scoped (or globally unique for definitions) refIDs
needed for round-trip resolution by the EOS ASCII sidecar. Default = ''
at the column level; backfill and uniqueness will follow in subsequent
commits."
```

---

### Task 2: Add migration helpers — backfill + index creation

**Files:**
- Modify: `cmd/server/main.go`
- Create: `internal/database/migrations/refid_migration.go`

The backfill is in its own file so it can be unit-tested without spinning up the whole server.

- [ ] **Step 1: Create `refid_migration.go`**

```go
// Package migrations contains one-shot, idempotent schema migrations
// invoked from the server's startup AutoMigrate flow.
package migrations

import (
	"fmt"

	"gorm.io/gorm"
)

// refIDTables enumerates every table that received a ref_id column in
// task 14c. Order doesn't matter — each statement is independent.
var refIDTables = []string{
	"fixture_instances",
	"fixture_definitions",
	"looks",
	"look_boards",
}

// BackfillRefIDs copies id → ref_id for every row whose ref_id is empty.
// Idempotent: safe to run on every server start.
func BackfillRefIDs(db *gorm.DB) error {
	for _, table := range refIDTables {
		if !db.Migrator().HasTable(table) {
			continue
		}
		if !db.Migrator().HasColumn(table, "ref_id") {
			continue
		}
		stmt := fmt.Sprintf(
			`UPDATE %s SET ref_id = id WHERE ref_id IS NULL OR ref_id = ''`,
			table,
		)
		if err := db.Exec(stmt).Error; err != nil {
			return fmt.Errorf("backfill ref_id for %s: %w", table, err)
		}
	}
	return nil
}

// CreateRefIDIndexes creates the unique indexes that enforce ref_id
// uniqueness. Run after BackfillRefIDs so existing rows can satisfy the
// constraint. Uses CREATE UNIQUE INDEX IF NOT EXISTS for idempotency.
func CreateRefIDIndexes(db *gorm.DB) error {
	stmts := []struct {
		name string
		sql  string
	}{
		{
			"idx_fixture_instances_project_refid",
			`CREATE UNIQUE INDEX IF NOT EXISTS idx_fixture_instances_project_refid
				ON fixture_instances(project_id, ref_id)`,
		},
		{
			"idx_fixture_definitions_refid",
			`CREATE UNIQUE INDEX IF NOT EXISTS idx_fixture_definitions_refid
				ON fixture_definitions(ref_id)`,
		},
		{
			"idx_looks_project_refid",
			`CREATE UNIQUE INDEX IF NOT EXISTS idx_looks_project_refid
				ON looks(project_id, ref_id)`,
		},
		{
			"idx_look_boards_project_refid",
			`CREATE UNIQUE INDEX IF NOT EXISTS idx_look_boards_project_refid
				ON look_boards(project_id, ref_id)`,
		},
	}
	for _, s := range stmts {
		if err := db.Exec(s.sql).Error; err != nil {
			return fmt.Errorf("create index %s: %w", s.name, err)
		}
	}
	return nil
}
```

- [ ] **Step 2: Write a unit test for the backfill**

Create `internal/database/migrations/refid_migration_test.go`:

```go
package migrations

import (
	"testing"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func openTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	return db
}

func TestBackfillRefIDs_PopulatesEmptyRefIDs(t *testing.T) {
	db := openTestDB(t)
	if err := db.Exec(`CREATE TABLE fixture_instances (id TEXT PRIMARY KEY, project_id TEXT, ref_id TEXT)`).Error; err != nil {
		t.Fatalf("create table: %v", err)
	}
	if err := db.Exec(`INSERT INTO fixture_instances (id, project_id, ref_id) VALUES ('a','p1',''),('b','p1',NULL),('c','p1','custom')`).Error; err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := BackfillRefIDs(db); err != nil {
		t.Fatalf("backfill: %v", err)
	}

	var rows []struct {
		ID, RefID string
	}
	if err := db.Raw(`SELECT id, ref_id FROM fixture_instances ORDER BY id`).Scan(&rows).Error; err != nil {
		t.Fatalf("scan: %v", err)
	}
	want := map[string]string{"a": "a", "b": "b", "c": "custom"}
	for _, r := range rows {
		if got := r.RefID; got != want[r.ID] {
			t.Errorf("row %s: ref_id = %q, want %q", r.ID, got, want[r.ID])
		}
	}
}

func TestBackfillRefIDs_SkipsMissingTablesAndColumns(t *testing.T) {
	db := openTestDB(t)
	// No tables exist — backfill should be a no-op (no error).
	if err := BackfillRefIDs(db); err != nil {
		t.Fatalf("backfill on empty schema: %v", err)
	}
}

func TestCreateRefIDIndexes_Idempotent(t *testing.T) {
	db := openTestDB(t)
	for _, table := range refIDTables {
		if err := db.Exec(`CREATE TABLE ` + table + ` (id TEXT PRIMARY KEY, project_id TEXT, ref_id TEXT)`).Error; err != nil {
			t.Fatalf("create %s: %v", table, err)
		}
	}
	if err := CreateRefIDIndexes(db); err != nil {
		t.Fatalf("create indexes: %v", err)
	}
	// Run twice — IF NOT EXISTS should make this a no-op.
	if err := CreateRefIDIndexes(db); err != nil {
		t.Fatalf("create indexes second run: %v", err)
	}
}
```

- [ ] **Step 3: Run the tests — expect PASS**

```bash
go test ./internal/database/migrations/...
```

Expected: 3 tests pass.

- [ ] **Step 4: Wire the migration into `cmd/server/main.go`**

After the existing `tablesWithFK` loop (around line 156), add:

```go
	log.Println("Database migrations complete")

	// Task 14c: backfill ref_id columns and create unique indexes.
	// Both functions are idempotent so they're safe to run on every boot.
	if err := migrations.BackfillRefIDs(db); err != nil {
		log.Fatalf("Failed to backfill ref_ids: %v", err)
	}
	if err := migrations.CreateRefIDIndexes(db); err != nil {
		log.Fatalf("Failed to create ref_id indexes: %v", err)
	}
```

Add the import:

```go
import (
	// ... existing imports ...
	"github.com/bbernstein/lacylights-go/internal/database/migrations"
)
```

- [ ] **Step 5: Build the server to confirm wiring**

```bash
go build ./cmd/server
```

Expected: clean build.

- [ ] **Step 6: Commit**

```bash
git add internal/database/migrations/ cmd/server/main.go
git commit -m "feat(migrations): backfill RefID columns and create unique indexes

Idempotent backfill copies id → ref_id for any pre-task-14c rows that
landed before the column existed. Unique indexes ((project_id, ref_id)
on three tables, global on fixture_definitions) enforce the contract."
```

---

### Task 3: Default `RefID = ID` in repository `Create*` methods

The four affected repos already auto-assign `cuid.New()` to `ID` if blank. Mirror that pattern for `RefID`: if blank at create time, copy the `ID`.

**Files:**
- Modify: `internal/database/repositories/fixture_repository.go`
- Modify: `internal/database/repositories/look_repository.go`
- Modify: `internal/database/repositories/look_board_repository.go`

- [ ] **Step 1: Test for `LookBoardRepository.Create` defaulting RefID**

Add to `internal/database/repositories/look_board_repository_test.go` (or create the file if it doesn't exist — mirror the structure of `effect_repository_test.go`). At a minimum:

```go
func TestLookBoardRepository_Create_DefaultsRefIDToID(t *testing.T) {
	repo, _ := newLookBoardRepoForTest(t)
	board := &models.LookBoard{
		ProjectID: "p-1",
		Name:      "Top",
	}
	if err := repo.Create(context.Background(), board); err != nil {
		t.Fatalf("create: %v", err)
	}
	if board.ID == "" {
		t.Fatalf("expected ID assigned")
	}
	if board.RefID != board.ID {
		t.Errorf("RefID = %q, want %q (the auto-assigned ID)", board.RefID, board.ID)
	}
}

func TestLookBoardRepository_Create_PreservesExplicitRefID(t *testing.T) {
	repo, _ := newLookBoardRepoForTest(t)
	board := &models.LookBoard{
		ProjectID: "p-1",
		Name:      "Top",
		RefID:     "explicit-ref",
	}
	if err := repo.Create(context.Background(), board); err != nil {
		t.Fatalf("create: %v", err)
	}
	if board.RefID != "explicit-ref" {
		t.Errorf("RefID = %q, want %q (caller-supplied)", board.RefID, "explicit-ref")
	}
}
```

If `look_board_repository_test.go` doesn't have a test helper, add this above the tests:

```go
func newLookBoardRepoForTest(t *testing.T) (*LookBoardRepository, *gorm.DB) {
	t.Helper()
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := db.AutoMigrate(&models.LookBoard{}, &models.LookBoardButton{}, &models.Look{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return NewLookBoardRepository(db), db
}
```

Add imports as needed: `"context"`, `"testing"`, `"github.com/bbernstein/lacylights-go/internal/database/models"`, `"github.com/glebarez/sqlite"`, `"gorm.io/gorm"`, `"gorm.io/gorm/logger"`.

- [ ] **Step 2: Run the test — expect FAIL**

```bash
go test ./internal/database/repositories/ -run TestLookBoardRepository_Create_DefaultsRefIDToID -v
```

Expected: FAIL — `RefID = "", want <ID>`.

- [ ] **Step 3: Update `Create` and `CreateWithButtons` in `look_board_repository.go`**

Replace `func (r *LookBoardRepository) Create` body so that after `board.ID = cuid.New()` is set, the RefID also defaults:

```go
func (r *LookBoardRepository) Create(ctx context.Context, board *models.LookBoard) error {
	if board.ID == "" {
		board.ID = cuid.New()
	}
	if board.RefID == "" {
		board.RefID = board.ID
	}
	return r.db.WithContext(ctx).Create(board).Error
}
```

Update `CreateWithButtons` likewise — after the `if board.ID == ""` block:

```go
		if board.ID == "" {
			board.ID = cuid.New()
		}
		if board.RefID == "" {
			board.RefID = board.ID
		}
```

- [ ] **Step 4: Re-run the test — expect PASS**

```bash
go test ./internal/database/repositories/ -run TestLookBoardRepository_Create -v
```

Expected: 2 tests pass.

- [ ] **Step 5: Apply the same pattern to the other three repos**

In `internal/database/repositories/fixture_repository.go`, find every method that creates a `models.FixtureInstance` (`Create`, `CreateWithChannels`) and a `models.FixtureDefinition` (`CreateDefinition`, `CreateDefinitionWithChannels`). Add the same `if X.RefID == "" { X.RefID = X.ID }` block right after the ID assignment.

Example for `CreateWithChannels`:

```go
func (r *FixtureRepository) CreateWithChannels(ctx context.Context, fixture *models.FixtureInstance, channels []models.InstanceChannel) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if fixture.ID == "" {
			fixture.ID = cuid.New()
		}
		if fixture.RefID == "" {
			fixture.RefID = fixture.ID
		}
		// ... rest unchanged ...
	})
}
```

In `internal/database/repositories/look_repository.go`, do the same for `Create` and `CreateWithFixtureValues`:

```go
	if look.ID == "" {
		look.ID = cuid.New()
	}
	if look.RefID == "" {
		look.RefID = look.ID
	}
```

- [ ] **Step 6: Add equivalent unit tests for `FixtureInstance`, `FixtureDefinition`, `Look`**

In each repo's `_test.go`, add a `TestX_Create_DefaultsRefIDToID` and `TestX_Create_PreservesExplicitRefID` mirroring Step 1 (replace model name and helper).

- [ ] **Step 7: Run all repo tests**

```bash
go test ./internal/database/repositories/ -v
```

Expected: all tests pass, including the 8 new ones (2 per repo × 4 repos).

- [ ] **Step 8: Commit**

```bash
git add internal/database/repositories/
git commit -m "feat(repos): default RefID = ID in Create methods

Mirrors the existing 'cuid.New() if blank' pattern: if a caller doesn't
supply an explicit RefID, the row's auto-assigned ID is copied in. The
EOS importer overrides this for round-trip stability; everything else
gets a sensible default."
```

---

### Task 4: New repository methods for sidecar resolution

Adds the lookup methods the mapper and resolvers will call.

**Files:**
- Modify: `internal/database/repositories/fixture_repository.go`
- Modify: `internal/database/repositories/look_repository.go`
- Modify: `internal/database/repositories/look_board_repository.go`
- Modify: respective `_test.go` files

- [ ] **Step 1: Define sentinel errors in `fixture_repository.go`**

Near the top of the file (after imports), add:

```go
// ErrChannelOffsetNotFound is returned by UpdateInstanceChannelFadeBehavior
// when the targeted offset doesn't exist on the instance. Mappers convert it
// to a SIDECAR_UNRESOLVED warning rather than failing the import.
var ErrChannelOffsetNotFound = errors.New("instance channel offset not found")
```

Ensure `"errors"` is imported.

- [ ] **Step 2: Test `FindInstanceByRefID`**

In `internal/database/repositories/fixture_repository_test.go` add:

```go
func TestFixtureRepository_FindInstanceByRefID_ResolvesAndDistinguishesProjects(t *testing.T) {
	repo, _ := newFixtureRepoForTest(t) // existing helper or follow pattern from Task 3
	ctx := context.Background()

	a := &models.FixtureInstance{ProjectID: "p1", DefinitionID: seedDef(t, repo), Name: "A", RefID: "ch-1"}
	b := &models.FixtureInstance{ProjectID: "p2", DefinitionID: seedDef(t, repo), Name: "B", RefID: "ch-1"} // same RefID, different project
	if err := repo.CreateWithChannels(ctx, a, nil); err != nil {
		t.Fatalf("create a: %v", err)
	}
	if err := repo.CreateWithChannels(ctx, b, nil); err != nil {
		t.Fatalf("create b: %v", err)
	}

	got, err := repo.FindInstanceByRefID(ctx, "p1", "ch-1")
	if err != nil {
		t.Fatalf("find: %v", err)
	}
	if got == nil || got.ID != a.ID {
		t.Errorf("got %v, want %v", got, a.ID)
	}

	got, err = repo.FindInstanceByRefID(ctx, "p1", "missing")
	if err != nil {
		t.Fatalf("find missing: %v", err)
	}
	if got != nil {
		t.Errorf("expected nil for unknown refID, got %v", got)
	}
}
```

`seedDef` is a helper that creates a minimal `FixtureDefinition` and returns its ID — define it in the test file if not already present.

- [ ] **Step 3: Implement `FindInstanceByRefID`**

In `fixture_repository.go`:

```go
// FindInstanceByRefID resolves a fixture instance by (project, refID).
// Returns (nil, nil) on miss — convention shared with FindByID.
func (r *FixtureRepository) FindInstanceByRefID(ctx context.Context, projectID, refID string) (*models.FixtureInstance, error) {
	var fi models.FixtureInstance
	result := r.db.WithContext(ctx).
		Where("project_id = ? AND ref_id = ?", projectID, refID).
		First(&fi)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &fi, nil
}
```

- [ ] **Step 4: Test `UpdateInstanceChannelFadeBehavior`**

```go
func TestFixtureRepository_UpdateInstanceChannelFadeBehavior_OverridesOnlyTargetOffset(t *testing.T) {
	repo, _ := newFixtureRepoForTest(t)
	ctx := context.Background()

	defID := seedDef(t, repo)
	fi := &models.FixtureInstance{ProjectID: "p1", DefinitionID: defID, Name: "A"}
	channels := []models.InstanceChannel{
		{Offset: 0, Name: "Intensity", Type: "INTENSITY", FadeBehavior: "FADE"},
		{Offset: 1, Name: "Red", Type: "COLOR_R", FadeBehavior: "FADE"},
		{Offset: 2, Name: "Green", Type: "COLOR_G", FadeBehavior: "FADE"},
	}
	if err := repo.CreateWithChannels(ctx, fi, channels); err != nil {
		t.Fatalf("create: %v", err)
	}

	if err := repo.UpdateInstanceChannelFadeBehavior(ctx, fi.ID, 1, "SNAP_END"); err != nil {
		t.Fatalf("update: %v", err)
	}

	got, err := repo.GetInstanceChannels(ctx, fi.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	want := map[int]string{0: "FADE", 1: "SNAP_END", 2: "FADE"}
	for _, c := range got {
		if c.FadeBehavior != want[c.Offset] {
			t.Errorf("offset %d: %q, want %q", c.Offset, c.FadeBehavior, want[c.Offset])
		}
	}
}

func TestFixtureRepository_UpdateInstanceChannelFadeBehavior_UnknownOffsetReturnsSentinel(t *testing.T) {
	repo, _ := newFixtureRepoForTest(t)
	ctx := context.Background()

	defID := seedDef(t, repo)
	fi := &models.FixtureInstance{ProjectID: "p1", DefinitionID: defID, Name: "A"}
	if err := repo.CreateWithChannels(ctx, fi, []models.InstanceChannel{{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"}}); err != nil {
		t.Fatalf("create: %v", err)
	}

	err := repo.UpdateInstanceChannelFadeBehavior(ctx, fi.ID, 5, "SNAP")
	if !errors.Is(err, ErrChannelOffsetNotFound) {
		t.Errorf("got %v, want ErrChannelOffsetNotFound", err)
	}
}
```

- [ ] **Step 5: Implement `UpdateInstanceChannelFadeBehavior`**

In `fixture_repository.go`:

```go
// UpdateInstanceChannelFadeBehavior updates the FadeBehavior on a single
// (instanceID, offset) row. Returns ErrChannelOffsetNotFound if no matching
// row exists — callers convert this to a structured warning.
func (r *FixtureRepository) UpdateInstanceChannelFadeBehavior(ctx context.Context, instanceID string, offset int, behavior string) error {
	res := r.db.WithContext(ctx).
		Model(&models.InstanceChannel{}).
		Where("fixture_id = ? AND `offset` = ?", instanceID, offset).
		Update("fade_behavior", behavior)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrChannelOffsetNotFound
	}
	return nil
}
```

The backticks around `offset` are because `OFFSET` is a SQL reserved word; quoting keeps SQLite happy.

- [ ] **Step 6: Test + implement `FindDefinitionByRefID`**

Test:

```go
func TestFixtureRepository_FindDefinitionByRefID_Global(t *testing.T) {
	repo, _ := newFixtureRepoForTest(t)
	ctx := context.Background()

	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "Dimmer", RefID: "def-generic-dimmer", Type: "DIMMER"}
	if err := repo.CreateDefinition(ctx, def); err != nil {
		t.Fatalf("create def: %v", err)
	}

	got, err := repo.FindDefinitionByRefID(ctx, "def-generic-dimmer")
	if err != nil {
		t.Fatalf("find: %v", err)
	}
	if got == nil || got.ID != def.ID {
		t.Errorf("got %v, want def %v", got, def.ID)
	}
}
```

Implementation:

```go
func (r *FixtureRepository) FindDefinitionByRefID(ctx context.Context, refID string) (*models.FixtureDefinition, error) {
	var d models.FixtureDefinition
	result := r.db.WithContext(ctx).Where("ref_id = ?", refID).First(&d)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &d, nil
}
```

- [ ] **Step 7: Test + implement `LookRepository.MapByRefID` and `FindByRefID`**

Test (in `look_repository_test.go`):

```go
func TestLookRepository_MapByRefID_ReturnsPresentOnly(t *testing.T) {
	repo, _ := newLookRepoForTest(t)
	ctx := context.Background()

	a := &models.Look{ProjectID: "p1", Name: "A", RefID: "L1"}
	b := &models.Look{ProjectID: "p1", Name: "B", RefID: "L2"}
	other := &models.Look{ProjectID: "p2", Name: "X", RefID: "L1"} // same refID, different project — must not leak
	for _, l := range []*models.Look{a, b, other} {
		if err := repo.Create(ctx, l); err != nil {
			t.Fatalf("create: %v", err)
		}
	}

	got, err := repo.MapByRefID(ctx, "p1", []string{"L1", "L2", "missing"})
	if err != nil {
		t.Fatalf("map: %v", err)
	}
	want := map[string]string{"L1": a.ID, "L2": b.ID}
	if len(got) != 2 {
		t.Fatalf("got %d entries, want 2: %v", len(got), got)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("got[%q] = %q, want %q", k, got[k], v)
		}
	}
}
```

Implementation in `look_repository.go`:

```go
// MapByRefID resolves a batch of (projectID, refID) pairs in one query.
// Returns a map keyed by refID; unresolved refIDs are absent from the map
// (the caller emits SIDECAR_UNRESOLVED warnings for misses).
func (r *LookRepository) MapByRefID(ctx context.Context, projectID string, refIDs []string) (map[string]string, error) {
	out := make(map[string]string, len(refIDs))
	if len(refIDs) == 0 {
		return out, nil
	}
	type row struct {
		ID    string
		RefID string
	}
	var rows []row
	err := r.db.WithContext(ctx).
		Model(&models.Look{}).
		Select("id, ref_id").
		Where("project_id = ? AND ref_id IN ?", projectID, refIDs).
		Find(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.RefID] = r.ID
	}
	return out, nil
}

// FindByRefID resolves a single (projectID, refID). (nil, nil) on miss.
func (r *LookRepository) FindByRefID(ctx context.Context, projectID, refID string) (*models.Look, error) {
	var look models.Look
	result := r.db.WithContext(ctx).
		Where("project_id = ? AND ref_id = ?", projectID, refID).
		First(&look)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &look, nil
}
```

- [ ] **Step 8: Test + implement `LookBoardRepository.FindByRefID`**

Test:

```go
func TestLookBoardRepository_FindByRefID(t *testing.T) {
	repo, _ := newLookBoardRepoForTest(t)
	ctx := context.Background()

	board := &models.LookBoard{ProjectID: "p1", Name: "Top", RefID: "lb-1"}
	if err := repo.Create(ctx, board); err != nil {
		t.Fatalf("create: %v", err)
	}

	got, err := repo.FindByRefID(ctx, "p1", "lb-1")
	if err != nil {
		t.Fatalf("find: %v", err)
	}
	if got == nil || got.ID != board.ID {
		t.Errorf("got %v, want %v", got, board.ID)
	}

	miss, err := repo.FindByRefID(ctx, "p1", "missing")
	if err != nil || miss != nil {
		t.Errorf("miss: got (%v, %v), want (nil, nil)", miss, err)
	}
}
```

Implementation in `look_board_repository.go`:

```go
func (r *LookBoardRepository) FindByRefID(ctx context.Context, projectID, refID string) (*models.LookBoard, error) {
	var b models.LookBoard
	result := r.db.WithContext(ctx).
		Where("project_id = ? AND ref_id = ?", projectID, refID).
		First(&b)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &b, nil
}
```

- [ ] **Step 9: Run all repo tests**

```bash
go test ./internal/database/repositories/ -v
```

Expected: all new tests pass, no regressions.

- [ ] **Step 10: Commit**

```bash
git add internal/database/repositories/
git commit -m "feat(repos): add RefID-based lookups + per-channel fade behavior update

- FixtureRepository.FindInstanceByRefID, FindDefinitionByRefID,
  UpdateInstanceChannelFadeBehavior (+ ErrChannelOffsetNotFound sentinel)
- LookRepository.MapByRefID, FindByRefID
- LookBoardRepository.FindByRefID

These are the lookup primitives the EOS sidecar mapper will use to
re-attach LookBoards and per-channel fade behaviors during import."
```

---

## Phase 2 — `FixtureGroup` model + repository

### Task 5: Add `FixtureGroup` and `FixtureGroupMember` models

**Files:**
- Modify: `internal/database/models/models.go`

- [ ] **Step 1: Append the two new structs at the bottom of `models.go`**

```go
// FixtureGroup represents a named collection of fixture instances within a
// project. Surfaces in EOS ASCII as $Group blocks; each LacyLights group has
// an optional EosNumber that the writer uses for stable group numbering.
// Table: fixture_groups
type FixtureGroup struct {
	ID           string  `gorm:"column:id;primaryKey"`
	ProjectID    string  `gorm:"column:project_id;index;not null"`
	Name         string  `gorm:"column:name;not null"`
	Description  *string `gorm:"column:description"`
	EosNumber    *int    `gorm:"column:eos_number"` // nullable; stable across exports once assigned
	RefID        string  `gorm:"column:ref_id;not null;default:''"`
	ProjectOrder *int    `gorm:"column:project_order"`

	CreatedAt time.Time `gorm:"column:created_at;autoCreateTime"`
	UpdatedAt time.Time `gorm:"column:updated_at;autoUpdateTime"`

	Members []FixtureGroupMember `gorm:"foreignKey:GroupID;constraint:OnDelete:CASCADE"`
}

// FixtureGroupMember is a junction row tying a FixtureGroup to a
// FixtureInstance. Composite PK (group_id, fixture_id) ensures one
// row per membership; the OrderIndex column gives stable iteration.
// Table: fixture_group_members
type FixtureGroupMember struct {
	GroupID    string `gorm:"column:group_id;primaryKey"`
	FixtureID  string `gorm:"column:fixture_id;primaryKey"`
	OrderIndex int    `gorm:"column:order_index;not null"`
}
```

Note: the column is named `order_index`, not `order` — `ORDER` is a SQL reserved word and quoting it on every read is friction.

- [ ] **Step 2: Build to confirm types compile**

```bash
go build ./internal/database/models/...
```

- [ ] **Step 3: Commit**

```bash
git add internal/database/models/models.go
git commit -m "feat(models): add FixtureGroup and FixtureGroupMember

FixtureGroup is a named collection of fixtures within a project; survives
EOS ASCII round-trip via \$Group blocks. Members live in a junction table
with composite PK and OrderIndex for stable iteration. EosNumber is
nullable (auto-assigned on first export) for round-trip stability."
```

---

### Task 6: Register `FixtureGroup` tables in migrations + add EOS-number index

**Files:**
- Modify: `cmd/server/main.go`
- Modify: `internal/database/migrations/refid_migration.go`

- [ ] **Step 1: Add the two tables to `tablesWithFK` in `main.go`**

In the `tablesWithFK` slice (around line 105), insert after the `instance_channels` row:

```go
		{"fixture_instances", &models.FixtureInstance{}, []string{"id", "project_id"}},
		{"instance_channels", &models.InstanceChannel{}, []string{"id", "fixture_id"}},
		// Task 14c: fixture groups + junction
		{"fixture_groups", &models.FixtureGroup{}, []string{"id", "project_id"}},
		{"fixture_group_members", &models.FixtureGroupMember{}, []string{"group_id", "fixture_id"}},
		{"looks", &models.Look{}, []string{"id", "project_id"}},
```

Order matters: `FixtureGroup` before `FixtureGroupMember` (FK target before source).

- [ ] **Step 2: Add the `eos_number` partial unique index**

In `internal/database/migrations/refid_migration.go`, extend `CreateRefIDIndexes`:

```go
		{
			"idx_fixture_groups_project_refid",
			`CREATE UNIQUE INDEX IF NOT EXISTS idx_fixture_groups_project_refid
				ON fixture_groups(project_id, ref_id)`,
		},
		{
			"idx_fixture_groups_project_eos_number",
			`CREATE UNIQUE INDEX IF NOT EXISTS idx_fixture_groups_project_eos_number
				ON fixture_groups(project_id, eos_number)
				WHERE eos_number IS NOT NULL`,
		},
```

Append both entries to the existing `stmts` slice. Also add `"fixture_groups"` to `refIDTables` so the backfill covers it.

- [ ] **Step 3: Add a migration test for the new index**

Append to `refid_migration_test.go`:

```go
func TestCreateRefIDIndexes_EnforcesEosNumberPartialUniqueness(t *testing.T) {
	db := openTestDB(t)
	if err := db.Exec(`CREATE TABLE fixture_groups (id TEXT PRIMARY KEY, project_id TEXT, ref_id TEXT, eos_number INTEGER)`).Error; err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := CreateRefIDIndexes(db); err != nil {
		t.Fatalf("create indexes: %v", err)
	}

	// Two groups in the same project with EosNumber=1 → second insert must fail.
	if err := db.Exec(`INSERT INTO fixture_groups (id, project_id, ref_id, eos_number) VALUES ('a','p1','a',1)`).Error; err != nil {
		t.Fatalf("first: %v", err)
	}
	if err := db.Exec(`INSERT INTO fixture_groups (id, project_id, ref_id, eos_number) VALUES ('b','p1','b',1)`).Error; err == nil {
		t.Errorf("expected unique-constraint failure on duplicate EosNumber")
	}

	// Two groups with NULL EosNumber must succeed (partial index ignores NULLs).
	if err := db.Exec(`INSERT INTO fixture_groups (id, project_id, ref_id, eos_number) VALUES ('c','p1','c',NULL)`).Error; err != nil {
		t.Fatalf("third: %v", err)
	}
	if err := db.Exec(`INSERT INTO fixture_groups (id, project_id, ref_id, eos_number) VALUES ('d','p1','d',NULL)`).Error; err != nil {
		t.Fatalf("fourth: %v", err)
	}
}
```

- [ ] **Step 4: Run migration tests**

```bash
go test ./internal/database/migrations/...
```

Expected: 4 tests pass.

- [ ] **Step 5: Build the server**

```bash
go build ./cmd/server
```

- [ ] **Step 6: Commit**

```bash
git add cmd/server/main.go internal/database/migrations/
git commit -m "feat(migrations): register FixtureGroup tables + EOS-number unique index

Adds fixture_groups and fixture_group_members to the AutoMigrate list,
extends BackfillRefIDs to cover fixture_groups, and adds a partial unique
index on (project_id, eos_number) WHERE eos_number IS NOT NULL — null
EosNumbers don't conflict, but assigned numbers stay unique within a
project."
```

---

### Task 7: `FixtureGroupRepository` — type, constructor, CRUD

**Files:**
- Create: `internal/database/repositories/fixture_group_repository.go`
- Create: `internal/database/repositories/fixture_group_repository_test.go`

- [ ] **Step 1: Test scaffold + first test (`Create`)**

Create `internal/database/repositories/fixture_group_repository_test.go`:

```go
package repositories

import (
	"context"
	"errors"
	"testing"

	"github.com/bbernstein/lacylights-go/internal/database/migrations"
	"github.com/bbernstein/lacylights-go/internal/database/models"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func newFixtureGroupRepoForTest(t *testing.T) (*FixtureGroupRepository, *FixtureRepository, *gorm.DB) {
	t.Helper()
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := db.AutoMigrate(
		&models.Project{},
		&models.FixtureDefinition{},
		&models.ChannelDefinition{},
		&models.FixtureInstance{},
		&models.InstanceChannel{},
		&models.FixtureGroup{},
		&models.FixtureGroupMember{},
	); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := migrations.CreateRefIDIndexes(db); err != nil {
		t.Fatalf("indexes: %v", err)
	}
	return NewFixtureGroupRepository(db), NewFixtureRepository(db), db
}

func seedFixtureForGroup(t *testing.T, fr *FixtureRepository, projectID, refID string) *models.FixtureInstance {
	t.Helper()
	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "Dimmer", Type: "DIMMER"}
	if err := fr.CreateDefinition(context.Background(), def); err != nil {
		t.Fatalf("create def: %v", err)
	}
	fi := &models.FixtureInstance{ProjectID: projectID, DefinitionID: def.ID, Name: refID, RefID: refID}
	if err := fr.CreateWithChannels(context.Background(), fi, nil); err != nil {
		t.Fatalf("create fi: %v", err)
	}
	return fi
}

func TestFixtureGroupRepository_Create_DefaultsRefIDAndAssignsID(t *testing.T) {
	repo, _, _ := newFixtureGroupRepoForTest(t)
	g := &models.FixtureGroup{ProjectID: "p1", Name: "Movers"}
	if err := repo.Create(context.Background(), g); err != nil {
		t.Fatalf("create: %v", err)
	}
	if g.ID == "" {
		t.Fatalf("expected ID assigned")
	}
	if g.RefID != g.ID {
		t.Errorf("RefID = %q, want %q", g.RefID, g.ID)
	}
}
```

- [ ] **Step 2: Skeleton implementation in `fixture_group_repository.go`**

```go
package repositories

import (
	"context"
	"errors"
	"fmt"

	"github.com/bbernstein/lacylights-go/internal/database/models"
	"github.com/lucsky/cuid"
	"gorm.io/gorm"
)

// FixtureGroupRepository handles fixture-group data access.
type FixtureGroupRepository struct {
	db *gorm.DB
}

// NewFixtureGroupRepository creates a new FixtureGroupRepository.
func NewFixtureGroupRepository(db *gorm.DB) *FixtureGroupRepository {
	return &FixtureGroupRepository{db: db}
}

// Create creates a new fixture group (no members).
func (r *FixtureGroupRepository) Create(ctx context.Context, g *models.FixtureGroup) error {
	if g.ID == "" {
		g.ID = cuid.New()
	}
	if g.RefID == "" {
		g.RefID = g.ID
	}
	return r.db.WithContext(ctx).Create(g).Error
}
```

- [ ] **Step 3: Run the test — expect PASS**

```bash
go test ./internal/database/repositories/ -run TestFixtureGroupRepository_Create -v
```

- [ ] **Step 4: Add `FindByID`, `FindByProjectID`, `FindByRefID`, `FindByEosNumber`, `Update`, `Delete`**

Append to `fixture_group_repository.go`:

```go
// FindByID returns a group by primary key. (nil, nil) on miss.
func (r *FixtureGroupRepository) FindByID(ctx context.Context, id string) (*models.FixtureGroup, error) {
	var g models.FixtureGroup
	result := r.db.WithContext(ctx).First(&g, "id = ?", id)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &g, nil
}

// FindByProjectID returns all groups in a project, sorted by ProjectOrder
// (NULL last) then Name.
func (r *FixtureGroupRepository) FindByProjectID(ctx context.Context, projectID string) ([]models.FixtureGroup, error) {
	var groups []models.FixtureGroup
	result := r.db.WithContext(ctx).
		Where("project_id = ?", projectID).
		Order("project_order IS NULL, project_order ASC, name ASC, id ASC").
		Find(&groups)
	return groups, result.Error
}

// FindByRefID resolves a group by (project, refID).
func (r *FixtureGroupRepository) FindByRefID(ctx context.Context, projectID, refID string) (*models.FixtureGroup, error) {
	var g models.FixtureGroup
	result := r.db.WithContext(ctx).
		Where("project_id = ? AND ref_id = ?", projectID, refID).
		First(&g)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &g, nil
}

// FindByEosNumber resolves a group by (project, eosNumber).
func (r *FixtureGroupRepository) FindByEosNumber(ctx context.Context, projectID string, eosNumber int) (*models.FixtureGroup, error) {
	var g models.FixtureGroup
	result := r.db.WithContext(ctx).
		Where("project_id = ? AND eos_number = ?", projectID, eosNumber).
		First(&g)
	if result.Error != nil {
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, result.Error
	}
	return &g, nil
}

// Update saves a group's mutable fields (name, description, eos_number,
// project_order). RefID is intentionally not part of the update set —
// it's frozen post-creation.
func (r *FixtureGroupRepository) Update(ctx context.Context, g *models.FixtureGroup) error {
	return r.db.WithContext(ctx).
		Model(&models.FixtureGroup{}).
		Where("id = ?", g.ID).
		Updates(map[string]interface{}{
			"name":          g.Name,
			"description":   g.Description,
			"eos_number":    g.EosNumber,
			"project_order": g.ProjectOrder,
		}).Error
}

// Delete deletes a group; cascade FK on members removes their rows.
func (r *FixtureGroupRepository) Delete(ctx context.Context, id string) error {
	return r.db.WithContext(ctx).Delete(&models.FixtureGroup{}, "id = ?", id).Error
}
```

- [ ] **Step 5: Add membership methods**

```go
// CreateWithMembers atomically creates a group and its members.
func (r *FixtureGroupRepository) CreateWithMembers(ctx context.Context, g *models.FixtureGroup, fixtureIDs []string) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if g.ID == "" {
			g.ID = cuid.New()
		}
		if g.RefID == "" {
			g.RefID = g.ID
		}
		if err := tx.Create(g).Error; err != nil {
			return err
		}
		return r.replaceMembersTx(tx, g.ID, fixtureIDs)
	})
}

// GetMembers returns the members of a group sorted by OrderIndex.
func (r *FixtureGroupRepository) GetMembers(ctx context.Context, groupID string) ([]models.FixtureGroupMember, error) {
	var ms []models.FixtureGroupMember
	result := r.db.WithContext(ctx).
		Where("group_id = ?", groupID).
		Order("order_index ASC, fixture_id ASC").
		Find(&ms)
	return ms, result.Error
}

// SetMembers transactionally replaces the membership list. OrderIndex is
// assigned in input-list order (0, 1, 2, ...).
func (r *FixtureGroupRepository) SetMembers(ctx context.Context, groupID string, fixtureIDs []string) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return r.replaceMembersTx(tx, groupID, fixtureIDs)
	})
}

func (r *FixtureGroupRepository) replaceMembersTx(tx *gorm.DB, groupID string, fixtureIDs []string) error {
	if err := tx.Delete(&models.FixtureGroupMember{}, "group_id = ?", groupID).Error; err != nil {
		return err
	}
	if len(fixtureIDs) == 0 {
		return nil
	}
	rows := make([]models.FixtureGroupMember, 0, len(fixtureIDs))
	for i, fid := range fixtureIDs {
		rows = append(rows, models.FixtureGroupMember{
			GroupID:    groupID,
			FixtureID:  fid,
			OrderIndex: i,
		})
	}
	return tx.Create(&rows).Error
}

// AddMembers appends the given fixtures to the group, skipping duplicates.
// New rows get OrderIndex = current max + 1, +2, ...
func (r *FixtureGroupRepository) AddMembers(ctx context.Context, groupID string, fixtureIDs []string) error {
	if len(fixtureIDs) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Find the current max OrderIndex.
		var maxOrder *int
		if err := tx.Model(&models.FixtureGroupMember{}).
			Select("MAX(order_index)").
			Where("group_id = ?", groupID).
			Scan(&maxOrder).Error; err != nil {
			return err
		}
		next := 0
		if maxOrder != nil {
			next = *maxOrder + 1
		}

		// Find existing members to skip duplicates.
		var existingIDs []string
		if err := tx.Model(&models.FixtureGroupMember{}).
			Where("group_id = ?", groupID).
			Pluck("fixture_id", &existingIDs).Error; err != nil {
			return err
		}
		existing := map[string]bool{}
		for _, id := range existingIDs {
			existing[id] = true
		}

		var rows []models.FixtureGroupMember
		for _, fid := range fixtureIDs {
			if existing[fid] {
				continue
			}
			rows = append(rows, models.FixtureGroupMember{
				GroupID:    groupID,
				FixtureID:  fid,
				OrderIndex: next,
			})
			next++
			existing[fid] = true
		}
		if len(rows) == 0 {
			return nil
		}
		return tx.Create(&rows).Error
	})
}

// RemoveMembers deletes the listed fixtures from the group; missing IDs
// are silently ignored. Surviving members keep their OrderIndex (gaps
// are fine — readers sort by it).
func (r *FixtureGroupRepository) RemoveMembers(ctx context.Context, groupID string, fixtureIDs []string) error {
	if len(fixtureIDs) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).
		Where("group_id = ? AND fixture_id IN ?", groupID, fixtureIDs).
		Delete(&models.FixtureGroupMember{}).Error
}

// ReorderMembers updates OrderIndex according to the supplied list. Any
// fixtureIDs not currently members are silently ignored. Any current
// members not listed retain their existing OrderIndex (so partial
// reorders are possible, though the GraphQL surface always sends a full
// list).
func (r *FixtureGroupRepository) ReorderMembers(ctx context.Context, groupID string, fixtureIDs []string) error {
	if len(fixtureIDs) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		for i, fid := range fixtureIDs {
			res := tx.Model(&models.FixtureGroupMember{}).
				Where("group_id = ? AND fixture_id = ?", groupID, fid).
				Update("order_index", i)
			if res.Error != nil {
				return res.Error
			}
		}
		return nil
	})
}
```

- [ ] **Step 6: Add `AssignNextEosNumber` for the writer**

```go
// AssignNextEosNumber returns one more than the largest EosNumber in the
// project, or 1 if no group has an assigned number. It does NOT mutate
// state — callers persist via Update.
func (r *FixtureGroupRepository) AssignNextEosNumber(ctx context.Context, projectID string) (int, error) {
	var maxNum *int
	err := r.db.WithContext(ctx).
		Model(&models.FixtureGroup{}).
		Where("project_id = ?", projectID).
		Select("MAX(eos_number)").
		Scan(&maxNum).Error
	if err != nil {
		return 0, fmt.Errorf("max eos_number: %w", err)
	}
	if maxNum == nil {
		return 1, nil
	}
	return *maxNum + 1, nil
}
```

- [ ] **Step 7: Tests for every method**

Append to `fixture_group_repository_test.go`:

```go
func TestFixtureGroupRepository_CreateWithMembers_AssignsOrder(t *testing.T) {
	repo, fr, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()

	a := seedFixtureForGroup(t, fr, "p1", "ch-1")
	b := seedFixtureForGroup(t, fr, "p1", "ch-2")
	c := seedFixtureForGroup(t, fr, "p1", "ch-3")

	g := &models.FixtureGroup{ProjectID: "p1", Name: "All"}
	if err := repo.CreateWithMembers(ctx, g, []string{a.ID, c.ID, b.ID}); err != nil {
		t.Fatalf("create: %v", err)
	}

	ms, err := repo.GetMembers(ctx, g.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if len(ms) != 3 {
		t.Fatalf("got %d, want 3", len(ms))
	}
	if ms[0].FixtureID != a.ID || ms[0].OrderIndex != 0 {
		t.Errorf("ms[0] = %v", ms[0])
	}
	if ms[1].FixtureID != c.ID || ms[1].OrderIndex != 1 {
		t.Errorf("ms[1] = %v", ms[1])
	}
	if ms[2].FixtureID != b.ID || ms[2].OrderIndex != 2 {
		t.Errorf("ms[2] = %v", ms[2])
	}
}

func TestFixtureGroupRepository_SetMembers_Replaces(t *testing.T) {
	repo, fr, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()
	a := seedFixtureForGroup(t, fr, "p1", "ch-1")
	b := seedFixtureForGroup(t, fr, "p1", "ch-2")
	c := seedFixtureForGroup(t, fr, "p1", "ch-3")

	g := &models.FixtureGroup{ProjectID: "p1", Name: "G"}
	if err := repo.CreateWithMembers(ctx, g, []string{a.ID, b.ID}); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := repo.SetMembers(ctx, g.ID, []string{c.ID}); err != nil {
		t.Fatalf("set: %v", err)
	}
	ms, _ := repo.GetMembers(ctx, g.ID)
	if len(ms) != 1 || ms[0].FixtureID != c.ID {
		t.Errorf("after set: %v", ms)
	}
}

func TestFixtureGroupRepository_AddMembers_SkipsDuplicates(t *testing.T) {
	repo, fr, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()
	a := seedFixtureForGroup(t, fr, "p1", "ch-1")
	b := seedFixtureForGroup(t, fr, "p1", "ch-2")

	g := &models.FixtureGroup{ProjectID: "p1", Name: "G"}
	_ = repo.CreateWithMembers(ctx, g, []string{a.ID})
	if err := repo.AddMembers(ctx, g.ID, []string{a.ID, b.ID}); err != nil {
		t.Fatalf("add: %v", err)
	}
	ms, _ := repo.GetMembers(ctx, g.ID)
	if len(ms) != 2 {
		t.Errorf("want 2 members, got %d", len(ms))
	}
}

func TestFixtureGroupRepository_RemoveMembers(t *testing.T) {
	repo, fr, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()
	a := seedFixtureForGroup(t, fr, "p1", "ch-1")
	b := seedFixtureForGroup(t, fr, "p1", "ch-2")
	g := &models.FixtureGroup{ProjectID: "p1", Name: "G"}
	_ = repo.CreateWithMembers(ctx, g, []string{a.ID, b.ID})

	if err := repo.RemoveMembers(ctx, g.ID, []string{a.ID, "missing"}); err != nil {
		t.Fatalf("remove: %v", err)
	}
	ms, _ := repo.GetMembers(ctx, g.ID)
	if len(ms) != 1 || ms[0].FixtureID != b.ID {
		t.Errorf("after remove: %v", ms)
	}
}

func TestFixtureGroupRepository_ReorderMembers(t *testing.T) {
	repo, fr, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()
	a := seedFixtureForGroup(t, fr, "p1", "ch-1")
	b := seedFixtureForGroup(t, fr, "p1", "ch-2")
	c := seedFixtureForGroup(t, fr, "p1", "ch-3")
	g := &models.FixtureGroup{ProjectID: "p1", Name: "G"}
	_ = repo.CreateWithMembers(ctx, g, []string{a.ID, b.ID, c.ID})

	if err := repo.ReorderMembers(ctx, g.ID, []string{c.ID, a.ID, b.ID}); err != nil {
		t.Fatalf("reorder: %v", err)
	}
	ms, _ := repo.GetMembers(ctx, g.ID)
	want := []string{c.ID, a.ID, b.ID}
	for i, id := range want {
		if ms[i].FixtureID != id {
			t.Errorf("ms[%d] = %s, want %s", i, ms[i].FixtureID, id)
		}
	}
}

func TestFixtureGroupRepository_AssignNextEosNumber(t *testing.T) {
	repo, _, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()

	n, err := repo.AssignNextEosNumber(ctx, "p1")
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	if n != 1 {
		t.Errorf("first = %d, want 1", n)
	}

	one := 1
	if err := repo.Create(ctx, &models.FixtureGroup{ProjectID: "p1", Name: "A", EosNumber: &one}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	five := 5
	if err := repo.Create(ctx, &models.FixtureGroup{ProjectID: "p1", Name: "B", EosNumber: &five}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	n, _ = repo.AssignNextEosNumber(ctx, "p1")
	if n != 6 {
		t.Errorf("after seeding 1+5 = %d, want 6", n)
	}
}

func TestFixtureGroupRepository_FindByEosNumber(t *testing.T) {
	repo, _, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()
	three := 3
	g := &models.FixtureGroup{ProjectID: "p1", Name: "G", EosNumber: &three}
	if err := repo.Create(ctx, g); err != nil {
		t.Fatalf("create: %v", err)
	}
	got, err := repo.FindByEosNumber(ctx, "p1", 3)
	if err != nil || got == nil || got.ID != g.ID {
		t.Errorf("got %v, %v", got, err)
	}
	miss, _ := repo.FindByEosNumber(ctx, "p1", 99)
	if miss != nil {
		t.Errorf("miss should be nil")
	}
}

func TestFixtureGroupRepository_CascadeDeleteOnFixture(t *testing.T) {
	repo, fr, _ := newFixtureGroupRepoForTest(t)
	ctx := context.Background()
	a := seedFixtureForGroup(t, fr, "p1", "ch-1")
	g := &models.FixtureGroup{ProjectID: "p1", Name: "G"}
	_ = repo.CreateWithMembers(ctx, g, []string{a.ID})

	if err := fr.Delete(ctx, a.ID); err != nil {
		t.Fatalf("delete fixture: %v", err)
	}

	// Group still exists; membership row gone (FK ON DELETE not set on
	// FixtureID by default — verify behavior). If GORM's default cascade
	// fires, this should be 0; if not, it'll be 1 with a dangling FK.
	ms, _ := repo.GetMembers(ctx, g.ID)
	if len(ms) != 0 {
		t.Errorf("expected cascade delete; got %d members", len(ms))
	}
}

// (Suppress unused import warning if errors isn't otherwise used)
var _ = errors.New
```

**Note on the cascade test:** the design specifies cascade-on-fixture-delete, but the FK on `FixtureID` isn't declared in the model. If this test fails, decide whether to: (a) add `gorm:"foreignKey:FixtureID;constraint:OnDelete:CASCADE"` on `FixtureGroupMember.FixtureID` (not currently — composite PK constrains it), or (b) override `FixtureRepository.Delete` to also clean up `fixture_group_members` in a transaction. Option (b) is the simpler change since GORM's tag-based cascading on a composite-PK junction is finicky. If the test fails, do (b): wrap `FixtureRepository.Delete` in a transaction that first deletes from `fixture_group_members` where `fixture_id = ?`, then deletes the instance. Document the cascade decision in `fixture_repository.go` with a comment.

- [ ] **Step 8: Run all tests for the new repo**

```bash
go test ./internal/database/repositories/ -v -run TestFixtureGroupRepository
```

Expected: all 9 tests pass. If `TestFixtureGroupRepository_CascadeDeleteOnFixture` fails, apply remediation (b) above before continuing.

- [ ] **Step 9: Commit**

```bash
git add internal/database/repositories/fixture_group_repository.go internal/database/repositories/fixture_group_repository_test.go internal/database/repositories/fixture_repository.go
git commit -m "feat(repos): add FixtureGroupRepository with CRUD + membership ops

Includes Create/CreateWithMembers/Update/Delete, FindByID/FindByProjectID/
FindByRefID/FindByEosNumber, GetMembers/SetMembers/AddMembers/RemoveMembers/
ReorderMembers, and AssignNextEosNumber for the writer's auto-numbering
flow. Cascade on fixture delete handled in FixtureRepository.Delete."
```

---

## Phase 3 — GraphQL surface

### Task 8: Schema additions — `FixtureGroup` type, queries, mutations, refId fields

**Files:**
- Modify: `internal/graphql/schema/schema.graphql`

- [ ] **Step 1: Add `refId` fields to existing types**

Find each of these in `schema.graphql` and insert `refId: String!` immediately after the `id: ID!` line:

- `type FixtureDefinition` (line ~590)
- `type FixtureInstance` (line ~627)
- `type Look` (line ~675)
- `type LookBoard` (line ~697)

Example for `Look`:

```graphql
type Look {
  id: ID!
  refId: String!
  name: String!
  # ... rest unchanged ...
}
```

- [ ] **Step 2: Add `FixtureGroup` type and inputs**

At the bottom of `schema.graphql` (or in the natural section adjacent to `LookBoard`), add:

```graphql
type FixtureGroup {
  id: ID!
  refId: String!
  name: String!
  description: String
  eosNumber: Int
  projectOrder: Int
  project: Project!
  fixtures: [FixtureInstance!]!
  createdAt: String!
  updatedAt: String!
}

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

- [ ] **Step 3: Add queries and mutations**

Find the existing `extend type Query` block (or `type Query` if not extended). Add:

```graphql
extend type Query {
  fixtureGroup(id: ID!): FixtureGroup
  fixtureGroups(projectId: ID!): [FixtureGroup!]!
}

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

If the file uses `type Query` / `type Mutation` (not extends), inline the new fields directly into those blocks.

- [ ] **Step 4: Run codegen**

```bash
make generate
```

Expected: `generated/generated.go` and resolver stubs are updated. Resolver stubs for the new queries/mutations may be added to `schema.resolvers.go` automatically — gqlgen typically inserts skeletons that `panic("not implemented")`. Locate them; they're what Task 10 wires up.

- [ ] **Step 5: Build to confirm wiring**

```bash
go build ./...
```

Expected: build fails with "function returns FixtureGroup but resolver is not implemented" or similar gqlgen-stub panics resolved at runtime. If it builds, gqlgen populated stubs successfully.

- [ ] **Step 6: Commit (just schema + generated; resolver impl follows in Task 9)**

```bash
git add internal/graphql/schema/schema.graphql internal/graphql/generated/ internal/graphql/resolvers/schema.resolvers.go
git commit -m "feat(graphql): schema for FixtureGroup CRUD + bulk + refId fields

Adds FixtureGroup type with full CRUD, bulk variants, and dedicated
membership operations (addFixturesToGroup, removeFixturesFromGroup,
reorderFixturesInGroup). Exposes the new RefID column as a read-only
field on FixtureInstance, FixtureDefinition, Look, LookBoard. Resolver
stubs panic until Task 9 wires them up."
```

---

### Task 9: Resolver helpers — `fixture_group_resolvers.go`

**Files:**
- Create: `internal/graphql/resolvers/fixture_group_resolvers.go`
- Create: `internal/graphql/resolvers/fixture_group_resolvers_test.go`
- Modify: `internal/graphql/resolvers/resolver.go` (add `FixtureGroupRepo` field)
- Modify: `internal/graphql/resolvers/schema.resolvers.go` (delegate stubs to helpers)
- Modify: `cmd/server/main.go` (wire repo into resolver)

- [ ] **Step 1: Add `FixtureGroupRepo` to the `Resolver` struct**

In `internal/graphql/resolvers/resolver.go`, locate the `Resolver` struct definition and add the new field alongside the existing repo fields:

```go
type Resolver struct {
	// ... existing repo fields ...
	FixtureGroupRepo *repositories.FixtureGroupRepository
}
```

In `cmd/server/main.go`, locate where `&resolvers.Resolver{...}` is constructed (the GraphQL server setup). Add:

```go
		FixtureGroupRepo: repositories.NewFixtureGroupRepository(db),
```

- [ ] **Step 2: Create `fixture_group_resolvers.go`**

```go
package resolvers

import (
	"context"
	"errors"
	"fmt"

	"github.com/bbernstein/lacylights-go/internal/database/models"
	"github.com/bbernstein/lacylights-go/internal/database/repositories"
	"github.com/bbernstein/lacylights-go/internal/graphql/generated"
	"gorm.io/gorm"
)

// fixtureGroupToGraphQL converts a model to its generated wire shape.
// Centralized here so every resolver returns the same field set —
// avoids drift if a column is added later.
func (r *Resolver) fixtureGroupToGraphQL(ctx context.Context, g *models.FixtureGroup) (*generated.FixtureGroup, error) {
	proj, err := r.ProjectRepo.FindByID(ctx, g.ProjectID)
	if err != nil {
		return nil, err
	}
	fixtures, err := r.fixturesForGroup(ctx, g.ID)
	if err != nil {
		return nil, err
	}
	return &generated.FixtureGroup{
		ID:           g.ID,
		RefID:        g.RefID,
		Name:         g.Name,
		Description:  g.Description,
		EosNumber:    g.EosNumber,
		ProjectOrder: g.ProjectOrder,
		Project:      projectModelToGraphQL(proj), // existing helper in resolvers
		Fixtures:     fixtures,
		CreatedAt:    g.CreatedAt.UTC().Format("2006-01-02T15:04:05Z"),
		UpdatedAt:    g.UpdatedAt.UTC().Format("2006-01-02T15:04:05Z"),
	}, nil
}

// fixturesForGroup loads members ordered by OrderIndex, then resolves to
// FixtureInstance models in the same order.
func (r *Resolver) fixturesForGroup(ctx context.Context, groupID string) ([]*generated.FixtureInstance, error) {
	members, err := r.FixtureGroupRepo.GetMembers(ctx, groupID)
	if err != nil {
		return nil, err
	}
	out := make([]*generated.FixtureInstance, 0, len(members))
	for _, m := range members {
		fi, err := r.FixtureRepo.FindByID(ctx, m.FixtureID)
		if err != nil {
			return nil, err
		}
		if fi == nil {
			continue // member references a deleted fixture; skip
		}
		out = append(out, fixtureInstanceModelToGraphQL(fi)) // existing helper
	}
	return out, nil
}

// FixtureGroupQuery resolves Query.fixtureGroup(id).
func (r *Resolver) FixtureGroupQuery(ctx context.Context, id string) (*generated.FixtureGroup, error) {
	g, err := r.FixtureGroupRepo.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if g == nil {
		return nil, nil
	}
	if err := r.ensureProjectAccess(ctx, g.ProjectID); err != nil {
		return nil, err
	}
	return r.fixtureGroupToGraphQL(ctx, g)
}

// FixtureGroupsQuery resolves Query.fixtureGroups(projectId).
func (r *Resolver) FixtureGroupsQuery(ctx context.Context, projectID string) ([]*generated.FixtureGroup, error) {
	if err := r.ensureProjectAccess(ctx, projectID); err != nil {
		return nil, err
	}
	gs, err := r.FixtureGroupRepo.FindByProjectID(ctx, projectID)
	if err != nil {
		return nil, err
	}
	out := make([]*generated.FixtureGroup, 0, len(gs))
	for i := range gs {
		gql, err := r.fixtureGroupToGraphQL(ctx, &gs[i])
		if err != nil {
			return nil, err
		}
		out = append(out, gql)
	}
	return out, nil
}

// CreateFixtureGroup resolves Mutation.createFixtureGroup.
func (r *Resolver) CreateFixtureGroup(ctx context.Context, input generated.CreateFixtureGroupInput) (*generated.FixtureGroup, error) {
	if err := r.ensureProjectAccess(ctx, input.ProjectID); err != nil {
		return nil, err
	}
	if err := r.assertFixturesInProject(ctx, input.ProjectID, input.FixtureIds); err != nil {
		return nil, err
	}
	g := &models.FixtureGroup{
		ProjectID:   input.ProjectID,
		Name:        input.Name,
		Description: input.Description,
		EosNumber:   input.EosNumber,
	}
	if err := r.FixtureGroupRepo.CreateWithMembers(ctx, g, input.FixtureIds); err != nil {
		return nil, err
	}
	return r.fixtureGroupToGraphQL(ctx, g)
}

// UpdateFixtureGroup resolves Mutation.updateFixtureGroup.
func (r *Resolver) UpdateFixtureGroup(ctx context.Context, input generated.UpdateFixtureGroupInput) (*generated.FixtureGroup, error) {
	g, err := r.FixtureGroupRepo.FindByID(ctx, input.ID)
	if err != nil {
		return nil, err
	}
	if g == nil {
		return nil, fmt.Errorf("fixture group %s not found", input.ID)
	}
	if err := r.ensureProjectAccess(ctx, g.ProjectID); err != nil {
		return nil, err
	}
	if input.Name != nil {
		g.Name = *input.Name
	}
	if input.Description != nil {
		g.Description = input.Description
	}
	if input.EosNumber != nil {
		g.EosNumber = input.EosNumber
	}
	if input.ProjectOrder != nil {
		g.ProjectOrder = input.ProjectOrder
	}
	if err := r.FixtureGroupRepo.Update(ctx, g); err != nil {
		return nil, err
	}
	return r.fixtureGroupToGraphQL(ctx, g)
}

// DeleteFixtureGroup resolves Mutation.deleteFixtureGroup.
func (r *Resolver) DeleteFixtureGroup(ctx context.Context, id string) (bool, error) {
	g, err := r.FixtureGroupRepo.FindByID(ctx, id)
	if err != nil {
		return false, err
	}
	if g == nil {
		return false, nil
	}
	if err := r.ensureProjectAccess(ctx, g.ProjectID); err != nil {
		return false, err
	}
	if err := r.FixtureGroupRepo.Delete(ctx, id); err != nil {
		return false, err
	}
	return true, nil
}

// AddFixturesToGroup, RemoveFixturesFromGroup, ReorderFixturesInGroup
// share the same auth + reload-and-return pattern.

func (r *Resolver) AddFixturesToGroup(ctx context.Context, groupID string, fixtureIDs []string) (*generated.FixtureGroup, error) {
	g, err := r.requireGroup(ctx, groupID)
	if err != nil {
		return nil, err
	}
	if err := r.assertFixturesInProject(ctx, g.ProjectID, fixtureIDs); err != nil {
		return nil, err
	}
	if err := r.FixtureGroupRepo.AddMembers(ctx, groupID, fixtureIDs); err != nil {
		return nil, err
	}
	return r.fixtureGroupToGraphQL(ctx, g)
}

func (r *Resolver) RemoveFixturesFromGroup(ctx context.Context, groupID string, fixtureIDs []string) (*generated.FixtureGroup, error) {
	g, err := r.requireGroup(ctx, groupID)
	if err != nil {
		return nil, err
	}
	if err := r.FixtureGroupRepo.RemoveMembers(ctx, groupID, fixtureIDs); err != nil {
		return nil, err
	}
	return r.fixtureGroupToGraphQL(ctx, g)
}

func (r *Resolver) ReorderFixturesInGroup(ctx context.Context, input generated.ReorderFixturesInGroupInput) (*generated.FixtureGroup, error) {
	g, err := r.requireGroup(ctx, input.GroupID)
	if err != nil {
		return nil, err
	}
	if err := r.FixtureGroupRepo.ReorderMembers(ctx, input.GroupID, input.FixtureIds); err != nil {
		return nil, err
	}
	return r.fixtureGroupToGraphQL(ctx, g)
}

// requireGroup loads the group and gates project access. Helpers above
// share this so the auth check is in one place.
func (r *Resolver) requireGroup(ctx context.Context, id string) (*models.FixtureGroup, error) {
	g, err := r.FixtureGroupRepo.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if g == nil {
		return nil, fmt.Errorf("fixture group %s not found", id)
	}
	if err := r.ensureProjectAccess(ctx, g.ProjectID); err != nil {
		return nil, err
	}
	return g, nil
}

// assertFixturesInProject ensures every supplied fixtureID belongs to the
// expected project. Without this check, a caller could add fixtures from
// a different project to a group, breaking the project-scoped invariant.
func (r *Resolver) assertFixturesInProject(ctx context.Context, projectID string, fixtureIDs []string) error {
	for _, id := range fixtureIDs {
		fi, err := r.FixtureRepo.FindByID(ctx, id)
		if err != nil {
			return err
		}
		if fi == nil {
			return fmt.Errorf("fixture %s not found", id)
		}
		if fi.ProjectID != projectID {
			return fmt.Errorf("fixture %s belongs to project %s, expected %s", id, fi.ProjectID, projectID)
		}
	}
	return nil
}

// Bulk variants — straightforward fanout. Atomic semantics are not
// promised: a partial failure leaves earlier successes committed.
// Callers (notably MCP) are expected to retry idempotently.
func (r *Resolver) BulkCreateFixtureGroups(ctx context.Context, inputs []*generated.CreateFixtureGroupInput) ([]*generated.FixtureGroup, error) {
	out := make([]*generated.FixtureGroup, 0, len(inputs))
	for _, in := range inputs {
		g, err := r.CreateFixtureGroup(ctx, *in)
		if err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, nil
}

func (r *Resolver) BulkUpdateFixtureGroups(ctx context.Context, inputs []*generated.UpdateFixtureGroupInput) ([]*generated.FixtureGroup, error) {
	out := make([]*generated.FixtureGroup, 0, len(inputs))
	for _, in := range inputs {
		g, err := r.UpdateFixtureGroup(ctx, *in)
		if err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, nil
}

func (r *Resolver) BulkDeleteFixtureGroups(ctx context.Context, ids []string) (int, error) {
	count := 0
	for _, id := range ids {
		ok, err := r.DeleteFixtureGroup(ctx, id)
		if err != nil {
			return count, err
		}
		if ok {
			count++
		}
	}
	return count, nil
}

// Suppress unused imports if helpers above don't use them yet.
var (
	_ = errors.New
	_ = repositories.ErrChannelOffsetNotFound
	_ = (*gorm.DB)(nil)
)
```

If this file references helper functions that don't exist yet (`projectModelToGraphQL`, `fixtureInstanceModelToGraphQL`, `ensureProjectAccess`), grep `internal/graphql/resolvers/` for similar functions and use the actual names. Common forms in this codebase:

- `r.ensureProjectAccess(ctx, projectID) error` — defined somewhere in the resolvers package; per memory notes from the multi-tenant work.
- Model→GraphQL converters — usually inline at resolver call sites; if there isn't a `projectModelToGraphQL`, build a `*generated.Project` literal inline.

Read `internal/graphql/resolvers/helpers.go` and `auth_resolvers.go` first to find the exact names before saving this file. Replace placeholder calls with the real ones.

- [ ] **Step 3: Wire generated stubs to helpers in `schema.resolvers.go`**

For each generated stub gqlgen produced (e.g., `func (r *queryResolver) FixtureGroup(ctx context.Context, id string) (*generated.FixtureGroup, error)`), replace the `panic("not implemented")` body with a one-line delegation:

```go
func (r *queryResolver) FixtureGroup(ctx context.Context, id string) (*generated.FixtureGroup, error) {
	return r.FixtureGroupQuery(ctx, id)
}

func (r *queryResolver) FixtureGroups(ctx context.Context, projectID string) ([]*generated.FixtureGroup, error) {
	return r.FixtureGroupsQuery(ctx, projectID)
}

// ... and similarly for every mutation stub.
```

The exact list of stubs depends on what gqlgen wrote — search the file for `not implemented` and replace each.

- [ ] **Step 4: Build to confirm wiring**

```bash
go build ./...
```

Fix any reference errors (commonly: helper function names, generated type field types).

- [ ] **Step 5: Test resolver — happy path + auth gate**

Create `internal/graphql/resolvers/fixture_group_resolvers_test.go`. Mirror the pattern from `eos_resolver_test.go` for setting up an in-memory test client.

```go
package resolvers

import (
	"context"
	"testing"

	"github.com/bbernstein/lacylights-go/internal/database/models"
	"github.com/bbernstein/lacylights-go/internal/database/repositories"
	"github.com/bbernstein/lacylights-go/internal/graphql/generated"
)

// Reuse whatever test helper newTestResolver / newTestClient pattern exists
// in the resolvers package (see eos_resolver_test.go for the existing
// idiom). The harness below sketches the calls; replace setup helpers
// with the package's actual ones during implementation.

func TestResolver_CreateAndQueryFixtureGroup(t *testing.T) {
	r, td := newTestResolver(t) // existing helper in this package
	ctx := authedCtx(t, td, "project-1") // existing helper

	// Seed two fixtures in project-1.
	a := seedFixture(t, td, "project-1", "ch-1") // existing or new helper
	b := seedFixture(t, td, "project-1", "ch-2")

	in := generated.CreateFixtureGroupInput{
		ProjectID:  "project-1",
		Name:       "Movers",
		FixtureIds: []string{a.ID, b.ID},
	}
	g, err := r.CreateFixtureGroup(ctx, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if g.Name != "Movers" {
		t.Errorf("name = %q", g.Name)
	}
	if len(g.Fixtures) != 2 {
		t.Errorf("members = %d", len(g.Fixtures))
	}

	// Query it back.
	q, err := r.FixtureGroupQuery(ctx, g.ID)
	if err != nil || q == nil {
		t.Fatalf("query: %v %v", q, err)
	}
}

func TestResolver_FixtureGroupAuthGate(t *testing.T) {
	r, td := newTestResolver(t)
	otherCtx := authedCtx(t, td, "project-OTHER")
	a := seedFixture(t, td, "project-1", "ch-1")
	g := &models.FixtureGroup{ProjectID: "project-1", Name: "G"}
	if err := td.fixtureGroupRepo.CreateWithMembers(context.Background(), g, []string{a.ID}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if _, err := r.FixtureGroupQuery(otherCtx, g.ID); err == nil {
		t.Errorf("expected access denial")
	}
}

func TestResolver_AddRemoveReorderFixturesInGroup(t *testing.T) {
	r, td := newTestResolver(t)
	ctx := authedCtx(t, td, "project-1")
	a := seedFixture(t, td, "project-1", "ch-1")
	b := seedFixture(t, td, "project-1", "ch-2")
	c := seedFixture(t, td, "project-1", "ch-3")

	g, _ := r.CreateFixtureGroup(ctx, generated.CreateFixtureGroupInput{
		ProjectID:  "project-1",
		Name:       "G",
		FixtureIds: []string{a.ID},
	})

	if _, err := r.AddFixturesToGroup(ctx, g.ID, []string{b.ID, c.ID}); err != nil {
		t.Fatalf("add: %v", err)
	}
	if _, err := r.ReorderFixturesInGroup(ctx, generated.ReorderFixturesInGroupInput{
		GroupID:    g.ID,
		FixtureIds: []string{c.ID, a.ID, b.ID},
	}); err != nil {
		t.Fatalf("reorder: %v", err)
	}
	// Round-trip the order through a query.
	q, _ := r.FixtureGroupQuery(ctx, g.ID)
	if len(q.Fixtures) != 3 || q.Fixtures[0].ID != c.ID {
		t.Errorf("post-reorder fixtures: %v", q.Fixtures)
	}
}

// If newTestResolver / authedCtx / seedFixture aren't already exported,
// see eos_resolver_test.go and crud_test.go in this package for how the
// existing tests build them — duplicate the convention.

var _ = repositories.NewFixtureGroupRepository
```

Run:

```bash
ARTNET_ENABLED=false go test ./internal/graphql/resolvers/ -v -run FixtureGroup
```

Expected: 3 tests pass.

- [ ] **Step 6: Resolver: also expose `refId` on the four existing types**

For each of `FixtureInstance`, `FixtureDefinition`, `Look`, `LookBoard`, gqlgen will generate a stub field resolver if the struct doesn't already include `RefID`. Two cases:

- If the model→gql converters used in the resolvers populate `RefID` directly (the generated GraphQL struct now has a `RefID string` field after `make generate`), no additional resolver work is needed — the field is read from the model.
- If gqlgen generates a method-based field resolver, implement it on the appropriate `*xxxResolver`:

```go
func (r *fixtureInstanceResolver) RefID(ctx context.Context, obj *generated.FixtureInstance) (string, error) {
	return obj.RefID, nil
}
```

Run `go build ./...` after Task 9 Step 4 — gqlgen errors will show which case applies.

- [ ] **Step 7: Commit**

```bash
git add internal/graphql/
git add cmd/server/main.go
git commit -m "feat(graphql): implement FixtureGroup resolvers + refId field

Helpers in fixture_group_resolvers.go cover CRUD, membership ops, and
bulk variants; schema.resolvers.go stubs delegate to them. RefID is
exposed read-only on FixtureInstance/FixtureDefinition/Look/LookBoard.
Project-access auth gates every entrypoint via ensureProjectAccess."
```

---

## Phase 4 — Mapper integration (importer)

### Task 10: Add `WarnGroupChannelUnresolved` and structured-kind sidecar warnings

**Files:**
- Modify: `internal/services/import_eos/warnings.go`

- [ ] **Step 1: Add the new warning code**

In `warnings.go`, add to the `WarningCode` const block (alphabetized region):

```go
	WarnGroupChannelUnresolved WarningCode = "GROUP_CHANNEL_UNRESOLVED"
```

- [ ] **Step 2: Build**

```bash
go build ./internal/services/import_eos/...
```

- [ ] **Step 3: Commit**

```bash
git add internal/services/import_eos/warnings.go
git commit -m "feat(import_eos): add WarnGroupChannelUnresolved warning code

Used by the Task 14c mapper when a \$Group block references a channel
that wasn't patched in the same file. The group is still created with
the resolvable members; missing channels surface as one warning per
miss for review."
```

---

### Task 11: Deterministic RefID derivation in the importer

**Files:**
- Modify: `internal/services/import_eos/mapper.go`

The mapper currently lets `RefID` default to the row's CUID. For round-trip stability we need each EOS-derived entity's RefID to be a function of its EOS data, not of which CUID GORM happens to mint.

- [ ] **Step 1: Define ref-id helpers near the top of `mapper.go`**

After the package-level constants (around line 26), add:

```go
// EOS-derived RefID formats. Stable across re-imports: the same input
// file always yields the same RefIDs regardless of how many times it's
// imported into how many fresh projects. This is what makes the
// $$ LACYLIGHTS: sidecar resolve cleanly on round-trip.
func eosFixtureInstanceRefID(eosChannel int) string {
	return fmt.Sprintf("ch-%d", eosChannel)
}

func eosLookRefIDForCue(cueListNumber int, cueNumber float64) string {
	return fmt.Sprintf("cue-%d-%s", cueListNumber, formatCueNumber(cueNumber))
}

func eosLookRefIDForPalette(paletteKind, paletteNumber string) string {
	return fmt.Sprintf("palette-%s-%s", paletteKind, paletteNumber)
}

func eosFixtureDefRefID(manufacturer, model string) string {
	return fmt.Sprintf("def-%s-%s", strings.ReplaceAll(manufacturer, "/", "_"), strings.ReplaceAll(model, "/", "_"))
}

// formatCueNumber matches the export side's cue-number formatting — it
// strips trailing zeros so that 1.5 → "1.5" and 1.0 → "1".
func formatCueNumber(n float64) string {
	s := strconv.FormatFloat(n, 'f', -1, 64)
	if !strings.Contains(s, ".") {
		return s
	}
	s = strings.TrimRight(s, "0")
	s = strings.TrimRight(s, ".")
	if s == "" {
		s = "0"
	}
	return s
}
```

Add `"strings"` to the imports if not already present.

- [ ] **Step 2: Set RefID on `FixtureInstance` creation**

Find the loop in `Apply()` that creates `FixtureInstance`s (around line 140). Add the RefID assignment to the struct literal:

```go
		instance := &models.FixtureInstance{
			ProjectID:    projectID,
			DefinitionID: defID,
			Name:         label,
			Universe:     universe,
			StartChannel: address,
			ProjectOrder: &order,
			RefID:        eosFixtureInstanceRefID(pe.Channel),
		}
```

- [ ] **Step 3: Set RefID on synthesized `FixtureDefinition` creation**

Find where `mr.SynthesizedDef` is created (around line 81). Before `m.fixtureRepo.CreateDefinitionWithChannels`, add:

```go
		mr.SynthesizedDef.RefID = eosFixtureDefRefID(mr.SynthesizedDef.Manufacturer, mr.SynthesizedDef.Model)
		if err := m.fixtureRepo.CreateDefinitionWithChannels(ctx, mr.SynthesizedDef, mr.SynthesizedChannels); err != nil {
			return nil, fmt.Errorf("create synth def: %w", err)
		}
```

For matched (existing) definitions there's nothing to do — they already have a RefID from a prior creation.

- [ ] **Step 4: Set RefID on `Look` creation in `applyCues`**

Find `applyCues` and locate the loop where each cue's `Look` is created. Add the RefID:

```go
		look := &models.Look{
			ProjectID: projectID,
			Name:      lookName,
			RefID:     eosLookRefIDForCue(cueListNumber, cueNum),
		}
```

`cueListNumber` is the integer cue-list number being processed; locate its source in the surrounding code (likely a loop variable or `show.CueLists[i].Number`).

For looks created in `applyPalettes`, use `eosLookRefIDForPalette`:

```go
		look := &models.Look{
			ProjectID: projectID,
			Name:      lookName,
			RefID:     eosLookRefIDForPalette(paletteKind, palette.Number),
		}
```

`paletteKind` is one of `"color"`, `"beam"`, `"focus"`, `"intensity"`, `"preset"` — pick based on which palette type is being processed (the existing code already discriminates).

- [ ] **Step 5: Build to verify**

```bash
go build ./internal/services/import_eos/...
```

- [ ] **Step 6: Add a determinism test**

In `mapper_test.go`:

```go
func TestMapper_RefIDsDeterministicAcrossProjects(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()

	// Import the same minimal patch into two distinct fresh projects.
	importInto := func(name string) string {
		f := openFixtureFile(t, "minimal_patch.asc")
		defer f.Close()
		svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo,
			deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
		res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr(name)})
		if err != nil {
			t.Fatalf("import %s: %v", name, err)
		}
		return res.ProjectID
	}

	p1 := importInto("Project A")
	p2 := importInto("Project B")

	a, _ := deps.fixtureRepo.FindByProjectID(context.Background(), p1)
	b, _ := deps.fixtureRepo.FindByProjectID(context.Background(), p2)
	if len(a) != len(b) {
		t.Fatalf("instance counts differ: %d vs %d", len(a), len(b))
	}
	// Sort by ProjectOrder (= EOS channel) so we compare the same fixture pair.
	sortByOrder := func(s []models.FixtureInstance) {
		sort.Slice(s, func(i, j int) bool {
			oi, oj := 0, 0
			if s[i].ProjectOrder != nil {
				oi = *s[i].ProjectOrder
			}
			if s[j].ProjectOrder != nil {
				oj = *s[j].ProjectOrder
			}
			return oi < oj
		})
	}
	sortByOrder(a)
	sortByOrder(b)
	for i := range a {
		if a[i].RefID != b[i].RefID {
			t.Errorf("RefID mismatch at index %d: %q vs %q", i, a[i].RefID, b[i].RefID)
		}
		if !strings.HasPrefix(a[i].RefID, "ch-") {
			t.Errorf("expected EOS-derived RefID, got %q", a[i].RefID)
		}
	}
}
```

Add imports: `"sort"`, `"strings"`.

- [ ] **Step 7: Run the test**

```bash
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v -run TestMapper_RefIDsDeterministic
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go
git commit -m "feat(import_eos): assign deterministic EOS-derived RefIDs

FixtureInstance.RefID = ch-<eosChannel>
FixtureDefinition.RefID (synthesized) = def-<manuf>-<model>
Look.RefID = cue-<cueListNumber>-<cueNumber> | palette-<kind>-<num>

Same input file → same RefIDs across re-imports into fresh projects.
This is what makes the sidecar resolve correctly on round-trip."
```

---

### Task 12: Implement `applyGroups`

**Files:**
- Modify: `internal/services/import_eos/mapper.go`

- [ ] **Step 1: Add `fixtureGroupRepo` to the `Mapper` struct + constructor**

Update the `Mapper` struct (line ~29) and `NewMapper` (line ~39):

```go
type Mapper struct {
	projectRepo      *repositories.ProjectRepository
	fixtureRepo      *repositories.FixtureRepository
	fixtureGroupRepo *repositories.FixtureGroupRepository
	lookRepo         *repositories.LookRepository
	cueListRepo      *repositories.CueListRepository
	cueRepo          *repositories.CueRepository
	lookBoardRepo    *repositories.LookBoardRepository
}

func NewMapper(
	p *repositories.ProjectRepository,
	f *repositories.FixtureRepository,
	fg *repositories.FixtureGroupRepository,
	l *repositories.LookRepository,
	cl *repositories.CueListRepository,
	c *repositories.CueRepository,
	lb *repositories.LookBoardRepository,
) *Mapper {
	return &Mapper{p, f, fg, l, cl, c, lb}
}
```

- [ ] **Step 2: Update `Service` to plumb the new repo through**

Open `internal/services/import_eos/service.go`. Locate the service's repo fields and `NewServiceWithDeps`. Add `fixtureGroupRepo` as a parameter and wire it to `NewMapper`. Mirror the field order in `Mapper`.

- [ ] **Step 3: Replace the `applyGroups` stub**

Replace the existing function body (lines 505-516) with:

```go
func (m *Mapper) applyGroups(ctx context.Context, projectID string, show *Show, chToFix map[int]string, groupsCount *int, warn *Collector) error {
	for _, g := range show.Groups {
		// Resolve group members from EOS channel numbers to fixture IDs.
		fixtureIDs := make([]string, 0, len(g.Channels))
		for _, ch := range g.Channels {
			fid, ok := chToFix[ch]
			if !ok {
				warn.Add(WarnGroupChannelUnresolved, SeverityWarn,
					fmt.Sprintf("group %s references unpatched channel %d", g.Number, ch),
					map[string]string{
						"groupNumber": g.Number,
						"channel":     strconv.Itoa(ch),
					})
				continue
			}
			fixtureIDs = append(fixtureIDs, fid)
		}

		name := g.Label
		if name == "" && g.UnicodeText != nil {
			name = *g.UnicodeText
		}
		if name == "" {
			name = fmt.Sprintf("Group %s", g.Number)
		}

		var eosNumber *int
		if n, err := strconv.Atoi(g.Number); err == nil {
			eosNumber = &n
		}

		// Idempotent re-import: if a group with the same EosNumber already
		// exists in this project, update its name and members rather than
		// creating a duplicate.
		if eosNumber != nil {
			existing, err := m.fixtureGroupRepo.FindByEosNumber(ctx, projectID, *eosNumber)
			if err != nil {
				return fmt.Errorf("find existing group: %w", err)
			}
			if existing != nil {
				existing.Name = name
				if err := m.fixtureGroupRepo.Update(ctx, existing); err != nil {
					return fmt.Errorf("update group: %w", err)
				}
				if err := m.fixtureGroupRepo.SetMembers(ctx, existing.ID, fixtureIDs); err != nil {
					return fmt.Errorf("set members: %w", err)
				}
				*groupsCount++
				continue
			}
		}

		fg := &models.FixtureGroup{
			ProjectID: projectID,
			Name:      name,
			EosNumber: eosNumber,
		}
		if err := m.fixtureGroupRepo.CreateWithMembers(ctx, fg, fixtureIDs); err != nil {
			return fmt.Errorf("create group: %w", err)
		}
		*groupsCount++
	}
	return nil
}
```

- [ ] **Step 4: Update the `Apply()` callsite (line ~169)**

Change:

```go
	if err := m.applyGroups(ctx, projectID, show, &res.GroupsCount, warn); err != nil {
```

to:

```go
	if err := m.applyGroups(ctx, projectID, show, eosChannelToInstanceID, &res.GroupsCount, warn); err != nil {
```

- [ ] **Step 5: Update test deps to include the new repo**

In `internal/services/import_eos/testdeps_test.go`, add the new repo:

```go
type testDeps struct {
	db               *gorm.DB
	projectRepo      *repositories.ProjectRepository
	fixtureRepo      *repositories.FixtureRepository
	fixtureGroupRepo *repositories.FixtureGroupRepository
	// ... rest unchanged ...
}
```

In the AutoMigrate list, add:

```go
		&models.FixtureGroup{},
		&models.FixtureGroupMember{},
```

In the return:

```go
		fixtureGroupRepo: repositories.NewFixtureGroupRepository(db),
```

Anywhere `NewServiceWithDeps` or `NewMapper` is called in tests, update the call to pass the new repo.

- [ ] **Step 6: Add `MustListGroupsByProject` test helper**

Append to `testdeps_test.go`:

```go
func (d *testDeps) MustListGroupsByProject(t *testing.T, projectID string) []models.FixtureGroup {
	t.Helper()
	gs, err := d.fixtureGroupRepo.FindByProjectID(context.Background(), projectID)
	if err != nil {
		t.Fatalf("list groups: %v", err)
	}
	return gs
}
```

Add `"context"` import.

- [ ] **Step 7: Add test fixture `groups_only.asc`**

Create `internal/services/import_eos/testdata/groups_only.asc`. Minimum viable content (mirror `presets_groups.asc` if it exists; otherwise:

```
Ident 3:0
Manufacturer ETC
Console Eos

$ParamType 1 Intensity
$$ColorAttribute 1

$Personality 1
$$Manuf Generic
$$Model Dimmer
$$Footprint 1
$$PersChan 1 1 1 0 0

$Patch 1 1 1
   Text Light A
$Patch 2 2 1
   Text Light B
$Patch 3 3 1
   Text Light C

$Group 1
   Text SR Specials
   1 2

$Group 2
   Text All Lights
   1 Thru 3
```

- [ ] **Step 8: Mapper test for group creation**

In `mapper_test.go`:

```go
func TestMapper_GroupsCreated(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()

	f := openFixtureFile(t, "groups_only.asc")
	defer f.Close()

	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("Test Show")})
	if err != nil {
		t.Fatalf("Import: %v", err)
	}
	if res.GroupsCount != 2 {
		t.Errorf("GroupsCount = %d, want 2", res.GroupsCount)
	}

	groups := deps.MustListGroupsByProject(t, res.ProjectID)
	if len(groups) != 2 {
		t.Fatalf("got %d groups, want 2", len(groups))
	}

	byEos := map[int]models.FixtureGroup{}
	for _, g := range groups {
		if g.EosNumber == nil {
			t.Errorf("group %s has nil EosNumber", g.Name)
			continue
		}
		byEos[*g.EosNumber] = g
	}

	if got := byEos[1].Name; got != "SR Specials" {
		t.Errorf("group 1 name = %q", got)
	}
	if got := byEos[2].Name; got != "All Lights" {
		t.Errorf("group 2 name = %q", got)
	}

	// Membership check: group 2 should have 3 fixtures.
	ms2, err := deps.fixtureGroupRepo.GetMembers(context.Background(), byEos[2].ID)
	if err != nil {
		t.Fatalf("members: %v", err)
	}
	if len(ms2) != 3 {
		t.Errorf("group 2 members = %d, want 3", len(ms2))
	}
}

func TestMapper_GroupChannelUnresolvedWarn(t *testing.T) {
	// Construct an in-memory .asc with a group that references channel 99
	// (not in the patch). Verify the warning is emitted and the resolvable
	// members still land.
	asc := `Ident 3:0
$ParamType 1 Intensity
$Personality 1
$$Manuf Generic
$$Model Dimmer
$$Footprint 1
$$PersChan 1 1 1 0 0
$Patch 1 1 1
   Text A
$Group 1
   Text Mostly
   1 99
`
	deps := newTestDeps(t)
	defer deps.close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), strings.NewReader(asc), Options{NewProjectName: ptr("T")})
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if res.GroupsCount != 1 {
		t.Errorf("GroupsCount = %d", res.GroupsCount)
	}
	saw := false
	for _, w := range res.Warnings {
		if w.Code == WarnGroupChannelUnresolved {
			saw = true
		}
	}
	if !saw {
		t.Errorf("expected WarnGroupChannelUnresolved")
	}
}
```

Add the imports as needed: `"strings"`.

- [ ] **Step 9: Run mapper tests**

```bash
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v -run TestMapper_Group
```

Expected: 2 tests pass.

- [ ] **Step 10: Commit**

```bash
git add internal/services/import_eos/ internal/services/import_eos/testdata/groups_only.asc
git commit -m "feat(import_eos): persist \$Group blocks via FixtureGroup model

applyGroups now resolves EOS channel numbers to FixtureInstance IDs via
the existing eosChannelToInstanceID map and persists groups with a
FixtureGroup row + members. Idempotent re-import via FindByEosNumber.
Channels that don't resolve emit WarnGroupChannelUnresolved per miss."
```

---

### Task 13: Implement `applySidecar` — look boards

**Files:**
- Modify: `internal/services/import_eos/mapper.go`

- [ ] **Step 1: Replace the `applySidecar` stub with the look-board branch**

Begin by replacing the body to handle look boards (other branches stay no-op for now):

```go
func (m *Mapper) applySidecar(ctx context.Context, projectID string, sc Sidecar, warn *Collector) error {
	if err := m.applySidecarLookBoards(ctx, projectID, sc.LookBoards, warn); err != nil {
		return err
	}
	if err := m.applySidecarFadeBehaviors(ctx, projectID, sc.FadeBehaviors, warn); err != nil {
		return err
	}
	if err := m.applySidecarSynthDefs(ctx, projectID, sc.SynthDefs, warn); err != nil {
		return err
	}
	return nil
}

func (m *Mapper) applySidecarLookBoards(ctx context.Context, projectID string, boards []SidecarLookBoard, warn *Collector) error {
	if len(boards) == 0 {
		return nil
	}
	// Collect all referenced look refIDs and resolve in one query.
	refIDSet := map[string]struct{}{}
	for _, b := range boards {
		for _, btn := range b.Buttons {
			refIDSet[btn.LookRefID] = struct{}{}
		}
	}
	refIDs := make([]string, 0, len(refIDSet))
	for r := range refIDSet {
		refIDs = append(refIDs, r)
	}
	lookByRef, err := m.lookRepo.MapByRefID(ctx, projectID, refIDs)
	if err != nil {
		return fmt.Errorf("resolve look refids: %w", err)
	}

	for _, b := range boards {
		buttons := make([]models.LookBoardButton, 0, len(b.Buttons))
		for _, btn := range b.Buttons {
			lookID, ok := lookByRef[btn.LookRefID]
			if !ok {
				warn.Add(WarnSidecarUnresolved, SeverityWarn,
					fmt.Sprintf("look board %q references unknown look %q", b.RefID, btn.LookRefID),
					map[string]string{
						"kind":        "look_board_button",
						"boardRefId":  b.RefID,
						"lookRefId":   btn.LookRefID,
					})
				continue
			}
			color := btn.Color
			buttons = append(buttons, models.LookBoardButton{
				LookID:   lookID,
				LayoutX:  btn.X,
				LayoutY:  btn.Y,
				Color:    &color,
			})
		}

		// Idempotent: update existing board with same RefID, else create.
		existing, err := m.lookBoardRepo.FindByRefID(ctx, projectID, b.RefID)
		if err != nil {
			return fmt.Errorf("find look board: %w", err)
		}
		if existing != nil {
			existing.Name = b.Name
			if err := m.lookBoardRepo.Update(ctx, existing); err != nil {
				return fmt.Errorf("update look board: %w", err)
			}
			if err := m.lookBoardRepo.DeleteButtons(ctx, existing.ID); err != nil {
				return fmt.Errorf("delete buttons: %w", err)
			}
			for i := range buttons {
				buttons[i].LookBoardID = existing.ID
			}
			if len(buttons) > 0 {
				if err := m.lookBoardRepo.CreateButtons(ctx, buttons); err != nil {
					return fmt.Errorf("recreate buttons: %w", err)
				}
			}
			continue
		}
		board := &models.LookBoard{
			ProjectID: projectID,
			Name:      b.Name,
			RefID:     b.RefID,
		}
		if err := m.lookBoardRepo.CreateWithButtons(ctx, board, buttons); err != nil {
			return fmt.Errorf("create look board: %w", err)
		}
	}
	return nil
}

// applySidecarFadeBehaviors and applySidecarSynthDefs are stubs filled
// in by Tasks 14 and 15.
func (m *Mapper) applySidecarFadeBehaviors(ctx context.Context, projectID string, fbs []SidecarFadeBehavior, warn *Collector) error {
	return nil
}

func (m *Mapper) applySidecarSynthDefs(ctx context.Context, projectID string, sds []SidecarSynthDef, warn *Collector) error {
	return nil
}
```

- [ ] **Step 2: Test with a look-board sidecar fixture**

Locate `testdata/sidecar_roundtrip.asc` (per resumption-state memory it should exist). If it doesn't, create it minimally:

```
Ident 3:0
$ParamType 1 Intensity
$Personality 1
$$Manuf Generic
$$Model Dimmer
$$Footprint 1
$$PersChan 1 1 1 0 0
$Patch 1 1 1
   Text A
$CueList 1
   $$NoteText "Main"
   $Cue 1 Cue 1
   1 100
$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:look_board {"refId":"board-a","name":"Top","buttons":[{"lookRefId":"cue-1-1","x":0,"y":0,"color":"#ff0000"}]}
```

The `lookRefId` matches what Task 11 makes the importer assign to the cue-1 look (`cue-1-1`).

- [ ] **Step 3: Add a mapper test**

```go
func TestMapper_SidecarLookBoardRebuilt(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()

	f := openFixtureFile(t, "sidecar_roundtrip.asc")
	defer f.Close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("T")})
	if err != nil {
		t.Fatalf("import: %v", err)
	}

	boards, _ := deps.lookBoardRepo.FindByProjectID(context.Background(), res.ProjectID)
	if len(boards) != 1 {
		t.Fatalf("got %d boards, want 1", len(boards))
	}
	if boards[0].Name != "Top" {
		t.Errorf("name = %q", boards[0].Name)
	}
	btns, _ := deps.lookBoardRepo.GetButtons(context.Background(), boards[0].ID)
	if len(btns) != 1 {
		t.Fatalf("got %d buttons, want 1", len(btns))
	}
	if btns[0].Color == nil || *btns[0].Color != "#ff0000" {
		t.Errorf("color = %v", btns[0].Color)
	}
}
```

- [ ] **Step 4: Test the unresolved-button case**

```go
func TestMapper_SidecarLookBoardUnresolvedButton(t *testing.T) {
	asc := `Ident 3:0
$ParamType 1 Intensity
$Personality 1
$$Manuf Generic
$$Model Dimmer
$$Footprint 1
$$PersChan 1 1 1 0 0
$Patch 1 1 1
   Text A
$CueList 1
   $Cue 1 Cue 1
   1 100
$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:look_board {"refId":"b1","name":"X","buttons":[{"lookRefId":"cue-1-1","x":0,"y":0,"color":"#ff"},{"lookRefId":"missing","x":1,"y":0,"color":"#00"}]}
`
	deps := newTestDeps(t)
	defer deps.close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), strings.NewReader(asc), Options{NewProjectName: ptr("T")})
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	boards, _ := deps.lookBoardRepo.FindByProjectID(context.Background(), res.ProjectID)
	if len(boards) != 1 {
		t.Fatalf("got %d boards", len(boards))
	}
	btns, _ := deps.lookBoardRepo.GetButtons(context.Background(), boards[0].ID)
	if len(btns) != 1 {
		t.Errorf("got %d buttons (should drop the unresolved one)", len(btns))
	}
	saw := false
	for _, w := range res.Warnings {
		if w.Code == WarnSidecarUnresolved && w.Context["kind"] == "look_board_button" {
			saw = true
		}
	}
	if !saw {
		t.Errorf("expected WarnSidecarUnresolved kind=look_board_button")
	}
}
```

- [ ] **Step 5: Run tests**

```bash
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v -run TestMapper_Sidecar
```

Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go
git add internal/services/import_eos/testdata/
git commit -m "feat(import_eos): apply sidecar look_board records

Resolves lookRefIds via LookRepository.MapByRefID, builds LookBoardButton
rows, idempotently reuses existing boards (matched by RefID) or creates
new ones. Unresolved button refIDs degrade to WarnSidecarUnresolved
{kind=look_board_button} rather than failing the whole record."
```

---

### Task 14: Implement `applySidecar` — fade behaviors

**Files:**
- Modify: `internal/services/import_eos/mapper.go`

- [ ] **Step 1: Implement `applySidecarFadeBehaviors`**

Replace the stub:

```go
func (m *Mapper) applySidecarFadeBehaviors(ctx context.Context, projectID string, fbs []SidecarFadeBehavior, warn *Collector) error {
	validBehaviors := map[string]bool{"FADE": true, "SNAP": true, "SNAP_END": true}
	for _, fb := range fbs {
		inst, err := m.fixtureRepo.FindInstanceByRefID(ctx, projectID, fb.InstanceRefID)
		if err != nil {
			return fmt.Errorf("find instance %s: %w", fb.InstanceRefID, err)
		}
		if inst == nil {
			warn.Add(WarnSidecarUnresolved, SeverityWarn,
				fmt.Sprintf("fade_behavior references unknown fixture %q", fb.InstanceRefID),
				map[string]string{
					"kind":          "fade_behavior",
					"instanceRefId": fb.InstanceRefID,
				})
			continue
		}
		for _, c := range fb.Channels {
			if !validBehaviors[c.Behavior] {
				warn.Add(WarnSidecarUnresolved, SeverityWarn,
					fmt.Sprintf("fade_behavior has invalid behavior %q for fixture %q offset %d",
						c.Behavior, fb.InstanceRefID, c.Offset),
					map[string]string{
						"kind":          "fade_behavior_invalid",
						"instanceRefId": fb.InstanceRefID,
						"offset":        strconv.Itoa(c.Offset),
						"behavior":      c.Behavior,
					})
				continue
			}
			err := m.fixtureRepo.UpdateInstanceChannelFadeBehavior(ctx, inst.ID, c.Offset, c.Behavior)
			if err != nil {
				if errors.Is(err, repositories.ErrChannelOffsetNotFound) {
					warn.Add(WarnSidecarUnresolved, SeverityWarn,
						fmt.Sprintf("fade_behavior offset %d not found on fixture %q", c.Offset, fb.InstanceRefID),
						map[string]string{
							"kind":          "fade_behavior_offset",
							"instanceRefId": fb.InstanceRefID,
							"offset":        strconv.Itoa(c.Offset),
						})
					continue
				}
				return fmt.Errorf("update fade behavior: %w", err)
			}
		}
	}
	return nil
}
```

- [ ] **Step 2: Tests**

```go
func TestMapper_SidecarFadeBehaviorApplied(t *testing.T) {
	asc := `Ident 3:0
$ParamType 1 Intensity
$ParamType 11 Red
$Personality 1
$$Manuf Generic
$$Model RGB
$$Footprint 3
$$PersChan 1 1 1 0 0
$$PersChan 11 1 2 0 0
$$PersChan 12 1 3 0 0
$Patch 1 1 1
   Text A
$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:fade_behavior {"instanceRefId":"ch-1","channels":[{"offset":1,"behavior":"SNAP_END"}]}
`
	deps := newTestDeps(t)
	defer deps.close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), strings.NewReader(asc), Options{NewProjectName: ptr("T")})
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	instances, _ := deps.fixtureRepo.FindByProjectID(context.Background(), res.ProjectID)
	if len(instances) != 1 {
		t.Fatalf("got %d instances, want 1", len(instances))
	}
	channels, _ := deps.fixtureRepo.GetInstanceChannels(context.Background(), instances[0].ID)
	want := map[int]string{0: "FADE", 1: "SNAP_END", 2: "FADE"}
	for _, c := range channels {
		if c.FadeBehavior != want[c.Offset] {
			t.Errorf("offset %d: %q, want %q", c.Offset, c.FadeBehavior, want[c.Offset])
		}
	}
}

func TestMapper_SidecarFadeBehaviorOffsetMissing(t *testing.T) {
	asc := `Ident 3:0
$ParamType 1 Intensity
$Personality 1
$$Manuf Generic
$$Model Dimmer
$$Footprint 1
$$PersChan 1 1 1 0 0
$Patch 1 1 1
   Text A
$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:fade_behavior {"instanceRefId":"ch-1","channels":[{"offset":99,"behavior":"SNAP"}]}
`
	deps := newTestDeps(t)
	defer deps.close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), strings.NewReader(asc), Options{NewProjectName: ptr("T")})
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	saw := false
	for _, w := range res.Warnings {
		if w.Code == WarnSidecarUnresolved && w.Context["kind"] == "fade_behavior_offset" {
			saw = true
		}
	}
	if !saw {
		t.Errorf("expected WarnSidecarUnresolved kind=fade_behavior_offset")
	}
}
```

- [ ] **Step 3: Run tests**

```bash
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v -run TestMapper_SidecarFade
```

Expected: 2 tests pass.

- [ ] **Step 4: Commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go
git commit -m "feat(import_eos): apply sidecar fade_behavior records

Per-channel FadeBehavior overrides are reapplied via the new
UpdateInstanceChannelFadeBehavior repo method. Unknown instances,
unknown offsets, and invalid behavior strings each surface as a
WarnSidecarUnresolved with a structured kind for FE grouping."
```

---

### Task 15: Implement `applySidecar` — synth defs (advisory)

**Files:**
- Modify: `internal/services/import_eos/mapper.go`

- [ ] **Step 1: Implement the advisory branch**

```go
func (m *Mapper) applySidecarSynthDefs(ctx context.Context, projectID string, sds []SidecarSynthDef, warn *Collector) error {
	for _, sd := range sds {
		def, err := m.fixtureRepo.FindDefinitionByRefID(ctx, sd.DefRefID)
		if err != nil {
			return fmt.Errorf("find def: %w", err)
		}
		if def == nil {
			warn.Add(WarnSidecarUnresolved, SeverityInfo,
				fmt.Sprintf("synth_def references unknown definition %q (%s/%s)",
					sd.DefRefID, sd.Manufacturer, sd.Model),
				map[string]string{
					"kind":         "synth_def",
					"defRefId":     sd.DefRefID,
					"manufacturer": sd.Manufacturer,
					"model":        sd.Model,
				})
			continue
		}
		// Found — already linked. No-op (informational).
	}
	return nil
}
```

- [ ] **Step 2: Test**

```go
func TestMapper_SidecarSynthDefAdvisory(t *testing.T) {
	asc := `Ident 3:0
$ParamType 1 Intensity
$Personality 1
$$Manuf Generic
$$Model Dimmer
$$Footprint 1
$$PersChan 1 1 1 0 0
$Patch 1 1 1
   Text A
$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:synth_def {"defRefId":"def-Other-Thing","manufacturer":"Other","model":"Thing","channelFingerprint":"1"}
`
	deps := newTestDeps(t)
	defer deps.close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
		deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), strings.NewReader(asc), Options{NewProjectName: ptr("T")})
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	saw := false
	for _, w := range res.Warnings {
		if w.Code == WarnSidecarUnresolved && w.Context["kind"] == "synth_def" {
			saw = true
		}
	}
	if !saw {
		t.Errorf("expected WarnSidecarUnresolved kind=synth_def")
	}
}
```

- [ ] **Step 3: Run + commit**

```bash
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v -run TestMapper_SidecarSynthDef
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go
git commit -m "feat(import_eos): synth_def sidecar records are advisory

If the referenced definition exists in the project, no-op (already linked
during fixture matching). If absent, emit WarnSidecarUnresolved
{kind=synth_def}. Either way, import proceeds — synth_def is informational."
```

---

### Task 16: Idempotent re-import test

**Files:**
- Modify: `internal/services/import_eos/mapper_test.go`

- [ ] **Step 1: Test re-import doesn't duplicate groups**

```go
func TestMapper_GroupsIdempotentReimport(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()

	importOnce := func(targetID *string) (*Result, error) {
		f := openFixtureFile(t, "groups_only.asc")
		defer f.Close()
		svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo,
			deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
		opts := Options{}
		if targetID != nil {
			opts.TargetProjectID = targetID
		} else {
			opts.NewProjectName = ptr("Idem")
		}
		return svc.Import(context.Background(), f, opts)
	}

	res1, err := importOnce(nil)
	if err != nil {
		t.Fatalf("first import: %v", err)
	}
	first := deps.MustListGroupsByProject(t, res1.ProjectID)
	if len(first) != 2 {
		t.Fatalf("first import: %d groups", len(first))
	}

	if _, err := importOnce(&res1.ProjectID); err != nil {
		t.Fatalf("re-import: %v", err)
	}
	second := deps.MustListGroupsByProject(t, res1.ProjectID)
	if len(second) != 2 {
		t.Errorf("after re-import: %d groups (want 2)", len(second))
	}
}
```

- [ ] **Step 2: Run + commit**

```bash
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v -run TestMapper_GroupsIdempotent
git add internal/services/import_eos/mapper_test.go
git commit -m "test(import_eos): re-importing same .asc into the same project doesn't duplicate groups"
```

---

## Phase 5 — Writer integration (exporter)

### Task 17: Wire `FixtureGroupRepository` into the export `Service`

**Files:**
- Modify: `internal/services/export_eos/service.go`
- Modify: `cmd/server/main.go` (export service constructor call)
- Modify: `internal/graphql/resolvers/eos_helpers.go` (or wherever export is invoked)

- [ ] **Step 1: Add the repo field + constructor parameter**

Update `service.go`:

```go
type Service struct {
	projectRepo      *repositories.ProjectRepository
	fixtureRepo      *repositories.FixtureRepository
	fixtureGroupRepo *repositories.FixtureGroupRepository
	lookRepo         *repositories.LookRepository
	cueListRepo      *repositories.CueListRepository
	cueRepo          *repositories.CueRepository
	lookBoardRepo    *repositories.LookBoardRepository
}

func NewServiceWithDeps(
	p *repositories.ProjectRepository,
	f *repositories.FixtureRepository,
	fg *repositories.FixtureGroupRepository,
	l *repositories.LookRepository,
	cl *repositories.CueListRepository,
	c *repositories.CueRepository,
	lb *repositories.LookBoardRepository,
) *Service {
	return &Service{p, f, fg, l, cl, c, lb}
}
```

Update `validateDependencies` to add a check for `fixtureGroupRepo == nil`.

- [ ] **Step 2: Update call sites**

Search the codebase:

```bash
grep -rn "exporteos.NewServiceWithDeps\|export_eos.NewServiceWithDeps" --include="*.go" .
```

For each result, add the `repositories.NewFixtureGroupRepository(db)` parameter in the right position.

- [ ] **Step 3: Update the export service test deps**

Open `internal/services/export_eos/testdeps_test.go`. Add `fixtureGroupRepo` and the migration entry, mirroring the import-side change (Task 12 Step 5).

- [ ] **Step 4: Build**

```bash
go build ./...
```

- [ ] **Step 5: Commit**

```bash
git add internal/services/export_eos/ cmd/server/main.go internal/graphql/resolvers/eos_helpers.go internal/services/export_eos/testdeps_test.go
git commit -m "feat(export_eos): wire FixtureGroupRepository through the Service

Adds the repo to Service struct + constructor + validation. All existing
call sites updated to pass the new dependency. Sets up Task 18 to load
groups during export."
```

---

### Task 18: Emit `$Group` blocks during export

**Files:**
- Modify: `internal/services/export_eos/loader.go`
- Modify: `internal/services/export_eos/group.go`

- [ ] **Step 1: Add a `loadGroups` method on `Service`**

Append to `loader.go`:

```go
// loadGroups returns the project's FixtureGroups as writer-shape rows,
// resolving members to EOS channel numbers. Empty groups (no resolvable
// members) are skipped with WarnExportEmptyGroupSkipped. Groups missing
// an EosNumber are auto-assigned the next available number and the
// updated number is persisted so subsequent exports stay stable.
func (s *Service) loadGroups(
	ctx context.Context,
	projectID string,
	eosByInstance map[string]int,
	collector *importeos.Collector,
) ([]GroupOut, error) {
	groups, err := s.fixtureGroupRepo.FindByProjectID(ctx, projectID)
	if err != nil {
		return nil, fmt.Errorf("export_eos: groups: %w", err)
	}
	// Sort: assigned EosNumber first (ascending), then nil-EosNumber
	// (alphabetic), then ID for tie-break. This makes auto-assignment
	// deterministic.
	sort.SliceStable(groups, func(i, j int) bool {
		ai, bi := groups[i].EosNumber, groups[j].EosNumber
		switch {
		case ai != nil && bi != nil:
			if *ai != *bi {
				return *ai < *bi
			}
		case ai != nil:
			return true
		case bi != nil:
			return false
		}
		if groups[i].Name != groups[j].Name {
			return groups[i].Name < groups[j].Name
		}
		return groups[i].ID < groups[j].ID
	})

	// Auto-assign EosNumbers. NOTE: this mutates DB state during a
	// nominally read-only export — intentional, since the alternative
	// (renumber on every export) breaks round-trip stability.
	maxAssigned := 0
	for _, g := range groups {
		if g.EosNumber != nil && *g.EosNumber > maxAssigned {
			maxAssigned = *g.EosNumber
		}
	}
	for i := range groups {
		if groups[i].EosNumber != nil {
			continue
		}
		maxAssigned++
		next := maxAssigned
		groups[i].EosNumber = &next
		if err := s.fixtureGroupRepo.Update(ctx, &groups[i]); err != nil {
			return nil, fmt.Errorf("export_eos: persist auto-assigned eos_number: %w", err)
		}
	}

	out := make([]GroupOut, 0, len(groups))
	for _, g := range groups {
		members, err := s.fixtureGroupRepo.GetMembers(ctx, g.ID)
		if err != nil {
			return nil, fmt.Errorf("export_eos: group members: %w", err)
		}
		channels := make([]int, 0, len(members))
		for _, m := range members {
			ch, ok := eosByInstance[m.FixtureID]
			if !ok {
				continue // unpatched fixture — silently exclude
			}
			channels = append(channels, ch)
		}
		if len(channels) == 0 {
			if collector != nil {
				collector.Add(importeos.WarnExportEmptyGroupSkipped, importeos.SeverityInfo,
					fmt.Sprintf("group %s has no patched members; skipped on export", g.Name),
					map[string]string{"groupId": g.ID, "groupName": g.Name})
			}
			continue
		}
		number := strconv.Itoa(*g.EosNumber)
		out = append(out, GroupOut{
			Number:   number,
			Label:    g.Name,
			Channels: channels,
		})
	}
	return out, nil
}
```

`WarnExportEmptyGroupSkipped` is a new warning code. Add it to `internal/services/import_eos/warnings.go` (the writer reuses the import-eos package's warning constants):

```go
	WarnExportEmptyGroupSkipped WarningCode = "EXPORT_EMPTY_GROUP_SKIPPED"
```

- [ ] **Step 2: Replace the placeholder in `loadBundle`**

In `loader.go`, locate line 96 (`Groups: []GroupOut{}, // FixtureGroup model not yet present (Task 14c)`) and replace with the actual call:

```go
	groupsOut, err := s.loadGroups(ctx, projectID, eosChannelByInstance, collector)
	if err != nil {
		return nil, err
	}
```

Then update the bundle return:

```go
	return &bundle{
		ProjectName:   proj.Name,
		ParamTypes:    paramTypes,
		Personalities: personalities,
		Patch:         patch,
		Palettes:      palettes,
		CueLists:      regularLists,
		Groups:        groupsOut,
		Sidecar:       sidecar,
	}, nil
```

- [ ] **Step 3: Test**

In `internal/services/export_eos/writer_test.go` (or a new test file):

```go
func TestExport_GroupsEmitted(t *testing.T) {
	deps := newExportTestDeps(t) // existing helper
	defer deps.close()
	ctx := context.Background()

	// Seed project, two fixtures (channels 1,2), one group containing both.
	proj := &models.Project{Name: "T"}
	if err := deps.projectRepo.Create(ctx, proj); err != nil {
		t.Fatalf("project: %v", err)
	}
	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "Dimmer", Type: "DIMMER"}
	deps.fixtureRepo.CreateDefinition(ctx, def)

	one, two := 1, 2
	a := &models.FixtureInstance{ProjectID: proj.ID, DefinitionID: def.ID, Name: "A", Universe: 1, StartChannel: 1, ProjectOrder: &one}
	b := &models.FixtureInstance{ProjectID: proj.ID, DefinitionID: def.ID, Name: "B", Universe: 1, StartChannel: 2, ProjectOrder: &two}
	deps.fixtureRepo.CreateWithChannels(ctx, a, []models.InstanceChannel{{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"}})
	deps.fixtureRepo.CreateWithChannels(ctx, b, []models.InstanceChannel{{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"}})

	g := &models.FixtureGroup{ProjectID: proj.ID, Name: "All"}
	deps.fixtureGroupRepo.CreateWithMembers(ctx, g, []string{a.ID, b.ID})

	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Export(ctx, proj.ID)
	if err != nil {
		t.Fatalf("export: %v", err)
	}
	if !strings.Contains(res.Content, "$Group 1") {
		t.Errorf("missing $Group 1; output:\n%s", res.Content)
	}
	if !strings.Contains(res.Content, "Text All") {
		t.Errorf("missing Text All")
	}

	// EosNumber should now be persisted.
	persisted, _ := deps.fixtureGroupRepo.FindByID(ctx, g.ID)
	if persisted.EosNumber == nil || *persisted.EosNumber != 1 {
		t.Errorf("expected EosNumber=1 persisted; got %v", persisted.EosNumber)
	}
}

func TestExport_EmptyGroupSkipped(t *testing.T) {
	deps := newExportTestDeps(t)
	defer deps.close()
	ctx := context.Background()
	proj := &models.Project{Name: "T"}
	deps.projectRepo.Create(ctx, proj)

	g := &models.FixtureGroup{ProjectID: proj.ID, Name: "Empty"}
	deps.fixtureGroupRepo.CreateWithMembers(ctx, g, nil)

	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, _ := svc.Export(ctx, proj.ID)
	if strings.Contains(res.Content, "$Group") {
		t.Errorf("empty group should not be emitted")
	}
	saw := false
	for _, w := range res.Warnings {
		if w.Code == importeos.WarnExportEmptyGroupSkipped {
			saw = true
		}
	}
	if !saw {
		t.Errorf("expected WarnExportEmptyGroupSkipped")
	}
}
```

- [ ] **Step 4: Run**

```bash
ARTNET_ENABLED=false go test ./internal/services/export_eos/ -v -run TestExport_Group
ARTNET_ENABLED=false go test ./internal/services/export_eos/ -v -run TestExport_Empty
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add internal/services/export_eos/ internal/services/import_eos/warnings.go
git commit -m "feat(export_eos): emit \$Group blocks from FixtureGroup rows

loadGroups loads project groups, auto-assigns EosNumbers (persisted so
subsequent exports stay stable), resolves members to EOS channel numbers
via eosByInstance. Empty groups skipped with WarnExportEmptyGroupSkipped."
```

---

### Task 19: Sidecar emission — use `RefID` and add `fade_behavior`

**Files:**
- Modify: `internal/services/export_eos/loader.go`

- [ ] **Step 1: Update `buildSidecar` to use `RefID` instead of `ID`**

In `loader.go`, the `buildSidecar` function uses `b.ID` and `btn.LookID` directly as refIDs. Change those to use the new `RefID` columns:

```go
		var sb []importeos.SidecarLookBoardButton
		for _, btn := range buttons {
			color := ""
			if btn.Color != nil {
				color = *btn.Color
			}
			// Resolve LookID → Look.RefID. We need the Look row to do this.
			look, err := s.lookRepo.FindByID(ctx, btn.LookID)
			if err != nil {
				return SidecarOut{}, fmt.Errorf("export_eos: look for button: %w", err)
			}
			if look == nil {
				continue // dangling button reference; skip
			}
			sb = append(sb, importeos.SidecarLookBoardButton{
				LookRefID: look.RefID,
				X:         btn.LayoutX,
				Y:         btn.LayoutY,
				Color:     color,
			})
		}
		out.LookBoards = append(out.LookBoards, importeos.SidecarLookBoard{
			RefID:   b.RefID,
			Name:    b.Name,
			Buttons: sb,
		})
```

For `SynthDefs`, change `DefRefID: id` to `DefRefID: dm.RefID`:

```go
		out.SynthDefs = append(out.SynthDefs, importeos.SidecarSynthDef{
			DefRefID:           dm.RefID,
			Manufacturer:       dm.Manufacturer,
			Model:              dm.Model,
			ChannelFingerprint: channelFingerprint(defChannels[id]),
		})
```

- [ ] **Step 2: Emit `fade_behavior` records**

After the LookBoards loop in `buildSidecar`, before the SynthDefs loop, add:

```go
	// fade_behavior: any FixtureInstance with non-default channel fade
	// behaviors gets a record. Sorted by RefID for determinism.
	instances, err := s.fixtureRepo.FindByProjectID(ctx, projectID)
	if err != nil {
		return SidecarOut{}, fmt.Errorf("export_eos: instances for fade_behavior: %w", err)
	}
	sort.SliceStable(instances, func(i, j int) bool { return instances[i].RefID < instances[j].RefID })
	for i := range instances {
		fi := &instances[i]
		channels, err := s.fixtureRepo.GetInstanceChannels(ctx, fi.ID)
		if err != nil {
			return SidecarOut{}, fmt.Errorf("export_eos: instance channels: %w", err)
		}
		var nonDefault []importeos.SidecarFadeBehaviorChannel
		for _, c := range channels {
			if c.FadeBehavior != "" && c.FadeBehavior != "FADE" {
				nonDefault = append(nonDefault, importeos.SidecarFadeBehaviorChannel{
					Offset:   c.Offset,
					Behavior: c.FadeBehavior,
				})
			}
		}
		if len(nonDefault) == 0 {
			continue
		}
		sort.Slice(nonDefault, func(a, b int) bool { return nonDefault[a].Offset < nonDefault[b].Offset })
		out.FadeBehaviors = append(out.FadeBehaviors, importeos.SidecarFadeBehavior{
			InstanceRefID: fi.RefID,
			Channels:      nonDefault,
		})
	}
```

- [ ] **Step 3: Test**

```go
func TestExport_SidecarFadeBehavior(t *testing.T) {
	deps := newExportTestDeps(t)
	defer deps.close()
	ctx := context.Background()

	proj := &models.Project{Name: "T"}
	deps.projectRepo.Create(ctx, proj)
	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "RGB", Type: "DIMMER"}
	deps.fixtureRepo.CreateDefinition(ctx, def)

	one := 1
	fi := &models.FixtureInstance{ProjectID: proj.ID, DefinitionID: def.ID, Name: "A", Universe: 1, StartChannel: 1, ProjectOrder: &one}
	channels := []models.InstanceChannel{
		{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"},
		{Offset: 1, Name: "R", Type: "COLOR_R", FadeBehavior: "SNAP_END"},
	}
	deps.fixtureRepo.CreateWithChannels(ctx, fi, channels)

	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, _ := svc.Export(ctx, proj.ID)

	if !strings.Contains(res.Content, `"behavior":"SNAP_END"`) {
		t.Errorf("missing fade_behavior in output:\n%s", res.Content)
	}
	if !strings.Contains(res.Content, `"instanceRefId":"`+fi.RefID+`"`) {
		t.Errorf("instanceRefId not %s in output", fi.RefID)
	}
}
```

- [ ] **Step 4: Run + commit**

```bash
ARTNET_ENABLED=false go test ./internal/services/export_eos/ -v -run TestExport_Sidecar
git add internal/services/export_eos/loader.go
git commit -m "feat(export_eos): emit sidecar via RefID columns + fade_behavior records

Switches LookBoard refid emission to use the new RefID column instead of
the row's CUID; resolves button look refids through Look.RefID. Adds
fade_behavior emission for any InstanceChannel where FadeBehavior !=
'FADE'. Determinism preserved: sort by refID then by offset."
```

---

### Task 20: Round-trip tests for groups + sidecar

**Files:**
- Modify: `internal/services/export_eos/roundtrip_test.go`

- [ ] **Step 1: Test groups round-trip**

```go
func TestEosRoundtrip_GroupsPreserved(t *testing.T) {
	src := newExportTestDeps(t)
	defer src.close()
	ctx := context.Background()

	// Seed project + 3 fixtures + 1 group.
	proj := &models.Project{Name: "RT"}
	src.projectRepo.Create(ctx, proj)
	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "Dimmer", Type: "DIMMER"}
	src.fixtureRepo.CreateDefinition(ctx, def)
	mkInst := func(name string, ch int) *models.FixtureInstance {
		c := ch
		fi := &models.FixtureInstance{ProjectID: proj.ID, DefinitionID: def.ID, Name: name, Universe: 1, StartChannel: ch, ProjectOrder: &c}
		src.fixtureRepo.CreateWithChannels(ctx, fi, []models.InstanceChannel{{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"}})
		return fi
	}
	a, b, c := mkInst("A", 1), mkInst("B", 2), mkInst("C", 3)

	g := &models.FixtureGroup{ProjectID: proj.ID, Name: "Main"}
	src.fixtureGroupRepo.CreateWithMembers(ctx, g, []string{a.ID, b.ID, c.ID})

	// Export.
	exportSvc := NewServiceWithDeps(src.projectRepo, src.fixtureRepo, src.fixtureGroupRepo, src.lookRepo, src.cueListRepo, src.cueRepo, src.lookBoardRepo)
	exportRes, err := exportSvc.Export(ctx, proj.ID)
	if err != nil {
		t.Fatalf("export: %v", err)
	}

	// Re-import into a fresh deps stack.
	dst := newImportTestDeps(t) // mirror existing roundtrip helper
	defer dst.close()
	importSvc := importeos.NewServiceWithDeps(dst.projectRepo, dst.fixtureRepo, dst.fixtureGroupRepo, dst.lookRepo, dst.cueListRepo, dst.cueRepo, dst.lookBoardRepo)
	importRes, err := importSvc.Import(ctx, strings.NewReader(exportRes.Content), importeos.Options{NewProjectName: ptr("RT2")})
	if err != nil {
		t.Fatalf("re-import: %v", err)
	}

	groups, _ := dst.fixtureGroupRepo.FindByProjectID(ctx, importRes.ProjectID)
	if len(groups) != 1 {
		t.Fatalf("got %d groups", len(groups))
	}
	if groups[0].Name != "Main" {
		t.Errorf("name = %q", groups[0].Name)
	}
	ms, _ := dst.fixtureGroupRepo.GetMembers(ctx, groups[0].ID)
	if len(ms) != 3 {
		t.Errorf("members = %d, want 3", len(ms))
	}
}
```

If `newImportTestDeps` doesn't exist as a separate helper, define it in the export-eos test helper file or compose using import-eos's own `testDeps`.

- [ ] **Step 2: Test fade behaviors round-trip**

Similar shape: seed a fixture with one non-default channel, export, re-import, assert the channel's `FadeBehavior` survives.

```go
func TestEosRoundtrip_FadeBehaviorsPreserved(t *testing.T) {
	src := newExportTestDeps(t)
	defer src.close()
	ctx := context.Background()
	proj := &models.Project{Name: "RT"}
	src.projectRepo.Create(ctx, proj)
	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "RGB", Type: "DIMMER"}
	src.fixtureRepo.CreateDefinition(ctx, def)
	one := 1
	fi := &models.FixtureInstance{ProjectID: proj.ID, DefinitionID: def.ID, Name: "A", Universe: 1, StartChannel: 1, ProjectOrder: &one}
	src.fixtureRepo.CreateWithChannels(ctx, fi, []models.InstanceChannel{
		{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"},
		{Offset: 1, Name: "R", Type: "COLOR_R", FadeBehavior: "SNAP_END"},
	})

	exportRes, _ := NewServiceWithDeps(src.projectRepo, src.fixtureRepo, src.fixtureGroupRepo, src.lookRepo, src.cueListRepo, src.cueRepo, src.lookBoardRepo).Export(ctx, proj.ID)

	dst := newImportTestDeps(t)
	defer dst.close()
	importRes, _ := importeos.NewServiceWithDeps(dst.projectRepo, dst.fixtureRepo, dst.fixtureGroupRepo, dst.lookRepo, dst.cueListRepo, dst.cueRepo, dst.lookBoardRepo).
		Import(ctx, strings.NewReader(exportRes.Content), importeos.Options{NewProjectName: ptr("RT2")})

	instances, _ := dst.fixtureRepo.FindByProjectID(ctx, importRes.ProjectID)
	if len(instances) != 1 {
		t.Fatalf("got %d", len(instances))
	}
	channels, _ := dst.fixtureRepo.GetInstanceChannels(ctx, instances[0].ID)
	want := map[int]string{0: "FADE", 1: "SNAP_END"}
	for _, c := range channels {
		if c.FadeBehavior != want[c.Offset] {
			t.Errorf("offset %d: %q, want %q", c.Offset, c.FadeBehavior, want[c.Offset])
		}
	}
}
```

- [ ] **Step 3: Update determinism test if needed**

Open `roundtrip_test.go` (or wherever `TestExport_Deterministic` lives — per resumption-state memory, it exists). Run it twice on the same input and assert the outputs are byte-identical. With the new auto-assign-EosNumber persistence, ensure the *first* run's auto-assignment doesn't make the *second* run's output differ. Test pattern: export once (which assigns numbers), then export again, then compare.

```go
func TestExport_DeterministicAfterAutoAssign(t *testing.T) {
	deps := newExportTestDeps(t)
	defer deps.close()
	ctx := context.Background()
	// Seed a project with a group that has nil EosNumber.
	proj := &models.Project{Name: "D"}
	deps.projectRepo.Create(ctx, proj)
	def := &models.FixtureDefinition{Manufacturer: "Generic", Model: "Dimmer", Type: "DIMMER"}
	deps.fixtureRepo.CreateDefinition(ctx, def)
	one := 1
	fi := &models.FixtureInstance{ProjectID: proj.ID, DefinitionID: def.ID, Name: "A", Universe: 1, StartChannel: 1, ProjectOrder: &one}
	deps.fixtureRepo.CreateWithChannels(ctx, fi, []models.InstanceChannel{{Offset: 0, Name: "I", Type: "INTENSITY", FadeBehavior: "FADE"}})
	g := &models.FixtureGroup{ProjectID: proj.ID, Name: "G"}
	deps.fixtureGroupRepo.CreateWithMembers(ctx, g, []string{fi.ID})

	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.fixtureGroupRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	first, _ := svc.Export(ctx, proj.ID)
	second, _ := svc.Export(ctx, proj.ID)
	if first.Content != second.Content {
		t.Errorf("non-deterministic output\nFIRST:\n%s\n\nSECOND:\n%s", first.Content, second.Content)
	}
}
```

- [ ] **Step 4: Run all export tests**

```bash
ARTNET_ENABLED=false go test ./internal/services/export_eos/ -v
ARTNET_ENABLED=false go test ./internal/services/import_eos/ -v
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add internal/services/export_eos/roundtrip_test.go
git commit -m "test(export_eos): round-trip tests for groups, fade behaviors, auto-assign determinism"
```

---

## Phase 6 — Final wiring + verification

### Task 21: Update `repositories_test.go` AutoMigrate

**Files:**
- Modify: `internal/database/repositories/repositories_test.go`

- [ ] **Step 1: Add new models**

Locate the `AutoMigrate(...)` call at the package-level test setup. Add:

```go
		&models.FixtureGroup{},
		&models.FixtureGroupMember{},
```

Per memory note: this file's AutoMigrate must be kept in sync with new models, otherwise downstream repo tests will fail with missing-table errors.

- [ ] **Step 2: Run full repo test suite**

```bash
go test ./internal/database/repositories/ -v
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add internal/database/repositories/repositories_test.go
git commit -m "test(repositories): add FixtureGroup tables to shared AutoMigrate"
```

---

### Task 22: End-to-end verification — full test suite + lint

- [ ] **Step 1: Run all tests**

```bash
ARTNET_ENABLED=false go test ./... -count=1
```

Expected: every package passes. If any test fails:
- Read the failure carefully — don't reflexively change the test.
- If it's a wiring issue (a place that constructs `NewMapper` / `NewServiceWithDeps` / `Resolver{...}` without the new repo), fix the wiring.
- If it's a model-related test that doesn't yet know about `FixtureGroup` AutoMigrate, add it to that test's setup.
- Otherwise, investigate before patching.

- [ ] **Step 2: Run lint**

```bash
make lint
```

Expected: no errors. Common gotchas to fix:
- Unused imports.
- Shadowed variables (e.g., `g := ... ; g, err := ...`).
- Errors not wrapped with `fmt.Errorf("ctx: %w", err)`.

- [ ] **Step 3: Run codegen + build to confirm no drift**

```bash
make generate
go build ./...
git status # confirm no untracked changes from regeneration
```

Expected: `git status` shows clean working tree (codegen produced no diff because the schema hasn't moved since Task 8).

- [ ] **Step 4: Run the OTBPA round-trip test specifically**

```bash
ARTNET_ENABLED=false go test ./internal/services/export_eos/ -v -run TestEosRoundtrip_OTBPA
```

Expected: passes. If `golden_otbpa.asc` has groups (per resumption-state memory it has 5), this is the most realistic round-trip check.

- [ ] **Step 5: If a `lacylights-test` integration test asserts group count is 0 or 'groups skipped', update it**

```bash
grep -rn "GROUPS_SKIPPED\|groups_skipped\|groupsCount.*0" ~/src/lacylights/lacylights-test/ 2>/dev/null
```

If any contract test in the test repo asserts on the old behavior (groups dropped), follow up in a separate PR — don't modify the test repo from this branch unless explicitly necessary for CI to pass.

---

### Task 23: Update memory file + push branch + open PR

- [ ] **Step 1: Update the resumption-state memory**

Edit `~/.claude/projects/-Users-<user>-src-lacylights/memory/eos_ascii_importer.md`. Mark Task 14c done in the status section, list the new PR, and clear the "What remains" Task 14c bullet.

- [ ] **Step 2: Push branch**

```bash
git push -u origin feature/eos-task-14c-fixture-groups
```

- [ ] **Step 3: Open PR**

```bash
gh pr create --title "feat(eos): Task 14c — FixtureGroup model + sidecar application" --body "$(cat <<'EOF'
## Summary

Closes the EOS round-trip data-loss gap for \$Group blocks and
\`\$\$ LACYLIGHTS:\` sidecar records.

- New \`FixtureGroup\` + \`FixtureGroupMember\` models with full GraphQL CRUD,
  bulk variants, and dedicated membership operations.
- New \`RefID\` column on \`FixtureInstance\`, \`FixtureDefinition\`, \`Look\`,
  \`LookBoard\` (project-scoped unique, except FixtureDefinition which is
  globally unique). Backfill + indexes added in main.go migration.
- Importer assigns deterministic EOS-derived RefIDs (\`ch-<n>\`,
  \`cue-<list>-<num>\`, \`def-<manuf>-<model>\`) so the sidecar resolves
  cleanly across round-trips.
- Mapper's \`applyGroups\` and \`applySidecar\` now persist data instead
  of warning-and-dropping.
- Exporter emits \`\$Group\` blocks (with auto-assigned, persisted
  EosNumber) and sidecar fade_behavior records.

## Test plan

- [x] Unit tests for new repo methods + FixtureGroupRepository
- [x] Mapper integration tests (groups, look_board, fade_behavior, synth_def, idempotency, deterministic refIDs)
- [x] Writer tests ($Group emission, empty-group skip, fade_behavior emission, determinism)
- [x] Round-trip tests (groups, fade behaviors)
- [x] GraphQL resolver tests (CRUD, auth gate, membership ops)
- [x] make lint passes
- [x] OTBPA golden round-trip passes

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Verify CI**

```bash
gh pr checks $(gh pr view --json number -q .number)
```

If checks fail, address per the project's iteration rules (lint, tests, coverage), then re-push.

---

## Self-review

Run through the spec sections one more time and confirm every requirement maps to a task:

- **Data model** (FixtureGroup, FixtureGroupMember, RefID column) → Tasks 1, 5
- **Migration & backfill** → Tasks 2, 6
- **Repository surface** (FixtureGroupRepository + 3 method-add tasks) → Tasks 3, 4, 7
- **GraphQL surface** (refId fields, FixtureGroup type, queries, mutations, bulk, auth) → Tasks 8, 9
- **Mapper changes** (applyGroups, applySidecar look_board / fade_behavior / synth_def, deterministic refIDs, warning code) → Tasks 10, 11, 12, 13, 14, 15, 16
- **Writer changes** ($Group emission, sidecar fade_behavior, RefID-based emission, determinism) → Tasks 17, 18, 19, 20
- **Test deps & repositories_test.go updates** → Task 21
- **End-to-end verification** → Task 22
- **Memory file update + PR** → Task 23

**Type consistency:** `eosFixtureInstanceRefID`, `eosLookRefIDForCue`, `eosLookRefIDForPalette`, `eosFixtureDefRefID` are defined in Task 11 and used in Task 11 only. `applySidecarLookBoards`, `applySidecarFadeBehaviors`, `applySidecarSynthDefs` are stubbed in Task 13 then filled by Tasks 13/14/15 in order. `WarnGroupChannelUnresolved` defined Task 10, used Task 12. `WarnExportEmptyGroupSkipped` defined Task 18, used Task 18. `ErrChannelOffsetNotFound` defined Task 4, used Tasks 4 + 14. `MustListGroupsByProject` defined Task 12, used Tasks 12 + 16.

**Placeholder check:** No "TBD" / "TODO" / "implement later" in the plan. Steps that say "use the codebase's existing helper" point to the file where the helper is defined and offer concrete fallback if the helper doesn't have the expected name.

**Spec coverage gap:** none identified.
