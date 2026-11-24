# GDTF Fixture Import — Design (Stream 3)

**Date:** 2026-10-15
**Status:** Draft design. User decisions so far:
- Accept single `.gdtf` files, `.zip` archives of them, or a folder of them.
- Target GDTF **1.2** (DIN SPEC 15800:2022).
- Use the **source-precedence model** from the Eos design ([2026-10-15-eos-library-byo-import-design.md](2026-10-15-eos-library-byo-import-design.md) §6).

**§9 answered 2026-10-15:**
1. Precedence default is USER > GDTF > OFL > BUILTIN > EOS > SYNTHESIZED.
2. Best-effort import for 1.1 (with a warning); reject 1.0.
3. One mode per DMX break.
4. Re-importing the same FixtureTypeID updates the definition in place.

**Progress (2026-10-16): merged, not released.** All PRs were squash-merged with the user's permission, using Claude Code review as the gate:
- go#103 `a930c40`, go#104 `141a02e`, fe#195 `2d4a4e8`, fe#196 `8d75a71`, mcp#212 `9d7b2b8` and mac#46 `7ec6aba`.
- Stream 1 merged at the same time: go#102, fe#194 and mcp#211.

Review-driven additions before merge:
- Source-ID-first matching in project import.
- Same-name multi-source round trip.
- OFL-only update checks.
- Reclassification of legacy OFL rows against the embedded bundle.
- Run-once source backfill.
- Admin-only precedence changes.
- GDTF hardening: overflow guard, expansion and extraction budgets, request caps of 200 files and 128 MB, serialized imports.
- Frontend operation lock and UTF-8 byte batching.
- MCP streaming import with a header-independent zip reader.

Open follow-ups:
- PR G (contract test).
- OFL orphan fix.
- Browser zip reader parity with MCP.
- Unique index on (source, source_id).
- Leave `source_payload` out of list queries.
- GDTF mapper version in the hash.
- A single auth policy for definition-changing mutations.
- MCP path allow-list.
- Done 2026-10-16: go#105 `fa1cc89` (dmx coverage flake fix) and go#106 `ead6199` (source-precedence lookup returns DB errors; import test DBs now migrate `models.Setting`).

**History (2026-10-15):**
- PR A (source model) is go#103.
- PR B (GDTF importer) is go#104. It is stacked: it includes #103 and a merge of #102. Merge order is #102, then #103, then #104.
- PR C (frontend source badges) is fe#195.
- PR F (Mac folder picker) is mac#46.
- PR D (frontend import screen) is fe#196. It is stacked on fe#195 and merges in fe#194, so merge fe#194, then fe#195, then fe#196.
- PR E (MCP tool) is mcp#212. Merge it after go#104.
- PR G (contract test) is not started.
- Found while building: OFL update paths orphan definitions (new ID on library update; `replace` leaves channels and modes behind). This needs a follow-up PR.

**Parent plan:** [2026-10-15-fixture-fidelity-non-etc-plan.md](2026-10-15-fixture-fidelity-non-etc-plan.md)
**Spec sources:** `mvrdevelopment/spec` `gdtf-spec.md` (`main` = 1.2; `next` = approved clarifications).
- Reference implementations for the algorithms: pygdtf (MIT) `utils.get_dmx_channels` and `DmxChannel._read_xml`; OFL (MIT) `plugins/gdtf/` for attribute → capability mapping.
- We write our own Go implementation and don't copy code.

## 1. Legal / data rules

- The GDTF spec is an open standard, and independent MIT and Apache implementations exist. Writing our own parser is fine.
- GDTF Share files belong to their content owners. The Share terms forbid commercial reuse without a licence. So **only files a user supplies are imported**:
  - no scraping of GDTF Share,
  - no bundled GDTF library,
  - no Share files in repos or test data.
- Tests use synthetic `description.xml` files that we write ourselves.
- "GDTF" is a registered trademark of the GDTF Share operators. Use it only descriptively ("Import GDTF files"); no logos.

## 2. Inputs and transport

The user can pick:
- one or more `.gdtf` files,
- one or more `.zip` files, each containing `.gdtf` files at any depth,
- a folder, via `<input webkitdirectory>`. All `.gdtf` and `.zip` files under it are used.

