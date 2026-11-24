# ETC Eos ASCII Importer / Exporter — Design

**Date:** 2026-04-28
**Status:** Design approved by user; implementation plan to follow.
**Related sample files:**
- Native binary (not used as fixture): `docs/OTBPA DRESS TUES 2026-04-14 21-59-58.esf3d`
- Native binary export (not used as fixture): `docs/OTBPA DRESS TUES 2026-04-28 07-52-08.esf`
- **Real-world golden fixture:** `docs/OTBPA DRESS TUES.asc` (ETC Eos ASCII, Format 3.20, ~6.4k lines)

## Goal

Add bi-directional import/export support for ETC EOS / ETCNomad shows in LacyLights, using the documented ETC Eos ASCII text interchange format as the wire format. The feature must be reachable from the existing LacyLights frontend UI and from the LacyLights MCP server, sharing a single backend implementation.

## Non-Goals

- We will **not** parse or write the native ETC binary `.esf3d` / `.esf` show files. They are an undocumented proprietary serialization (UTF-16 + tagged binary records) and reverse-engineering them from sample files is high-risk and out of scope.
- We will not parse the older USITT 5.02 ASCII subset on its own. Eos ASCII is a strict superset for our purposes; if we ever need USITT compatibility we add it later as a parser flag.
- We will not attempt to model EOS-specific concepts that have no LacyLights equivalent (effects engines, magic sheets, partitions, sub-bump behavior, action triggers). They are detected and reported as warnings on import, and lossy concepts on the LacyLights side are carried out-of-band via a sidecar (see "Round-trip strategy").

## Scope (chosen scope: "everything practical")

The importer/exporter aims to handle:

- **Patch:** fixture personalities, fixture instances, addresses, channel labels.
- **Cues:** all cue lists, cues, cue parts, up/down/follow/hang times, labels, blocks, channel/parameter levels. EOS *tracking* is resolved at import (see "Cue tracking" below) so each LacyLights look has the full state.
- **Cue parts:** an EOS cue with parts (`Cue 5/2`) becomes one LacyLights cue per part inside the same cue list, named `Cue 5 Part 2 - {label}`, preserving each part's distinct timing.
- **Palettes / Presets:** Color, Beam, Focus, Intensity palettes, and Presets, materialized as standalone LacyLights looks in dedicated cue lists.
- **Groups:** EOS groups → LacyLights groups (same concept).
- **Submasters:** EOS submasters / faders → skipped on import with structured warning. LacyLights has no submaster concept, so nothing on the export side to map.
- **Effects, partitions, magic sheets, action triggers:** detected and reported as warnings on import; not modeled in LacyLights.

LacyLights-only concepts that can't be expressed cleanly in Eos ASCII (Look Boards, per-channel `FadeBehavior`, synthesized fixture definitions) are:

1. exported as the closest valid Eos ASCII representation possible, **plus**
2. emitted into a `$$ LACYLIGHTS:` comment-sidecar block at end-of-file that EOS ignores but our importer reads back, enabling lossless `LacyLights → Eos ASCII → LacyLights` round-trip.

## High-Level Decisions (with rationale)

| Decision | Choice | Rationale |
|---|---|---|
| Wire format | ETC Eos ASCII (`.asc`) | Documented, text, supports the full feature set; binary `.esf3d` is undocumented and brittle. |
| Direction | Both import and export | User goal is round-trip, not one-way migration. |
| Scope | "Everything practical" with explicit lossy warnings | Anything less makes round-tripping a real EOS show feel broken; full fidelity is intractable. |
| Placement | Backend Go service; thin GraphQL surface; FE + MCP exposure | Keep parsing/serialization in one place, expose via existing pipelines. |
| Fixture matching | Match-then-synthesize | Lowest friction; users can review synthesized definitions afterwards. |
| Cue mapping | One LacyLights look per EOS cue (palette refs resolved at import) | Lossless on cue side; avoids inventing a composition model. |
| Palettes / Presets | Standalone looks in dedicated cue lists (Color/Beam/Focus/Intensity/Presets) | Reusable as building blocks without composition primitives. |
| Lossy bits on export | Clean ASCII + `$$ LACYLIGHTS:` sidecar comment block | Any console reads the file; LacyLights reads sidecar for lossless round-trip. |
| Errors | Hard errors abort import; soft issues become structured `EosWarning` entries | Lets the UI/MCP render a useful warning summary instead of an opaque blob. |
| Testing | Hand-authored ASCII fixture corpus + real-world golden fixture | Per-feature coverage in repo, real-world regression anchor from day one. |

