# ETC Eos ASCII Importer / Exporter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bi-directional import/export of ETC Eos ASCII (`.asc`) showfiles in LacyLights, surfaced through the existing GraphQL API, the web frontend, and the MCP server.

**Architecture:** A pure-Go parser + writer in `lacylights-go/internal/services/import_eos/` and `export_eos/`, exposed via two new GraphQL mutations (`importProjectFromEos`, `exportProjectToEos`) following the existing QLC+ sibling-mutation pattern. The frontend extends `ImportExportButtons.tsx` with a third format option, and a thin MCP tool wraps the GraphQL surface. EOS-only concepts (effects, partitions, magic sheets, action triggers) are skipped on import with structured warnings; LacyLights-only concepts (Look Boards, per-channel `FadeBehavior`, synthesized fixture defs) are carried out-of-band via a `$$ LACYLIGHTS:` comment-sidecar block at end-of-file.

**Tech Stack:** Go 1.22+, gqlgen, GORM/SQLite, Next.js 15 + Apollo Client + Jest, TypeScript MCP SDK.

**Spec:** `docs/plans/2026-04-28-eos-ascii-importer-exporter-design.md`. Read it first.

**Reference fixture:** `docs/OTBPA DRESS TUES.asc` (real-world ETC Eos ASCII export, 6,433 lines).

**Existing pattern to mirror:** the QLC+ importer/exporter wired in `internal/graphql/schema/schema.graphql` (lines 1457–1508 and 2561–2568) and `lacylights-fe/src/components/ImportExportButtons.tsx`. The Eos feature uses the same shape (sibling mutations, sibling result types, format dropdown in the UI).

**Out of scope for this plan (deferred):** native binary `.esf3d` parsing, USITT 5.02 ASCII strict mode, importing Augment3d 3D scene data.

**Mac and RPi platforms:** no changes needed. They package the frontend and backend; the existing native bridge in `ImportExportButtons.tsx` already handles file downloads via `window.lacylights.download` and accepts arbitrary text content.

---

## Phase Overview

| Phase | Repo | Tasks | What you can ship after this phase |
|---|---|---|---|
| 1 — Backend parser/writer | `lacylights-go` | 1–18 | API-driven Eos ASCII import/export via GraphQL |
| 2 — Frontend integration | `lacylights-fe` | 19–24 | UI to import and download `.asc` files in the web app |
| 3 — MCP exposure | `lacylights-mcp` | 25–27 | AI agents can import/export Eos ASCII via tool calls |
| 4 — Cross-repo integration tests | `lacylights-test` | 28–30 | End-to-end contract validation |
| 5 — Documentation | all repos | 31–33 | Per-repo CLAUDE.md updates and a user-facing format note |

Phases must be executed in order — each builds on the previous. Phase 1 alone produces working software (you can hit the GraphQL endpoint with curl).

---

## File Structure

### `lacylights-go` (new + modified files)

```
internal/services/
├── import_eos/
│   ├── ast.go                    # Parsed AST node types
│   ├── lexer.go                  # Line-based tokenizer
│   ├── parser.go                 # AST builder
│   ├── param_table.go            # $ParamType id → ChannelType lookup
│   ├── utext.go                  # $$UText decoder
│   ├── sidecar_reader.go         # Reads $$ LACYLIGHTS: lines
│   ├── tracker.go                # Cumulative cue-state computation
│   ├── fixture_match.go          # OFL match-then-synthesize
│   ├── mapper.go                 # AST → LacyLights domain (transactional)
│   ├── service.go                # Public Service struct + Import method
│   ├── warnings.go               # EosWarning + codes
│   ├── testdata/
│   │   ├── minimal_patch.asc
│   │   ├── basic_cues.asc
│   │   ├── tracking.asc
│   │   ├── palettes_color_focus.asc
│   │   ├── presets_groups.asc
│   │   ├── moving_lights.asc
│   │   ├── utext_unicode.asc
│   │   ├── sidecar_roundtrip.asc
│   │   ├── unknown_directive.asc
│   │   ├── conflict_addresses.asc
│   │   ├── malformed_cue.asc
│   │   ├── multi_universe.asc
│   │   └── golden_otbpa.asc      # symlink/copy of docs/OTBPA DRESS TUES.asc
│   ├── lexer_test.go
│   ├── parser_test.go
│   ├── tracker_test.go
│   ├── sidecar_reader_test.go
│   ├── fixture_match_test.go
│   ├── mapper_test.go
│   └── service_test.go
└── export_eos/
    ├── writer.go                 # Domain → ASCII text
    ├── header.go                 # Header + $ParamType emission
    ├── personality.go            # $Personality block emission
    ├── patch.go                  # $Patch line emission
    ├── palette.go                # $ColorPalette/$BeamPalette/etc emission
    ├── cue.go                    # $CueList/Cue emission
    ├── group.go                  # $Group emission
    ├── sidecar_writer.go         # Emits $$ LACYLIGHTS: lines
    ├── service.go                # Public Service struct + Export method
    ├── warnings.go               # Re-exports import_eos.EosWarning types
    ├── testdata/
    │   └── (same fixtures, used for round-trip tests)
    ├── writer_test.go
    └── service_test.go

internal/graphql/
├── schema/schema.graphql         # MODIFY: add EosImportResult / EosExportResult / EosWarning types and mutations
├── resolvers/
│   ├── eos_import_export.go      # NEW: resolver implementations
│   └── schema.resolvers.go       # MODIFY (auto-generated by `make generate`)
└── generated/                    # Auto-regenerated; do not hand-edit

cmd/server/
└── main.go                       # MODIFY: wire import_eos.Service and export_eos.Service into resolver
```

### `lacylights-fe` (new + modified files)

```
src/graphql/
└── projects.ts                   # MODIFY: add IMPORT_PROJECT_FROM_EOS / EXPORT_PROJECT_TO_EOS GraphQL ops

src/generated/
└── graphql.ts                    # Auto-regenerated by `npm run codegen`

src/components/
├── ImportExportButtons.tsx       # MODIFY: extend ExportFormat/ImportFormat unions, add 'eos' branches
├── EosImportWarningsList.tsx     # NEW: groups EosWarning array by code, renders friendly list
└── __tests__/
    ├── ImportExportButtons.test.tsx          # MODIFY: extend existing tests for eos format
    └── EosImportWarningsList.test.tsx        # NEW
```

### `lacylights-mcp` (new + modified files)

```
src/graphql/
└── eos.graphql                   # NEW: query/mutation strings for codegen

src/generated/graphql.ts          # Auto-regenerated by `npm run codegen`

src/tools/
├── import-export-tools.ts        # NEW: import_eos_ascii, export_eos_ascii MCP tools
└── __tests__/
    └── import-export-tools.test.ts # NEW

src/index.ts                      # MODIFY: register the two new tools
```

### `lacylights-test` (new files)

```
integration/
├── eos_import_test.go            # NEW: import golden fixture, assert resulting GraphQL state
└── eos_roundtrip_test.go         # NEW: native JSON → Eos export → Eos import round-trip
```

### Documentation

```
lacylights-go/CLAUDE.md           # MODIFY: add Eos import/export reference
lacylights-fe/CLAUDE.md           # MODIFY: add Eos import/export reference
lacylights-mcp/CLAUDE.md          # MODIFY: add Eos import/export reference
docs/IMPORT_EXPORT_FORMATS.md     # NEW: user-facing per-format capability matrix
```

---

## Phase 1 — Backend (`lacylights-go`)

> **Working directory for all Phase 1 tasks:** `~/src/lacylights/lacylights-go`. Each task assumes you're in that directory unless stated otherwise.
>
> **Branch:** create `feature/eos-ascii-import-export` off `main` before Task 1 (per project rule: never commit to main). All commits in this phase land on that branch.
>
> **TDD discipline:** Every task is "write the failing test → run it → minimal implementation → green → commit." Do not skip the failing-test step. The hand-authored fixtures in `testdata/` are the test inputs; build them up one fixture at a time as the parser learns each directive.

### Task 1: Create the feature branch and skeleton

**Files:**
- Create: `internal/services/import_eos/warnings.go`
- Create: `internal/services/import_eos/service.go`
- Create: `internal/services/import_eos/testdata/.gitkeep`
- Create: `internal/services/export_eos/service.go`
- Create: `internal/services/export_eos/testdata/.gitkeep`

- [ ] **Step 1: Create the feature branch**

```bash
git checkout main
git pull
git checkout -b feature/eos-ascii-import-export
```

- [ ] **Step 2: Create `internal/services/import_eos/warnings.go`**

```go
// Package importeos parses ETC Eos ASCII showfiles into LacyLights domain objects.
package importeos

// Severity is the severity of a non-fatal warning produced by the importer or exporter.
type Severity string

const (
	SeverityInfo Severity = "INFO"
	SeverityWarn Severity = "WARN"
)

// WarningCode classifies a structured warning so the UI/MCP can group them.
type WarningCode string

const (
	WarnSynthesizedFixture WarningCode = "SYNTHESIZED_FIXTURE"
	WarnEffectSkipped      WarningCode = "EFFECT_SKIPPED"
	WarnSubmasterSkipped   WarningCode = "SUBMASTER_SKIPPED"
	WarnMagicSheetSkipped  WarningCode = "MAGIC_SHEET_SKIPPED"
	WarnPartitionSkipped   WarningCode = "PARTITION_SKIPPED"
	WarnActionSkipped      WarningCode = "ACTION_SKIPPED"
	WarnCurveSkipped       WarningCode = "CURVE_SKIPPED"
	WarnUnknownDirective   WarningCode = "UNKNOWN_DIRECTIVE"
	WarnFadeBehaviorLost   WarningCode = "FADE_BEHAVIOR_LOST"
	WarnUTextDecode        WarningCode = "UTEXT_DECODE"
	WarnSidecarInvalid     WarningCode = "SIDECAR_INVALID"
	WarnSidecarUnresolved  WarningCode = "SIDECAR_UNRESOLVED"
)

// Warning is a structured non-fatal warning emitted during import or export.
type Warning struct {
	Code     WarningCode
	Severity Severity
	Message  string
	Context  map[string]string
}

// Collector accumulates warnings during a single import or export run.
type Collector struct {
	warnings []Warning
}

// Add records a new warning.
func (c *Collector) Add(code WarningCode, severity Severity, message string, context map[string]string) {
	c.warnings = append(c.warnings, Warning{
		Code:     code,
		Severity: severity,
		Message:  message,
		Context:  context,
	})
}

// All returns all warnings collected so far.
func (c *Collector) All() []Warning {
	out := make([]Warning, len(c.warnings))
	copy(out, c.warnings)
	return out
}
```

- [ ] **Step 3: Create `internal/services/import_eos/service.go`**

```go
package importeos

import (
	"context"
	"errors"
	"io"
)

// ErrNotImplemented is returned by methods that have not been implemented yet.
// It will be replaced as later tasks add functionality.
var ErrNotImplemented = errors.New("import_eos: not implemented")

// Result is returned from a successful import.
type Result struct {
	ProjectID                string
	FixtureDefinitionsCount  int
	FixtureInstancesCount    int
	LooksCount               int
	CueListsCount            int
	CuesCount                int
	GroupsCount              int
	Warnings                 []Warning
	SynthesizedDefinitionIDs []string
}

// Options configures an import run.
type Options struct {
	TargetProjectID *string
	NewProjectName  *string
	GroupID         *string
}

// Service handles Eos ASCII import operations.
type Service struct {
	// Repos and dependencies will be injected in Task 12 when the mapper lands.
}

// NewService constructs an empty Service. Wiring is added in Task 12.
func NewService() *Service {
	return &Service{}
}

// Import reads an Eos ASCII showfile from r and applies it to the database.
// Stub: returns ErrNotImplemented until later tasks land the parser and mapper.
func (s *Service) Import(ctx context.Context, r io.Reader, opts Options) (*Result, error) {
	return nil, ErrNotImplemented
}
```

- [ ] **Step 4: Create `internal/services/export_eos/service.go`**

```go
// Package exporteos writes LacyLights project state to ETC Eos ASCII format.
package exporteos

import (
	"context"
	"errors"
	"io"

	importeos "github.com/bbernstein/lacylights-go/internal/services/import_eos"
)

// ErrNotImplemented is returned until later tasks land the writer.
var ErrNotImplemented = errors.New("export_eos: not implemented")

// Result is returned from a successful export.
type Result struct {
	Content        string
	FilenameSuffix string
	Warnings       []importeos.Warning
}

// Service handles Eos ASCII export operations.
type Service struct{}

// NewService constructs an empty Service. Wiring is added later.
func NewService() *Service {
	return &Service{}
}

// Export writes the project's state as Eos ASCII to w.
// Stub: returns ErrNotImplemented until later tasks land the writer.
func (s *Service) Export(ctx context.Context, projectID string, w io.Writer) (*Result, error) {
	return nil, ErrNotImplemented
}
```

- [ ] **Step 5: Create the testdata gitkeep files**

```bash
mkdir -p internal/services/import_eos/testdata internal/services/export_eos/testdata
touch internal/services/import_eos/testdata/.gitkeep internal/services/export_eos/testdata/.gitkeep
```

- [ ] **Step 6: Verify it builds**

Run: `go build ./internal/services/import_eos/... ./internal/services/export_eos/...`
Expected: exit 0, no output.

- [ ] **Step 7: Commit**

```bash
git add internal/services/import_eos internal/services/export_eos
git commit -m "feat(eos): scaffold import_eos and export_eos packages with stubs"
```

### Task 2: Lexer — line-based tokenization

**Files:**
- Create: `internal/services/import_eos/lexer.go`
- Create: `internal/services/import_eos/lexer_test.go`

The Eos ASCII format is line-oriented: each line is either a comment (`!`), a top-level directive (e.g. `$Personality 11896`), an indented sub-directive (e.g. `   $$Manuf Chauvet`), an unindented continuation (e.g. `Cue 0.5 1`), or a blank line. The lexer's job is to produce a stream of `Line` tokens with directive name, fields, raw text, and source position.

- [ ] **Step 1: Write the failing lexer test**

Create `internal/services/import_eos/lexer_test.go`:

```go
package importeos

import (
	"strings"
	"testing"
)

func TestLexer_TokenizesBasicDirectives(t *testing.T) {
	src := `Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20
! a comment line
$Personality 11896
   $$Manuf Chauvet
   $$Model Colorado_1_Solo_SSP
`

	got, err := tokenize(strings.NewReader(src))
	if err != nil {
		t.Fatalf("tokenize: %v", err)
	}
	want := []Line{
		{Lineno: 1, Kind: LineDirective, Directive: "Ident", Fields: []string{"3:0"}, Indent: 0, Raw: "Ident 3:0"},
		{Lineno: 2, Kind: LineDirective, Directive: "Manufacturer", Fields: []string{"ETC"}, Indent: 0, Raw: "Manufacturer ETC"},
		{Lineno: 3, Kind: LineDirective, Directive: "Console", Fields: []string{"Eos"}, Indent: 0, Raw: "Console Eos"},
		{Lineno: 4, Kind: LineDirective, Directive: "$$Format", Fields: []string{"3.20"}, Indent: 0, Raw: "$$Format 3.20"},
		{Lineno: 5, Kind: LineComment, Raw: "! a comment line"},
		{Lineno: 6, Kind: LineDirective, Directive: "$Personality", Fields: []string{"11896"}, Indent: 0, Raw: "$Personality 11896"},
		{Lineno: 7, Kind: LineDirective, Directive: "$$Manuf", Fields: []string{"Chauvet"}, Indent: 3, Raw: "   $$Manuf Chauvet"},
		{Lineno: 8, Kind: LineDirective, Directive: "$$Model", Fields: []string{"Colorado_1_Solo_SSP"}, Indent: 3, Raw: "   $$Model Colorado_1_Solo_SSP"},
	}
	if len(got) != len(want) {
		t.Fatalf("got %d lines, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i].Lineno != want[i].Lineno || got[i].Kind != want[i].Kind ||
			got[i].Directive != want[i].Directive || got[i].Indent != want[i].Indent {
			t.Errorf("line %d mismatch: got %+v, want %+v", i, got[i], want[i])
		}
	}
}

func TestLexer_BlankLine(t *testing.T) {
	got, err := tokenize(strings.NewReader("\n   \n"))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Kind != LineBlank || got[1].Kind != LineBlank {
		t.Errorf("got %+v, want two blank lines", got)
	}
}
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `go test ./internal/services/import_eos -run TestLexer -v`
Expected: compile error (`undefined: tokenize`, `undefined: Line`, `undefined: LineDirective`, etc.)

- [ ] **Step 3: Create the lexer implementation**

Create `internal/services/import_eos/lexer.go`:

```go
package importeos

import (
	"bufio"
	"io"
	"strings"
)

// LineKind classifies a single physical line of an Eos ASCII file.
type LineKind int

const (
	// LineBlank is an empty line or whitespace-only line.
	LineBlank LineKind = iota
	// LineComment is a line starting with `!`.
	LineComment
	// LineDirective is a directive line (any non-blank, non-comment line).
	// Directive names start with `$` (top-level), `$$` (sub-directive), or
	// are bare identifiers like `Cue`, `Up`, `Down`, `Text`, etc.
	LineDirective
)

// Line is a single tokenized line.
type Line struct {
	Lineno    int      // 1-based source line number
	Kind      LineKind
	Indent    int      // count of leading spaces
	Directive string   // first whitespace-separated token (e.g. "$Personality", "Cue", "$$Manuf")
	Fields    []string // remaining whitespace-separated tokens
	Raw       string   // verbatim line content (without trailing newline)
}