**Decision: unzip on the client and send only `description.xml`.**
- A `.gdtf` is a zip holding `description.xml` plus thumbnails, wheel PNGs and 3D models. The models can be tens of MB, and LacyLights doesn't use them.
- So the frontend opens each archive in the browser with `fflate` (~8 KB gzipped; no native deps), pulls out `description.xml`, and sends just the XML strings. That's typically 20 KB – 1 MB per fixture.
- **Why:**
  - It matches every existing import, which already sends file content as a GraphQL `String`.
  - It avoids adding an `Upload` scalar and multipart plumbing, raising the 32 MiB gqlgen multipart limit, and fighting reverse-proxy body limits on the Pi.
  - A folder of 200 fixtures is a few MB instead of a few GB.
- **Server side:**
  - The Go package also exposes `ExtractDescriptions(r io.ReaderAt, size int64)`, which handles `.gdtf` and `.zip`, nested.
  - It's used by tests, by any future server-side path, and as a reference for the TS extractor's behaviour.
  - Zip safety:
    - ≤ 2,000 entries per archive,
    - ≤ 32 MB decompressed for any `description.xml`,
    - nested-zip depth ≤ 2,
    - no extraction to disk.
- **MCP:** a new tool `import_gdtf_fixtures({paths: string[]})` reads files, zips or folders from the MCP host filesystem, extracts with the same logic in Node (`fflate`), and calls the same mutation.
- **Mac app:** the WebView open panel currently sets `canChooseDirectories = false` (`lacylights-mac/.../WebViewController.swift:325`). It must honour `parameters.allowsDirectories` so folder pick works there.

**GraphQL:**

```graphql
input GdtfFileInput {
  fileName: String!        # original .gdtf name (or "archive.zip/inner/Foo.gdtf")
  descriptionXml: String!  # contents of description.xml
}
input GdtfImportOptions {
  onExisting: GdtfExistingPolicy = UPDATE   # same FixtureTypeID already imported
}
enum GdtfExistingPolicy { UPDATE SKIP }
type GdtfImportFileResult {
  fileName: String!
  status: GdtfImportStatus!                 # CREATED UPDATED UNCHANGED SKIPPED FAILED
  definition: FixtureDefinition
  manufacturer: String
  model: String
  modeCount: Int
  warnings: [String!]!
  error: String
}
type GdtfImportResult {
  results: [GdtfImportFileResult!]!
  createdCount: Int!
  updatedCount: Int!
  unchangedCount: Int!
  failedCount: Int!
}
extend type Mutation {
  importGdtfFixtures(files: [GdtfFileInput!]!, options: GdtfImportOptions): GdtfImportResult!
}
```

- Each file runs in its own transaction, so one bad file doesn't fail the batch.
- Limits:
  - per-file XML ≤ 32 MB;
  - files per call: no default limit, but the frontend sends batches of 25 to show progress and keep requests small.

## 3. Source-precedence model (shared with Eos; built here first)

Adds columns to `fixture_definitions` via GORM AutoMigrate:

| Column | Type | Notes |
|---|---|---|
| `source` | text, not null, default `'USER'` | `BUILTIN \| OFL \| GDTF \| EOS \| USER \| SYNTHESIZED`. `EOS` is reserved for the on-hold Eos work |
| `source_id` | text, nullable | OFL `manufacturer/key`, GDTF `FixtureTypeID` (GUID, upper-cased), Eos GUID |
| `source_version` | text, nullable | OFL version; GDTF `DataVersion` + last `Revision@Date`/`Text` |
| `source_hash` | text, nullable | SHA-256 of the source document (OFL JSON / GDTF `description.xml`) |
| `source_payload` | blob, nullable | gzip of the source document, kept so capability storage (Stream 2) can re-derive data without a re-upload. GDTF only for now |

- Index on `(source, source_id)`.
- **Backfill** runs at startup and is idempotent: only rows where `source` is the default and not yet classified.
  - `ofl_source_hash IS NOT NULL` → `OFL` (copy hash to `source_hash` and version to `source_version`).
  - `is_built_in` → `BUILTIN`.
  - Eos-synthesized definitions, identified by the `eosFixtureDefRefID` RefID prefix → `SYNTHESIZED`.
  - Everything else → `USER`.