## Architecture & Module Layout

### Backend — `lacylights-go`

New packages mirroring existing native JSON import/export:

```
internal/services/
├── import_eos/
│   ├── parser.go          # Eos ASCII tokenizer + grammar
│   ├── ast.go             # Parsed-show AST (patch, cues, palettes, subs, groups, effects)
│   ├── mapper.go          # AST → LacyLights domain models (uses fixture/look/cue repos)
│   ├── fixture_match.go   # OFL/built-in match-then-synthesize logic
│   ├── param_table.go     # $ParamType id → LacyLights ChannelType lookup
│   ├── utext.go           # $$UText follow-record decoding
│   ├── sidecar.go         # Reads `$$ LACYLIGHTS:` comment metadata
│   ├── warnings.go        # Structured warning collector
│   └── *_test.go
└── export_eos/
    ├── writer.go          # Domain models → Eos ASCII text
    ├── sidecar.go         # Emits `$$ LACYLIGHTS:` lines for lossy bits
    ├── fixture_emit.go    # LacyLights fixture → Eos personality emission
    ├── utext.go           # Emits $$UText follow-records when labels need it
    └── *_test.go
```

Boundaries:

- `parser` produces a strongly-typed AST. It does **not** touch the database, repos, or any LacyLights model. It is tolerant of unknown `$` directives (logs a warning, skips the line).
- `mapper` consumes the AST + repos, applies match-then-synthesize, deduplicates fixture defs, builds looks/cues/palettes-as-looks. **All DB writes happen inside one transaction.**
- `writer` reads project state via repos, emits ASCII deterministically (stable ordering by cue number, fixture address, etc.; LF line endings; fixed-format timestamps). Same input must produce byte-identical output.
- `sidecar` (import + export) is an isolated subsystem so the lossless extension can evolve without touching the core ASCII grammar.

### GraphQL surface

Extend the existing `importProject` / `exportProject` mutations with a `format: ImportFormat!` enum (values `NATIVE_JSON`, `EOS_ASCII`). If the existing mutations' return type cannot extend cleanly, add `importProjectEos` / `exportProjectEos` siblings — decision deferred until the implementation plan reads `schema.graphql`. Either way, both the frontend and MCP get a single new `format` parameter, and the backend's `import_eos` / `export_eos` packages are the only callers of the new enum value.

The GraphQL response carries:

```graphql
type ImportProjectResult {
  project: Project!
  stats: ImportStats!
  warnings: [EosWarning!]!         # new field, empty for NATIVE_JSON
  synthesizedDefinitionIds: [ID!]! # new field, empty for NATIVE_JSON
}

type ExportProjectResult {
  content: String!                 # ASCII text or JSON string depending on format
  warnings: [EosWarning!]!         # new field, empty for NATIVE_JSON
  filenameSuffix: String!          # ".asc" or ".json"
}

type EosWarning {
  code: EosWarningCode!
  severity: EosWarningSeverity!    # INFO | WARN
  message: String!
  context: [EosWarningContextEntry!]!
}
```

### Frontend — `lacylights-fe`