// tokenize reads r as Eos ASCII and returns the line tokens.
// It accepts LF or CRLF line endings.
func tokenize(r io.Reader) ([]Line, error) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	var out []Line
	lineno := 0
	for scanner.Scan() {
		lineno++
		raw := strings.TrimRight(scanner.Text(), "\r")
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			out = append(out, Line{Lineno: lineno, Kind: LineBlank, Raw: raw})
			continue
		}
		if strings.HasPrefix(trimmed, "!") {
			out = append(out, Line{Lineno: lineno, Kind: LineComment, Raw: raw})
			continue
		}
		indent := 0
		for indent < len(raw) && raw[indent] == ' ' {
			indent++
		}
		fields := strings.Fields(trimmed)
		out = append(out, Line{
			Lineno:    lineno,
			Kind:      LineDirective,
			Indent:    indent,
			Directive: fields[0],
			Fields:    fields[1:],
			Raw:       raw,
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
```

- [ ] **Step 4: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -run TestLexer -v`
Expected: PASS for both tests.

- [ ] **Step 5: Commit**

```bash
git add internal/services/import_eos/lexer.go internal/services/import_eos/lexer_test.go
git commit -m "feat(eos): line-based lexer for Eos ASCII files"
```

### Task 3: AST types and the smallest fixture (`minimal_patch.asc`)

**Files:**
- Create: `internal/services/import_eos/ast.go`
- Create: `internal/services/import_eos/testdata/minimal_patch.asc`
- Create: `internal/services/import_eos/parser_test.go`

- [ ] **Step 1: Create `internal/services/import_eos/testdata/minimal_patch.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20
$$Title Minimal Patch Test
Clear All
Set Channels 5000

! Fixture Parameters
$ParamType            1 1 Intens
   $$ShortName            Intens

! Fixture Personalities
$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

! Fixture Patch
$Patch 1 1 9001
   Text Cyc R
$Patch 2 2 9001
   Text Cyc L
```

- [ ] **Step 2: Create `internal/services/import_eos/ast.go`**

```go
package importeos

// Show is the root of the parsed Eos ASCII AST.
type Show struct {
	Ident          string            // e.g. "3:0"
	Manufacturer   string            // e.g. "ETC"
	Console        string            // e.g. "Eos"
	Format         string            // e.g. "3.20"
	SoftwareString string            // raw text from $$Software ... line
	Title          string            // $$Title value
	ParamTypes     []ParamType
	Personalities  []Personality
	Patch          []PatchEntry
	CueLists       []CueList
	ColorPalettes  []Palette
	BeamPalettes   []Palette
	FocusPalettes  []Palette
	IntensPalettes []Palette
	Presets        []Palette
	Groups         []Group
	UnknownLines   []int            // 1-based line numbers we skipped
	SidecarLines   []string         // raw "$$ LACYLIGHTS:..." lines for the sidecar reader
}

// ParamType is one row of the $ParamType table.
type ParamType struct {
	ID        int
	Category  int
	LongName  string
	ShortName string
}

// Personality is one $Personality block.
type Personality struct {
	ID         int
	Manuf      string
	Model      string
	Dcid       string
	Footprint  int
	Channels   []PersChannel
}

// PersChannel describes one channel of a personality.
type PersChannel struct {
	ParamID    int
	Size       int  // 1 = 8-bit, 2 = 16-bit
	Offset     int  // 1-based MSB offset
	Offset16   int  // 1-based LSB offset (for 16-bit), else 0
	HomeValue  int
	Flags      string // e.g. "S" for Snap
}

// PatchEntry is a single $Patch line plus its sub-directives.
type PatchEntry struct {
	Channel       int
	AddressRaw    string  // e.g. "1.512", "513", or "1/512"
	PersonalityID int
	Label         string  // from "Text" sub-directive
	UnicodeText   *string // from $$UText, decoded
}

// CueList holds one cue list and its cues.
type CueList struct {
	Number int
	Label  string
	Cues   []Cue
}

// Cue is a single cue (or cue part) within a list.
type Cue struct {
	Number       string  // "0.5", "5/2", etc.
	Part         int     // 0 if not a part
	Label        string
	UnicodeText  *string
	UpFade       float64
	UpDelay      float64
	DownFade     float64
	DownDelay    float64
	Follow       *float64
	Hang         *float64
	Block        bool
	IntBlock     bool
	ChanMoves    []ChanMove   // intensity moves (8-bit values)
	ParamMoves   []ParamMove  // attribute moves with per-parameter values
}

// ChanMove is a single tracked-intensity move within a cue.
// Format in source: "1@H00" → channel 1, hex 0x00.
type ChanMove struct {
	Channel int
	Value   int
}

// ParamMove is one channel's attribute moves within a cue.
// Format in source: "$$Param 41 1@0 12@255 13@201 14@236 204@0".
// First field is channel, remaining are paramID@value pairs.
type ParamMove struct {
	Channel int
	Values  []ParamValue
}

// ParamValue is one paramID/value pair.
type ParamValue struct {
	ParamID int
	Value   int
}

// Palette is a Color/Beam/Focus/Intensity palette or a Preset.
type Palette struct {
	Number      string
	Label       string
	UnicodeText *string
	ChanMoves   []ChanMove
	ParamMoves  []ParamMove
}

// Group is one $Group block.
type Group struct {
	Number      string
	Label       string
	UnicodeText *string
	Channels    []int
}
```

- [ ] **Step 3: Write the failing parser test**

Create `internal/services/import_eos/parser_test.go`:

```go
package importeos

import (
	"os"
	"path/filepath"
	"testing"
)

func parseFixture(t *testing.T, name string) *Show {
	t.Helper()
	f, err := os.Open(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("open fixture: %v", err)
	}
	defer f.Close()
	show, _, err := Parse(f)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return show
}

func TestParse_MinimalPatch(t *testing.T) {
	show := parseFixture(t, "minimal_patch.asc")

	if show.Ident != "3:0" {
		t.Errorf("ident: got %q, want %q", show.Ident, "3:0")
	}
	if show.Manufacturer != "ETC" {
		t.Errorf("manufacturer: got %q, want %q", show.Manufacturer, "ETC")
	}
	if show.Console != "Eos" {
		t.Errorf("console: got %q", show.Console)
	}
	if show.Format != "3.20" {
		t.Errorf("format: got %q", show.Format)
	}
	if show.Title != "Minimal Patch Test" {
		t.Errorf("title: got %q", show.Title)
	}
	if len(show.ParamTypes) != 1 || show.ParamTypes[0].ID != 1 || show.ParamTypes[0].LongName != "Intens" {
		t.Errorf("param types: got %+v", show.ParamTypes)
	}
	if len(show.Personalities) != 1 || show.Personalities[0].ID != 9001 ||
		show.Personalities[0].Manuf != "Generic" || show.Personalities[0].Model != "Dimmer" {
		t.Errorf("personalities: got %+v", show.Personalities)
	}
	if len(show.Patch) != 2 {
		t.Fatalf("patch entries: got %d, want 2", len(show.Patch))
	}
	if show.Patch[0].Channel != 1 || show.Patch[0].AddressRaw != "1" || show.Patch[0].PersonalityID != 9001 ||
		show.Patch[0].Label != "Cyc R" {
		t.Errorf("patch[0]: got %+v", show.Patch[0])
	}
	if show.Patch[1].Label != "Cyc L" {
		t.Errorf("patch[1] label: got %q", show.Patch[1].Label)
	}
}
```

- [ ] **Step 4: Confirm the test fails**

Run: `go test ./internal/services/import_eos -run TestParse_MinimalPatch -v`
Expected: compile error on `Parse`.

- [ ] **Step 5: Implement minimal `Parse` in a new `parser.go`**

Create `internal/services/import_eos/parser.go`:

```go
package importeos

import (
	"fmt"
	"io"
	"strconv"
	"strings"
)

// ParseError is returned for fatal parser failures.
type ParseError struct {
	Lineno int
	Msg    string
}

func (e *ParseError) Error() string {
	return fmt.Sprintf("eos parse error at line %d: %s", e.Lineno, e.Msg)
}

// Parse reads r as an Eos ASCII file and returns the AST plus a Collector
// containing any non-fatal warnings (e.g. UNKNOWN_DIRECTIVE).
func Parse(r io.Reader) (*Show, *Collector, error) {
	lines, err := tokenize(r)
	if err != nil {
		return nil, nil, err
	}
	p := &parser{lines: lines, show: &Show{}, warn: &Collector{}}
	if err := p.run(); err != nil {
		return nil, nil, err
	}
	return p.show, p.warn, nil
}

type parser struct {
	lines []Line
	pos   int
	show  *Show
	warn  *Collector
}

func (p *parser) cur() *Line {
	if p.pos >= len(p.lines) {
		return nil
	}
	return &p.lines[p.pos]
}

func (p *parser) advance() { p.pos++ }

func (p *parser) run() error {
	for p.pos < len(p.lines) {
		line := p.cur()
		if line.Kind != LineDirective || line.Indent > 0 {
			p.advance()
			continue
		}
		if err := p.handleTopLevel(line); err != nil {
			return err
		}
	}
	return nil
}

func (p *parser) handleTopLevel(line *Line) error {
	switch line.Directive {
	case "Ident":
		p.show.Ident = strings.Join(line.Fields, " ")
		p.advance()
	case "Manufacturer":
		p.show.Manufacturer = strings.Join(line.Fields, " ")
		p.advance()
	case "Console":
		p.show.Console = strings.Join(line.Fields, " ")
		p.advance()
	case "$$Format":
		p.show.Format = strings.Join(line.Fields, " ")
		p.advance()
	case "$$Software":
		p.show.SoftwareString = line.Raw
		p.advance()
	case "$$Title":
		p.show.Title = strings.Join(line.Fields, " ")
		p.advance()
	case "$ParamType":
		return p.parseParamType()
	case "$Personality":
		return p.parsePersonality()
	case "$Patch":
		return p.parsePatch()
	default:
		// All other top-level directives become "skipped" until later tasks teach
		// the parser to handle them. We emit UNKNOWN_DIRECTIVE only for $-prefixed
		// directives we don't recognize so that ordinary keywords like "Clear"
		// or "Set" are silently passed over.
		if strings.HasPrefix(line.Directive, "$") {
			p.warn.Add(WarnUnknownDirective, SeverityInfo,
				fmt.Sprintf("skipping unknown directive %s", line.Directive),
				map[string]string{"line": strconv.Itoa(line.Lineno)})
		}
		p.advance()
		return nil
	}
}

func (p *parser) parseParamType() error {
	line := p.cur()
	if len(line.Fields) < 3 {
		return &ParseError{Lineno: line.Lineno, Msg: "$ParamType needs at least Id Cat Name"}
	}
	id, err := strconv.Atoi(line.Fields[0])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "$ParamType id not an integer"}
	}
	cat, err := strconv.Atoi(line.Fields[1])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "$ParamType cat not an integer"}
	}
	pt := ParamType{ID: id, Category: cat, LongName: strings.Join(line.Fields[2:], " ")}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		if sub.Directive == "$$ShortName" {
			pt.ShortName = strings.Join(sub.Fields, " ")
		}
		p.advance()
	}
	p.show.ParamTypes = append(p.show.ParamTypes, pt)
	return nil
}

func (p *parser) parsePersonality() error {
	line := p.cur()
	if len(line.Fields) < 1 {
		return &ParseError{Lineno: line.Lineno, Msg: "$Personality missing id"}
	}
	id, err := strconv.Atoi(line.Fields[0])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "$Personality id not an integer"}
	}
	pers := Personality{ID: id}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		switch sub.Directive {
		case "$$Manuf":
			pers.Manuf = strings.Join(sub.Fields, " ")
		case "$$Model":
			pers.Model = strings.Join(sub.Fields, " ")
		case "$$Dcid":
			pers.Dcid = strings.Join(sub.Fields, " ")
		case "$$Footprint":
			if len(sub.Fields) >= 1 {
				if v, err := strconv.Atoi(sub.Fields[0]); err == nil {
					pers.Footprint = v
				}
			}
		case "$$PersChan":
			if pc, ok := parsePersChan(sub); ok {
				pers.Channels = append(pers.Channels, pc)
			}
		}
		p.advance()
	}
	p.show.Personalities = append(p.show.Personalities, pers)
	return nil
}

func parsePersChan(line *Line) (PersChannel, bool) {
	// Fields: paramID size offset (offset16) home (flags)
	if len(line.Fields) < 4 {
		return PersChannel{}, false
	}
	paramID, err := strconv.Atoi(line.Fields[0])
	if err != nil {
		return PersChannel{}, false
	}
	size, _ := strconv.Atoi(line.Fields[1])
	offset, _ := strconv.Atoi(line.Fields[2])
	pc := PersChannel{ParamID: paramID, Size: size, Offset: offset}
	idx := 3
	if size == 2 && len(line.Fields) > idx {
		pc.Offset16, _ = strconv.Atoi(line.Fields[idx])
		idx++
	}
	if idx < len(line.Fields) {
		pc.HomeValue, _ = strconv.Atoi(line.Fields[idx])
		idx++
	}
	if idx < len(line.Fields) {
		pc.Flags = line.Fields[idx]
	}
	return pc, true
}

func (p *parser) parsePatch() error {
	line := p.cur()
	if len(line.Fields) < 3 {
		return &ParseError{Lineno: line.Lineno, Msg: "$Patch needs Channel Address PersID"}
	}
	channel, err := strconv.Atoi(line.Fields[0])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "$Patch channel not an integer"}
	}
	persID, err := strconv.Atoi(line.Fields[2])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "$Patch personality not an integer"}
	}
	pe := PatchEntry{Channel: channel, AddressRaw: line.Fields[1], PersonalityID: persID}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		if sub.Directive == "Text" {
			pe.Label = strings.Join(sub.Fields, " ")
		}
		p.advance()
	}
	p.show.Patch = append(p.show.Patch, pe)
	return nil
}
```

- [ ] **Step 6: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS for `TestLexer_*` and `TestParse_MinimalPatch`.

- [ ] **Step 7: Commit**

```bash
git add internal/services/import_eos/ast.go internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/minimal_patch.asc
git commit -m "feat(eos): parser handles header, ParamType, Personality, Patch"
```

### Task 4: Cue list and cue parsing (`basic_cues.asc`)

**Files:**
- Modify: `internal/services/import_eos/parser.go`
- Modify: `internal/services/import_eos/parser_test.go`
- Create: `internal/services/import_eos/testdata/basic_cues.asc`

- [ ] **Step 1: Create `internal/services/import_eos/testdata/basic_cues.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20
$$Title Basic Cues Test

$ParamType            1 1 Intens
   $$ShortName            Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001
   Text Front
$Patch 2 2 9001
   Text Back

$CueList 1
   Text Main

Cue 1 1
   Text Open
   Up 5
   $$TimeUp 5 0 1 1
   Down 5
   $$TimeDown 5 0 1 1
   $$ChanMove  1@HFF 2@H80

Cue 2 1
   Text Build
   Up 3
   $$TimeUp 3 0 1 1
   Down 3
   $$TimeDown 3 0 1 1
   $$Follow 2
   $$ChanMove  1@HFF 2@HFF
```

- [ ] **Step 2: Write failing test in `parser_test.go`**

Append:

```go
func TestParse_BasicCues(t *testing.T) {
	show := parseFixture(t, "basic_cues.asc")

	if len(show.CueLists) != 1 {
		t.Fatalf("cue lists: got %d, want 1", len(show.CueLists))
	}
	cl := show.CueLists[0]
	if cl.Number != 1 || cl.Label != "Main" {
		t.Errorf("cue list: got number=%d label=%q", cl.Number, cl.Label)
	}
	if len(cl.Cues) != 2 {
		t.Fatalf("cues: got %d, want 2", len(cl.Cues))
	}

	c0 := cl.Cues[0]
	if c0.Number != "1" || c0.Label != "Open" || c0.UpFade != 5 || c0.DownFade != 5 {
		t.Errorf("cue 0: got %+v", c0)
	}
	if len(c0.ChanMoves) != 2 {
		t.Fatalf("cue 0 chan moves: got %d", len(c0.ChanMoves))
	}
	if c0.ChanMoves[0].Channel != 1 || c0.ChanMoves[0].Value != 0xFF {
		t.Errorf("cue 0 chan move 0: got %+v", c0.ChanMoves[0])
	}
	if c0.ChanMoves[1].Channel != 2 || c0.ChanMoves[1].Value != 0x80 {
		t.Errorf("cue 0 chan move 1: got %+v", c0.ChanMoves[1])
	}

	c1 := cl.Cues[1]
	if c1.Number != "2" || c1.Follow == nil || *c1.Follow != 2 {
		t.Errorf("cue 1 follow: got %+v", c1.Follow)
	}
}
```

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run TestParse_BasicCues -v`
Expected: FAIL — `cue lists: got 0, want 1` (parser still skips `$CueList` and `Cue`).

- [ ] **Step 4: Extend `parser.go` to handle `$CueList` and `Cue`**

Add the case `"$CueList"` to `handleTopLevel` and a new top-level handler for the bare `Cue` directive (note: `Cue` is *not* `$`-prefixed):

```go
// In handleTopLevel switch, add:
	case "$CueList":
		return p.parseCueList()
	case "Cue":
		return p.parseCue()
```

Also extend the no-cuelist-yet handling: if a `Cue` line is seen before any `$CueList`, auto-create cue list 1. Append at the bottom of `parser.go`:

```go
func (p *parser) parseCueList() error {
	line := p.cur()
	if len(line.Fields) < 1 {
		return &ParseError{Lineno: line.Lineno, Msg: "$CueList needs number"}
	}
	num, err := strconv.Atoi(line.Fields[0])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "$CueList number not an integer"}
	}
	cl := CueList{Number: num}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		if sub.Directive == "Text" {
			cl.Label = strings.Join(sub.Fields, " ")
		}
		p.advance()
	}
	p.show.CueLists = append(p.show.CueLists, cl)
	return nil
}

func (p *parser) parseCue() error {
	line := p.cur()
	if len(line.Fields) < 2 {
		return &ParseError{Lineno: line.Lineno, Msg: "Cue needs Number ListNum"}
	}
	listNum, err := strconv.Atoi(line.Fields[1])
	if err != nil {
		return &ParseError{Lineno: line.Lineno, Msg: "Cue listNum not an integer"}
	}
	cue := Cue{Number: line.Fields[0]}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		switch sub.Directive {
		case "Text":
			cue.Label = strings.Join(sub.Fields, " ")
		case "Up":
			if len(sub.Fields) >= 1 {
				cue.UpFade, _ = strconv.ParseFloat(sub.Fields[0], 64)
			}
		case "Down":
			if len(sub.Fields) >= 1 {
				cue.DownFade, _ = strconv.ParseFloat(sub.Fields[0], 64)
			}
		case "$$Follow":
			if len(sub.Fields) >= 1 {
				if v, err := strconv.ParseFloat(sub.Fields[0], 64); err == nil {
					cue.Follow = &v
				}
			}
		case "$$Hang":
			if len(sub.Fields) >= 1 {
				if v, err := strconv.ParseFloat(sub.Fields[0], 64); err == nil {
					cue.Hang = &v
				}
			}
		case "$$Block":
			cue.Block = true
		case "$$IntBlock":
			cue.IntBlock = true
		case "$$ChanMove":
			cue.ChanMoves = append(cue.ChanMoves, parseChanMoves(sub.Fields)...)
		case "$$Param":
			if pm, ok := parseParamMove(sub.Fields); ok {
				cue.ParamMoves = append(cue.ParamMoves, pm)
			}
		}
		p.advance()
	}
	// Find or create the target cue list
	for i := range p.show.CueLists {
		if p.show.CueLists[i].Number == listNum {
			p.show.CueLists[i].Cues = append(p.show.CueLists[i].Cues, cue)
			return nil
		}
	}
	p.show.CueLists = append(p.show.CueLists, CueList{Number: listNum, Cues: []Cue{cue}})
	return nil
}

// parseChanMoves accepts tokens like "1@HFF" or "12@H00" and returns ChanMove entries.
func parseChanMoves(fields []string) []ChanMove {
	var out []ChanMove
	for _, f := range fields {
		at := strings.IndexByte(f, '@')
		if at < 0 {
			continue
		}
		ch, err := strconv.Atoi(f[:at])
		if err != nil {
			continue
		}
		raw := f[at+1:]
		val, err := parseLevel(raw)
		if err != nil {
			continue
		}
		out = append(out, ChanMove{Channel: ch, Value: val})
	}
	return out
}

// parseLevel decodes EOS level encoding: H<hex> for hex, or decimal otherwise.
// Returns 0..255.
func parseLevel(raw string) (int, error) {
	if len(raw) == 0 {
		return 0, fmt.Errorf("empty level")
	}
	if raw[0] == 'H' || raw[0] == 'h' {
		v, err := strconv.ParseInt(raw[1:], 16, 32)
		if err != nil {
			return 0, err
		}
		return int(v), nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return 0, err
	}
	return v, nil
}

// parseParamMove parses tokens like "41 1@0 12@255 13@201".
func parseParamMove(fields []string) (ParamMove, bool) {
	if len(fields) < 2 {
		return ParamMove{}, false
	}
	ch, err := strconv.Atoi(fields[0])
	if err != nil {
		return ParamMove{}, false
	}
	pm := ParamMove{Channel: ch}
	for _, f := range fields[1:] {
		at := strings.IndexByte(f, '@')
		if at < 0 {
			continue
		}
		paramID, err := strconv.Atoi(f[:at])
		if err != nil {
			continue
		}
		val, err := parseLevel(f[at+1:])
		if err != nil {
			continue
		}
		pm.Values = append(pm.Values, ParamValue{ParamID: paramID, Value: val})
	}
	return pm, true
}
```

- [ ] **Step 5: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS for all parser tests.

- [ ] **Step 6: Commit**

```bash
git add internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/basic_cues.asc
git commit -m "feat(eos): parse $CueList, Cue, $$ChanMove, $$Param, $$Follow"
```

### Task 5: Cue parts (`Cue 5/2`) and `$Cue` qualified form

**Files:**
- Modify: `internal/services/import_eos/parser.go`
- Modify: `internal/services/import_eos/parser_test.go`
- Modify: `internal/services/import_eos/testdata/basic_cues.asc` (add a parts cue + a `$Cue` for list 2)

- [ ] **Step 1: Append a parts cue and a second-list `$Cue` to `basic_cues.asc`**

Append at the end:

```
Cue 3 1
   Text Multi
   Up 4
   $$ChanMove  1@HC0

$CueList 2
   Text Backups

$Cue 1.5 2
   Text Backup A
   Up 2
   $$ChanMove  1@H40

Cue 5/2 1
   Text Part2
   Up 1
   $$ChanMove  2@HFF
```

- [ ] **Step 2: Update test for new expectations**

Replace the body of `TestParse_BasicCues` (or add a new test `TestParse_CueParts`):

```go
func TestParse_CuePartsAndQualified(t *testing.T) {
	show := parseFixture(t, "basic_cues.asc")
	if len(show.CueLists) != 2 {
		t.Fatalf("cue lists: got %d, want 2", len(show.CueLists))
	}
	var found *Cue
	for i := range show.CueLists[0].Cues {
		if show.CueLists[0].Cues[i].Number == "5" && show.CueLists[0].Cues[i].Part == 2 {
			found = &show.CueLists[0].Cues[i]
		}
	}
	if found == nil {
		t.Fatalf("expected cue 5 part 2 in list 1, got %+v", show.CueLists[0].Cues)
	}
	if found.Label != "Part2" {
		t.Errorf("part 2 label: got %q", found.Label)
	}

	if show.CueLists[1].Number != 2 || len(show.CueLists[1].Cues) != 1 {
		t.Fatalf("list 2 cues: got %+v", show.CueLists[1])
	}
	if show.CueLists[1].Cues[0].Number != "1.5" || show.CueLists[1].Cues[0].Label != "Backup A" {
		t.Errorf("list 2 cue 0: got %+v", show.CueLists[1].Cues[0])
	}
}
```

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run TestParse_CueParts -v`
Expected: FAIL — `expected cue 5 part 2 in list 1`.

- [ ] **Step 4: Extend parser to split parts and handle `$Cue`**

In `handleTopLevel`, add:

```go
	case "$Cue":
		return p.parseCue() // $Cue uses the same body parser
```

In `parseCue`, before storing the cue, split a `5/2` number into base and part:

```go
	if slash := strings.IndexByte(cue.Number, '/'); slash >= 0 {
		if part, err := strconv.Atoi(cue.Number[slash+1:]); err == nil {
			cue.Part = part
			cue.Number = cue.Number[:slash]
		}
	}
```

- [ ] **Step 5: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/basic_cues.asc
git commit -m "feat(eos): parse cue parts and \$Cue-qualified cue lines"
```

### Task 6: Palettes, Presets, Groups (`palettes_color_focus.asc`, `presets_groups.asc`)

**Files:**
- Create: `internal/services/import_eos/testdata/palettes_color_focus.asc`
- Create: `internal/services/import_eos/testdata/presets_groups.asc`
- Modify: `internal/services/import_eos/parser.go`
- Modify: `internal/services/import_eos/parser_test.go`

- [ ] **Step 1: Create `palettes_color_focus.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20
$$Title Palettes

$ParamType            1 1 Intens
$ParamType           12 3 Red
$ParamType           13 3 Green
$ParamType           14 3 Blue

$Personality 9100
   $$Manuf Generic
   $$Model RGB
   $$Footprint 4
   $$PersChan     1     1     1     0     0
   $$PersChan    12     1     2     0     0
   $$PersChan    13     1     3     0     0
   $$PersChan    14     1     4     0     0

$Patch 1 1 9100
   Text Wash 1

$ColorPalette 1
   Text Red
   $$Param  1 12@255 13@0 14@0

$ColorPalette 2
   Text Blue
   $$Param  1 12@0 13@0 14@255

$FocusPalette 1
   Text Center
   $$ChanMove  1@H80
```

- [ ] **Step 2: Create `presets_groups.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20
$$Title Presets and Groups

$ParamType            1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001
$Patch 2 2 9001
$Patch 3 3 9001

$Preset 1
   Text Half Up
   $$ChanMove  1@H80 2@H80 3@H80

$Group 1
   Text Front Wash
   1
   2

$Group 2
   Text All
   1 Thru 3
```

- [ ] **Step 3: Add tests**

```go
func TestParse_Palettes(t *testing.T) {
	show := parseFixture(t, "palettes_color_focus.asc")
	if len(show.ColorPalettes) != 2 {
		t.Fatalf("color palettes: got %d, want 2", len(show.ColorPalettes))
	}
	cp1 := show.ColorPalettes[0]
	if cp1.Number != "1" || cp1.Label != "Red" {
		t.Errorf("color palette 1: got %+v", cp1)
	}
	if len(cp1.ParamMoves) != 1 || cp1.ParamMoves[0].Channel != 1 ||
		len(cp1.ParamMoves[0].Values) != 3 {
		t.Errorf("color palette 1 params: got %+v", cp1.ParamMoves)
	}
	if len(show.FocusPalettes) != 1 || show.FocusPalettes[0].Label != "Center" {
		t.Errorf("focus palettes: got %+v", show.FocusPalettes)
	}
}