- `ofl_source_hash`, `ofl_version` and `is_built_in` stay for compatibility. New code reads `source`.
- **Writers:**
  - the OFL importer sets `source=OFL`;
  - the Eos ASCII synthesizer sets `SYNTHESIZED`;
  - `createFixtureDefinition` and project import set `USER`, unless an imported project JSON carries a `source`.
- **Lookups become source-aware.** No unique constraint exists on (manufacturer, model), and duplicates already occur.
  - OFL import looks up `(manufacturer, model, source = OFL)`, so it never overwrites a GDTF or USER definition.
  - GDTF import looks up by `(source = GDTF, source_id = FixtureTypeID)`.
  - The Eos ASCII matcher (`fixture_match.go`) tries candidates in precedence order.
- **Precedence:**
  - A server setting `fixtureSourcePrecedence` is stored in the existing settings key/value table.
  - Proposed default: **USER > GDTF > OFL > BUILTIN > EOS > SYNTHESIZED**. Reasoning: a user who deliberately imported a GDTF file, which is usually manufacturer-authored, means to use it over the community OFL file.
  - It's read by the Eos matcher, the picker ordering and the MCP "find definition" paths.
- **GraphQL:**
  - `FixtureDefinition { source: FixtureSource!, sourceId: String, sourceVersion: String }`
  - `FixtureDefinitionFilter.source`
  - `enum FixtureSource`
  - `query fixtureSourcePrecedence` / `mutation setFixtureSourcePrecedence`
- **Picker:**
  - Models are grouped by normalized manufacturer + model.
  - Each source is shown with a badge (user-approved).
  - The highest-precedence source is pre-selected.
- **Project export/import:** definitions carry `source`, `sourceId` and `sourceVersion`; the fields are optional for backwards compatibility. `source_payload` is not exported.

## 4. Parsing GDTF 1.2

- **Version:** `GDTF@DataVersion` is "Major.Minor".
  - **1.2 is supported.**
  - Higher minors (1.3+) are accepted with a warning.
  - What to do with **< 1.2** is open question Q2.
- **Required sections:** `FixtureType` (`Name`, `Manufacturer`, `FixtureTypeID`), `AttributeDefinitions`, `Geometries`, `DMXModes`.
- **AttributeDefinitions/Attributes:** we read `Name`, `Pretty`, `Feature` (`Group.Feature`) and `PhysicalUnit`.
  - Custom attributes are allowed by the spec.
  - `Feature` gives a fallback classifier.
- **Geometry tree:** read in full, because channel expansion needs it. Types are `Geometry`, `Axis`, `Beam`, …, and `GeometryReference` with `Break` children.
- **DMXChannel** (per mode):
  - `DMXBreak`: int, default 1, or `Overwrite`.
  - `Offset`: `"1"`, `"2,3"` (16-bit), …, or `None`, which marks a virtual channel and is skipped.
  - `Geometry`.
  - `InitialFunction`: a `Channel.LogicalChannel.Function` link; default is the first function of the first logical channel.
- **LogicalChannel:**
  - `Attribute`.
  - `Snap`: `Yes`/`On` mean snap; `No`/`Off` mean no snap.
- **ChannelFunction:** `Name`, `Attribute`, `DMXFrom`, `Default` (fallback: legacy `DMXChannel@Default`, then `DMXFrom`), `ModeMaster`, `ModeFrom`/`ModeTo`, and `ChannelSet` children.
- **DMXValue** `v/n[s]`:
  - `/n` mirrors bytes: `255/1` in 16-bit is 65535; `128/1` is 0x8080.
  - `/ns` shifts bytes: `255/1s` in 16-bit is 65280.
  - Values are normalized to the channel's byte count before comparing.
  - The end of a range is the next sibling's `DMXFrom − 1`, computed within each ModeMaster group, or the channel maximum for the last one.

### Channel expansion (geometry references and breaks)