```
src/components/
└── ImportExportButtons.tsx        # add format selector + auto-detect by extension
src/components/import-eos/
├── EosImportDialog.tsx            # file picker + options + warnings display
├── EosImportWarningsList.tsx      # structured warnings, grouped by code
└── __tests__/
```

- Format selector defaults to auto-detect (`.asc` → Eos, `.json` → native); user can override.
- Export side: button + filename suffix change, no new dialog.
- Import side: on success, render the warnings list grouped by `EosWarningCode` (Synthesized fixtures / Effects skipped / Submasters skipped / etc.) so the user can review.
- GraphQL bindings regenerate via existing `codegen.yml`. No new infrastructure.

### MCP — `lacylights-mcp`

```
src/tools/
└── import-export-tools.ts         # new file
```

Two new MCP tools, thin wrappers over the GraphQL surface:

- `import_eos_ascii(project_id_or_name, file_content, options)`
- `export_eos_ascii(project_id, options)`

All parsing/emitting stays in Go. Pattern matches existing tools in `src/tools/project-tools.ts`. Tools return the structured warnings list so an AI agent can react.

## Data Flow

### Import (Eos ASCII → LacyLights)

```
.asc file
   │
   ▼
[parser]          → AST: show metadata, $ParamType table, $Personality blocks,
   │                       $Patch entries, $CueList/Cue blocks (with $$ChanMove,
   │                       $$Param, $$TimeUp, $$TimeDown, $$Follow, $$Block, ...),
   │                       palettes ($ColorPalette, $BeamPalette, $FocusPalette,
   │                       $IntensPalette), $Preset, $Group, $Sub/$FaderDef,
   │                       $Effect, $Curve, $Partition, $$UText follow-records.
   ▼
[sidecar.Read]    → extracts `$$ LACYLIGHTS:` lines into typed extras struct
   │                  (look-board layouts, fade-behavior overrides, synth-def refs)
   ▼
[mapper] (one DB transaction):
   1. Build paramId → ChannelType map from $ParamType table.
   2. For each $Personality, run [fixture_match]:
        - try existing OFL/built-in match by manufacturer + model + footprint +
          channel layout + DCID (when present);
        - else synthesize a new FixtureDefinition from PersChan/PersSlot data,
          tagging channels via the param table.
   3. Create FixtureInstances for each $Patch entry. Patch addresses may be in
      `universe.address` form (e.g. `1.512`) or as a flat absolute address;
      both are normalized to LacyLights' (universe, address) tuple.
   4. Build palette looks: one Look per palette; group into 4 cue lists
      ("Color Palettes", "Beam Palettes", "Focus Palettes", "Intensity Palettes").
      $Preset → "Presets" cue list.
   5. **Cue tracking + palette resolution.** Walk each cue list in order,
      maintaining a cumulative channel-state map. For each cue:
        a. Apply `$$ChanMove` (intensity moves) and `$$Param` (parameter
           moves) to the cumulative state.
        b. Resolve any palette references in the moves to concrete channel
           values via the palette tables built in step 4.
        c. Snapshot the cumulative state into a new Look named
           `Cue {number} - {label}` (or `Cue {number} Part {part} - {label}`
           for parts), and append a Cue to the matching cue list with
           up/down/follow/hang timing and Block flags.
      The resulting LacyLights looks are full snapshots; tracking is consumed
      at import time and not re-introduced on export.
   6. Apply sidecar extras: rebuild Look Boards, restore SNAP / SNAP_END flags,
      relink synthesized defs to their original LacyLights fixture def IDs.
   7. Collect warnings (effects skipped, sub bumps skipped, partitions skipped,
      synthesized fixtures, unknown directives, $$UText decode failures).
   ▼
ImportResult {
  stats: ImportStats,
  warnings: []EosWarning,
  synthesizedDefinitionIds: []string,
}
```

### Export (LacyLights → Eos ASCII)