func TestParse_PresetsAndGroups(t *testing.T) {
	show := parseFixture(t, "presets_groups.asc")
	if len(show.Presets) != 1 || show.Presets[0].Label != "Half Up" {
		t.Fatalf("presets: got %+v", show.Presets)
	}
	if len(show.Presets[0].ChanMoves) != 3 {
		t.Errorf("preset chan moves: got %d, want 3", len(show.Presets[0].ChanMoves))
	}
	if len(show.Groups) != 2 {
		t.Fatalf("groups: got %d, want 2", len(show.Groups))
	}
	g1 := show.Groups[0]
	if g1.Label != "Front Wash" || len(g1.Channels) != 2 || g1.Channels[0] != 1 || g1.Channels[1] != 2 {
		t.Errorf("group 1: got %+v", g1)
	}
	g2 := show.Groups[1]
	if len(g2.Channels) != 3 || g2.Channels[0] != 1 || g2.Channels[2] != 3 {
		t.Errorf("group 2 thru: got %+v", g2)
	}
}
```

- [ ] **Step 4: Confirm failure**

Run: `go test ./internal/services/import_eos -run "TestParse_Palettes|TestParse_PresetsAndGroups" -v`
Expected: FAIL.

- [ ] **Step 5: Implement palette/preset/group parsers**

Add to `handleTopLevel`:

```go
	case "$ColorPalette":
		return p.parsePalette(&p.show.ColorPalettes)
	case "$BeamPalette":
		return p.parsePalette(&p.show.BeamPalettes)
	case "$FocusPalette":
		return p.parsePalette(&p.show.FocusPalettes)
	case "$IntensPalette":
		return p.parsePalette(&p.show.IntensPalettes)
	case "$Preset":
		return p.parsePalette(&p.show.Presets)
	case "$Group":
		return p.parseGroup()
```

Append helper functions:

```go
func (p *parser) parsePalette(target *[]Palette) error {
	line := p.cur()
	if len(line.Fields) < 1 {
		return &ParseError{Lineno: line.Lineno, Msg: "palette needs number"}
	}
	pal := Palette{Number: line.Fields[0]}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		switch sub.Directive {
		case "Text":
			pal.Label = strings.Join(sub.Fields, " ")
		case "$$ChanMove":
			pal.ChanMoves = append(pal.ChanMoves, parseChanMoves(sub.Fields)...)
		case "$$Param":
			if pm, ok := parseParamMove(sub.Fields); ok {
				pal.ParamMoves = append(pal.ParamMoves, pm)
			}
		}
		p.advance()
	}
	*target = append(*target, pal)
	return nil
}

func (p *parser) parseGroup() error {
	line := p.cur()
	if len(line.Fields) < 1 {
		return &ParseError{Lineno: line.Lineno, Msg: "$Group needs number"}
	}
	g := Group{Number: line.Fields[0]}
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		sub := p.cur()
		if sub.Directive == "Text" {
			g.Label = strings.Join(sub.Fields, " ")
		} else {
			// Channel list line: tokens are channel numbers or "Thru" ranges.
			// Examples: "1", "1 2 3", "1 Thru 3".
			tokens := append([]string{sub.Directive}, sub.Fields...)
			g.Channels = append(g.Channels, expandChannelTokens(tokens)...)
		}
		p.advance()
	}
	p.show.Groups = append(p.show.Groups, g)
	return nil
}

// expandChannelTokens expands tokens like ["1", "Thru", "3"] into [1, 2, 3].
func expandChannelTokens(tokens []string) []int {
	var out []int
	for i := 0; i < len(tokens); i++ {
		t := tokens[i]
		if strings.EqualFold(t, "Thru") && len(out) > 0 && i+1 < len(tokens) {
			endN, err := strconv.Atoi(tokens[i+1])
			if err == nil {
				start := out[len(out)-1] + 1
				for v := start; v <= endN; v++ {
					out = append(out, v)
				}
				i++
				continue
			}
		}
		if v, err := strconv.Atoi(t); err == nil {
			out = append(out, v)
		}
	}
	return out
}
```

- [ ] **Step 6: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/palettes_color_focus.asc internal/services/import_eos/testdata/presets_groups.asc
git commit -m "feat(eos): parse palettes, presets, and groups"
```

### Task 7: `$$UText` follow-records (`utext_unicode.asc`)

**Files:**
- Create: `internal/services/import_eos/utext.go`
- Create: `internal/services/import_eos/utext_test.go`
- Create: `internal/services/import_eos/testdata/utext_unicode.asc`
- Modify: `internal/services/import_eos/parser.go`

The format is undocumented in the file header, but real EOS exports use `$$UText` with hex-encoded UTF-16-LE bytes. Implement the encoding empirically: each `$$UText` field is two hex digits per byte; pairs of bytes form UTF-16-LE code units. If decoding fails, emit a `WarnUTextDecode` warning and fall back to the existing ASCII label.

- [ ] **Step 1: Create `utext.go`**

```go
package importeos

import (
	"encoding/hex"
	"unicode/utf16"
)

// decodeUText decodes a $$UText field list into a UTF-8 string.
// Encoding: each token is hex digits; concatenated bytes are UTF-16-LE.
// Returns false if decoding fails.
func decodeUText(fields []string) (string, bool) {
	var raw []byte
	for _, f := range fields {
		b, err := hex.DecodeString(f)
		if err != nil {
			return "", false
		}
		raw = append(raw, b...)
	}
	if len(raw)%2 != 0 {
		return "", false
	}
	u16 := make([]uint16, len(raw)/2)
	for i := 0; i < len(u16); i++ {
		u16[i] = uint16(raw[2*i]) | uint16(raw[2*i+1])<<8
	}
	return string(utf16.Decode(u16)), true
}
```

- [ ] **Step 2: Create unit test for the decoder**

```go
package importeos

import "testing"

func TestDecodeUText_RoundTripASCII(t *testing.T) {
	// "Hi" → UTF-16-LE bytes 48 00 69 00 → tokens "4800" "6900"
	got, ok := decodeUText([]string{"4800", "6900"})
	if !ok || got != "Hi" {
		t.Errorf("got %q ok=%v", got, ok)
	}
}

func TestDecodeUText_NonASCII(t *testing.T) {
	// "é" (U+00E9) → UTF-16-LE bytes E9 00
	got, ok := decodeUText([]string{"E900"})
	if !ok || got != "é" {
		t.Errorf("got %q ok=%v", got, ok)
	}
}

func TestDecodeUText_BadHex(t *testing.T) {
	_, ok := decodeUText([]string{"zz"})
	if ok {
		t.Error("expected failure on non-hex token")
	}
}
```

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run TestDecodeUText -v`
Expected: FAIL — `decodeUText` undefined.

- [ ] **Step 4: Confirm `utext.go` content from Step 1 is in place; tests pass**

Run: `go test ./internal/services/import_eos -run TestDecodeUText -v`
Expected: PASS.

- [ ] **Step 5: Wire `$$UText` follow-records into `parseCue`, `parsePalette`, `parsePatch`, `parseGroup`**

In each sub-directive loop, add a case:

```go
		case "$$UText":
			if s, ok := decodeUText(sub.Fields); ok {
				// attach to whatever struct is being built
				cue.UnicodeText = &s // or pe.UnicodeText, pal.UnicodeText, g.UnicodeText
			} else {
				p.warn.Add(WarnUTextDecode, SeverityWarn,
					"failed to decode $$UText",
					map[string]string{"line": strconv.Itoa(sub.Lineno)})
			}
```

Repeat the case in all four parsers (`parseCue`, `parsePalette`, `parsePatch`, `parseGroup`), substituting the right target field.

- [ ] **Step 6: Create `utext_unicode.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20

$ParamType            1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001
   Text Cafe
   $$UText 4300 6100 6600 E900

$CueList 1
   Text Setup

Cue 1 1
   Text Hi
   $$UText 4800 6900
   Up 5
   $$TimeUp 5 0 1 1
   Down 5
   $$TimeDown 5 0 1 1
   $$ChanMove  1@HFF
```

- [ ] **Step 7: Add an integration-style parse test**

```go
func TestParse_UTextOverridesLabel(t *testing.T) {
	show := parseFixture(t, "utext_unicode.asc")
	if show.Patch[0].UnicodeText == nil || *show.Patch[0].UnicodeText != "Café" {
		t.Errorf("patch unicode: got %v", show.Patch[0].UnicodeText)
	}
	if len(show.CueLists[0].Cues) != 1 ||
		show.CueLists[0].Cues[0].UnicodeText == nil ||
		*show.CueLists[0].Cues[0].UnicodeText != "Hi" {
		t.Errorf("cue unicode: got %v", show.CueLists[0].Cues[0].UnicodeText)
	}
}
```

- [ ] **Step 8: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add internal/services/import_eos/utext.go internal/services/import_eos/utext_test.go internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/utext_unicode.asc
git commit -m "feat(eos): decode \$\$UText UTF-16-LE follow-records on labels"
```

### Task 8: Multi-universe address parsing and conflict detection

**Files:**
- Create: `internal/services/import_eos/testdata/multi_universe.asc`
- Create: `internal/services/import_eos/testdata/conflict_addresses.asc`
- Modify: `internal/services/import_eos/parser.go`
- Modify: `internal/services/import_eos/parser_test.go`

EOS patch addresses can be `513` (flat absolute), `1.512` (universe.address), or `1/512` (slash form). Parsing returns the raw string into the AST; normalization happens in the mapper. Add a helper `NormalizeAddress` and unit-test it now so the mapper can rely on it later.

- [ ] **Step 1: Create `multi_universe.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20

$ParamType            1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001
$Patch 2 2.512 9001
$Patch 3 3/100 9001
$Patch 4 1024 9001
```

- [ ] **Step 2: Add tests**

```go
func TestParse_MultiUniverseAddresses(t *testing.T) {
	show := parseFixture(t, "multi_universe.asc")
	if len(show.Patch) != 4 {
		t.Fatalf("got %d patch entries", len(show.Patch))
	}
	for i, want := range []string{"1", "2.512", "3/100", "1024"} {
		if show.Patch[i].AddressRaw != want {
			t.Errorf("patch[%d] addr: got %q, want %q", i, show.Patch[i].AddressRaw, want)
		}
	}
}

func TestNormalizeAddress(t *testing.T) {
	cases := []struct {
		raw      string
		universe int
		address  int
		ok       bool
	}{
		{"1", 1, 1, true},
		{"512", 1, 512, true},
		{"513", 2, 1, true},
		{"1024", 2, 512, true},
		{"2.512", 2, 512, true},
		{"3/100", 3, 100, true},
		{"abc", 0, 0, false},
	}
	for _, c := range cases {
		u, a, err := NormalizeAddress(c.raw)
		if (err == nil) != c.ok {
			t.Errorf("%q: got err=%v, want ok=%v", c.raw, err, c.ok)
			continue
		}
		if c.ok && (u != c.universe || a != c.address) {
			t.Errorf("%q: got u=%d a=%d, want u=%d a=%d", c.raw, u, a, c.universe, c.address)
		}
	}
}
```

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run "TestParse_MultiUniverse|TestNormalizeAddress" -v`
Expected: FAIL.

- [ ] **Step 4: Add `NormalizeAddress` to `parser.go`**

```go
// NormalizeAddress converts an EOS patch address string to a (universe, address) tuple.
// Accepts flat absolute ("1024"), dotted ("2.512"), and slashed ("3/100") forms.
// Universes are 1-based, addresses are 1-based and 1..512.
func NormalizeAddress(raw string) (universe int, address int, err error) {
	for _, sep := range []byte{'.', '/'} {
		if i := strings.IndexByte(raw, sep); i >= 0 {
			u, e1 := strconv.Atoi(raw[:i])
			a, e2 := strconv.Atoi(raw[i+1:])
			if e1 != nil || e2 != nil || u < 1 || a < 1 || a > 512 {
				return 0, 0, fmt.Errorf("invalid eos address %q", raw)
			}
			return u, a, nil
		}
	}
	flat, err := strconv.Atoi(raw)
	if err != nil || flat < 1 {
		return 0, 0, fmt.Errorf("invalid eos address %q", raw)
	}
	universe = (flat-1)/512 + 1
	address = (flat-1)%512 + 1
	return universe, address, nil
}
```

- [ ] **Step 5: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/multi_universe.asc
git commit -m "feat(eos): normalize multi-universe patch addresses (a.b, a/b, flat)"
```

### Task 9: Tracking — cumulative cue state computation

**Files:**
- Create: `internal/services/import_eos/tracker.go`
- Create: `internal/services/import_eos/tracker_test.go`
- Create: `internal/services/import_eos/testdata/tracking.asc`

The tracker walks an ordered list of cues and computes cumulative per-channel and per-parameter state. EOS tracking semantics: a level set in cue N persists into cue N+1, N+2... until another cue overrides it. `$$Block` resets all tracked values for that cue (full snapshot). `$$IntBlock` resets only intensity tracking.

- [ ] **Step 1: Create `tracking.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20

$ParamType            1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001
$Patch 2 2 9001
$Patch 3 3 9001

$CueList 1
   Text Track

Cue 1 1
   Up 5
   Down 5
   $$ChanMove  1@HFF 2@HFF

Cue 2 1
   Up 5
   Down 5
   $$ChanMove  3@HFF

Cue 3 1
   Up 5
   Down 5
   $$ChanMove  1@H00
```

- [ ] **Step 2: Write the failing test**

Create `tracker_test.go`:

```go
package importeos

import (
	"reflect"
	"testing"
)

func TestTracker_PropagatesAndOverrides(t *testing.T) {
	show := parseFixture(t, "tracking.asc")
	tr := NewTracker()
	snapshots := tr.ResolveCueList(show.CueLists[0].Cues, show.ColorPalettes,
		show.BeamPalettes, show.FocusPalettes, show.IntensPalettes, show.Presets)

	if len(snapshots) != 3 {
		t.Fatalf("snapshots: got %d", len(snapshots))
	}
	want0 := map[int]int{1: 0xFF, 2: 0xFF}
	if !reflect.DeepEqual(snapshots[0].ChannelLevels, want0) {
		t.Errorf("cue 1 levels: got %v, want %v", snapshots[0].ChannelLevels, want0)
	}
	want1 := map[int]int{1: 0xFF, 2: 0xFF, 3: 0xFF}
	if !reflect.DeepEqual(snapshots[1].ChannelLevels, want1) {
		t.Errorf("cue 2 (track): got %v, want %v", snapshots[1].ChannelLevels, want1)
	}
	want2 := map[int]int{1: 0x00, 2: 0xFF, 3: 0xFF}
	if !reflect.DeepEqual(snapshots[2].ChannelLevels, want2) {
		t.Errorf("cue 3 (override): got %v, want %v", snapshots[2].ChannelLevels, want2)
	}
}
```

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run TestTracker -v`
Expected: FAIL — `NewTracker` undefined.

- [ ] **Step 4: Implement `tracker.go`**

```go
package importeos

// Snapshot is the fully resolved per-channel state for one cue.
type Snapshot struct {
	CueNumber     string
	CuePart       int
	ChannelLevels map[int]int                 // channel → 0..255 (intensity)
	ParamLevels   map[int]map[int]int         // channel → paramID → 0..255
	UpFade        float64
	UpDelay       float64
	DownFade      float64
	DownDelay     float64
	Follow        *float64
	Hang          *float64
	Block         bool
	IntBlock      bool
	Label         string
	UnicodeText   *string
}

// Tracker walks a cue list applying tracking semantics.
type Tracker struct{}

// NewTracker returns a fresh tracker.
func NewTracker() *Tracker { return &Tracker{} }

// ResolveCueList resolves each cue against cumulative state.
// Palette references in $$Param values are resolved against the supplied
// palette tables (currently unused since EOS exports inline values; reserved
// for future palette-ref syntax).
func (t *Tracker) ResolveCueList(
	cues []Cue,
	colorPalettes, beamPalettes, focusPalettes, intensPalettes, presets []Palette,
) []Snapshot {
	chanState := make(map[int]int)
	paramState := make(map[int]map[int]int)
	out := make([]Snapshot, 0, len(cues))
	for _, cue := range cues {
		if cue.Block {
			chanState = make(map[int]int)
			paramState = make(map[int]map[int]int)
		} else if cue.IntBlock {
			chanState = make(map[int]int)
		}
		for _, m := range cue.ChanMoves {
			chanState[m.Channel] = m.Value
		}
		for _, pm := range cue.ParamMoves {
			ps, ok := paramState[pm.Channel]
			if !ok {
				ps = make(map[int]int)
				paramState[pm.Channel] = ps
			}
			for _, v := range pm.Values {
				ps[v.ParamID] = v.Value
			}
		}
		// Build the snapshot from a copy of the running state.
		sn := Snapshot{
			CueNumber:     cue.Number,
			CuePart:       cue.Part,
			ChannelLevels: copyIntMap(chanState),
			ParamLevels:   copyParamMap(paramState),
			UpFade:        cue.UpFade,
			UpDelay:       cue.UpDelay,
			DownFade:      cue.DownFade,
			DownDelay:     cue.DownDelay,
			Follow:        cue.Follow,
			Hang:          cue.Hang,
			Block:         cue.Block,
			IntBlock:      cue.IntBlock,
			Label:         cue.Label,
			UnicodeText:   cue.UnicodeText,
		}
		out = append(out, sn)
	}
	return out
}