1. Start at `DMXMode@Geometry` and walk the tree.
2. A DMXChannel whose `Geometry` is a top-level template that a `GeometryReference` uses is instantiated **once per reference**:
   - Each instance offset is `Offset[i] + (Break.DMXOffset − 1)`, using the `Break` whose `DMXBreak` equals the channel's break.
   - For `Overwrite`, use the **last** `Break` child's DMXBreak and DMXOffset.
   - The instance name uses the reference `Name`, e.g. "Pixel 3".
3. Channels whose geometry isn't referenced are used as declared.
4. Channels are grouped by DMXBreak. **Multiple breaks** (e.g. dimmer on break 1, scroller on break 2) are separate patch footprints, possibly in different universes, and a LacyLights instance has one start address.
   - Proposal: **split such a mode into one LacyLights mode per break**, named "`<Mode>` (Break N)", so the user patches one instance per footprint (Q3).
5. Gaps in offsets become `OTHER` "No Function" channels. The `next` spec requires continuous offsets with NoFeature fillers anyway.

## 5. Mapping to LacyLights

| GDTF | LacyLights |
|---|---|
| FixtureType | `FixtureDefinition`: `Manufacturer` from `@Manufacturer`; `Model` from `@LongName`, falling back to `@Name`; `Source = GDTF`; `SourceID = FixtureTypeID`; `SourceVersion`; `SourceHash`; `SourcePayload` |
| DMXMode (× break) | `FixtureMode`: `Name` = mode name (+ " (Break N)"); `ChannelCount` = highest offset in that break |
| DMXChannel instance | `ChannelDefinition` + `ModeChannel`. `Offset` = first address − 1. Bytes 2..n become `"<name> Fine"`, `"<name> Fine 2"`, … with the same type (as OFL `addFine`). Channels are deduplicated across modes by (name, type, default, fade) |
| Channel name | Attribute `Pretty` (else attribute name), plus a geometry-reference prefix when the same attribute appears more than once in a mode ("Pixel 3 Red") |
| Channel type | Classify the first LogicalChannel's `Attribute` (table below); fall back on `Feature` |
| Default | InitialFunction's `Default` → coarse and fine bytes |
| Fade behaviour | `Snap = Yes/On` → SNAP; otherwise reuse `ofl.mapFadeBehavior(type, isDiscrete)` |
| `IsDiscrete` | True when the logical channel has more than one ChannelFunction (excluding ModeMaster-gated duplicates), or ChannelSets with `WheelSlotIndex` |
| `FixtureDefinition.Type` | Pan + Tilt → MOVING_HEAD. Colour-mixing attributes → LED_PAR. Only Dimmer (± strobe/control) → DIMMER. Strobe-dominant without colour → STROBE. Otherwise OTHER |
| ChannelFunction / ChannelSet ranges, wheels, physical data, relations, macros, presets, RDM | **Not stored yet.** They are kept in `source_payload` for Stream 2 (capabilities) |

### Attribute → ChannelType

Matching is case-insensitive, and `(n)` numbers are stripped (`Gobo2Pos` → `Gobo(n)Pos`).

| Attribute(s) | ChannelType |
|---|---|
| `Dimmer`, `HSB_Brightness` | INTENSITY |
| `Pan`, `Tilt` | PAN, TILT |
| `ColorAdd_R/G/B`, `ColorRGB_Red/Green/Blue` | RED, GREEN, BLUE |
| `ColorAdd_W` / `_WW` / `_CW` | WHITE / WARM_WHITE / COLD_WHITE |
| `ColorAdd_RY` (amber) / `_GY` (lime) / `_UV` | AMBER / LIME / UV |
| `ColorAdd_C/M/Y`, `ColorSub_C/M/Y`, `ColorRGB_Cyan/Magenta/Yellow` | CYAN, MAGENTA, YELLOW |
| `CTO`, `CTC`, `CTB` | COLOR_TEMPERATURE |
| `HSB_Hue`, `HSB_Saturation` | HUE, SATURATION |
| `Color(n)`, `Color(n)WheelIndex` | COLOR_WHEEL |
| `Gobo(n)`, `Gobo(n)WheelIndex`, `Gobo(n)SelectSpin/Shake/Effects` | GOBO |
| `Zoom`, `ZoomModeSpot/Beam`, `Focus(n)`, `Iris` | ZOOM, FOCUS, IRIS |
| `Shutter(n)`, `Shutter(n)Strobe*`, `Strobe*` | STROBE |
| `Prism(n)*`, `Effects(n)` (non-rate), `Gobo(n)Pos*`, `*Rotate`, `*Spin` (non-select) | EFFECT |
| `*MSpeed`, `Effects(n)Rate`, `ColorMacro(n)Rate` | SPEED |
| `Control(n)`, `*Reset`, `*Mode` (control group), `LampControl`, `Function`, `ColorMacro(n)` | MACRO |
| `ColorAdd_GC/BC/BM/RM`, `ColorSub_R/G/B`, `Tint`, `CIE_*`, `Frost*`, `Fan*`, `Fog*`, `Haze*`, `Dummy`, `NoFeature`, anything unknown | OTHER (by name), with Feature fallback: `Dimmer.Dimmer` → INTENSITY, `Control.Control` → MACRO |

