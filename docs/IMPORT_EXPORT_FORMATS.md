# LacyLights Import/Export Formats

LacyLights supports three interchange formats. This page summarizes what
each preserves so you can pick the right one for a given workflow.

| Capability | Native JSON | QLC+ (`.qxw`) | ETC Eos ASCII (`.asc`) |
|---|---|---|---|
| Patch (fixtures, addresses) | full | full | full (multi-universe `u.a`/`u/a`/flat absolute all normalized) |
| Cues + cue lists | full | full | full (tracking resolved at import) |
| Cue parts | full | partial | full |
| Look Boards | full | dropped | round-trip via `$$ LACYLIGHTS:` sidecar |
| Per-channel `FadeBehavior` | full | partial | round-trip via sidecar |
| Color / Beam / Focus / Intensity palettes | (looks) | (looks) | imported as standalone looks in dedicated cue lists |
| Presets | (looks) | (looks) | imported as looks |
| Groups | full | partial | full |
| Submasters / faders | n/a | partial | skipped on import (warning) |
| Effects / Partitions / Magic Sheets / Action Triggers / Curves | n/a | n/a | skipped on import (structured warnings) |

## When to use each

- **Native JSON** — round-tripping between LacyLights instances; fully lossless.
- **QLC+** — exchanging shows with QLC+ users; expect some loss on rich features.
- **ETC Eos ASCII** — exchanging shows with ETC Eos / ETCNomad consoles. Use
  when you want EOS to read your file directly. LacyLights-only concepts
  (Look Boards, per-channel fade behaviors, synthesized fixture definitions)
  ride along in a `$$ LACYLIGHTS:` sidecar comment block at end-of-file
  that EOS ignores but LacyLights re-reads on import.

## Where each format is wired

| Surface | Native JSON | QLC+ | ETC Eos ASCII |
|---|---|---|---|
| Backend (lacylights-go) | `internal/services/import_export/` | `internal/services/import_qlc/` + `export_qlc/` | `internal/services/import_eos/` + `export_eos/` |
| GraphQL mutations | `importProject` / `exportProject` | `importProjectFromQLC` / `exportProjectToQLC` | `importProjectFromEos` / `exportProjectToEos` |
| Frontend UI | `ImportExportButtons.tsx` ("LacyLights JSON") | `ImportExportButtons.tsx` ("QLC+") | `ImportExportButtons.tsx` ("ETC Eos") |
| MCP tools | (web UI only) | `qlc_import_guidance` (web UI only) | `import_eos_ascii`, `export_eos_ascii` |

## Eos ASCII specifics

### File format

LacyLights reads and writes the **ETC Eos ASCII** (`.asc`) text format —
the human-readable showfile EOS produces via *File → Export → Show File →
ETC ASCII Show File*. The native binary `.esf3d` format is **not**
supported; export to ASCII first.

Output is **deterministic**: the same source project produces a
byte-identical `.asc` across runs. This makes diffs and version control
practical.

### Encoding details

- `$$UText` follow-records (long human-readable text on cues) are
  encoded as **UTF-16-LE hex**, matching what EOS writes natively.
- Multi-universe addresses are accepted in `u.a`, `u/a`, and flat
  absolute (`1024` → universe 2 channel 512) forms; the importer
  normalizes to LacyLights's `(universe, startChannel)` shape.
- `$Patch` lines are auto-detected to support both the user-authored
  `<chan> <addr> <persID>` ordering and the library-driven
  `<chan> <persID> <addr> <wheel> <count>` ordering used by EOS exports.

### Lossy bits and the sidecar

When exporting to Eos ASCII, the writer emits LacyLights-only concepts
as `$$ LACYLIGHTS:` comment lines at the end of the file:

```text
$$ LACYLIGHTS: lookboard refId=lb-1 name="Main Board"
$$ LACYLIGHTS: fadebehavior fixture=fx-3 channel=2 mode=snap
$$ LACYLIGHTS: synthdef refId=def-12 sourceFixture="EOS Group 5"
```

EOS itself treats these as comments and ignores them. A subsequent
re-import into LacyLights re-reads the sidecar and reconstructs the
Look Boards, per-channel fade behaviors, and synthesized fixture
definitions. Showfiles that pass through EOS without re-export still
import cleanly — the sidecar is preserved in the file.

### Warnings

The importer emits structured `EosWarning` records (with `code`,
`severity`, `message`, and `context` map) rather than failing on
unsupported directives. Common codes:

| Code | Severity | Meaning |
|---|---|---|
| `EFFECT_SKIPPED` | INFO | EOS effect not modelable in LacyLights |
| `PARTITION_SKIPPED` | INFO | Partition definition skipped |
| `MAGIC_SHEET_SKIPPED` | INFO | Magic sheet skipped |
| `ACTION_TRIGGER_SKIPPED` | INFO | Action trigger skipped |
| `CURVE_SKIPPED` | INFO | Custom curve skipped |
| `FIXTURE_SYNTHESIZED` | INFO | No library match — definition synthesized from `$Patch` metadata |
| `UNPATCHED_CHANNEL` | WARN | `$Patch` line with `0` address — channel left unpatched |
| `GROUP_AUTO_ASSIGNED` | INFO | Multi-group user — project assigned to first group (specify `groupId` in a future API revision) |

### Import options

```graphql
input EosImportOptionsInput {
  newProjectName: String     # create a new project with this name
  targetProjectId: ID        # append into an existing project
  # exactly one of the above (or neither — defaults to $$Title)
}
```

`newProjectName` and `targetProjectId` are **mutually exclusive**; the
backend rejects both being set with an error.

## Known limitations

- Eos export emits **resolved** cue values. If the source EOS show used
  palette references in cues, those references are not preserved on
  round-trip — only the resulting integer values are. Palettes still
  survive as their own cue lists ("Color Palettes", "Beam Palettes",
  "Focus Palettes", "Intensity Palettes", "Presets").
- Native ETC binary `.esf3d` files are **not** supported. Use EOS's
  *Export Show File → ETC ASCII Show File* feature first.
- Submasters and faderdef directives are dropped on import with a
  warning. They have no equivalent in LacyLights's look/cue model.