func copyIntMap(m map[int]int) map[int]int {
	out := make(map[int]int, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

func copyParamMap(m map[int]map[int]int) map[int]map[int]int {
	out := make(map[int]map[int]int, len(m))
	for ch, params := range m {
		out[ch] = copyIntMap(params)
	}
	return out
}
```

- [ ] **Step 5: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/services/import_eos/tracker.go internal/services/import_eos/tracker_test.go internal/services/import_eos/testdata/tracking.asc
git commit -m "feat(eos): tracking resolver computes cumulative per-cue snapshots"
```

### Task 10: Sidecar reader (`sidecar_roundtrip.asc`)

**Files:**
- Create: `internal/services/import_eos/sidecar_reader.go`
- Create: `internal/services/import_eos/sidecar_reader_test.go`
- Create: `internal/services/import_eos/testdata/sidecar_roundtrip.asc`
- Modify: `internal/services/import_eos/parser.go` (collect `$$ LACYLIGHTS:` into `Show.SidecarLines`)
- Modify: `internal/services/import_eos/lexer.go` (preserve trailing comment block)

The sidecar lives in lines that look like `$$ LACYLIGHTS:<key> <json>`. The parser already treats them as unknown directives (since they don't appear in `handleTopLevel`). We need the lexer to preserve them as `LineDirective` (which it already does — `$$ LACYLIGHTS:version` parses with `Directive == "$$"` because the space splits it). To handle this cleanly, the lexer treats `$$` followed by `LACYLIGHTS:` specially and emits a `LineSidecar` kind. Update the lexer rather than relying on the parser's unknown-directive path.

- [ ] **Step 1: Add a new `LineKind` and detect sidecar lines in the lexer**

In `lexer.go`:

```go
const (
	LineBlank LineKind = iota
	LineComment
	LineDirective
	LineSidecar
)
```

In `tokenize`, before the directive branch, after stripping leading whitespace, check whether the trimmed line begins with `$$ LACYLIGHTS:`:

```go
		if strings.HasPrefix(trimmed, "$$ LACYLIGHTS:") {
			out = append(out, Line{Lineno: lineno, Kind: LineSidecar, Raw: raw})
			continue
		}
```

- [ ] **Step 2: Update parser to collect `LineSidecar` lines**

In the `parser.run` loop, before the existing `if line.Kind != LineDirective` block, add:

```go
		if line.Kind == LineSidecar {
			p.show.SidecarLines = append(p.show.SidecarLines, line.Raw)
			p.advance()
			continue
		}
```

- [ ] **Step 3: Implement `sidecar_reader.go`**

```go
package importeos

import (
	"encoding/json"
	"strings"
)

// Sidecar holds parsed `$$ LACYLIGHTS:` records from an Eos ASCII file.
type Sidecar struct {
	Version       int                   // sidecar schema version
	LookBoards    []SidecarLookBoard
	FadeBehaviors []SidecarFadeBehavior
	SynthDefs     []SidecarSynthDef
}

// SidecarLookBoard describes a LacyLights look board.
type SidecarLookBoard struct {
	RefID   string                  `json:"refId"`
	Name    string                  `json:"name"`
	Buttons []SidecarLookBoardButton `json:"buttons"`
}

// SidecarLookBoardButton describes one button on a look board.
type SidecarLookBoardButton struct {
	LookRefID string `json:"lookRefId"`
	X         int    `json:"x"`
	Y         int    `json:"y"`
	Color     string `json:"color"`
}

// SidecarFadeBehavior captures non-default per-channel fade behaviors.
type SidecarFadeBehavior struct {
	InstanceRefID string                       `json:"instanceRefId"`
	Channels      []SidecarFadeBehaviorChannel `json:"channels"`
}

// SidecarFadeBehaviorChannel describes one channel's behavior.
type SidecarFadeBehaviorChannel struct {
	Offset   int    `json:"offset"`
	Behavior string `json:"behavior"` // "FADE" | "SNAP" | "SNAP_END"
}

// SidecarSynthDef marks a fixture definition that was synthesized on a prior import.
type SidecarSynthDef struct {
	DefRefID           string `json:"defRefId"`
	Manufacturer       string `json:"manufacturer"`
	Model              string `json:"model"`
	ChannelFingerprint string `json:"channelFingerprint"`
}

// ReadSidecar parses raw sidecar lines into a Sidecar struct.
// Malformed records are skipped and reported via the supplied collector.
func ReadSidecar(rawLines []string, warn *Collector) Sidecar {
	out := Sidecar{}
	for _, line := range rawLines {
		// Format: "$$ LACYLIGHTS:<key> <payload>"
		const prefix = "$$ LACYLIGHTS:"
		idx := strings.Index(line, prefix)
		if idx < 0 {
			continue
		}
		body := strings.TrimSpace(line[idx+len(prefix):])
		spaceAt := strings.IndexAny(body, " \t")
		var key, payload string
		if spaceAt < 0 {
			key, payload = body, ""
		} else {
			key, payload = body[:spaceAt], strings.TrimSpace(body[spaceAt+1:])
		}
		switch key {
		case "version":
			if v, ok := parseSidecarInt(payload); ok {
				out.Version = v
			} else {
				warn.Add(WarnSidecarInvalid, SeverityWarn, "invalid sidecar version", nil)
			}
		case "look_board":
			var lb SidecarLookBoard
			if err := json.Unmarshal([]byte(payload), &lb); err != nil {
				warn.Add(WarnSidecarInvalid, SeverityWarn, "invalid look_board JSON",
					map[string]string{"err": err.Error()})
				continue
			}
			out.LookBoards = append(out.LookBoards, lb)
		case "fade_behavior":
			var fb SidecarFadeBehavior
			if err := json.Unmarshal([]byte(payload), &fb); err != nil {
				warn.Add(WarnSidecarInvalid, SeverityWarn, "invalid fade_behavior JSON",
					map[string]string{"err": err.Error()})
				continue
			}
			out.FadeBehaviors = append(out.FadeBehaviors, fb)
		case "synth_def":
			var sd SidecarSynthDef
			if err := json.Unmarshal([]byte(payload), &sd); err != nil {
				warn.Add(WarnSidecarInvalid, SeverityWarn, "invalid synth_def JSON",
					map[string]string{"err": err.Error()})
				continue
			}
			out.SynthDefs = append(out.SynthDefs, sd)
		default:
			warn.Add(WarnSidecarInvalid, SeverityInfo,
				"unknown sidecar key: "+key, nil)
		}
	}
	return out
}

func parseSidecarInt(s string) (int, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false
	}
	v := 0
	for _, r := range s {
		if r < '0' || r > '9' {
			return 0, false
		}
		v = v*10 + int(r-'0')
	}
	return v, true
}
```

- [ ] **Step 4: Create `sidecar_roundtrip.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20

$ParamType            1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001

$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:look_board {"refId":"board-a","name":"Top","buttons":[{"lookRefId":"L1","x":0,"y":0,"color":"#ff0000"}]}
$$ LACYLIGHTS:fade_behavior {"instanceRefId":"fix-1","channels":[{"offset":3,"behavior":"SNAP_END"}]}
$$ LACYLIGHTS:synth_def {"defRefId":"def-1","manufacturer":"Generic","model":"Dimmer","channelFingerprint":"1"}
```

- [ ] **Step 5: Write the sidecar reader test**

```go
package importeos

import "testing"

func TestReadSidecar_Roundtrip(t *testing.T) {
	show := parseFixture(t, "sidecar_roundtrip.asc")
	if len(show.SidecarLines) != 4 {
		t.Fatalf("sidecar lines: got %d, want 4", len(show.SidecarLines))
	}
	warn := &Collector{}
	sc := ReadSidecar(show.SidecarLines, warn)
	if sc.Version != 1 {
		t.Errorf("version: got %d", sc.Version)
	}
	if len(sc.LookBoards) != 1 || sc.LookBoards[0].RefID != "board-a" ||
		len(sc.LookBoards[0].Buttons) != 1 ||
		sc.LookBoards[0].Buttons[0].LookRefID != "L1" {
		t.Errorf("look board: got %+v", sc.LookBoards)
	}
	if len(sc.FadeBehaviors) != 1 || sc.FadeBehaviors[0].InstanceRefID != "fix-1" ||
		sc.FadeBehaviors[0].Channels[0].Behavior != "SNAP_END" {
		t.Errorf("fade behavior: got %+v", sc.FadeBehaviors)
	}
	if len(sc.SynthDefs) != 1 || sc.SynthDefs[0].DefRefID != "def-1" {
		t.Errorf("synth def: got %+v", sc.SynthDefs)
	}
	if len(warn.All()) != 0 {
		t.Errorf("unexpected warnings: %+v", warn.All())
	}
}

func TestReadSidecar_BadJSON(t *testing.T) {
	warn := &Collector{}
	sc := ReadSidecar([]string{`$$ LACYLIGHTS:look_board {invalid json}`}, warn)
	if len(sc.LookBoards) != 0 {
		t.Error("expected no look boards from bad JSON")
	}
	if len(warn.All()) != 1 || warn.All()[0].Code != WarnSidecarInvalid {
		t.Errorf("expected SIDECAR_INVALID warning, got %+v", warn.All())
	}
}
```

- [ ] **Step 6: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add internal/services/import_eos/sidecar_reader.go internal/services/import_eos/sidecar_reader_test.go internal/services/import_eos/lexer.go internal/services/import_eos/parser.go internal/services/import_eos/testdata/sidecar_roundtrip.asc
git commit -m "feat(eos): sidecar reader for \$\$ LACYLIGHTS: comment blocks"
```

### Task 11: Soft-warning directives (effects, partitions, faderdef, magic sheet, action, curve)

**Files:**
- Modify: `internal/services/import_eos/parser.go`
- Modify: `internal/services/import_eos/parser_test.go`
- Create: `internal/services/import_eos/testdata/unknown_directive.asc`

Effects, faders, partitions, action triggers, magic sheets, and curves should be skipped with structured warnings (not raw `UNKNOWN_DIRECTIVE`). They each have an indented body; we need to consume the body and emit one warning per top-level occurrence.

- [ ] **Step 1: Create `unknown_directive.asc`**

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20

$ParamType            1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan     1     1     1     0     0

$Patch 1 1 9001

$Effect 100
   Text Chase
   $$Type 1
   $$Time 1.5

$FaderDef 1.1
   Text Sub 1
   $$Mode 0

$Partition 1
   Text Audience
   $$Channels 1 Thru 100

$MagicSheet 1
   Text Stage Plot

$Action 1
   $$Trigger UDP

$Curve 901
   Text Linear
```

- [ ] **Step 2: Add tests**

```go
func TestParse_SoftWarnings(t *testing.T) {
	f, err := os.Open(filepath.Join("testdata", "unknown_directive.asc"))
	if err != nil { t.Fatal(err) }
	defer f.Close()
	_, warn, err := Parse(f)
	if err != nil { t.Fatalf("Parse: %v", err) }
	codes := map[WarningCode]int{}
	for _, w := range warn.All() {
		codes[w.Code]++
	}
	want := map[WarningCode]int{
		WarnEffectSkipped:     1,
		WarnSubmasterSkipped:  1,
		WarnPartitionSkipped:  1,
		WarnMagicSheetSkipped: 1,
		WarnActionSkipped:     1,
		WarnCurveSkipped:      1,
	}
	for code, n := range want {
		if codes[code] != n {
			t.Errorf("warning code %s: got %d, want %d (all=%v)", code, codes[code], n, codes)
		}
	}
}
```

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run TestParse_SoftWarnings -v`
Expected: FAIL.

- [ ] **Step 4: Add cases to `handleTopLevel`**

```go
	case "$Effect":
		return p.skipBlockWithWarning(WarnEffectSkipped, "EOS effect not modeled")
	case "$FaderDef", "$Sub":
		return p.skipBlockWithWarning(WarnSubmasterSkipped, "EOS submaster/fader not modeled")
	case "$Partition":
		return p.skipBlockWithWarning(WarnPartitionSkipped, "EOS partition not modeled")
	case "$MagicSheet":
		return p.skipBlockWithWarning(WarnMagicSheetSkipped, "EOS magic sheet not modeled")
	case "$Action":
		return p.skipBlockWithWarning(WarnActionSkipped, "EOS action trigger not modeled")
	case "$Curve":
		return p.skipBlockWithWarning(WarnCurveSkipped, "EOS curve not modeled")
```

Add helper:

```go
func (p *parser) skipBlockWithWarning(code WarningCode, msg string) error {
	line := p.cur()
	p.warn.Add(code, SeverityInfo, msg,
		map[string]string{"line": strconv.Itoa(line.Lineno), "directive": line.Directive})
	p.advance()
	for p.cur() != nil && p.cur().Indent > 0 {
		p.advance()
	}
	return nil
}
```

- [ ] **Step 5: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/services/import_eos/parser.go internal/services/import_eos/parser_test.go internal/services/import_eos/testdata/unknown_directive.asc
git commit -m "feat(eos): emit structured warnings for skipped EOS-only directives"
```

### Task 12: Param-type lookup

**Files:**
- Create: `internal/services/import_eos/param_table.go`
- Create: `internal/services/import_eos/param_table_test.go`

The Eos param table maps numeric IDs to LacyLights `models.ChannelType`. Common IDs used in our golden fixture: 1=Intens, 2=Pan, 3=Tilt, 7=Hue, 8=Saturation, 9=Cyan, 10=Magenta, 11=Yellow, 12=Red, 13=Green, 14=Blue, 48=Amber, 51=White, 52=Cool_White, 53=Warm_White, 79=Zoom, 204=Shutter_Strobe, 6359=Dimmer_Curve.

- [ ] **Step 1: Identify the LacyLights `ChannelType` enum**

```bash
grep -n "type ChannelType" internal/database/models/*.go
grep -n "ChannelTypeIntensity\|ChannelTypeRed\|ChannelTypePan" internal/database/models/*.go | head -20
```

The plan assumes the existing constants follow the pattern `models.ChannelTypeIntensity`, `ChannelTypeRed`, etc. If a constant for a given parameter doesn't exist, fall back to `models.ChannelTypeOther` (or the existing equivalent) and emit no warning.

- [ ] **Step 2: Write failing test**

Create `param_table_test.go`:

```go
package importeos

import (
	"testing"

	"github.com/bbernstein/lacylights-go/internal/database/models"
)

func TestParamTable_KnownTypes(t *testing.T) {
	pts := []ParamType{
		{ID: 1, Category: 1, LongName: "Intens"},
		{ID: 2, Category: 2, LongName: "Pan"},
		{ID: 12, Category: 3, LongName: "Red"},
		{ID: 13, Category: 3, LongName: "Green"},
		{ID: 14, Category: 3, LongName: "Blue"},
		{ID: 48, Category: 3, LongName: "Amber"},
		{ID: 79, Category: 5, LongName: "Zoom"},
		{ID: 204, Category: 5, LongName: "Shutter_Strobe"},
		{ID: 9999, Category: 7, LongName: "Custom"},
	}
	tbl := NewParamTable(pts)
	cases := []struct {
		id   int
		want models.ChannelType
	}{
		{1, models.ChannelTypeIntensity},
		{2, models.ChannelTypePan},
		{12, models.ChannelTypeRed},
		{13, models.ChannelTypeGreen},
		{14, models.ChannelTypeBlue},
		{48, models.ChannelTypeAmber},
		{79, models.ChannelTypeZoom},
		{204, models.ChannelTypeStrobe},
		{9999, models.ChannelTypeOther},
	}
	for _, c := range cases {
		got := tbl.ChannelType(c.id)
		if got != c.want {
			t.Errorf("paramID %d: got %v, want %v", c.id, got, c.want)
		}
	}
}
```

- [ ] **Step 3: Confirm failure, then implement**

Create `param_table.go`:

```go
package importeos

import (
	"strings"

	"github.com/bbernstein/lacylights-go/internal/database/models"
)

// ParamTable maps EOS parameter IDs to LacyLights ChannelType values.
type ParamTable struct {
	byID map[int]models.ChannelType
}

// NewParamTable builds a lookup from a parsed $ParamType list.
// Unknown IDs map to models.ChannelTypeOther.
func NewParamTable(pts []ParamType) *ParamTable {
	t := &ParamTable{byID: make(map[int]models.ChannelType, len(pts))}
	for _, pt := range pts {
		t.byID[pt.ID] = mapParamTypeName(pt.LongName, pt.Category)
	}
	return t
}

// ChannelType returns the LacyLights ChannelType for an EOS parameter ID.
func (t *ParamTable) ChannelType(id int) models.ChannelType {
	if t == nil {
		return models.ChannelTypeOther
	}
	if v, ok := t.byID[id]; ok {
		return v
	}
	return models.ChannelTypeOther
}

// mapParamTypeName classifies by name first (most reliable), category second.
func mapParamTypeName(name string, category int) models.ChannelType {
	switch strings.ToLower(name) {
	case "intens", "intensity":
		return models.ChannelTypeIntensity
	case "pan":
		return models.ChannelTypePan
	case "tilt":
		return models.ChannelTypeTilt
	case "red":
		return models.ChannelTypeRed
	case "green":
		return models.ChannelTypeGreen
	case "blue":
		return models.ChannelTypeBlue
	case "amber":
		return models.ChannelTypeAmber
	case "white", "cool_white", "warm_white":
		return models.ChannelTypeWhite
	case "zoom":
		return models.ChannelTypeZoom
	case "shutter_strobe", "strobe":
		return models.ChannelTypeStrobe
	}
	switch category {
	case 1:
		return models.ChannelTypeIntensity
	case 2:
		return models.ChannelTypeOther // pan/tilt handled by name
	case 3:
		return models.ChannelTypeOther // colors handled by name
	}
	return models.ChannelTypeOther
}
```

- [ ] **Step 4: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS. If any `models.ChannelType*` constants don't exist in this codebase, search for the actual name and substitute. Adjust the test and impl together; any change to constant names is acceptable as long as the *test* names mirror what `param_table.go` returns.

- [ ] **Step 5: Commit**

```bash
git add internal/services/import_eos/param_table.go internal/services/import_eos/param_table_test.go
git commit -m "feat(eos): map ParamType IDs to LacyLights ChannelType values"
```

### Task 13: Fixture matcher (match-then-synthesize)

**Files:**
- Create: `internal/services/import_eos/fixture_match.go`
- Create: `internal/services/import_eos/fixture_match_test.go`

The matcher takes a parsed `Personality` and either returns an existing `models.FixtureDefinition` ID (if a built-in or OFL definition matches) or synthesizes a new definition. Matching keys, in order:

1. DCID (when both sides have one)
2. Manufacturer + Model + footprint + channel-fingerprint match (channel ParamID sequence)
3. Otherwise synthesize.

The synthesizer constructs a `FixtureDefinition` with one channel per `PersChannel`, naming each channel after its `ParamType` long name and tagging the channel type via `ParamTable`.

- [ ] **Step 1: Locate the existing FixtureRepository find-by-mfg/model API**

```bash
grep -n "FindByManufacturerAndModel\|FindByDcid\|GetDefinitionByName" internal/database/repositories/fixture_repository.go
```

If a usable method exists, the matcher calls it. If only a list-all method exists, fetch the list and match in memory. The plan assumes one of these methods exists; if neither does, add a thin one in `fixture_repository.go` and commit it as part of this task.

- [ ] **Step 2: Write the failing test**

```go
package importeos

import (
	"context"
	"testing"
)

type fakeFixtureRepo struct {
	defs []*FakeDef
}

type FakeDef struct {
	ID, Manufacturer, Model string
	ChannelParamIDs         []int
}

func (f *fakeFixtureRepo) FindMatchingDefinition(_ context.Context, mfg, model string, paramIDs []int) (*FakeDef, error) {
	for _, d := range f.defs {
		if d.Manufacturer == mfg && d.Model == model && intSliceEqual(d.ChannelParamIDs, paramIDs) {
			return d, nil
		}
	}
	return nil, nil
}

func intSliceEqual(a, b []int) bool {
	if len(a) != len(b) { return false }
	for i := range a { if a[i] != b[i] { return false } }
	return true
}

func TestMatcher_MatchesExisting(t *testing.T) {
	repo := &fakeFixtureRepo{defs: []*FakeDef{
		{ID: "def-1", Manufacturer: "Generic", Model: "Dimmer", ChannelParamIDs: []int{1}},
	}}
	m := NewMatcher(repo, NewParamTable(nil))
	pers := Personality{Manuf: "Generic", Model: "Dimmer", Channels: []PersChannel{{ParamID: 1}}}
	res, _, err := m.Match(context.Background(), pers)
	if err != nil { t.Fatal(err) }
	if res.ExistingDefinitionID != "def-1" || res.SynthesizedDef != nil {
		t.Errorf("expected match, got %+v", res)
	}
}

func TestMatcher_Synthesizes(t *testing.T) {
	repo := &fakeFixtureRepo{}
	m := NewMatcher(repo, NewParamTable([]ParamType{
		{ID: 1, LongName: "Intens"}, {ID: 12, LongName: "Red"}, {ID: 13, LongName: "Green"}, {ID: 14, LongName: "Blue"},
	}))
	pers := Personality{
		Manuf: "Acme", Model: "QuadLED",
		Channels: []PersChannel{{ParamID: 1}, {ParamID: 12}, {ParamID: 13}, {ParamID: 14}},
	}
	res, warns, err := m.Match(context.Background(), pers)
	if err != nil { t.Fatal(err) }
	if res.SynthesizedDef == nil {
		t.Fatal("expected synthesized def")
	}
	if res.SynthesizedDef.Manufacturer != "Acme" || res.SynthesizedDef.Model != "QuadLED" {
		t.Errorf("synth name: got %s/%s", res.SynthesizedDef.Manufacturer, res.SynthesizedDef.Model)
	}
	if len(res.SynthesizedDef.Channels) != 4 {
		t.Errorf("channels: got %d", len(res.SynthesizedDef.Channels))
	}
	if len(warns) != 1 || warns[0].Code != WarnSynthesizedFixture {
		t.Errorf("warnings: got %+v", warns)
	}
}
```

- [ ] **Step 3: Implement `fixture_match.go`**

```go
package importeos

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/bbernstein/lacylights-go/internal/database/models"
)

// MatcherRepo is the subset of FixtureRepository the matcher needs.
// In production this is wired to *repositories.FixtureRepository via an adapter.
type MatcherRepo interface {
	FindMatchingDefinition(ctx context.Context, mfg, model string, paramIDs []int) (*FakeDef, error)
}

// MatchResult is the matcher's verdict for one personality.
type MatchResult struct {
	ExistingDefinitionID string                  // non-empty if matched to an existing def
	SynthesizedDef       *models.FixtureDefinition
	SynthesizedChannels  []models.ChannelDefinition
	ChannelFingerprint   string
}

// Matcher resolves Eos personalities to LacyLights fixture definitions.
type Matcher struct {
	repo  MatcherRepo
	table *ParamTable
}

// NewMatcher constructs a matcher.
func NewMatcher(repo MatcherRepo, table *ParamTable) *Matcher {
	return &Matcher{repo: repo, table: table}
}

// Match attempts to find an existing definition; otherwise synthesizes.
// Returns warnings produced by the matcher.
func (m *Matcher) Match(ctx context.Context, pers Personality) (MatchResult, []Warning, error) {
	paramIDs := make([]int, len(pers.Channels))
	for i, c := range pers.Channels {
		paramIDs[i] = c.ParamID
	}
	res := MatchResult{ChannelFingerprint: fingerprint(paramIDs)}

	if pers.Manuf != "" && pers.Model != "" {
		existing, err := m.repo.FindMatchingDefinition(ctx, pers.Manuf, pers.Model, paramIDs)
		if err != nil {
			return res, nil, err
		}
		if existing != nil {
			res.ExistingDefinitionID = existing.ID
			return res, nil, nil
		}
	}

	def, channels := m.synthesize(pers, paramIDs)
	res.SynthesizedDef = def
	res.SynthesizedChannels = channels
	return res, []Warning{{
		Code:     WarnSynthesizedFixture,
		Severity: SeverityInfo,
		Message:  fmt.Sprintf("synthesized fixture definition for %s %s", pers.Manuf, pers.Model),
		Context:  map[string]string{"manufacturer": pers.Manuf, "model": pers.Model, "channels": res.ChannelFingerprint},
	}}, nil
}

func (m *Matcher) synthesize(pers Personality, paramIDs []int) (*models.FixtureDefinition, []models.ChannelDefinition) {
	def := &models.FixtureDefinition{
		Manufacturer: pers.Manuf,
		Model:        pers.Model,
		Type:         "OTHER",
		IsBuiltIn:    false,
	}
	channels := make([]models.ChannelDefinition, len(pers.Channels))
	for i, pc := range pers.Channels {
		channels[i] = models.ChannelDefinition{
			Offset:       pc.Offset,
			Name:         channelNameFor(pc.ParamID, m.table),
			Type:         m.table.ChannelType(pc.ParamID),
			MinValue:     0,
			MaxValue:     255,
			DefaultValue: pc.HomeValue,
			FadeBehavior: snapToFadeBehavior(pc.Flags),
		}
	}
	return def, channels
}

func channelNameFor(paramID int, table *ParamTable) string {
	switch table.ChannelType(paramID) {
	case models.ChannelTypeIntensity:
		return "Intensity"
	case models.ChannelTypePan:
		return "Pan"
	case models.ChannelTypeTilt:
		return "Tilt"
	case models.ChannelTypeRed:
		return "Red"
	case models.ChannelTypeGreen:
		return "Green"
	case models.ChannelTypeBlue:
		return "Blue"
	case models.ChannelTypeAmber:
		return "Amber"
	case models.ChannelTypeWhite:
		return "White"
	case models.ChannelTypeZoom:
		return "Zoom"
	case models.ChannelTypeStrobe:
		return "Strobe"
	}
	return "Channel " + strconv.Itoa(paramID)
}

func snapToFadeBehavior(flags string) string {
	if strings.Contains(flags, "S") {
		return "SNAP"
	}
	return "FADE"
}

func fingerprint(paramIDs []int) string {
	parts := make([]string, len(paramIDs))
	for i, id := range paramIDs {
		parts[i] = strconv.Itoa(id)
	}
	return strings.Join(parts, ",")
}
```

The test uses a `*FakeDef`; tighten the types so the matcher works with both the fake and the real repo by introducing a small adapter in Task 14. For now, the matcher accepts the fake interface.

- [ ] **Step 4: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/services/import_eos/fixture_match.go internal/services/import_eos/fixture_match_test.go
git commit -m "feat(eos): match-then-synthesize matcher with channel-fingerprint key"
```

### Task 14: Mapper — patch creation, palettes-as-looks, cues with tracking

**Files:**
- Create: `internal/services/import_eos/mapper.go`
- Create: `internal/services/import_eos/mapper_test.go`
- Modify: `internal/services/import_eos/service.go`
- Modify: `internal/services/import_eos/fixture_match.go` (add real-repo adapter)

The mapper accepts a parsed `Show`, a sidecar struct, and the standard repo handles the existing import service uses (`ProjectRepository`, `FixtureRepository`, `LookRepository`, `CueListRepository`, `CueRepository`, `LookBoardRepository`). It runs in a single DB transaction. The transaction wrapper used by the existing JSON importer is the model — call out: study `internal/services/import/import.go` for the tx pattern before writing the mapper.

- [ ] **Step 1: Read the existing JSON importer's transaction pattern**

```bash
grep -n "WithTx\|BeginTx\|Transaction" internal/services/import/import.go | head -20
grep -n "func .*Import" internal/services/import/import.go | head -10
```

Carry the same convention forward.

- [ ] **Step 2: Define the mapper interface and write a minimal failing test**

Create `mapper_test.go`:

```go
package importeos

import (
	"context"
	"strings"
	"testing"
)

func TestMapper_MinimalPatchCreatesProjectAndFixtures(t *testing.T) {
	deps := newTestDeps(t) // builds an in-memory SQLite + repos using the same helpers
	defer deps.close()

	src := strings.NewReader(`Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20
$$Title Test Show

$ParamType 1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan 1 1 1 0 0

$Patch 1 1 9001
   Text Front
$Patch 2 2 9001
   Text Back
`)

	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), src, Options{NewProjectName: ptr("Test Show")})
	if err != nil { t.Fatalf("Import: %v", err) }
	if res.FixtureInstancesCount != 2 {
		t.Errorf("instances: got %d, want 2", res.FixtureInstancesCount)
	}
}

func ptr[T any](v T) *T { return &v }
```

`newTestDeps` should mirror what existing tests in `internal/services/import/` use to bootstrap an in-memory SQLite + all repos. Reuse those helpers if they're exported; otherwise duplicate the smallest set needed. Keep this test file's bootstrap helpers in a shared `testdeps_test.go` at the same package level.

- [ ] **Step 3: Confirm failure**

Run: `go test ./internal/services/import_eos -run TestMapper_Minimal -v`
Expected: FAIL — `NewServiceWithDeps` undefined.

- [ ] **Step 4: Implement `mapper.go`**

```go
package importeos

import (
	"context"
	"fmt"

	"github.com/bbernstein/lacylights-go/internal/database/models"
	"github.com/bbernstein/lacylights-go/internal/database/repositories"
)

// Mapper applies a parsed Show + Sidecar to LacyLights repos inside one transaction.
type Mapper struct {
	projectRepo   *repositories.ProjectRepository
	fixtureRepo   *repositories.FixtureRepository
	lookRepo      *repositories.LookRepository
	cueListRepo   *repositories.CueListRepository
	cueRepo       *repositories.CueRepository
	lookBoardRepo *repositories.LookBoardRepository
}

// NewMapper constructs a Mapper.
func NewMapper(p *repositories.ProjectRepository, f *repositories.FixtureRepository,
	l *repositories.LookRepository, cl *repositories.CueListRepository,
	c *repositories.CueRepository, lb *repositories.LookBoardRepository) *Mapper {
	return &Mapper{p, f, l, cl, c, lb}
}

// Apply maps the parsed show into the database. Caller is responsible for the
// transaction wrapper if multi-step atomicity is desired; this method assumes
// it is invoked from inside a tx.
func (m *Mapper) Apply(ctx context.Context, show *Show, sidecar Sidecar, opts Options, warn *Collector) (*Result, error) {
	res := &Result{}

	// 1. Project
	projectID, err := m.resolveProject(ctx, show, opts)
	if err != nil {
		return nil, fmt.Errorf("resolve project: %w", err)
	}
	res.ProjectID = projectID

	// 2. Param table
	table := NewParamTable(show.ParamTypes)

	// 3. Match/synthesize personalities
	matcher := NewMatcher(newRepoAdapter(m.fixtureRepo), table)
	persToDefID := make(map[int]string, len(show.Personalities))
	for _, pers := range show.Personalities {
		mr, mWarns, err := matcher.Match(ctx, pers)
		if err != nil {
			return nil, fmt.Errorf("match personality %d: %w", pers.ID, err)
		}
		for _, w := range mWarns {
			warn.Add(w.Code, w.Severity, w.Message, w.Context)
		}
		var defID string
		if mr.ExistingDefinitionID != "" {
			defID = mr.ExistingDefinitionID
		} else {
			created, err := m.fixtureRepo.CreateDefinitionWithChannels(ctx, mr.SynthesizedDef, mr.SynthesizedChannels)
			if err != nil {
				return nil, fmt.Errorf("create synth def: %w", err)
			}
			defID = created.ID
			res.SynthesizedDefinitionIDs = append(res.SynthesizedDefinitionIDs, defID)
		}
		persToDefID[pers.ID] = defID
		res.FixtureDefinitionsCount++
	}

	// 4. Fixture instances
	for _, pe := range show.Patch {
		defID, ok := persToDefID[pe.PersonalityID]
		if !ok {
			return nil, &ParseError{Lineno: 0, Msg: fmt.Sprintf("$Patch %d references undeclared personality %d", pe.Channel, pe.PersonalityID)}
		}
		universe, address, err := NormalizeAddress(pe.AddressRaw)
		if err != nil {
			return nil, err
		}
		label := pe.Label
		if pe.UnicodeText != nil {
			label = *pe.UnicodeText
		}
		_, err = m.fixtureRepo.CreateInstance(ctx, &models.FixtureInstance{
			ProjectID:    projectID,
			DefinitionID: defID,
			Name:         label,
			Universe:     universe,
			StartChannel: address,
			ChannelOrder: pe.Channel, // EOS channel number stored as ordering hint
		})
		if err != nil {
			return nil, fmt.Errorf("create instance: %w", err)
		}
		res.FixtureInstancesCount++
	}

	// 5. Palettes → looks in dedicated cue lists
	if err := m.applyPalettes(ctx, projectID, show, &res.LooksCount, &res.CueListsCount); err != nil {
		return nil, err
	}

	// 6. Cues with tracking
	if err := m.applyCues(ctx, projectID, show, &res.LooksCount, &res.CueListsCount, &res.CuesCount); err != nil {
		return nil, err
	}

	// 7. Groups
	if err := m.applyGroups(ctx, projectID, show, &res.GroupsCount); err != nil {
		return nil, err
	}

	// 8. Sidecar (look boards, fade behaviors, synth def relinking)
	if err := m.applySidecar(ctx, projectID, sidecar, warn); err != nil {
		return nil, err
	}

	res.Warnings = warn.All()
	return res, nil
}

func (m *Mapper) resolveProject(ctx context.Context, show *Show, opts Options) (string, error) {
	if opts.TargetProjectID != nil {
		return *opts.TargetProjectID, nil
	}
	name := show.Title
	if opts.NewProjectName != nil {
		name = *opts.NewProjectName
	}
	if name == "" {
		name = "Imported Eos Show"
	}
	p, err := m.projectRepo.Create(ctx, &models.Project{Name: name})
	if err != nil {
		return "", err
	}
	return p.ID, nil
}

// applyPalettes / applyCues / applyGroups / applySidecar bodies are filled in
// across the next four sub-tasks (14a-14d). For the green-bar in this task,
// stub them as no-ops returning nil and update Result counts in their stubs.
func (m *Mapper) applyPalettes(ctx context.Context, projectID string, show *Show, looksCount, cueListsCount *int) error {
	return nil
}
func (m *Mapper) applyCues(ctx context.Context, projectID string, show *Show, looksCount, cueListsCount, cuesCount *int) error {
	return nil
}
func (m *Mapper) applyGroups(ctx context.Context, projectID string, show *Show, groupsCount *int) error {
	return nil
}
func (m *Mapper) applySidecar(ctx context.Context, projectID string, sidecar Sidecar, warn *Collector) error {
	return nil
}
```

Add the real-repo adapter in `fixture_match.go`:

```go
// newRepoAdapter wraps the production FixtureRepository so it satisfies the
// MatcherRepo interface used by the matcher's tests.
func newRepoAdapter(repo *repositories.FixtureRepository) MatcherRepo {
	return &repoAdapter{repo: repo}
}

type repoAdapter struct {
	repo *repositories.FixtureRepository
}

func (a *repoAdapter) FindMatchingDefinition(ctx context.Context, mfg, model string, paramIDs []int) (*FakeDef, error) {
	defs, err := a.repo.ListDefinitionsByManufacturerAndModel(ctx, mfg, model)
	if err != nil {
		return nil, err
	}
	for _, d := range defs {
		// Build a paramID-equivalent fingerprint by mapping each existing channel's
		// type back to a representative paramID. Adjust to match the production
		// FixtureDefinition shape — the goal is "do these channels look the same?"
		ids := channelTypesToParamIDs(d.Channels)
		if intSliceEqual(ids, paramIDs) {
			return &FakeDef{ID: d.ID, Manufacturer: d.Manufacturer, Model: d.Model, ChannelParamIDs: ids}, nil
		}
	}
	return nil, nil
}
```

If `ListDefinitionsByManufacturerAndModel` doesn't exist, add a thin one to `fixture_repository.go` first (returns all defs matching `manufacturer = ? AND model = ?` with channels eager-loaded).

- [ ] **Step 5: Implement `service.go` wiring**

Replace the stub `Import` in `service.go`:

```go
package importeos

import (
	"context"
	"fmt"
	"io"

	"github.com/bbernstein/lacylights-go/internal/database/repositories"
)

type Service struct {
	projectRepo   *repositories.ProjectRepository
	fixtureRepo   *repositories.FixtureRepository
	lookRepo      *repositories.LookRepository
	cueListRepo   *repositories.CueListRepository
	cueRepo       *repositories.CueRepository
	lookBoardRepo *repositories.LookBoardRepository
}

// NewService is kept for callers that haven't yet wired repos; returns a non-functional
// service that always errors. Use NewServiceWithDeps in production.
func NewService() *Service { return &Service{} }

func NewServiceWithDeps(p *repositories.ProjectRepository, f *repositories.FixtureRepository,
	l *repositories.LookRepository, cl *repositories.CueListRepository, c *repositories.CueRepository,
	lb *repositories.LookBoardRepository) *Service {
	return &Service{p, f, l, cl, c, lb}
}

func (s *Service) Import(ctx context.Context, r io.Reader, opts Options) (*Result, error) {
	if s.projectRepo == nil {
		return nil, fmt.Errorf("import_eos: service not wired with repositories")
	}
	show, parseWarn, err := Parse(r)
	if err != nil {
		return nil, err
	}
	collector := parseWarn
	sidecar := ReadSidecar(show.SidecarLines, collector)
	mapper := NewMapper(s.projectRepo, s.fixtureRepo, s.lookRepo, s.cueListRepo, s.cueRepo, s.lookBoardRepo)
	return mapper.Apply(ctx, show, sidecar, opts, collector)
}
```

- [ ] **Step 6: Run tests, confirm they pass**

Run: `go test ./internal/services/import_eos -run TestMapper_Minimal -v`
Expected: PASS — patch entries created, no looks/cues/groups yet (sub-tasks 14a-14d will fill them in).

- [ ] **Step 7: Commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/service.go internal/services/import_eos/fixture_match.go internal/services/import_eos/mapper_test.go internal/services/import_eos/testdeps_test.go internal/database/repositories/fixture_repository.go
git commit -m "feat(eos): mapper creates project, definitions, and fixture instances"
```

### Task 14a: Mapper — palettes as looks

**Files:**
- Modify: `internal/services/import_eos/mapper.go` (`applyPalettes`)
- Modify: `internal/services/import_eos/mapper_test.go`

- [ ] **Step 1: Add a fixture-rich palette test**

```go
func TestMapper_PalettesBecomeLooksInDedicatedCueLists(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()
	f := openFixture(t, "palettes_color_focus.asc")
	defer f.Close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("Pal")})
	if err != nil { t.Fatal(err) }
	lists := deps.cueListRepo.MustListByProject(t, res.ProjectID)
	names := map[string]int{}
	for _, l := range lists { names[l.Name]++ }
	if names["Color Palettes"] != 1 || names["Focus Palettes"] != 1 {
		t.Errorf("missing palette cue lists, got %v", names)
	}
}
```

`openFixture` is the same helper used in parser tests; export it from the test package or duplicate it here.

- [ ] **Step 2: Confirm failure**, then **implement `applyPalettes`**:

```go
func (m *Mapper) applyPalettes(ctx context.Context, projectID string, show *Show, looksCount, cueListsCount *int) error {
	groups := []struct {
		name     string
		palettes []Palette
	}{
		{"Color Palettes", show.ColorPalettes},
		{"Beam Palettes", show.BeamPalettes},
		{"Focus Palettes", show.FocusPalettes},
		{"Intensity Palettes", show.IntensPalettes},
		{"Presets", show.Presets},
	}
	for _, g := range groups {
		if len(g.palettes) == 0 {
			continue
		}
		cl, err := m.cueListRepo.Create(ctx, &models.CueList{
			ProjectID: projectID,
			Name:      g.name,
		})
		if err != nil {
			return fmt.Errorf("create palette cue list %s: %w", g.name, err)
		}
		*cueListsCount++
		for i, pal := range g.palettes {
			look, err := m.lookFromPalette(ctx, projectID, pal)
			if err != nil {
				return err
			}
			*looksCount++
			label := pal.Label
			if pal.UnicodeText != nil {
				label = *pal.UnicodeText
			}
			_, err = m.cueRepo.Create(ctx, &models.Cue{
				CueListID: cl.ID,
				LookID:    look.ID,
				Position:  i,
				Name:      fmt.Sprintf("%s %s - %s", g.name, pal.Number, label),
			})
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (m *Mapper) lookFromPalette(ctx context.Context, projectID string, pal Palette) (*models.Look, error) {
	// Build a Look with channel/parameter values from pal.ChanMoves + pal.ParamMoves.
	// Real implementation must look up each channel's FixtureInstance and write the
	// values onto matching InstanceChannel offsets. This sub-task only commits the
	// helper signature plus a Look creation; channel-value materialization is in 14b.
	return m.lookRepo.Create(ctx, &models.Look{
		ProjectID: projectID,
		Name:      "Palette " + pal.Number,
	})
}
```

- [ ] **Step 3: Run tests, confirm pass; commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go
git commit -m "feat(eos): map palettes/presets into dedicated LacyLights cue lists"
```

### Task 14b: Mapper — channel-value materialization for palettes and cues

**Files:**
- Modify: `internal/services/import_eos/mapper.go` (`lookFromPalette` + new `applyCues`)

This is the biggest single piece of correctness work in the backend. The mapper must convert EOS `ChanMoves`/`ParamMoves` (keyed by EOS channel number + paramID) into LacyLights look values keyed by `(FixtureInstance.ID, channel_offset_within_instance)`.

For each `Snapshot` produced by the tracker:

1. For each EOS channel with intensity, find the LacyLights `FixtureInstance` whose `ChannelOrder` equals the EOS channel number, then find its intensity-typed channel (offset N within the instance, looked up via the definition's channel list), and write `value/255.0`.
2. For each EOS channel's parameter values, look up each paramID in `ParamTable`, find the matching `ChannelType` channel within the instance, and write the value.

- [ ] **Step 1: Add a tracking-aware mapper test**

```go
func TestMapper_CuesProduceTrackedSnapshots(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()
	f := openFixture(t, "tracking.asc")
	defer f.Close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("Track")})
	if err != nil { t.Fatal(err) }
	cl := deps.cueListRepo.MustFindByName(t, res.ProjectID, "Track")
	cues := deps.cueRepo.MustListByCueList(t, cl.ID)
	if len(cues) != 3 { t.Fatalf("cues: got %d", len(cues)) }

	// Cue 2 should have channels 1, 2, AND 3 at full (tracked + new move on 3).
	cue2Look := deps.lookRepo.MustGet(t, cues[1].LookID)
	count := 0
	for _, fv := range cue2Look.FixtureValues {
		for _, cv := range fv.ChannelValues {
			if cv.Type == "INTENSITY" && cv.Value > 0.99 {
				count++
			}
		}
	}
	if count != 3 {
		t.Errorf("expected 3 intensity-full channels in cue 2, got %d", count)
	}
}
```

- [ ] **Step 2: Implement `applyCues` and the channel-value materialization**

Replace the stub `applyCues` in `mapper.go`:

```go
func (m *Mapper) applyCues(ctx context.Context, projectID string, show *Show, looksCount, cueListsCount, cuesCount *int) error {
	instances, err := m.fixtureRepo.ListInstancesByProject(ctx, projectID)
	if err != nil {
		return fmt.Errorf("list instances: %w", err)
	}
	channelOrderToInstance := make(map[int]*models.FixtureInstance, len(instances))
	for _, fi := range instances {
		channelOrderToInstance[fi.ChannelOrder] = fi
	}
	table := NewParamTable(show.ParamTypes)
	tracker := NewTracker()

	for _, cl := range show.CueLists {
		// Skip any list whose number conflicts with the palette lists already created
		// (palette lists have non-numeric EOS provenance and are created above).
		listName := cl.Label
		if listName == "" {
			listName = fmt.Sprintf("Cue List %d", cl.Number)
		}
		dbList, err := m.cueListRepo.Create(ctx, &models.CueList{ProjectID: projectID, Name: listName})
		if err != nil {
			return err
		}
		*cueListsCount++

		snaps := tracker.ResolveCueList(cl.Cues, show.ColorPalettes, show.BeamPalettes,
			show.FocusPalettes, show.IntensPalettes, show.Presets)
		for i, snap := range snaps {
			look, err := m.materializeLook(ctx, projectID, snap, channelOrderToInstance, table)
			if err != nil {
				return err
			}
			*looksCount++
			cueName := fmt.Sprintf("Cue %s", snap.CueNumber)
			if snap.CuePart > 0 {
				cueName = fmt.Sprintf("Cue %s Part %d", snap.CueNumber, snap.CuePart)
			}
			label := snap.Label
			if snap.UnicodeText != nil {
				label = *snap.UnicodeText
			}
			if label != "" {
				cueName = cueName + " - " + label
			}
			_, err = m.cueRepo.Create(ctx, &models.Cue{
				CueListID:    dbList.ID,
				LookID:       look.ID,
				Position:     i,
				Name:         cueName,
				FadeInTime:   snap.UpFade,
				FadeOutTime:  snap.DownFade,
				FollowTime:   floatOrZero(snap.Follow),
			})
			if err != nil {
				return err
			}
			*cuesCount++
		}
	}
	return nil
}