## 6. Re-import / updates

- **Same `FixtureTypeID` already imported as GDTF:**
  - same `source_hash` → `UNCHANGED`;
  - different hash → `UPDATED` (or `SKIPPED` with `onExisting: SKIP`).
- **How updates work:**
  - the existing definition's **ID and RefID are kept** and its channels and modes are rebuilt in one transaction, so projects keep their references;
  - fixture instances keep their copied channels, as they do for OFL updates today;
  - the UI reports how many patched fixtures use an updated definition.
  - First verify how the OFL update path handles definitions that are in use (it currently creates a new ID) and stay consistent with it. If it's unsafe, fix both.
- **Same manufacturer + model from a different source:** it coexists; the picker shows both, with badges.

## 7. Frontend UX

- **Import/Export screen:** a new "Fixture definitions" import card with:
  - three pickers: **Files** (`.gdtf,.zip`, multiple), **Folder** (`webkitdirectory`) and drag-and-drop;
  - client-side extraction, then batches of 25 to `importGdtfFixtures` with a progress bar;
  - a results table (status, manufacturer/model, modes, warnings), downloadable as CSV.
- **Add/Edit fixture modals:** a source badge (USER, GDTF, OFL, …) on each model row. When a model exists in several sources, rows are ordered by precedence and the top one is pre-selected.
- **Settings:** the source-precedence order (a reorderable list).

## 8. Delivery (PRs)

| # | Repo | PR | Notes |
|---|---|---|---|
| A | go | **Source model**: columns + backfill, OFL/Eos writers set source, source-aware lookups, GraphQL `source`/`sourceId`/`sourceVersion` + filter + precedence setting | Independent of GDTF; can start now |
| B | go | **`internal/services/gdtf`**: archive extraction, XML parse, DMXValue, channel expansion (references, breaks, Overwrite), attribute classifier, mapper, `importGdtfFixtures` mutation | Synthetic test XML for: RGBW par, 16-bit mover with wheels, pixel bar via GeometryReference, multi-break dimmer + scroller, Overwrite, virtual channels, `/s` values, bad input |
| C | fe | Source badges + precedence setting | After A |
| D | fe | GDTF import card (fflate, files, zip, folder, drag-drop, batching, results) | After B |
| E | mcp | `import_gdtf_fixtures` tool (paths: files, zips, folders); show `source` in definition outputs | After B |
| F | mac | Allow directory selection in the WebView open panel | Small, independent |
| G | test | Contract test: `importGdtfFixtures` with synthetic files; source-precedence behaviour | After B |

## 9. Open questions

1. **Precedence default:** is USER > GDTF > OFL > BUILTIN > EOS > SYNTHESIZED right?
2. **GDTF < 1.2:** many files on GDTF Share are still 1.0/1.1. Options:
   - (a) reject with a clear message, or
   - (b) best-effort import with a warning. 1.1 differs mainly in legacy `DMXChannel@Default`, which we already fall back to.
   - Proposed: **(b) for 1.1, (a) for 1.0**. 1.0 predates `InitialFunction` and has other structural differences.
3. **Multi-break fixtures:** split into one mode per break (proposed)? Or import only break 1 with a warning?
4. **Re-import with the same FixtureTypeID:** update in place by default (proposed), or keep both versions?