```
project_id
   │
   ▼
[loader]          → reads project via repos: fixtures, looks, cue lists, look boards
   ▼
[writer]          → emits ASCII deterministically (LF line endings, stable order):
   1. Header: Ident 3:0, Manufacturer ETC, Console Eos, $$Format, $$Software,
      $$Title, default $$Time defaults, then $$ LACYLIGHTS:format-version.
   2. $ParamType block: emit the param-type rows we use (intensity, R/G/B/A/W,
      pan/tilt, zoom, strobe, …).
   3. $Personality blocks: for each unique FixtureDefinition referenced by a
      FixtureInstance, emit a $Personality with $$Manuf, $$Model, $$Footprint,
      $$PersChan / $$PersSlot per channel; if it was synthesized, also note it
      in the sidecar's `synth_defs` list.
   4. $Patch lines: one per FixtureInstance, sorted by EOS channel number.
   5. Palettes: re-emit Looks from "Color/Beam/Focus/Intensity Palettes" and
      "Presets" cue lists as $ColorPalette / $BeamPalette / $FocusPalette /
      $IntensPalette / $Preset blocks. Looks NOT in those cue lists are emitted
      as cues only.
   6. Cues: walk each non-palette cue list, emit $CueList n + Cue blocks with
      Up/Down/Follow/Hang times. Levels are emitted as full snapshots
      (every channel listed) rather than tracked moves — simpler, correct,
      and lossless for our model. **Known limitation:** cues that originally
      referenced a palette will be re-emitted with concrete values rather
      than palette references, since the reference was resolved at import.
      This is acceptable because palettes still round-trip as their own
      LacyLights cue lists; only the *cue→palette pointer* is not preserved.
   7. Groups: $Group blocks for LacyLights groups.
   8. Sidecar block at end-of-file:
        $$ LACYLIGHTS:version 1
        $$ LACYLIGHTS:look_board ...
        $$ LACYLIGHTS:fade_behavior ...
        $$ LACYLIGHTS:synth_def ...
   9. Warnings collected during emit (effect-in-cue references skipped, etc.).
   ▼
ExportResult {
  content: string,
  warnings: []EosWarning,
  filenameSuffix: ".asc",
}
```

### Invariants

- **Atomicity:** import is a single DB transaction; any parser/mapper error rolls back fully.
- **Round-trip lossless (LL → ASCII → LL):** when the importer is the same version, all LacyLights state survives via sidecar.
- **Round-trip preserved values (ASCII → LL → ASCII):** patch + cue values byte-equivalent (modulo allowed normalizations: stable sort order, fixed numeric formatting). EOS-only constructs we don't model are dropped on import and surface as warnings.
- **Determinism:** same input → byte-identical output. No map iteration order leaks; no embedded timestamps in deterministic positions.

## Round-trip Strategy

Lossless `LacyLights → Eos ASCII → LacyLights` is achieved via a `$$ LACYLIGHTS:` comment-sidecar appended to the end of the file. EOS treats lines starting with `!` or `$$` it doesn't recognize as comments, so the file remains valid Eos ASCII for any console.