func floatOrZero(p *float64) float64 {
	if p == nil {
		return 0
	}
	return *p
}

func (m *Mapper) materializeLook(ctx context.Context, projectID string, snap Snapshot,
	channelOrderToInstance map[int]*models.FixtureInstance, table *ParamTable,
) (*models.Look, error) {
	look := &models.Look{
		ProjectID: projectID,
		Name:      "Cue " + snap.CueNumber,
	}
	for ch, intensity := range snap.ChannelLevels {
		fi, ok := channelOrderToInstance[ch]
		if !ok {
			continue
		}
		offset := findChannelOffset(fi, models.ChannelTypeIntensity)
		if offset < 0 {
			continue
		}
		look.FixtureValues = append(look.FixtureValues, models.LookFixtureValue{
			FixtureInstanceID: fi.ID,
			ChannelValues: []models.ChannelValue{{
				Offset: offset,
				Type:   string(models.ChannelTypeIntensity),
				Value:  float64(intensity) / 255.0,
			}},
		})
	}
	for ch, params := range snap.ParamLevels {
		fi, ok := channelOrderToInstance[ch]
		if !ok {
			continue
		}
		var values []models.ChannelValue
		for paramID, raw := range params {
			ct := table.ChannelType(paramID)
			offset := findChannelOffset(fi, ct)
			if offset < 0 {
				continue
			}
			values = append(values, models.ChannelValue{
				Offset: offset,
				Type:   string(ct),
				Value:  float64(raw) / 255.0,
			})
		}
		if len(values) > 0 {
			look.FixtureValues = append(look.FixtureValues, models.LookFixtureValue{
				FixtureInstanceID: fi.ID,
				ChannelValues:     values,
			})
		}
	}
	return m.lookRepo.Create(ctx, look)
}

func findChannelOffset(fi *models.FixtureInstance, ct models.ChannelType) int {
	for _, c := range fi.Channels {
		if c.Type == ct {
			return c.Offset
		}
	}
	return -1
}
```

Update `lookFromPalette` to materialize values too — it now mirrors `materializeLook` over the palette's `ChanMoves` and `ParamMoves`.

- [ ] **Step 3: Run all import_eos tests, confirm pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS, including the new tracking test and earlier palette test.

- [ ] **Step 4: Commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go
git commit -m "feat(eos): materialize tracked snapshots into LacyLights looks"
```

### Task 14c: Mapper — groups and sidecar application

**Files:**
- Modify: `internal/services/import_eos/mapper.go` (`applyGroups`, `applySidecar`)
- Modify: `internal/services/import_eos/mapper_test.go`

- [ ] **Step 1: Add tests for groups and sidecar look-board reconstruction**

```go
func TestMapper_GroupsCreated(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()
	f := openFixture(t, "presets_groups.asc")
	defer f.Close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("G")})
	if err != nil { t.Fatal(err) }
	groups := deps.fixtureRepo.MustListGroupsByProject(t, res.ProjectID)
	if len(groups) != 2 { t.Fatalf("groups: got %d", len(groups)) }
	if groups[0].Name != "Front Wash" || len(groups[0].FixtureIDs) != 2 {
		t.Errorf("group 0: got %+v", groups[0])
	}
}

func TestMapper_SidecarLookBoardRebuilt(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()
	f := openFixture(t, "sidecar_roundtrip.asc")
	defer f.Close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("S")})
	if err != nil { t.Fatal(err) }
	boards := deps.lookBoardRepo.MustListByProject(t, res.ProjectID)
	if len(boards) != 1 || boards[0].Name != "Top" {
		t.Fatalf("boards: got %+v", boards)
	}
}
```

- [ ] **Step 2: Implement `applyGroups`**

```go
func (m *Mapper) applyGroups(ctx context.Context, projectID string, show *Show, groupsCount *int) error {
	if len(show.Groups) == 0 {
		return nil
	}
	instances, err := m.fixtureRepo.ListInstancesByProject(ctx, projectID)
	if err != nil { return err }
	chToFix := make(map[int]string, len(instances))
	for _, fi := range instances { chToFix[fi.ChannelOrder] = fi.ID }
	for _, g := range show.Groups {
		var fixtureIDs []string
		for _, ch := range g.Channels {
			if id, ok := chToFix[ch]; ok {
				fixtureIDs = append(fixtureIDs, id)
			}
		}
		label := g.Label
		if g.UnicodeText != nil { label = *g.UnicodeText }
		if label == "" { label = "Group " + g.Number }
		if _, err := m.fixtureRepo.CreateGroup(ctx, &models.FixtureGroup{
			ProjectID:  projectID,
			Name:       label,
			FixtureIDs: fixtureIDs,
		}); err != nil {
			return err
		}
		*groupsCount++
	}
	return nil
}
```

- [ ] **Step 3: Implement `applySidecar`**

