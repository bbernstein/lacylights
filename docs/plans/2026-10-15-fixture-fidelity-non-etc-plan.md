# Fixture Fidelity (no ETC data) — Plan

**Date:** 2026-10-15
**Status (2026-10-16):** Stream 1 merged (go#102, fe#194, mcp#211). Stream 3 (GDTF) merged: go#103, go#104, fe#195, fe#196, mcp#212 and mac#46. Neither is released yet. Stream 2 still needs a design pass. Open follow-ups are listed in the [GDTF design progress section](2026-10-15-gdtf-import-design.md).
**Why:** the Eos library import is on hold for legal reasons (see [research §4a](2026-10-15-eos-fixture-library-research.md)). This plan covers the improvements that don't depend on ETC data.
**Related:** [ETC/Carallon permission email draft](2026-10-15-etc-carallon-permission-email-draft.md) (not sent).

**Ground rule:** no ETC or Carallon data is used for any of this work. Eos parameter IDs come only from real `.asc` exports already in the repos (`docs/*.asc`, `import_eos/testdata/golden_otbpa.asc`).

## Stream 1: new channel types `COLOR_TEMPERATURE`, `HUE`, `SATURATION`, `SPEED`

Today these channels import as `OTHER`, or as `EFFECT` in the case of OFL speed capabilities.

### lacylights-go (PR 1)

| File | Change |
|---|---|
| `internal/graphql/schema/schema.graphql` | Add the 4 values to `enum ChannelType`; then `make generate` |
| `internal/services/ofl/service.go` `mapChannelType` | `ColorTemperature` → COLOR_TEMPERATURE. `Speed`, `EffectSpeed`, `PanTiltSpeed` → SPEED (previously EFFECT / EFFECT / OTHER) |
| `ofl/service.go` `mapFadeBehavior` | No change: the new types FADE, which matches what EFFECT and OTHER did, so fade behaviour doesn't change |
| `internal/services/import_eos/param_table.go` | Names `hue`, `saturation`, `color_temperature`/`colour_temperature`/`cct`/`ctc`/`color_temp`, and speed names (`speed`, `*_speed`, `*mspeed`) map to the new types |
| `import_eos/fixture_match.go` | `channelNameFor`: names for the new types. `paramIDForChannelType`: HUE → 7, SATURATION → 8 |
| `internal/services/export_eos/param_table.go` | HUE → `{7, 3, "Hue"}`, SATURATION → `{8, 3, "Saturation"}` (verified from real exports). COLOR_TEMPERATURE and SPEED stay on the generic "Other" row (999) **until verified against a real Eos ASCII export** |
| Tests | Table-driven tests for every mapping above, plus an import→export round-trip for HUE/SATURATION |

**Existing data.** Definitions already in a database keep their old types until the OFL fixtures are re-imported with update. The same thing happened with go#85, and the release notes will say so. Fixture instances copy their channel types at patch time, so already-patched fixtures keep their old type unless re-patched. This is acceptable because nothing changes behaviour (the fade behaviour stays the same).

**Open item:** Eos `$ParamType` IDs for colour temperature and speed parameters. Export a small test show from ETCnomad, using Eos as intended, with an LED fixture that has CCT and a mover with a speed channel, and read its `$ParamType` rows.

### lacylights-fe (PR 2, after PR 1 merges)

1. Run `npm run codegen` against the PR-1 backend.
2. `src/types/index.ts`: add the 4 enum values.
3. Add abbreviations in both maps (`utils/channelAbbreviation.ts`, `components/EffectEditorLayout.tsx`): `CCT`, `Hue`, `Sat`, `Spd`. These maps are `Record<ChannelType, string>`, so the compiler enforces completeness.
4. `EffectEditorLayout.getChannelTypeColor`: CCT gets a warm-white tone; HUE and SATURATION get neutral greys.
5. `MultiSelectControls`: decide whether CCT, HUE and SAT belong in the colour group. Proposed: yes, with grouping only; colour-picker maths stays RGB/CMY/W.
6. `utils/colorConversion.ts`: leave the new types out of RGB preview maths (as OTHER is today). A future enhancement could render CCT in the preview.
7. Tests for the abbreviations and colour mapping.

### lacylights-mcp (PR 3, after PR 1)

- `src/types/lighting.ts`: add the enum values.
- `src/tools/fixture-tools.ts`: capability analysis gets `hasColorTemperature`, `hasHueSat` and `hasSpeed`, with descriptions; `COLOR_CHANNEL_TYPES` gets COLOR_TEMPERATURE, HUE and SATURATION.
- Tests.

### lacylights-test (PR 4, optional)

- The OFL contract test asserts that an OFL fixture with a `ColorTemperature` channel imports as COLOR_TEMPERATURE.

## Stream 2: keep OFL capability ranges (design needed)

Today `ofl/resolve.go:290` keeps only `capabilities[0]`, so range labels such as "Strobe 1–33 Hz", gobo slots and colour-wheel slots are lost.

Rough shape:
- A `ChannelCapability` table (definitionChannelId, dmxMin, dmxMax, type, label, plus optional colour, slot and speed fields).
- Populated by the OFL import, Eos ASCII import (none available) and, later, GDTF.
- Exposed in GraphQL.
- UI: a range picker or labels on discrete channels.

**Questions for the user:**
- Where should labels show up? Options: the fader UI, look editor dropdowns, MCP context for AI look generation.
- Should fixture instances also copy capabilities, as they copy channels today?

## Stream 3: GDTF import (design drafted)

**Design:** [2026-10-15-gdtf-import-design.md](2026-10-15-gdtf-import-design.md).

User decisions:
- Accept single files, `.zip` archives and folders.
- Target GDTF 1.2.
- Use the source-precedence model.

Open questions are listed in §9 of the design. The original notes follow:

The user supplies `.gdtf` files: zip archives of `description.xml` plus media.
- **Map:** DMXModes → modes; DMXChannels/LogicalChannels → channels; Attribute → ChannelType (GDTF attribute names are standardised: `Dimmer`, `Pan`, `ColorAdd_R`, `CTC`, `HSB_Hue`, …); ChannelFunctions → capabilities (needs Stream 2).
- **Legal:** importing files a user downloaded is fine. Don't scrape or bundle GDTF Share; its terms forbid that.

**Questions for the user:**
- Upload of single files only, or a folder or zip of many?
- Which minimum GDTF version (1.1 / 1.2)?
- Should GDTF definitions follow the source-precedence model from the Eos design (`Source = GDTF`)?