Sidecar contents (proposed v1 schema). All references use **stable refIds** (matching the existing native-JSON export's `refId` convention), not internal database IDs, so a file exported from machine A imports cleanly on machine B:

```
$$ LACYLIGHTS:version 1
$$ LACYLIGHTS:look_board {"refId":"<board>","name":"Top Board","buttons":[{"lookRefId":"<lk>","x":0,"y":0,"color":"#ff0000"}, ...]}
$$ LACYLIGHTS:fade_behavior {"instanceRefId":"<fix>","channels":[{"offset":3,"behavior":"SNAP_END"}]}
$$ LACYLIGHTS:synth_def {"defRefId":"<def>","manufacturer":"…","model":"…","channelFingerprint":"…"}
```

- Each sidecar line is one logical record; values are JSON strings on a single line for tolerant parsing.
- The sidecar parser is permissive: malformed records degrade with a warning rather than failing the whole import.
- The schema is versioned so we can extend it without breaking older readers.
- Refs are reconciled on import by matching the existing import logic's refId resolution; if a referenced refId can't be resolved (e.g. fade_behavior references an instance that didn't get imported), the record is skipped with a `SIDECAR_UNRESOLVED` warning, not a hard error.

## Errors & Warnings

### Hard errors (abort import, no DB writes)

- ASCII parse error — malformed token or unexpected EOF, returned with `line:col`.
- Unsupported version — `$$Format` major version we don't handle.
- Reference integrity error — cue references a palette that doesn't exist; patch references an undeclared personality.
- Channel address conflict — two patch entries claim the same DMX universe/address.
- Repo failure during transaction — wrapped via `fmt.Errorf("eos import: %w", err)` and rolled back.

### Soft warnings (import proceeds)

Structured `EosWarning`:

```go
type EosWarning struct {
    Code     EosWarningCode  // SYNTHESIZED_FIXTURE, EFFECT_SKIPPED, SUBMASTER_SKIPPED,
                             // MAGIC_SHEET_SKIPPED, PARTITION_SKIPPED, ACTION_SKIPPED,
                             // UNKNOWN_DIRECTIVE, FADE_BEHAVIOR_LOST, UTEXT_DECODE,
                             // SIDECAR_INVALID, ...
    Severity Severity        // INFO | WARN
    Message  string
    Context  map[string]string  // {"cue":"5/2.5", "personality":"VL3500 Wash"}
}
```

The same type is used on export for outbound warnings (effects referenced from a cue dropped, fade-behavior overrides emitted only via sidecar, etc.).

### Robustness rules

- Parser tolerates unknown `$` and `$$` directives — logs `UNKNOWN_DIRECTIVE` warning, skips the line. Forward compatibility with newer EOS console versions.
- `$$UText` follow-records attach to the preceding label-bearing record; decode failures degrade to ASCII fallback with a warning.
- Sidecar parsing failures degrade gracefully — malformed `$$ LACYLIGHTS:` lines emit `SIDECAR_INVALID` and the rest of the file still imports.
- Export never fails on non-fatal mapping gaps — it always produces a valid file plus warnings.

## Testing Strategy

Per-decision: unit tests + hand-authored ASCII fixture corpus + the real-world golden fixture from day one.

```
internal/services/import_eos/
├── testdata/
│   ├── minimal_patch.asc            # 4 dimmers, no cues
│   ├── basic_cues.asc               # patch + 5 cues with up/down/follow
│   ├── palettes_color_focus.asc     # color + focus palettes referenced by cues
│   ├── presets_groups.asc           # presets and groups
│   ├── moving_lights.asc            # multi-parameter personalities (P/T, RGB, zoom)
│   ├── utext_unicode.asc            # labels with non-ASCII via $$UText
│   ├── sidecar_roundtrip.asc        # contains $$ LACYLIGHTS: block
│   ├── unknown_directive.asc        # forward-compat tolerance
│   ├── conflict_addresses.asc       # negative test - hard error
│   ├── malformed_cue.asc            # negative test - parse error
│   └── golden_otbpa.asc             # copy of docs/OTBPA DRESS TUES.asc
└── *_test.go
```

Test layers:

1. **Parser tests** — feed each fixture, assert AST matches a hand-written expected struct (subset match for stability).
2. **Mapper tests** — in-memory SQLite (existing pattern), import each fixture, assert resulting fixture defs / instances / cue lists / looks / groups via repo queries.
3. **Round-trip tests** — for each fixture: `parse → map → export → parse`, assert AST equivalence (modulo allowed normalizations).
4. **Sidecar tests** — verify lossy bits (Look Boards, SNAP flags, synthesized defs) survive `LacyLights → ASCII → LacyLights` byte-for-byte on the LacyLights side.
5. **Negative tests** — assert the right `EosWarningCode` or hard error is produced for each malformed fixture.
6. **Determinism test** — same project exported twice produces byte-identical output.
7. **Golden fixture test** — full import of `golden_otbpa.asc` succeeds, produces non-empty patch / cues / palettes / groups, and the warnings list matches an expected snapshot (effects, partitions etc. skipped as expected).

Frontend tests:

- Snapshot test of `EosImportWarningsList` rendering each `EosWarningCode`.
- Jest test confirming the format selector wires the right enum value to the mutation, and auto-detection by file extension.

MCP tests:

- Contract test against a mocked GraphQL client confirming the two new tools' input/output shape.

CI: all of the above run under existing `make test` / `npm test`. No new infrastructure.

## Real-World Fixture Notes (from `docs/OTBPA DRESS TUES.asc`)

Confirmed directives present in the sample, all of which the design accommodates:

| Directive | Count | Path |
|---|---|---|
| `$ParamType` | 21 | param-table lookup feeds channel-type tagging |
| `$Personality` | 5 | match-then-synthesize |
| `$Patch` | 44 | fixture instances |
| `$CueList` | 1 | cue lists |
| `$ColorPalette` | 2 | palette-as-look path |
| `$Group` | 5 | LacyLights groups |
| `$Effect` | 18 | EFFECT_SKIPPED warnings (lossy by design) |
| `$Curve` | 11 | not modeled; warnings on import |
| `$Partition` | 4 | PARTITION_SKIPPED warnings |
| `$FaderDef` | 1 | SUBMASTER_SKIPPED warning |
| `$$UText` | varies | unicode follow-record decoding |

Two refinements vs. the initial design that the fixture made explicit:

1. **`$$UText` follow-records** must be attached to the preceding label-bearing record — added to AST as optional `unicodeText *string` on label-bearing nodes; writer emits `$$UText` only when needed.
2. **Parameter-ID indirection** — EOS `$$Param` lines reference parameter IDs (1, 12, 13, 14, 48, …) that the file's own `$ParamType` table maps to types. The parser stays purely structural; the mapper owns the `paramId → ChannelType` lookup.

## Open Items (deferred to implementation plan)

- Decide between extending existing `importProject` / `exportProject` mutations with a `format` enum vs. adding sibling mutations. Decision driven by current return-type contracts in `internal/graphql/schema/schema.graphql`.
- Decide naming convention for the four palette cue lists ("Color Palettes" etc.) — case, prefix, whether they're hidden from normal cue-list browsing.
- Decide whether unmatched fixture personalities should emit warnings as `INFO` (synthesized successfully) or `WARN` (review recommended). Probably `INFO` unless slot/parameter coverage is incomplete.
- Decide whether to hard-fail or soft-warn on `$$Format` versions other than 3.x. Lean: soft-warn, attempt parse, hard-fail only on actually-incompatible major-version changes.
- Determine the exact `$$UText` encoding (the file header describes it as "encoded unicode representation" without specifying). The implementation plan should examine `$$UText` lines in the golden fixture, confirm encoding (likely hex-encoded UTF-16), and document.
- Verify the syntax EOS uses for palette references inside `$$Param` lines (e.g. `7@CP5` vs. `7@\"Color Palette 5\"`). The golden fixture has direct numeric values throughout; we may need a synthetic fixture or additional samples to exercise palette-referenced cues.
- Decide cue-numbering convention for LacyLights cues created from EOS cue parts: `Cue 5 Part 2` vs. `Cue 5.2`. Numbering must remain unique within the cue list and be reversible on export.

## Out-of-Scope Future Extensions

- Native binary `.esf3d` reader (low priority).
- USITT 5.02 ASCII strict-mode export (only if a customer needs MA/grandMA interop).
- Importing `working.a3d` Augment3d 3D scene (visualization only; no LacyLights model for it today).
- Effects engine modeling on the LacyLights side (then we could round-trip `$Effect` instead of warning).