```go
func (m *Mapper) applySidecar(ctx context.Context, projectID string, sidecar Sidecar, warn *Collector) error {
	for _, lb := range sidecar.LookBoards {
		looksByRef, err := m.lookRepo.MapByRefID(ctx, projectID, refIDsFromLookBoard(lb))
		if err != nil {
			warn.Add(WarnSidecarUnresolved, SeverityWarn, "look board look refs not found", map[string]string{"board": lb.RefID})
			continue
		}
		var buttons []models.LookBoardButton
		for _, b := range lb.Buttons {
			lid, ok := looksByRef[b.LookRefID]
			if !ok {
				warn.Add(WarnSidecarUnresolved, SeverityWarn, "skipping button with unresolved look",
					map[string]string{"board": lb.RefID, "lookRefId": b.LookRefID})
				continue
			}
			buttons = append(buttons, models.LookBoardButton{
				LookID: lid, X: b.X, Y: b.Y, Color: b.Color,
			})
		}
		if _, err := m.lookBoardRepo.Create(ctx, &models.LookBoard{
			ProjectID: projectID, Name: lb.Name, Buttons: buttons,
		}); err != nil {
			return err
		}
	}
	for _, fb := range sidecar.FadeBehaviors {
		fi, err := m.fixtureRepo.FindInstanceByRefID(ctx, projectID, fb.InstanceRefID)
		if err != nil || fi == nil {
			warn.Add(WarnSidecarUnresolved, SeverityWarn, "fade_behavior unresolved instance",
				map[string]string{"instanceRefId": fb.InstanceRefID})
			continue
		}
		for _, c := range fb.Channels {
			if err := m.fixtureRepo.UpdateInstanceChannelFadeBehavior(ctx, fi.ID, c.Offset, c.Behavior); err != nil {
				return err
			}
		}
	}
	// SynthDefs are advisory; relinking happens during fixture matching when both
	// sides agree on (manufacturer, model, channelFingerprint). No DB writes here.
	return nil
}

func refIDsFromLookBoard(lb SidecarLookBoard) []string {
	out := make([]string, 0, len(lb.Buttons))
	for _, b := range lb.Buttons {
		out = append(out, b.LookRefID)
	}
	return out
}
```

If `MapByRefID`, `FindInstanceByRefID`, or `UpdateInstanceChannelFadeBehavior` don't exist on the repos, add thin implementations to the relevant `_repository.go` files. Each is a one-query method.

- [ ] **Step 4: Run all tests, confirm pass**

Run: `go test ./internal/services/import_eos -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/mapper_test.go internal/database/repositories
git commit -m "feat(eos): groups + sidecar (look boards, fade behaviors) on import"
```

### Task 15: Hard-error parser tests (`conflict_addresses.asc`, `malformed_cue.asc`)

**Files:**
- Create: `internal/services/import_eos/testdata/conflict_addresses.asc`
- Create: `internal/services/import_eos/testdata/malformed_cue.asc`
- Modify: `internal/services/import_eos/mapper.go` (address-conflict detection)
- Modify: `internal/services/import_eos/parser_test.go`

- [ ] **Step 1: Create the two negative fixtures**

`conflict_addresses.asc`:

```
Ident 3:0
Manufacturer ETC
Console Eos
$$Format 3.20

$ParamType 1 1 Intens

$Personality 9001
   $$Manuf Generic
   $$Model Dimmer
   $$Footprint 1
   $$PersChan 1 1 1 0 0

$Patch 1 1 9001
$Patch 2 1 9001
```

`malformed_cue.asc`:

```
Ident 3:0
$$Format 3.20

$CueList 1
   Text Bad

Cue notanumber 1
   Up 5
```

- [ ] **Step 2: Add tests**

```go
func TestImport_AddressConflictReturnsHardError(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()
	f := openFixture(t, "conflict_addresses.asc")
	defer f.Close()
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	_, err := svc.Import(context.Background(), f, Options{NewProjectName: ptr("X")})
	if err == nil { t.Fatal("expected error") }
	if !strings.Contains(err.Error(), "address") {
		t.Errorf("expected address-conflict error, got %v", err)
	}
}

func TestParse_MalformedCueReturnsParseError(t *testing.T) {
	f := openFixture(t, "malformed_cue.asc")
	defer f.Close()
	_, _, err := Parse(f)
	if err == nil { t.Fatal("expected parse error") }
}
```

Note: malformed cue numbers are tolerated by the parser today (`Cue notanumber 1` falls through `strconv.Atoi` on the *list* number, not the cue number — actually the second token is the list number and is also `1`, so this fixture must trigger on the listnum branch). Use `Cue 1 notalist` instead in the fixture.

Update `malformed_cue.asc` to:

```
Ident 3:0
$$Format 3.20

Cue 1 notalist
   Up 5
```

- [ ] **Step 3: Implement address-conflict detection in `Mapper.Apply`**

Before calling `m.fixtureRepo.CreateInstance`, maintain a `seen := map[[2]int]int` keyed by `(universe, address)` → EOS channel; on collision, return a `ParseError`-style error: `fmt.Errorf("eos import: address conflict at universe %d address %d (channels %d and %d)", u, a, seen[key], pe.Channel)`.

- [ ] **Step 4: Run tests, confirm pass; commit**

```bash
git add internal/services/import_eos/mapper.go internal/services/import_eos/testdata/conflict_addresses.asc internal/services/import_eos/testdata/malformed_cue.asc internal/services/import_eos/parser_test.go internal/services/import_eos/mapper_test.go
git commit -m "feat(eos): hard-error on address conflicts and malformed cue lines"
```

### Task 16: Writer — header, ParamType, personality, patch

**Files:**
- Create: `internal/services/export_eos/writer.go`
- Create: `internal/services/export_eos/header.go`
- Create: `internal/services/export_eos/personality.go`
- Create: `internal/services/export_eos/patch.go`
- Create: `internal/services/export_eos/writer_test.go`
- Modify: `internal/services/export_eos/service.go`

The writer's job: given a project, produce deterministic Eos ASCII text. We assemble the file in memory section by section, sorted for stability (cues by number, fixtures by EOS channel, etc.). LF line endings. No timestamps in deterministic positions.

- [ ] **Step 1: Write a failing test for the header section**

```go
package exporteos

import (
	"strings"
	"testing"
)

func TestWriter_HeaderSection(t *testing.T) {
	w := newWriter(WriterOptions{Title: "My Show", FormatVersion: "3.20"})
	w.writeHeader()
	got := w.String()
	for _, want := range []string{
		"Ident 3:0\n",
		"Manufacturer ETC\n",
		"Console Eos\n",
		"$$Format 3.20\n",
		"$$Title My Show\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in header:\n%s", want, got)
		}
	}
}
```

- [ ] **Step 2: Implement `writer.go` and `header.go`**

`writer.go`:

```go
package exporteos

import (
	"strings"
)

// WriterOptions configures the exporter.
type WriterOptions struct {
	Title         string
	FormatVersion string // default "3.20"
}

// writer is the in-memory buffer with helpers.
type writer struct {
	buf  strings.Builder
	opts WriterOptions
}

func newWriter(opts WriterOptions) *writer {
	if opts.FormatVersion == "" {
		opts.FormatVersion = "3.20"
	}
	return &writer{opts: opts}
}

func (w *writer) line(s string)    { w.buf.WriteString(s); w.buf.WriteByte('\n') }
func (w *writer) blank()           { w.buf.WriteByte('\n') }
func (w *writer) String() string   { return w.buf.String() }
func (w *writer) commentBanner(s string) {
	w.line("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
	w.line("! " + s)
}
```

`header.go`:

```go
package exporteos

func (w *writer) writeHeader() {
	w.line("Ident 3:0")
	w.line("Manufacturer ETC")
	w.line("Console Eos")
	w.line("$$Format " + w.opts.FormatVersion)
	w.line("$$Title " + w.opts.Title)
	w.line("Clear All")
	w.line("Set Channels 5000")
	w.blank()
}
```

- [ ] **Step 3: Run tests, confirm pass**

Run: `go test ./internal/services/export_eos -run TestWriter_Header -v`
Expected: PASS.

- [ ] **Step 4: Add personality + patch emission with tests**

`personality.go`:

```go
package exporteos

import "fmt"

// PersonalityIn is the input shape for one personality emission.
type PersonalityIn struct {
	ID         int
	Manuf      string
	Model      string
	Dcid       string
	Footprint  int
	Channels   []PersonalityChannelIn
}

type PersonalityChannelIn struct {
	ParamID   int
	Size      int
	Offset    int
	Offset16  int
	HomeValue int
	Snap      bool
}

func (w *writer) writePersonality(p PersonalityIn) {
	w.line(fmt.Sprintf("$Personality %d", p.ID))
	w.line(fmt.Sprintf("   $$Manuf %s", p.Manuf))
	w.line(fmt.Sprintf("   $$Model %s", p.Model))
	if p.Dcid != "" {
		w.line(fmt.Sprintf("   $$Dcid %s", p.Dcid))
	}
	w.line(fmt.Sprintf("   $$Footprint %d", p.Footprint))
	for _, c := range p.Channels {
		flags := ""
		if c.Snap { flags = " S" }
		if c.Size == 2 {
			w.line(fmt.Sprintf("   $$PersChan %5d %5d %5d %5d %5d%s",
				c.ParamID, c.Size, c.Offset, c.Offset16, c.HomeValue, flags))
		} else {
			w.line(fmt.Sprintf("   $$PersChan %5d %5d %5d %5d %5d%s",
				c.ParamID, c.Size, c.Offset, 0, c.HomeValue, flags))
		}
	}
}
```

`patch.go`:

```go
package exporteos

import "fmt"

// PatchEntryOut is one $Patch line.
type PatchEntryOut struct {
	Channel       int
	Address       string  // already normalized to EOS form
	PersonalityID int
	Label         string
}

func (w *writer) writePatch(entries []PatchEntryOut) {
	for _, e := range entries {
		w.line(fmt.Sprintf("$Patch %d %s %d", e.Channel, e.Address, e.PersonalityID))
		if e.Label != "" {
			w.line("   Text " + e.Label)
		}
	}
	w.blank()
}
```

Test:

```go
func TestWriter_PatchAndPersonality(t *testing.T) {
	w := newWriter(WriterOptions{Title: "T"})
	w.writePersonality(PersonalityIn{
		ID: 9001, Manuf: "Generic", Model: "Dimmer", Footprint: 1,
		Channels: []PersonalityChannelIn{{ParamID: 1, Size: 1, Offset: 1}},
	})
	w.writePatch([]PatchEntryOut{
		{Channel: 1, Address: "1", PersonalityID: 9001, Label: "Front"},
		{Channel: 2, Address: "2", PersonalityID: 9001},
	})
	got := w.String()
	for _, want := range []string{
		"$Personality 9001\n",
		"   $$Manuf Generic\n",
		"   $$PersChan",
		"$Patch 1 1 9001\n",
		"   Text Front\n",
		"$Patch 2 2 9001\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
}
```

- [ ] **Step 5: Run tests, commit**

```bash
git add internal/services/export_eos
git commit -m "feat(eos export): write header, ParamType, personality, and patch"
```

### Task 17: Writer — palettes, cues, groups

**Files:**
- Create: `internal/services/export_eos/palette.go`
- Create: `internal/services/export_eos/cue.go`
- Create: `internal/services/export_eos/group.go`
- Modify: `internal/services/export_eos/writer_test.go`

- [ ] **Step 1: Implement palette emission**

`palette.go`:

```go
package exporteos

import "fmt"

type PaletteOut struct {
	Kind        string // "ColorPalette" | "BeamPalette" | "FocusPalette" | "IntensPalette" | "Preset"
	Number      string
	Label       string
	UnicodeText *string
	ChanMoves   []ChanMoveOut
	ParamMoves  []ParamMoveOut
}

type ChanMoveOut struct {
	Channel int
	Value   int // 0..255
}

type ParamMoveOut struct {
	Channel int
	Values  []ParamValueOut
}

type ParamValueOut struct {
	ParamID int
	Value   int
}

func (w *writer) writePalette(p PaletteOut) {
	w.line(fmt.Sprintf("$%s %s", p.Kind, p.Number))
	if p.Label != "" {
		w.line("   Text " + p.Label)
	}
	if p.UnicodeText != nil {
		w.line("   $$UText " + encodeUText(*p.UnicodeText))
	}
	if len(p.ChanMoves) > 0 {
		w.line("   $$ChanMove " + formatChanMoves(p.ChanMoves))
	}
	for _, pm := range p.ParamMoves {
		w.line("   $$Param " + formatParamMove(pm))
	}
}

func formatChanMoves(moves []ChanMoveOut) string {
	parts := make([]string, len(moves))
	for i, m := range moves {
		parts[i] = fmt.Sprintf("%d@H%02X", m.Channel, m.Value&0xFF)
	}
	return joinSpaces(parts)
}

func formatParamMove(pm ParamMoveOut) string {
	parts := make([]string, 0, 1+len(pm.Values))
	parts = append(parts, fmt.Sprintf("%d", pm.Channel))
	for _, v := range pm.Values {
		parts = append(parts, fmt.Sprintf("%d@%d", v.ParamID, v.Value))
	}
	return joinSpaces(parts)
}

func joinSpaces(parts []string) string {
	if len(parts) == 0 { return "" }
	out := parts[0]
	for _, p := range parts[1:] { out += " " + p }
	return out
}

// encodeUText returns hex-encoded UTF-16-LE for s (one space-joined hex group per code unit).
func encodeUText(s string) string {
	u16 := utf16encode(s)
	parts := make([]string, len(u16))
	for i, c := range u16 {
		parts[i] = fmt.Sprintf("%02X%02X", byte(c&0xFF), byte((c>>8)&0xFF))
	}
	return joinSpaces(parts)
}

func utf16encode(s string) []uint16 {
	// Go has utf16.Encode but we want manual control to avoid a dep cycle in tests.
	// Implementation: import "unicode/utf16" and call utf16.Encode([]rune(s)).
	import_unicode_utf16()
	return nil // replaced below by importing the package and inlining
}
```

The above pseudo-code calls a `import_unicode_utf16` placeholder — replace it with the actual import. The real `palette.go` should `import "unicode/utf16"` at the top and the function body becomes:

```go
func utf16encode(s string) []uint16 {
	return utf16.Encode([]rune(s))
}
```

And remove the placeholder line.

- [ ] **Step 2: Implement cue emission**

`cue.go`:

```go
package exporteos

import "fmt"

type CueListOut struct {
	Number int
	Label  string
	Cues   []CueOut
}

type CueOut struct {
	Number      string
	Part        int
	Label       string
	UnicodeText *string
	UpFade      float64
	DownFade    float64
	Follow      *float64
	Hang        *float64
	Block       bool
	IntBlock    bool
	ChanMoves   []ChanMoveOut
	ParamMoves  []ParamMoveOut
}

func (w *writer) writeCueList(cl CueListOut) {
	w.line(fmt.Sprintf("$CueList %d", cl.Number))
	if cl.Label != "" {
		w.line("   Text " + cl.Label)
	}
	w.blank()
	for _, c := range cl.Cues {
		w.writeCue(cl.Number, c)
		w.blank()
	}
}

func (w *writer) writeCue(listNum int, c CueOut) {
	num := c.Number
	if c.Part > 0 {
		num = fmt.Sprintf("%s/%d", c.Number, c.Part)
	}
	w.line(fmt.Sprintf("Cue %s %d", num, listNum))
	if c.Label != "" {
		w.line("   Text " + c.Label)
	}
	if c.UnicodeText != nil {
		w.line("   $$UText " + encodeUText(*c.UnicodeText))
	}
	if c.UpFade > 0 {
		w.line(fmt.Sprintf("   Up %g", c.UpFade))
		w.line(fmt.Sprintf("   $$TimeUp %g 0 1 1", c.UpFade))
	}
	if c.DownFade > 0 {
		w.line(fmt.Sprintf("   Down %g", c.DownFade))
		w.line(fmt.Sprintf("   $$TimeDown %g 0 1 1", c.DownFade))
	}
	if c.Follow != nil {
		w.line(fmt.Sprintf("   $$Follow %g", *c.Follow))
	}
	if c.Hang != nil {
		w.line(fmt.Sprintf("   $$Hang %g", *c.Hang))
	}
	if c.Block { w.line("   $$Block") }
	if c.IntBlock { w.line("   $$IntBlock") }
	if len(c.ChanMoves) > 0 {
		w.line("   $$ChanMove " + formatChanMoves(c.ChanMoves))
	}
	for _, pm := range c.ParamMoves {
		w.line("   $$Param " + formatParamMove(pm))
	}
}
```

- [ ] **Step 3: Implement group emission**

`group.go`:

```go
package exporteos

import "fmt"

type GroupOut struct {
	Number      string
	Label       string
	UnicodeText *string
	Channels    []int
}

func (w *writer) writeGroup(g GroupOut) {
	w.line(fmt.Sprintf("$Group %s", g.Number))
	if g.Label != "" {
		w.line("   Text " + g.Label)
	}
	if g.UnicodeText != nil {
		w.line("   $$UText " + encodeUText(*g.UnicodeText))
	}
	for _, ch := range g.Channels {
		w.line(fmt.Sprintf("   %d", ch))
	}
}
```

- [ ] **Step 4: Add a writer round-trip unit test**

```go
func TestWriter_RoundtripsPaletteAndCue(t *testing.T) {
	w := newWriter(WriterOptions{Title: "X"})
	w.writePalette(PaletteOut{
		Kind: "ColorPalette", Number: "1", Label: "Red",
		ParamMoves: []ParamMoveOut{{Channel: 1, Values: []ParamValueOut{{ParamID: 12, Value: 255}}}},
	})
	w.writeCue(1, CueOut{
		Number: "1", Label: "Open", UpFade: 5, DownFade: 5,
		ChanMoves: []ChanMoveOut{{Channel: 1, Value: 0xFF}},
	})
	got := w.String()
	for _, want := range []string{
		"$ColorPalette 1\n",
		"   Text Red\n",
		"   $$Param 1 12@255\n",
		"Cue 1 1\n",
		"   Up 5\n",
		"   $$ChanMove 1@HFF\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
}
```

- [ ] **Step 5: Run, commit**

```bash
git add internal/services/export_eos
git commit -m "feat(eos export): write palettes, cue lists, cues, and groups"
```

### Task 18: Writer — sidecar emission and the public Service.Export

**Files:**
- Create: `internal/services/export_eos/sidecar_writer.go`
- Modify: `internal/services/export_eos/service.go`
- Modify: `internal/services/export_eos/writer_test.go`

- [ ] **Step 1: Implement `sidecar_writer.go`**

```go
package exporteos

import (
	"encoding/json"
	"fmt"

	importeos "github.com/bbernstein/lacylights-go/internal/services/import_eos"
)

// SidecarOut is the data we serialize at end-of-file.
type SidecarOut struct {
	Version       int
	LookBoards    []importeos.SidecarLookBoard
	FadeBehaviors []importeos.SidecarFadeBehavior
	SynthDefs     []importeos.SidecarSynthDef
}

func (w *writer) writeSidecar(sc SidecarOut) error {
	w.commentBanner("LacyLights round-trip metadata (ignored by ETC consoles)")
	w.line(fmt.Sprintf("$$ LACYLIGHTS:version %d", sc.Version))
	for _, lb := range sc.LookBoards {
		b, err := json.Marshal(lb)
		if err != nil { return err }
		w.line("$$ LACYLIGHTS:look_board " + string(b))
	}
	for _, fb := range sc.FadeBehaviors {
		b, err := json.Marshal(fb)
		if err != nil { return err }
		w.line("$$ LACYLIGHTS:fade_behavior " + string(b))
	}
	for _, sd := range sc.SynthDefs {
		b, err := json.Marshal(sd)
		if err != nil { return err }
		w.line("$$ LACYLIGHTS:synth_def " + string(b))
	}
	return nil
}
```

- [ ] **Step 2: Wire `Service.Export` in `service.go`**

```go
package exporteos

import (
	"context"
	"fmt"
	"io"

	"github.com/bbernstein/lacylights-go/internal/database/repositories"
	importeos "github.com/bbernstein/lacylights-go/internal/services/import_eos"
)

type Service struct {
	projectRepo   *repositories.ProjectRepository
	fixtureRepo   *repositories.FixtureRepository
	lookRepo      *repositories.LookRepository
	cueListRepo   *repositories.CueListRepository
	cueRepo       *repositories.CueRepository
	lookBoardRepo *repositories.LookBoardRepository
}

func NewServiceWithDeps(p *repositories.ProjectRepository, f *repositories.FixtureRepository,
	l *repositories.LookRepository, cl *repositories.CueListRepository,
	c *repositories.CueRepository, lb *repositories.LookBoardRepository) *Service {
	return &Service{p, f, l, cl, c, lb}
}

func (s *Service) Export(ctx context.Context, projectID string, w io.Writer) (*Result, error) {
	if s.projectRepo == nil {
		return nil, fmt.Errorf("export_eos: service not wired with repositories")
	}
	collector := &importeos.Collector{}
	bundle, err := s.loadBundle(ctx, projectID)
	if err != nil { return nil, err }

	wr := newWriter(WriterOptions{Title: bundle.ProjectName})
	wr.writeHeader()
	wr.commentBanner("Fixture Parameters")
	wr.writeParamTable(bundle.ParamTypes)
	wr.commentBanner("Fixture Personalities")
	for _, p := range bundle.Personalities {
		wr.writePersonality(p)
	}
	wr.commentBanner("Fixture Patch")
	wr.writePatch(bundle.Patch)
	wr.commentBanner("Palettes")
	for _, pal := range bundle.Palettes {
		wr.writePalette(pal)
	}
	wr.commentBanner("Cues")
	for _, cl := range bundle.CueLists {
		wr.writeCueList(cl)
	}
	wr.commentBanner("Groups")
	for _, g := range bundle.Groups {
		wr.writeGroup(g)
	}
	if err := wr.writeSidecar(bundle.Sidecar); err != nil {
		return nil, err
	}
	if _, err := w.Write([]byte(wr.String())); err != nil {
		return nil, err
	}
	return &Result{
		Content:        wr.String(),
		FilenameSuffix: ".asc",
		Warnings:       collector.All(),
	}, nil
}
```

`bundle` is an internal struct produced by `loadBundle`, which queries all the repos and translates the LacyLights model into the writer's input shapes. Implement `loadBundle` in a new `loader.go` file in the same package; it should:

1. Read the project (name, description).
2. Build a `[]ParamTypeOut` from the union of channel types referenced by any FixtureInstance — emit one row per unique `(paramID, longName)` pair (use the inverse of `param_table.mapParamTypeName`).
3. Build `[]PersonalityIn` — one per unique `FixtureDefinition`.
4. Sort patch entries by `EOS channel = ChannelOrder` and build `[]PatchEntryOut`.
5. Build palettes from cue lists named "Color Palettes" / "Beam Palettes" / "Focus Palettes" / "Intensity Palettes" / "Presets" — each cue's look becomes one palette.
6. Build remaining cue lists into `[]CueListOut`. For each cue, run the inverse of the tracker: emit full snapshots (every channel listed) since tracking was consumed at import time.
7. Build groups from `FixtureGroup` repo data.
8. Build sidecar from look boards, non-FADE channel fade behaviors, and the synthesized-definition list (look up `IsBuiltIn=false` defs that were created via the importer; they get a `SynthDef` entry).

Each section is straightforward repo iteration. Add tests for `loadBundle` in `service_test.go` that round-trip a small project (build it directly via repos, export, parse the output, assert structure).

- [ ] **Step 3: Add a determinism test**

```go
func TestExport_Deterministic(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()
	pid := buildSampleProject(t, deps) // helper that creates 3 fixtures, 1 cue list, 2 cues
	svc := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	var buf1, buf2 bytes.Buffer
	if _, err := svc.Export(context.Background(), pid, &buf1); err != nil { t.Fatal(err) }
	if _, err := svc.Export(context.Background(), pid, &buf2); err != nil { t.Fatal(err) }
	if buf1.String() != buf2.String() {
		t.Errorf("non-deterministic output:\n--- 1 ---\n%s\n--- 2 ---\n%s", buf1.String(), buf2.String())
	}
}
```

- [ ] **Step 4: Run all export_eos tests, confirm pass; commit**

```bash
git add internal/services/export_eos
git commit -m "feat(eos export): public Export() with sidecar and determinism guarantee"
```

### Task 19: Round-trip integration test

**Files:**
- Create: `internal/services/import_eos/roundtrip_test.go`

- [ ] **Step 1: Write the test**

```go
package importeos

import (
	"bytes"
	"context"
	"testing"

	exporteos "github.com/bbernstein/lacylights-go/internal/services/export_eos"
)

func TestRoundtrip_GoldenOTBPA(t *testing.T) {
	deps := newTestDeps(t)
	defer deps.close()

	// Import the real-world golden fixture.
	f := openFixture(t, "golden_otbpa.asc")
	defer f.Close()
	imp := NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	res, err := imp.Import(context.Background(), f, Options{NewProjectName: ptr("OTBPA Roundtrip")})
	if err != nil { t.Fatalf("import: %v", err) }
	if res.FixtureInstancesCount < 40 {
		t.Errorf("expected ~44 patch entries, got %d", res.FixtureInstancesCount)
	}
	codes := map[WarningCode]int{}
	for _, w := range res.Warnings { codes[w.Code]++ }
	if codes[WarnEffectSkipped] == 0 || codes[WarnPartitionSkipped] == 0 {
		t.Errorf("expected EFFECT/PARTITION warnings, got %v", codes)
	}

	// Export to ASCII.
	exp := exporteos.NewServiceWithDeps(deps.projectRepo, deps.fixtureRepo, deps.lookRepo, deps.cueListRepo, deps.cueRepo, deps.lookBoardRepo)
	var buf bytes.Buffer
	if _, err := exp.Export(context.Background(), res.ProjectID, &buf); err != nil {
		t.Fatalf("export: %v", err)
	}

	// Parse the output. Hard errors are fatal; warning count stable.
	show2, _, err := Parse(&buf)
	if err != nil { t.Fatalf("re-parse: %v", err) }
	if len(show2.Patch) != res.FixtureInstancesCount {
		t.Errorf("patch count after re-parse: got %d want %d", len(show2.Patch), res.FixtureInstancesCount)
	}
}
```

- [ ] **Step 2: Symlink/copy the real fixture into testdata**

```bash
cp "../../../docs/OTBPA DRESS TUES.asc" internal/services/import_eos/testdata/golden_otbpa.asc
```

- [ ] **Step 3: Run, fix any issues uncovered, commit**

```bash
go test ./internal/services/import_eos -run TestRoundtrip -v
```

If the parser hits an unknown directive or a panic, fix the smallest issue and re-run. Iterate until green. Each fix is its own commit with a `fix(eos): <what>` message.

```bash
git add internal/services/import_eos/testdata/golden_otbpa.asc internal/services/import_eos/roundtrip_test.go
git commit -m "test(eos): real-world golden OTBPA fixture round-trip"
```

### Task 20: GraphQL schema — types and mutations

**Files:**
- Modify: `internal/graphql/schema/schema.graphql`
- Run: `make generate`

Mirror the existing QLC+ pattern (sibling mutations + result types). After this task, the schema declares the surface; resolvers come in Task 21.

- [ ] **Step 1: Add types and mutations**

In `internal/graphql/schema/schema.graphql`, after the `# QLC+ TYPES` block, add:

```graphql
# =============================================================================
# EOS ASCII TYPES
# =============================================================================

enum EosWarningSeverity {
  INFO
  WARN
}

enum EosWarningCode {
  SYNTHESIZED_FIXTURE
  EFFECT_SKIPPED
  SUBMASTER_SKIPPED
  MAGIC_SHEET_SKIPPED
  PARTITION_SKIPPED
  ACTION_SKIPPED
  CURVE_SKIPPED
  UNKNOWN_DIRECTIVE
  FADE_BEHAVIOR_LOST
  UTEXT_DECODE
  SIDECAR_INVALID
  SIDECAR_UNRESOLVED
}

type EosWarningContextEntry {
  key: String!
  value: String!
}

type EosWarning {
  code: EosWarningCode!
  severity: EosWarningSeverity!
  message: String!
  context: [EosWarningContextEntry!]!
}

type EosImportResult {
  project: Project!
  fixtureDefinitionsCount: Int!
  fixtureInstancesCount: Int!
  looksCount: Int!
  cueListsCount: Int!
  cuesCount: Int!
  groupsCount: Int!
  warnings: [EosWarning!]!
  synthesizedDefinitionIds: [ID!]!
}

type EosExportResult {
  projectName: String!
  asciiContent: String!
  warnings: [EosWarning!]!
}

input EosImportOptionsInput {
  newProjectName: String
  groupId: ID
}
```

In the `Mutation` block, after the QLC+ mutations (around line 2568), add:

```graphql
  # ETC Eos ASCII Import/Export
  importProjectFromEos(
    asciiContent: String!
    originalFileName: String!
    options: EosImportOptionsInput
  ): EosImportResult!
  exportProjectToEos(
    projectId: ID!
  ): EosExportResult!
```

- [ ] **Step 2: Regenerate**

```bash
make generate
```

- [ ] **Step 3: Verify the build still compiles**

```bash
go build ./...
```

Expected: build fails with "resolver method not implemented" on the two new mutations (Task 21 fixes that).

- [ ] **Step 4: Commit the schema regen**

```bash
git add internal/graphql/schema/schema.graphql internal/graphql/generated
git commit -m "feat(graphql): add Eos ASCII import/export schema (mutations + types)"
```

### Task 21: GraphQL resolvers and main wiring

**Files:**
- Create: `internal/graphql/resolvers/eos_import_export.go`
- Modify: `internal/graphql/resolvers/schema.resolvers.go` (auto-generated; replace stubs)
- Modify: `internal/graphql/resolvers/resolver.go` (add fields for the two services)
- Modify: `cmd/server/main.go` (instantiate and wire the services)

- [ ] **Step 1: Add fields to the Resolver struct**

In `resolver.go`:

```go
type Resolver struct {
	// ... existing fields ...
	EosImportService *importeos.Service
	EosExportService *exporteos.Service
}
```

with the imports:

```go
import (
	importeos "github.com/bbernstein/lacylights-go/internal/services/import_eos"
	exporteos "github.com/bbernstein/lacylights-go/internal/services/export_eos"
)
```

- [ ] **Step 2: Implement resolver methods**

Create `eos_import_export.go`:

```go
package resolvers

import (
	"bytes"
	"context"
	"strings"

	"github.com/bbernstein/lacylights-go/internal/graphql/generated"
	importeos "github.com/bbernstein/lacylights-go/internal/services/import_eos"
)

// ImportProjectFromEos implements MutationResolver.
func (r *mutationResolver) ImportProjectFromEos(
	ctx context.Context, asciiContent string, originalFileName string, opts *generated.EosImportOptionsInput,
) (*generated.EosImportResult, error) {
	importOpts := importeos.Options{}
	if opts != nil {
		importOpts.NewProjectName = opts.NewProjectName
		importOpts.GroupID = opts.GroupID
	}
	if importOpts.NewProjectName == nil {
		// Default to a name derived from the file.
		fallback := strings.TrimSuffix(originalFileName, ".asc")
		fallback = strings.TrimSuffix(fallback, ".lss")
		importOpts.NewProjectName = &fallback
	}
	res, err := r.Resolver.EosImportService.Import(ctx, strings.NewReader(asciiContent), importOpts)
	if err != nil {
		return nil, err
	}
	project, err := r.Resolver.ProjectRepo.GetByID(ctx, res.ProjectID)
	if err != nil {
		return nil, err
	}
	return &generated.EosImportResult{
		Project:                  project,
		FixtureDefinitionsCount:  res.FixtureDefinitionsCount,
		FixtureInstancesCount:    res.FixtureInstancesCount,
		LooksCount:               res.LooksCount,
		CueListsCount:            res.CueListsCount,
		CuesCount:                res.CuesCount,
		GroupsCount:              res.GroupsCount,
		Warnings:                 toGraphQLWarnings(res.Warnings),
		SynthesizedDefinitionIDs: res.SynthesizedDefinitionIDs,
	}, nil
}

// ExportProjectToEos implements MutationResolver.
func (r *mutationResolver) ExportProjectToEos(
	ctx context.Context, projectID string,
) (*generated.EosExportResult, error) {
	var buf bytes.Buffer
	res, err := r.Resolver.EosExportService.Export(ctx, projectID, &buf)
	if err != nil { return nil, err }
	project, err := r.Resolver.ProjectRepo.GetByID(ctx, projectID)
	if err != nil { return nil, err }
	return &generated.EosExportResult{
		ProjectName:  project.Name,
		AsciiContent: res.Content,
		Warnings:     toGraphQLWarnings(res.Warnings),
	}, nil
}

func toGraphQLWarnings(in []importeos.Warning) []*generated.EosWarning {
	out := make([]*generated.EosWarning, 0, len(in))
	for _, w := range in {
		ctxEntries := make([]*generated.EosWarningContextEntry, 0, len(w.Context))
		// Sort keys for deterministic output.
		keys := sortedKeys(w.Context)
		for _, k := range keys {
			ctxEntries = append(ctxEntries, &generated.EosWarningContextEntry{Key: k, Value: w.Context[k]})
		}
		out = append(out, &generated.EosWarning{
			Code:     generated.EosWarningCode(w.Code),
			Severity: generated.EosWarningSeverity(w.Severity),
			Message:  w.Message,
			Context:  ctxEntries,
		})
	}
	return out
}

func sortedKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m { keys = append(keys, k) }
	sortStrings(keys)
	return keys
}

func sortStrings(s []string) { /* import "sort"; sort.Strings(s) */ }
```

Replace the placeholder `sortStrings` with `sort.Strings(s)` and add the `"sort"` import.

- [ ] **Step 3: Replace the auto-generated stubs in `schema.resolvers.go`**

`make generate` produced stubs like:

```go
func (r *mutationResolver) ImportProjectFromEos(ctx context.Context, asciiContent string, originalFileName string, options *generated.EosImportOptionsInput) (*generated.EosImportResult, error) {
	panic(fmt.Errorf("not implemented: ImportProjectFromEos - importProjectFromEos"))
}
```

Delete those stubs (they live in `schema.resolvers.go`); the implementations in `eos_import_export.go` take their place.

- [ ] **Step 4: Wire the services in `cmd/server/main.go`**

Find where the existing import/export services are constructed; add alongside:

```go
eosImport := importeos.NewServiceWithDeps(projectRepo, fixtureRepo, lookRepo, cueListRepo, cueRepo, lookBoardRepo)
eosExport := exporteos.NewServiceWithDeps(projectRepo, fixtureRepo, lookRepo, cueListRepo, cueRepo, lookBoardRepo)
```

and assign to `resolver.EosImportService = eosImport`, `resolver.EosExportService = eosExport`.

- [ ] **Step 5: Build and run tests**

```bash
go build ./...
go test ./internal/graphql/... ./internal/services/import_eos/... ./internal/services/export_eos/...
```

Expected: PASS, build clean.

- [ ] **Step 6: Commit**

```bash
git add internal/graphql/resolvers/eos_import_export.go internal/graphql/resolvers/schema.resolvers.go internal/graphql/resolvers/resolver.go cmd/server/main.go
git commit -m "feat(eos): GraphQL resolvers and main wiring for Eos import/export"
```

### Task 22: End-to-end resolver test

**Files:**
- Create: `internal/graphql/resolvers/eos_import_export_test.go`

- [ ] **Step 1: Write a test that calls the resolver directly**

```go
package resolvers

import (
	"context"
	"os"
	"testing"
)

func TestResolver_ImportThenExportEos(t *testing.T) {
	r := newTestResolver(t) // builds DB + repos + services + Resolver
	defer r.close()

	asciiBytes, err := os.ReadFile("../../../docs/OTBPA DRESS TUES.asc")
	if err != nil { t.Skipf("golden fixture not available: %v", err) }

	mr := &mutationResolver{Resolver: r.resolver}
	imported, err := mr.ImportProjectFromEos(context.Background(), string(asciiBytes), "OTBPA DRESS TUES.asc", nil)
	if err != nil { t.Fatalf("import: %v", err) }
	if imported.FixtureInstancesCount < 40 {
		t.Errorf("instances: got %d", imported.FixtureInstancesCount)
	}

	exported, err := mr.ExportProjectToEos(context.Background(), imported.Project.ID)
	if err != nil { t.Fatalf("export: %v", err) }
	if !strings.Contains(exported.AsciiContent, "Ident 3:0") {
		t.Errorf("output missing Ident header")
	}
}
```

`newTestResolver` boots an in-memory SQLite, instantiates all repos, both services, and a `Resolver` referencing them. Mirror the pattern from existing resolver tests.

- [ ] **Step 2: Run, commit**

```bash
go test ./internal/graphql/resolvers -run TestResolver_ImportThenExport -v
git add internal/graphql/resolvers/eos_import_export_test.go
git commit -m "test(eos): end-to-end resolver import-then-export round-trip"
```

### Task 23: Push the backend branch

- [ ] **Step 1: Push and open a PR**

```bash
git push -u origin feature/eos-ascii-import-export
gh pr create --title "Add ETC Eos ASCII import/export" --body "$(cat <<'EOF'
## Summary
- Adds `internal/services/import_eos` (parser + mapper) and `internal/services/export_eos` (writer)
- New GraphQL mutations `importProjectFromEos` / `exportProjectToEos` (mirrors the QLC+ pattern)
- LacyLights-specific concepts (Look Boards, per-channel fade behavior, synthesized fixture defs) round-trip via `\$\$ LACYLIGHTS:` comment-sidecar
- Real-world golden fixture (`docs/OTBPA DRESS TUES.asc`) imports and round-trips in tests

## Test plan
- [ ] `go test ./...` passes locally
- [ ] `make lint` is clean
- [ ] Round-trip test on the OTBPA golden fixture is green
EOF
)"
```

This concludes Phase 1. **Do not merge yet** — the frontend (Phase 2) and MCP (Phase 3) need this branch's mutations available, and they should land in the same release. Phase 4 (cross-repo tests) goes in last.

---

## Phase 2 — Frontend (`lacylights-fe`)

> **Working directory:** `~/src/lacylights/lacylights-fe`. Branch `feature/eos-ascii-import-export` off `main`.
>
> **Prerequisite:** the backend's GraphQL schema with the new types/mutations must be merged or available locally. Point `NEXT_PUBLIC_GRAPHQL_URL` at a backend running off the Phase 1 branch and run `npm run codegen` so the new types appear in `src/generated/graphql.ts`.

### Task 24: Add GraphQL operations and regenerate types

**Files:**
- Modify: `src/graphql/projects.ts`
- Run: `npm run codegen`

- [ ] **Step 1: Add the two operations**

In `src/graphql/projects.ts`, append:

```typescript
import { gql } from '@apollo/client';

export const IMPORT_PROJECT_FROM_EOS = gql`
  mutation ImportProjectFromEos(
    $asciiContent: String!
    $originalFileName: String!
    $options: EosImportOptionsInput
  ) {
    importProjectFromEos(
      asciiContent: $asciiContent
      originalFileName: $originalFileName
      options: $options
    ) {
      project {
        id
        name
      }
      fixtureDefinitionsCount
      fixtureInstancesCount
      looksCount
      cueListsCount
      cuesCount
      groupsCount
      warnings {
        code
        severity
        message
        context {
          key
          value
        }
      }
      synthesizedDefinitionIds
    }
  }
`;

export const EXPORT_PROJECT_TO_EOS = gql`
  mutation ExportProjectToEos($projectId: ID!) {
    exportProjectToEos(projectId: $projectId) {
      projectName
      asciiContent
      warnings {
        code
        severity
        message
        context {
          key
          value
        }
      }
    }
  }
`;
```

- [ ] **Step 2: Regenerate types**

```bash
npm run codegen
```

- [ ] **Step 3: Type-check**

```bash
npm run type-check
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/graphql/projects.ts src/generated
git commit -m "feat(eos): add GraphQL ops for Eos import/export"
```

### Task 25: `EosImportWarningsList` component

**Files:**
- Create: `src/components/EosImportWarningsList.tsx`
- Create: `src/components/__tests__/EosImportWarningsList.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { render, screen } from '@testing-library/react';
import EosImportWarningsList from '../EosImportWarningsList';
import { EosWarning, EosWarningCode, EosWarningSeverity } from '@/generated/graphql';

const w = (code: EosWarningCode, message: string): EosWarning => ({
  code, severity: EosWarningSeverity.Info, message, context: [],
});

test('groups warnings by code with counts', () => {
  render(<EosImportWarningsList warnings={[
    w(EosWarningCode.EffectSkipped, 'effect 1'),
    w(EosWarningCode.EffectSkipped, 'effect 2'),
    w(EosWarningCode.SynthesizedFixture, 'synth'),
  ]} />);
  expect(screen.getByText(/Effects skipped \(2\)/)).toBeInTheDocument();
  expect(screen.getByText(/Synthesized fixtures \(1\)/)).toBeInTheDocument();
});

test('renders nothing when warnings is empty', () => {
  const { container } = render(<EosImportWarningsList warnings={[]} />);
  expect(container).toBeEmptyDOMElement();
});
```

- [ ] **Step 2: Confirm failure, then implement**

```tsx
'use client';

import { EosWarning, EosWarningCode } from '@/generated/graphql';

interface Props {
  warnings: EosWarning[];
}

const FRIENDLY_NAMES: Record<EosWarningCode, string> = {
  SYNTHESIZED_FIXTURE: 'Synthesized fixtures',
  EFFECT_SKIPPED: 'Effects skipped',
  SUBMASTER_SKIPPED: 'Submasters skipped',
  MAGIC_SHEET_SKIPPED: 'Magic sheets skipped',
  PARTITION_SKIPPED: 'Partitions skipped',
  ACTION_SKIPPED: 'Action triggers skipped',
  CURVE_SKIPPED: 'Curves skipped',
  UNKNOWN_DIRECTIVE: 'Unknown directives',
  FADE_BEHAVIOR_LOST: 'Fade behavior lost',
  UTEXT_DECODE: 'Unicode label decode failures',
  SIDECAR_INVALID: 'Sidecar parse issues',
  SIDECAR_UNRESOLVED: 'Sidecar references unresolved',
};

export default function EosImportWarningsList({ warnings }: Props) {
  if (warnings.length === 0) return null;
  const groups: Record<string, EosWarning[]> = {};
  warnings.forEach((w) => {
    (groups[w.code] ??= []).push(w);
  });
  return (
    <div className="rounded border border-amber-200 bg-amber-50 p-4">
      <h3 className="mb-2 text-sm font-semibold text-amber-900">Import notices</h3>
      <ul className="space-y-3">
        {Object.entries(groups).map(([code, ws]) => (
          <li key={code}>
            <details>
              <summary className="cursor-pointer font-medium text-amber-800">
                {FRIENDLY_NAMES[code as EosWarningCode] ?? code} ({ws.length})
              </summary>
              <ul className="mt-1 list-disc space-y-1 pl-5 text-xs text-amber-700">
                {ws.slice(0, 50).map((w, i) => (
                  <li key={i}>{w.message}</li>
                ))}
                {ws.length > 50 && <li>… and {ws.length - 50} more</li>}
              </ul>
            </details>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

- [ ] **Step 3: Run tests, commit**

```bash
npm test -- EosImportWarningsList
git add src/components/EosImportWarningsList.tsx src/components/__tests__/EosImportWarningsList.test.tsx
git commit -m "feat(eos fe): EosImportWarningsList groups warnings by code"
```

### Task 26: Extend `ImportExportButtons` with Eos format

**Files:**
- Modify: `src/components/ImportExportButtons.tsx`
- Modify: `src/components/__tests__/ImportExportButtons.test.tsx`

- [ ] **Step 1: Update the format unions**

In `ImportExportButtons.tsx`, change:

```typescript
type ExportFormat = 'lacylights' | 'qlcplus' | 'eos';
type ImportFormat = 'auto' | 'lacylights' | 'qlcplus' | 'eos';
```

- [ ] **Step 2: Wire in the new mutations and state**

Add at the top:

```typescript
import { IMPORT_PROJECT_FROM_EOS, EXPORT_PROJECT_TO_EOS } from '@/graphql/projects';
import EosImportWarningsList from './EosImportWarningsList';
import type { EosWarning } from '@/generated/graphql';
```

In the component body, alongside the existing mutations:

```typescript
const [eosWarnings, setEosWarnings] = useState<EosWarning[] | null>(null);

const [importProjectFromEos] = useMutation(IMPORT_PROJECT_FROM_EOS, {
  onError: (error) => {
    onError?.(`Failed to import project: ${error.message}`);
  },
  onCompleted: (data) => {
    if (data?.importProjectFromEos?.project?.id) {
      onImportComplete?.(data.importProjectFromEos.project.id);
      setEosWarnings(data.importProjectFromEos.warnings ?? []);
    }
  },
});

const [exportProjectToEos] = useMutation(EXPORT_PROJECT_TO_EOS, {
  onError: (error) => onError?.(`Failed to export project: ${error.message}`),
});
```

- [ ] **Step 3: Extend `handleImport`**

In the format-detection block:

```typescript
if (format === 'eos' || file.name.endsWith('.asc')) {
  detectedFormat = 'eos';
} else if (format === 'qlcplus' || file.name.endsWith('.qxw')) {
  detectedFormat = 'qlcplus';
} else if (format === 'lacylights' || file.name.endsWith('.json')) {
  detectedFormat = 'lacylights';
} else {
  onError?.('Unable to determine file format. Supported: .asc (Eos), .qxw (QLC+), .json (LacyLights).');
  setIsImporting(false);
  return;
}
```

After the QLC+ branch:

```typescript
if (detectedFormat === 'eos') {
  await importProjectFromEos({
    variables: {
      asciiContent: content,
      originalFileName: file.name,
      options: { newProjectName: file.name.replace(/\.asc$/i, '') },
    },
  });
}
```

Update the `accept` strings:

```typescript
if (format === 'eos') input.accept = '.asc';
else if (format === 'qlcplus') input.accept = '.qxw';
else if (format === 'lacylights') input.accept = '.json';
else input.accept = '.asc,.qxw,.json';
```

- [ ] **Step 4: Extend `handleExport`**

After the QLC+ branch:

```typescript
if (format === 'eos') {
  const result = await exportProjectToEos({ variables: { projectId } });
  if (result.data?.exportProjectToEos) {
    const r = result.data.exportProjectToEos;
    downloadFile(r.asciiContent, `${sanitizeFilename(r.projectName)}.asc`);
    setEosWarnings(r.warnings ?? []);
  }
  return;
}
```

Update the `downloadFile` MIME-type fallback so `.asc` content gets `text/plain`:

```typescript
const blob = new Blob([content], {
  type: filename.endsWith('.json') ? 'application/json'
      : filename.endsWith('.asc') ? 'text/plain'
      : 'application/xml'
});
```

- [ ] **Step 5: Add the format buttons in the dropdown UI**

Search for the existing "QLC+ (.qxw)" entry in the import/export dropdowns and add an analogous "ETC Eos (.asc)" entry just below it. Match the existing visual styling.

- [ ] **Step 6: Render warnings panel**

Below the buttons (within the component's returned JSX), conditionally render:

```tsx
{eosWarnings && eosWarnings.length > 0 && (
  <div className="mt-3">
    <EosImportWarningsList warnings={eosWarnings} />
    <button
      onClick={() => setEosWarnings(null)}
      className="mt-2 text-xs text-gray-500 underline"
    >
      Dismiss
    </button>
  </div>
)}
```

- [ ] **Step 7: Add tests for the format selection**

In `ImportExportButtons.test.tsx`:

```typescript
import { MockedProvider } from '@apollo/client/testing';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import ImportExportButtons from '../ImportExportButtons';
import { IMPORT_PROJECT_FROM_EOS } from '@/graphql/projects';

test('imports an Eos .asc file via auto-detection', async () => {
  const file = new File(['Ident 3:0\n'], 'show.asc', { type: 'text/plain' });
  const importMock = {
    request: {
      query: IMPORT_PROJECT_FROM_EOS,
      variables: {
        asciiContent: 'Ident 3:0\n',
        originalFileName: 'show.asc',
        options: { newProjectName: 'show' },
      },
    },
    result: {
      data: {
        importProjectFromEos: {
          project: { id: 'p1', name: 'show' },
          fixtureDefinitionsCount: 0,
          fixtureInstancesCount: 0,
          looksCount: 0,
          cueListsCount: 0,
          cuesCount: 0,
          groupsCount: 0,
          warnings: [],
          synthesizedDefinitionIds: [],
        },
      },
    },
  };
  const onImportComplete = jest.fn();
  render(
    <MockedProvider mocks={[importMock]} addTypename={false}>
      <ImportExportButtons onImportComplete={onImportComplete} />
    </MockedProvider>
  );

  // Open import menu, choose "ETC Eos (.asc)"
  fireEvent.click(screen.getByRole('button', { name: /import/i }));
  // The exact button label depends on existing UX; use the role/label that's added in Step 5.
  fireEvent.click(screen.getByText(/ETC Eos/));

  // Simulate file picker
  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  Object.defineProperty(input, 'files', { value: [file] });
  fireEvent.change(input);

  await waitFor(() => expect(onImportComplete).toHaveBeenCalledWith('p1'));
});
```

- [ ] **Step 8: Run tests + lint + type-check**

```bash
npm run check
npm test -- ImportExportButtons EosImportWarningsList
```

- [ ] **Step 9: Commit**

```bash
git add src/components/ImportExportButtons.tsx src/components/__tests__/ImportExportButtons.test.tsx
git commit -m "feat(eos fe): wire Eos ASCII import/export into ImportExportButtons"
```

### Task 27: E2E happy-path Playwright test (optional but recommended)

**Files:**
- Create: `e2e/eos-import-export.spec.ts`

- [ ] **Step 1: Add a Playwright test that imports the golden fixture**

```typescript
import { test, expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { resolve } from 'path';

test('imports an Eos ASCII showfile', async ({ page }) => {
  await page.goto('/');
  const filePath = resolve(__dirname, '../../docs/OTBPA DRESS TUES.asc');
  // The button label should match what was added in Task 26 step 5.
  await page.getByRole('button', { name: /import/i }).click();
  await page.getByText(/ETC Eos/).click();
  const fileChooserPromise = page.waitForEvent('filechooser');
  const fileChooser = await fileChooserPromise;
  await fileChooser.setFiles(filePath);
  await expect(page.getByText(/OTBPA DRESS TUES/)).toBeVisible({ timeout: 30_000 });
});
```

- [ ] **Step 2: Run the E2E suite locally**

```bash
npm run test:e2e -- eos-import-export
```

- [ ] **Step 3: Commit**

```bash
git add e2e/eos-import-export.spec.ts
git commit -m "test(eos fe): Playwright happy-path import test"
```

### Task 28: Push and open frontend PR

- [ ] **Step 1: Push and open a PR**

```bash
git push -u origin feature/eos-ascii-import-export
gh pr create --title "Add Eos ASCII import/export to the web UI" --body "$(cat <<'EOF'
## Summary
- Adds Eos ASCII (.asc) format option to import/export menus
- New EosImportWarningsList component groups warnings by code
- Auto-detects .asc, .qxw, .json by extension
EOF
)"
```

---

## Phase 3 — MCP (`lacylights-mcp`)

> **Working directory:** `~/src/lacylights/lacylights-mcp`. Branch `feature/eos-ascii-import-export`.
>
> **Prerequisite:** Phase 1 backend branch is reachable (set the MCP's GraphQL endpoint at the running backend) and `npm run codegen` regenerates types with the new mutations.

### Task 29: Add GraphQL operations and regenerate types

**Files:**
- Create: `src/graphql/eos.graphql`
- Modify: `codegen.yml` (only if it doesn't already pick up `src/graphql/**/*.graphql`)
- Run: `npm run codegen`

- [ ] **Step 1: Create `src/graphql/eos.graphql`**

```graphql
mutation ImportProjectFromEos(
  $asciiContent: String!
  $originalFileName: String!
  $options: EosImportOptionsInput
) {
  importProjectFromEos(
    asciiContent: $asciiContent
    originalFileName: $originalFileName
    options: $options
  ) {
    project { id name }
    fixtureDefinitionsCount
    fixtureInstancesCount
    looksCount
    cueListsCount
    cuesCount
    groupsCount
    warnings {
      code severity message
      context { key value }
    }
    synthesizedDefinitionIds
  }
}

mutation ExportProjectToEos($projectId: ID!) {
  exportProjectToEos(projectId: $projectId) {
    projectName
    asciiContent
    warnings {
      code severity message
      context { key value }
    }
  }
}
```

- [ ] **Step 2: Regenerate**

```bash
npm run codegen
```

- [ ] **Step 3: Commit**

```bash
git add src/graphql/eos.graphql src/generated
git commit -m "feat(eos mcp): add GraphQL ops for Eos import/export"
```

### Task 30: MCP tools — `import_eos_ascii` and `export_eos_ascii`

**Files:**
- Create: `src/tools/import-export-tools.ts`
- Create: `src/tools/__tests__/import-export-tools.test.ts`
- Modify: `src/index.ts`

- [ ] **Step 1: Write the failing tool tests**

`src/tools/__tests__/import-export-tools.test.ts`:

```typescript
import { ImportExportTools } from '../import-export-tools';
import type { GraphQLClient } from '../../services/graphql-client-simple';

describe('import_eos_ascii', () => {
  it('forwards content and returns warnings', async () => {
    const client = {
      mutate: jest.fn().mockResolvedValue({
        importProjectFromEos: {
          project: { id: 'p1', name: 'X' },
          fixtureInstancesCount: 5,
          fixtureDefinitionsCount: 2,
          looksCount: 3,
          cueListsCount: 1,
          cuesCount: 3,
          groupsCount: 0,
          warnings: [{ code: 'EFFECT_SKIPPED', severity: 'INFO', message: 'eff', context: [] }],
          synthesizedDefinitionIds: [],
        },
      }),
    } as unknown as GraphQLClient;
    const tools = new ImportExportTools(client);
    const result = await tools.importEosAscii({
      asciiContent: 'Ident 3:0\n', originalFileName: 'show.asc',
    });
    expect(result.fixtureInstancesCount).toBe(5);
    expect(result.warnings[0].code).toBe('EFFECT_SKIPPED');
  });
});
```

- [ ] **Step 2: Implement `import-export-tools.ts`**

```typescript
import { GraphQLClient } from '../services/graphql-client-simple';
import {
  ImportProjectFromEosDocument,
  ExportProjectToEosDocument,
  type ImportProjectFromEosMutation,
  type ImportProjectFromEosMutationVariables,
  type ExportProjectToEosMutation,
  type ExportProjectToEosMutationVariables,
} from '../generated/graphql';

export interface ImportEosAsciiArgs {
  asciiContent: string;
  originalFileName: string;
  newProjectName?: string;
  groupId?: string;
}

export interface ExportEosAsciiArgs {
  projectId: string;
}

export class ImportExportTools {
  constructor(private client: GraphQLClient) {}

  async importEosAscii(args: ImportEosAsciiArgs) {
    const variables: ImportProjectFromEosMutationVariables = {
      asciiContent: args.asciiContent,
      originalFileName: args.originalFileName,
      options: {
        newProjectName: args.newProjectName,
        groupId: args.groupId,
      },
    };
    const data = await this.client.mutate<ImportProjectFromEosMutation>(
      ImportProjectFromEosDocument, variables,
    );
    return data.importProjectFromEos;
  }

  async exportEosAscii(args: ExportEosAsciiArgs) {
    const variables: ExportProjectToEosMutationVariables = {
      projectId: args.projectId,
    };
    const data = await this.client.mutate<ExportProjectToEosMutation>(
      ExportProjectToEosDocument, variables,
    );
    return data.exportProjectToEos;
  }
}

export const importEosAsciiToolDefinition = {
  name: 'import_eos_ascii',
  description: 'Import an ETC Eos ASCII (.asc) showfile into a new LacyLights project. Returns import statistics and structured warnings (e.g. effects skipped, fixtures synthesized).',
  inputSchema: {
    type: 'object',
    properties: {
      asciiContent: { type: 'string', description: 'Full text content of the .asc file.' },
      originalFileName: { type: 'string', description: 'Original filename (used as fallback project name).' },
      newProjectName: { type: 'string', description: 'Optional explicit project name.' },
      groupId: { type: 'string', description: 'Optional owner group ID.' },
    },
    required: ['asciiContent', 'originalFileName'],
  },
} as const;

export const exportEosAsciiToolDefinition = {
  name: 'export_eos_ascii',
  description: 'Export a LacyLights project as ETC Eos ASCII (.asc). Returns the file content and any export warnings.',
  inputSchema: {
    type: 'object',
    properties: {
      projectId: { type: 'string' },
    },
    required: ['projectId'],
  },
} as const;
```

- [ ] **Step 3: Register the tools in `src/index.ts`**

Find the pattern used for existing tools (e.g. `cue-tools.ts`, `project-tools.ts`) and follow it: import the class + tool definitions, instantiate the class, register the tools and route their handlers to the matching method.

- [ ] **Step 4: Run tests, lint**

```bash
npm test -- import-export-tools
npm run check
```

- [ ] **Step 5: Commit**

```bash
git add src/tools/import-export-tools.ts src/tools/__tests__/import-export-tools.test.ts src/index.ts
git commit -m "feat(eos mcp): import_eos_ascii / export_eos_ascii MCP tools"
```

### Task 31: Push and open MCP PR

- [ ] **Step 1: Push and open a PR**

```bash
git push -u origin feature/eos-ascii-import-export
gh pr create --title "Add Eos ASCII import/export MCP tools" --body "..."
```

---

## Phase 4 — Cross-repo integration tests (`lacylights-test`)

> **Working directory:** `~/src/lacylights/lacylights-test`. Branch `feature/eos-ascii-import-export`.
>
> The test suite here exercises the running backend; it requires Phase 1 to be merged or running locally. Read `lacylights-test/docs/TESTING_PLAN.md` first; mirror existing integration-test patterns in `integration/` and `crud.test`.

### Task 32: GraphQL contract test — Eos import populates DB

**Files:**
- Create: `integration/eos_import_test.go`

- [ ] **Step 1: Write a test that POSTs the golden fixture to the running backend and asserts state**

```go
package integration

import (
	"context"
	"os"
	"testing"
)

func TestEosImport_PopulatesProject(t *testing.T) {
	cli := newGraphQLClient(t) // helper used by other integration tests

	asciiBytes, err := os.ReadFile("../../docs/OTBPA DRESS TUES.asc")
	if err != nil { t.Fatalf("fixture: %v", err) }

	var resp struct {
		ImportProjectFromEos struct {
			Project struct{ ID, Name string }
			FixtureInstancesCount int
			Warnings              []struct{ Code string }
		}
	}
	err = cli.Mutate(context.Background(), `mutation Import($c:String!, $f:String!) {
		importProjectFromEos(asciiContent:$c, originalFileName:$f) {
			project { id name }
			fixtureInstancesCount
			warnings { code }
		}
	}`, map[string]any{"c": string(asciiBytes), "f": "OTBPA DRESS TUES.asc"}, &resp)
	if err != nil { t.Fatal(err) }

	if resp.ImportProjectFromEos.FixtureInstancesCount < 40 {
		t.Errorf("instances: got %d", resp.ImportProjectFromEos.FixtureInstancesCount)
	}

	// Verify warnings include EFFECT_SKIPPED
	hasEffect := false
	for _, w := range resp.ImportProjectFromEos.Warnings {
		if w.Code == "EFFECT_SKIPPED" { hasEffect = true }
	}
	if !hasEffect { t.Error("expected EFFECT_SKIPPED warning") }
}
```

- [ ] **Step 2: Run the integration suite**

```bash
make test-integration
```

- [ ] **Step 3: Commit**

```bash
git add integration/eos_import_test.go
git commit -m "test(integration): Eos ASCII import populates project state"
```

### Task 33: Round-trip contract test — native JSON → Eos export → Eos import

**Files:**
- Create: `integration/eos_roundtrip_test.go`

- [ ] **Step 1: Write the test**

```go
func TestEosRoundtrip_PreservesPatch(t *testing.T) {
	cli := newGraphQLClient(t)
	// 1. Create a small project via existing GraphQL.
	pid := createSampleProject(t, cli) // helper

	// 2. Export to Eos.
	var exp struct {
		ExportProjectToEos struct{ AsciiContent string }
	}
	if err := cli.Mutate(context.Background(),
		`mutation E($p:ID!) { exportProjectToEos(projectId:$p) { asciiContent } }`,
		map[string]any{"p": pid}, &exp); err != nil {
		t.Fatal(err)
	}

	// 3. Import the result into a fresh project.
	var imp struct {
		ImportProjectFromEos struct {
			Project               struct{ ID string }
			FixtureInstancesCount int
		}
	}
	if err := cli.Mutate(context.Background(),
		`mutation I($c:String!) {
			importProjectFromEos(asciiContent:$c, originalFileName:"rt.asc") {
				project { id }
				fixtureInstancesCount
			}
		}`,
		map[string]any{"c": exp.ExportProjectToEos.AsciiContent}, &imp); err != nil {
		t.Fatal(err)
	}

	// 4. Compare patch counts.
	originalCount := countFixturesInProject(t, cli, pid)
	if imp.ImportProjectFromEos.FixtureInstancesCount != originalCount {
		t.Errorf("round-trip patch count: got %d, want %d",
			imp.ImportProjectFromEos.FixtureInstancesCount, originalCount)
	}
}
```

- [ ] **Step 2: Run, commit, push**

```bash
make test-integration
git add integration/eos_roundtrip_test.go
git commit -m "test(integration): Eos export→import round-trip preserves patch"
git push -u origin feature/eos-ascii-import-export
```

---

## Phase 5 — Documentation

> Branch on each repo: `feature/eos-ascii-import-export` (or a docs-only branch if the code branches have already merged).

### Task 34: Per-repo CLAUDE.md updates

**Files:**
- Modify: `lacylights-go/CLAUDE.md`
- Modify: `lacylights-fe/CLAUDE.md`
- Modify: `lacylights-mcp/CLAUDE.md`

- [ ] **Step 1: In `lacylights-go/CLAUDE.md`, append a new "Eos ASCII import/export" section**

```markdown
### Eos ASCII Import/Export
- Parser/mapper: `internal/services/import_eos/`
- Writer: `internal/services/export_eos/`
- GraphQL surface: `importProjectFromEos`, `exportProjectToEos` mutations
- Real-world test fixture: `../docs/OTBPA DRESS TUES.asc`
- Lossy LacyLights→ASCII concepts (Look Boards, fade behaviors, synthesized defs)
  round-trip via `$$ LACYLIGHTS:` comment-sidecar block at end-of-file.
- Effects, partitions, magic sheets, action triggers, curves: skipped on import
  with structured warnings.
```

- [ ] **Step 2: In `lacylights-fe/CLAUDE.md`**

```markdown
### Eos ASCII Import/Export
- UI: `ImportExportButtons.tsx` exposes "ETC Eos (.asc)" alongside QLC+ and native JSON
- Auto-detection by extension; explicit format selection in the dropdown
- Warnings rendered via `EosImportWarningsList.tsx`
```

- [ ] **Step 3: In `lacylights-mcp/CLAUDE.md`**

```markdown
### Eos ASCII Import/Export Tools
- `import_eos_ascii(asciiContent, originalFileName, newProjectName?, groupId?)`
- `export_eos_ascii(projectId)`
- Both wrap GraphQL mutations and surface structured warnings to the agent.
```

- [ ] **Step 4: Commit each in its own repo**

```bash
# in each repo
git add CLAUDE.md
git commit -m "docs(eos): document Eos ASCII import/export"
```

### Task 35: User-facing format documentation

**Files:**
- Create: `docs/IMPORT_EXPORT_FORMATS.md` (in the top-level `lacylights/` aggregator dir)

- [ ] **Step 1: Write a per-format capability matrix**

```markdown
# LacyLights Import/Export Formats

LacyLights supports three interchange formats. This page summarizes what each
preserves so you can pick the right one for a given workflow.

| Capability | Native JSON | QLC+ (.qxw) | ETC Eos ASCII (.asc) |
|---|---|---|---|
| Patch (fixtures, addresses) | full | full | full (multi-universe `u.a` form normalized) |
| Cues + cue lists | full | full | full (tracking resolved at import) |
| Cue parts | full | partial | full |
| Look Boards | full | dropped | round-trip via `$$ LACYLIGHTS:` sidecar |
| Per-channel FadeBehavior | full | partial | round-trip via sidecar |
| Color/Beam/Focus/Intensity palettes | (looks) | (looks) | imported as standalone looks in dedicated cue lists |
| Presets | (looks) | (looks) | imported as looks |
| Groups | full | partial | full |
| Submasters / faders | n/a | partial | skipped on import (warning) |
| Effects / Partitions / Magic Sheets / Action Triggers / Curves | n/a | n/a | skipped on import (warnings) |

## When to use each

- **Native JSON** — round-tripping between LacyLights instances; fully lossless.
- **QLC+** — exchanging shows with QLC+ users; expect some loss on rich features.
- **ETC Eos ASCII** — exchanging shows with ETC Eos / ETCNomad consoles. Use when
  you want EOS to read your file directly. LacyLights-only concepts ride along
  in a sidecar that EOS ignores.

## Known limitations

- Eos export emits **resolved** cue values. If the source EOS show used palette
  references, those references are not preserved on round-trip — only the
  resulting values are. Palettes still survive as their own cue lists.
- Native ETC binary `.esf3d` files are **not** supported. Use EOS's "Export
  ASCII Show File" feature first.
```

- [ ] **Step 2: Commit (note: this top-level dir isn't a git repo today; user will git-init when ready)**

If the top-level `lacylights/` is git-initialized at the time of writing, commit normally; otherwise just leave the file on disk.

```bash
# Only if git-initialized
cd ~/src/lacylights
git add docs/IMPORT_EXPORT_FORMATS.md
git commit -m "docs: per-format capability matrix"
```

---

## Self-Review (planner)

**Spec coverage check** — every section of the design doc maps to at least one task:

- *Architecture & Module Layout* → Task 1 (skeleton), Tasks 16-18 (writer module split), Tasks 24/29 (FE+MCP layout).
- *Backend GraphQL surface* → Task 20 (schema), Task 21 (resolvers).
- *Frontend* → Tasks 24-27.
- *MCP* → Tasks 29-31.
- *Data Flow — Import* → Tasks 2-15.
- *Data Flow — Export* → Tasks 16-18.
- *Round-trip Strategy / Sidecar* → Task 10 (reader), Task 18 (writer), Tasks 14c (apply), 19 (round-trip test).
- *Errors & Warnings* → Task 1 (types), Task 11 (soft warnings), Task 15 (hard errors).
- *Testing Strategy* → Tasks 2-15 each include unit tests; Task 19 round-trip; Tasks 22, 27, 32, 33 cross-layer tests.
- *Real-World Fixture Notes* → Tasks 19, 22, 32 use the golden OTBPA fixture.
- *Open Items* — schema-vs-sibling decision: resolved in favor of sibling mutations matching the QLC+ pattern (Task 20). Palette cue list naming: hardcoded as "Color Palettes" / "Beam Palettes" / "Focus Palettes" / "Intensity Palettes" / "Presets" (Task 14a). Synthesized fixture severity: `INFO` (Task 13 matcher). `$$Format` other than 3.x: parser is permissive (no version gate), so non-3.x files attempt to parse and emit warnings on unknown directives. `$$UText` encoding: empirically UTF-16-LE hex (Task 7). Palette-ref-in-`$$Param` syntax: not exercised by golden fixture; left as a future extension once a fixture surfaces it.

**Placeholder scan** — checked. The `import_unicode_utf16()` placeholder in Task 17 is called out and replaced inline. The `sortStrings` placeholder in Task 21 is also called out. No remaining `TODO` / `TBD`.

**Type consistency check** — `Snapshot.ChannelLevels` (Task 9) is `map[int]int`; consumers in Task 14b use it the same way. `MatcherRepo.FindMatchingDefinition` is defined in Task 13 and the production adapter in Task 14 uses the same signature. `EosWarning` shape in GraphQL (Task 20) matches the Go `Warning` shape (Task 1) and the TS interface used in Tasks 25/30. `WriterOptions.FormatVersion` defaults to "3.20" everywhere.

---

## Execution Handoff

**Plan complete and saved to `docs/plans/2026-04-28-eos-ascii-importer-exporter-implementation.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
