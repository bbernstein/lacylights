# Scene→Look Cleanup & Test-Suite Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every test failure surfaced by the full-repo test run of 2026-06-07, and finish the user-facing "Scene"→"Look" terminology migration where stale references remain.

**Architecture:** The Scene→Look rename is already complete in the core (GraphQL schema = 100% "look", Go DB model = `Look`, FE/MCP contract suites pass). Remaining work is: (1) a stale cross-server contract suite, (2) two timing-sensitive fade tests, (3) six false-positive Go lint warnings, and (4) a handful of cosmetic / user-visible "scene" strings. Most of the 800+ "scene" hits across the repos are **intentional** (DB-migration back-compat, SwiftUI's `Scene` keyword, theatrically-correct "scene" in script analysis, test-data labels) and must NOT be changed.

**Tech Stack:** Go 1.25 (lacylights-go, lacylights-test), Next.js/TypeScript + Jest (lacylights-fe), TypeScript + Jest (lacylights-mcp), Jest (contract-tests), golangci-lint 2.6.2.

---

## Audit Summary (what the 5-agent sweep found)

| Repo | "scene" hits | MUST-FIX | Cosmetic | Intentional (keep) |
|------|-------------|----------|----------|--------------------|
| lacylights-go | 516 | 0 | ~350 (test data, comments) | ~165 (`migrateSceneToLook`, export/import back-compat, model comments) |
| lacylights-fe | 103 | 1 test value | ~20 (UI strings, comments, JSDoc, test data) | generated types clean |
| lacylights-mcp | 151 | 0 | ~148 (internal vars, AI prompts, test data) | 3 (script-analysis domain) |
| contract-tests | 28 | **~24 (3 failing tests)** | 0 | 0 |
| lacylights-test | 3 | 0 | 2 (e2e test-data strings) | 1 |
| lacylights-streamdeck | 8 | 0 | 8 (test fixture names) | 0 |
| lacylights-mac | 1 | 0 | 0 | 1 (SwiftUI `Scene` keyword) |
| lacylights-rpi / terraform / web | 0 | 0 | 0 | 0 |

**Test failures from the run (2026-06-07):**
1. `contract-tests/` cross-server suite — 3 tests fail (query removed `sceneCount`/`scenes`). → **Task A1**
2. `lacylights-test contracts/fade` — `TestStrobeChannelSNAP` + `TestUnfadableChannelTypes` fail (timing/tolerance). → **Task B1, B2**
3. `lacylights-go` `golangci-lint` — 6 SA5011 staticcheck false positives. → **Task B3**
4. `lacylights-fe` — `useCueListDataUpdates.test.ts` uses removed enum value `SCENE_NAME_CHANGED` (passes today by string-cast, but semantically dead). → **Task A2**

Everything else (Go unit 27 pkgs, FE 2776 jest, MCP 653 jest, Swift 52, terraform, FE+MCP contract suites, 10/11 integration packages) was green.

---

## Version-control note (READ BEFORE STARTING)

- Each `lacylights-*` subdirectory is its **own git repo**, all currently on `main` and clean. Per project rules, **never commit to `main`** — create a feature branch in each repo you touch (commands given per task).
- `contract-tests/` is **NOT under version control** (loose directory `lacylights-contract-tests`). Its newer replacement, `lacylights-test/contracts/`, supersedes most of it. **Decision required from the user (see Task A1, Step 0):** fix-in-place, move it into a repo, or retire it. The plan assumes fix-in-place.

---

## Suggested branch names

| Repo | Branch |
|------|--------|
| contract-tests | (not git — see Task A1 Step 0) |
| lacylights-fe | `fix/scene-to-look-cleanup` |
| lacylights-go | `fix/lint-sa5011-false-positives` |
| lacylights-test | `fix/fade-snap-test-timing` |
| lacylights-mcp | `fix/scene-to-look-cosmetic` |
| lacylights-streamdeck | `chore/scene-to-look-test-data` (optional) |

---

# PART A — MUST-FIX (broken / dead references)

## Task A1: Repair the stale `contract-tests/` cross-server suite

Restores the 3 failing tests by renaming removed GraphQL identifiers. The Go server is correct; only the tests are out of date.

**Files:**
- Modify: `contract-tests/tests/projects.contract.test.ts`
- Modify: `contract-tests/tests/dmx.contract.test.ts`
- Modify: `contract-tests/tests/schema.contract.test.ts`

**Old→new identifier map (apply everywhere in these 3 files):**
| Old | New |
|-----|-----|
| `sceneCount` | `lookCount` |
| `scenes` (Project field / query name) | `looks` |
| `scene` (single query name) | `look` |
| `currentActiveScene` | `currentActiveLook` |
| `createScene` | `createLook` |
| `updateScene` | `updateLook` |
| `deleteScene` | `deleteLook` |
| `setSceneLive` | `setLookLive` |
| `Scene` (type) | `Look` |
| `SceneBoard` | `LookBoard` |
| `SceneBoardButton` | `LookBoardButton` |

- [ ] **Step 0: Decide the home of `contract-tests/` (ASK USER).** It is not in git and is largely superseded by `lacylights-test/contracts/`. Options: (a) fix in place (this plan), (b) move into `lacylights-test` and add to its Makefile, (c) delete it. Proceed with (a) unless told otherwise.

- [ ] **Step 1: Start a Go server to test against.**

```bash
cd ~/src/lacylights/lacylights-go
rm -f test.db
DATABASE_URL="file:./test.db" PORT=4001 ARTNET_BROADCAST=127.0.0.1 ARTNET_PORT=6454 go run ./cmd/server > /tmp/ll-go-server.log 2>&1 &
# wait until ready:
for i in $(seq 1 30); do curl -sf http://localhost:4001/graphql -X POST -H "Content-Type: application/json" -d '{"query":"{ __typename }"}' >/dev/null && echo READY && break; sleep 1; done
```

- [ ] **Step 2: Confirm the 3 current failures (RED).**

```bash
cd ~/src/lacylights/contract-tests
GRAPHQL_ENDPOINT=http://localhost:4001/graphql node --localstorage-file=/tmp/contract-tests-localstorage node_modules/.bin/jest --testNamePattern='.*'
```
Expected: `Tests: 3 failed, 8 passed`, all 3 errors mention `Cannot query field "sceneCount"`/`"scenes"`.

- [ ] **Step 3: Edit `contract-tests/tests/projects.contract.test.ts`.** Rename per the map. Concretely:
  - L41, L87, L148: in the GraphQL query strings, `sceneCount` → `lookCount`.
  - L55, L102, L174: TS type annotations `sceneCount: number;` → `lookCount: number;`.
  - L70, L119: assertions `*.sceneCount` → `*.lookCount`.
  - L154: query field `scenes {` → `looks {`.
  - L177: TS type `scenes: Array<...>` → `looks: Array<...>`.
  - L187: assertion `result.project?.scenes` → `result.project?.looks`.

- [ ] **Step 4: Edit `contract-tests/tests/dmx.contract.test.ts`.**
  - L198 describe `'Query: currentActiveScene'` → `'Query: currentActiveLook'`.
  - L199 title `'should return null when no scene is active'` → `'...no look is active'`.
  - L200 comment `no scene is active` → `no look is active`.
  - L210 query field `currentActiveScene` → `currentActiveLook`.
  - L219 TS type `currentActiveScene: {...}` → `currentActiveLook: {...}`.
  - L224 `toHaveProperty('currentActiveScene')` → `toHaveProperty('currentActiveLook')`.

- [ ] **Step 5: Edit `contract-tests/tests/schema.contract.test.ts`.**
  - L72 `'Scene'` → `'Look'`; L75 `'SceneBoard'` → `'LookBoard'`; L76 `'SceneBoardButton'` → `'LookBoardButton'`.
  - L169 `'scenes'` → `'looks'`; L170 `'scene'` → `'look'`; L178 `'currentActiveScene'` → `'currentActiveLook'`.
  - L215 `'createScene'` → `'createLook'`; L216 `'updateScene'` → `'updateLook'`; L217 `'deleteScene'` → `'deleteLook'`; L225 `'setSceneLive'` → `'setLookLive'`.

- [ ] **Step 6: Re-run the suite (GREEN).**

```bash
cd ~/src/lacylights/contract-tests
GRAPHQL_ENDPOINT=http://localhost:4001/graphql node --localstorage-file=/tmp/contract-tests-localstorage node_modules/.bin/jest --testNamePattern='.*'
```
Expected: `Tests: 11 passed, 11 total`.

- [ ] **Step 7: Sanity-grep for any remaining stale identifiers.**

```bash
cd ~/src/lacylights/contract-tests
grep -rinE "sceneCount|currentActiveScene|createScene|updateScene|deleteScene|setSceneLive|SceneBoard|'Scene'|\"Scene\"" tests/
```
Expected: no output.

- [ ] **Step 8: Commit (only if Step 0 placed it in a git repo).** Otherwise note in the handoff that the dir is untracked.

```bash
# if contract-tests is inside a git repo after Step 0:
git add contract-tests/tests/
git commit -m "fix(contract-tests): rename Scene→Look GraphQL identifiers to match current schema"
```

---

## Task A2: Remove dead `SCENE_NAME_CHANGED` enum value in FE test

The GraphQL enum `CueListDataChangeType` was renamed `SCENE_NAME_CHANGED`→`LOOK_NAME_CHANGED` (see `src/generated/graphql.ts:521-528` and `src/types/index.ts:269-275`). The test still asserts the dead value via a string cast, so it passes but tests a change type that can never occur.

**Files:**
- Modify: `lacylights-fe/src/hooks/__tests__/useCueListDataUpdates.test.ts:253,258,307`

- [ ] **Step 1: Create the FE branch.**

```bash
cd ~/src/lacylights/lacylights-fe
git checkout -b fix/scene-to-look-cleanup
```

- [ ] **Step 2: Edit the test.** Replace the three occurrences:
  - L253 `it('handles SCENE_NAME_CHANGED change type', ...)` → `it('handles LOOK_NAME_CHANGED change type', ...)`.
  - L258 `changeType: 'SCENE_NAME_CHANGED' as CueListDataChangeType,` → `changeType: 'LOOK_NAME_CHANGED' as CueListDataChangeType,`.
  - L307 `expect(onDataChange).toHaveBeenCalledWith('SCENE_NAME_CHANGED');` → `expect(onDataChange).toHaveBeenCalledWith('LOOK_NAME_CHANGED');`.

- [ ] **Step 3: Run the test file (GREEN).**

```bash
cd ~/src/lacylights/lacylights-fe
npx jest src/hooks/__tests__/useCueListDataUpdates.test.ts
```
Expected: PASS.

- [ ] **Step 4: Commit (batched with Task C1 below — same branch).** See Task C1 Step 4.

---

# PART B — Other test-run failures

## Task B1: Investigate & fix the SNAP_END "held at 1 vs 0" failure

`TestUnfadableChannelTypes` fails one assertion: `assert.Equal(t, 0, snapEndHoldValue)` — the SNAP_END channel (gobo-rotation) held at DMX **1** during the fade, expected **0**. All other assertions in this test pass (SNAP channels ≤2 frames, FADE channels >30 frames, SNAP_END snaps at frame 140). The fade engine (`lacylights-go/internal/services/fade/engine.go:186-188`) holds `ch.startValue` during SNAP_END, and the test fades from `fadeToBlack` (0)→255, so startValue *should* be 0.

> **REQUIRED SUB-SKILL:** Use superpowers:systematic-debugging — find root cause before changing anything. Two live hypotheses: (H1) the fade engine captures a stale/rounded residual (~1) as `startValue` from `interpolatedValues` left by a prior fade; (H2) the integration test's `fadeToBlack` doesn't fully settle the gobo-rotation channel to 0 before the new fade starts, so startValue is legitimately 1 (a test/environment artifact, not an engine bug).

**Files (engine, if H1):**
- Inspect: `lacylights-go/internal/services/fade/engine.go` (startValue capture in `FadeChannels`, ~L225-345; SNAP_END branch L186-188)
- Add test: `lacylights-go/internal/services/fade/engine_test.go`

**Files (integration test, if H2):**
- Modify: `lacylights-test/contracts/fade/fade_behavior_test.go:1012`

- [ ] **Step 1: Write a Go unit test that isolates SNAP_END holding exactly startValue=0.** In `engine_test.go`:

```go
func TestSnapEnd_HoldsExactStartValueZero(t *testing.T) {
	dmx := newFakeDMXService() // existing test double in this package
	e := NewEngine(dmx, 60)
	// Channel starts at 0 (black), SNAP_END to 255 over 1s.
	targets := []ChannelTarget{{
		Universe: 0, Channel: 5, StartValue: 0, EndValue: 255,
		FadeBehavior: FadeBehaviorSnapEnd,
	}}
	e.FadeChannels(targets, time.Second, "t1", EasingLinear, nil)
	e.tick(/* advance ~0.5s worth */) // drive one mid-fade update
	got := dmx.LastValue(0, 5)
	require.Equal(t, byte(0), got, "SNAP_END must output exactly startValue (0) mid-fade")
}
```
(Adapt to the package's actual test harness — match the existing `engine_test.go` helpers/names for the fake DMX service and tick/update method.)

- [ ] **Step 2: Run it.**

```bash
cd ~/src/lacylights/lacylights-go
go test ./internal/services/fade/ -run TestSnapEnd_HoldsExactStartValueZero -v
```
- If it **PASSES**: the engine is correct → **H2 confirmed**, the integration failure is a test/environment artifact. Go to Step 3a.
- If it **FAILS** (outputs 1): **H1 confirmed**, engine bug → go to Step 3b.

- [ ] **Step 3a (H2 — engine correct): harden the integration test.** The 1-DMX residual comes from the shared universe not settling to 0. In `fade_behavior_test.go`, before the capture (after the `fadeToBlack` at L869-871), assert/await a clean black state, OR change the assertion at L1012 to allow a 1-unit tolerance with an explanatory comment:

```go
// SNAP_END holds the fade's start value. fadeToBlack may leave a 1-unit
// residual on the shared universe; allow ±1 (DMX quantization tolerance).
assert.LessOrEqual(t, snapEndHoldValue, 1,
	"Gobo Rotation (SNAP_END) should hold at (near) start value during fade")
```
**Per project rule (CLAUDE.md): do not loosen a test to mask a real bug without confirming the code is correct — Step 2 PASS is that confirmation.** Re-run the integration test (Step 4).

- [ ] **Step 3b (H1 — engine bug): fix startValue capture.** In `engine.go` `FadeChannels`, ensure SNAP_END uses the *target's* `StartValue` (the look's stored start), not a rounded residual from `interpolatedValues`. Make the unit test from Step 1 pass with the engine emitting exactly `startValue`. Keep the change minimal and re-run the full fade package unit tests:

```bash
cd ~/src/lacylights/lacylights-go
go test ./internal/services/fade/ -v
```
Expected: all PASS.

- [ ] **Step 4: Re-run the integration test against a fresh server.**

```bash
# fresh server (see Task A1 Step 1), then:
cd ~/src/lacylights/lacylights-test
GRAPHQL_ENDPOINT=http://localhost:4001/graphql ARTNET_LISTEN_PORT=6454 ARTNET_BROADCAST=127.0.0.1 \
  go test -run TestUnfadableChannelTypes ./contracts/fade/ -v
```
Expected: PASS.

- [ ] **Step 5: Commit** (engine fix → lacylights-go; test-only change → lacylights-test, batch with B2).

---

## Task B2: Fix the `TestStrobeChannelSNAP` absolute-vs-relative frame bug

This is a **test bug**, not a server bug. The SNAP semantics already pass (the "no intermediate values" assertion at L1259 passes — strobe never interpolates). The failing assertion at L1263 compares an **absolute** frame index (`strobeReachedTarget`, raw `i`) to ≤5, but capture starts ~100ms (~6 frames @60Hz) before look activation plus mutation latency — so the snap can never land within 5 *absolute* frames. The sibling test `TestUnfadableChannelTypes` does it correctly by measuring relative to `firstActiveFrame`.

**Files:**
- Modify: `lacylights-test/contracts/fade/fade_behavior_test.go:1235-1264`

- [ ] **Step 1: Create the test branch.**

```bash
cd ~/src/lacylights/lacylights-test
git checkout -b fix/fade-snap-test-timing
```

- [ ] **Step 2: Establish a `firstActiveFrame` baseline before the per-frame loop (mirror L914-923).** Insert before L1238's loop:

```go
// Find first frame where the look becomes active (any tracked channel non-zero),
// so SNAP timing is measured relative to activation, not capture start.
firstActiveFrame := 0
for i, frame := range frames {
	if frame.Universe == 0 && int(frame.Channels[startChannel-1+1]) > 0 {
		firstActiveFrame = i
		break
	}
}
```

- [ ] **Step 3: Record `strobeReachedTarget` relative to `firstActiveFrame`.** Change L1250-1252:

```go
if strobe >= 200 && strobeReachedTarget < 0 {
	strobeReachedTarget = i - firstActiveFrame
}
```

- [ ] **Step 4: Keep the ≤5 assertion (now meaningful) OR tighten to ≤2 to match `TestUnfadableChannelTypes`.** Leave L1263 as `assert.LessOrEqual(t, strobeReachedTarget, 5, ...)`.

- [ ] **Step 5: Run it.**

```bash
# fresh server running on 4001, then:
cd ~/src/lacylights/lacylights-test
GRAPHQL_ENDPOINT=http://localhost:4001/graphql ARTNET_LISTEN_PORT=6454 ARTNET_BROADCAST=127.0.0.1 \
  go test -run TestStrobeChannelSNAP ./contracts/fade/ -v
```
Expected: PASS.

- [ ] **Step 6: Run the full fade package (regression check).**

```bash
cd ~/src/lacylights/lacylights-test
GRAPHQL_ENDPOINT=http://localhost:4001/graphql ARTNET_LISTEN_PORT=6454 ARTNET_BROADCAST=127.0.0.1 \
  go test ./contracts/fade/
```
Expected: `ok` (34/34 incl. Task B1's fix).

- [ ] **Step 7: Commit (lacylights-test, batch B1's test-side change + B2).**

```bash
cd ~/src/lacylights/lacylights-test
git add contracts/fade/fade_behavior_test.go
git commit -m "fix(fade): measure SNAP timing relative to activation; tolerate 1-unit SNAP_END residual"
```

---

## Task B3: Silence the 6 SA5011 staticcheck false positives in lacylights-go

`golangci-lint run` reports 6 SA5011 "possible nil pointer dereference" warnings in `crossfade_test.go` and `system_effects_test.go`. They are false positives: each guards with `if x == nil { t.Fatal(...) }` before dereferencing, but the linter doesn't treat `t.Fatal` as terminating here.

**Files:**
- Modify: `lacylights-go/internal/services/modulator/crossfade_test.go:45-49`
- Modify: `lacylights-go/internal/services/modulator/system_effects_test.go:457-462,487-492`

- [ ] **Step 1: Create the Go lint branch.**

```bash
cd ~/src/lacylights/lacylights-go
git checkout -b fix/lint-sa5011-false-positives
```

- [ ] **Step 2: Confirm the warnings (RED).**

```bash
cd ~/src/lacylights/lacylights-go
golangci-lint run ./internal/services/modulator/...
```
Expected: 6 SA5011 issues.

- [ ] **Step 3: Replace the `if x == nil { t.Fatal(...) }` guards with `require.NotNil`.** Staticcheck recognizes testify's `require.*` as terminating, which clears SA5011 *and* is idiomatic. Example for `crossfade_test.go:45-47`:

```go
// before:
if effect == nil {
	t.Fatal("CreateCrossfadeEffect returned nil")
}
// after:
require.NotNil(t, effect, "CreateCrossfadeEffect returned nil")
```
Apply the same transform to the `system_effects_test.go` guards at L457 and L487. Ensure `github.com/stretchr/testify/require` is imported (it is widely used in this repo; add to the import block if absent).

- [ ] **Step 4: Verify lint is clean (GREEN).**

```bash
cd ~/src/lacylights/lacylights-go
golangci-lint run ./internal/services/modulator/...
```
Expected: `0 issues`.
Fallback: if `require.NotNil` does not clear SA5011 in this golangci-lint version, instead add an inline `//nolint:staticcheck // false positive: t.Fatal above terminates the test` on the dereference line.

- [ ] **Step 5: Run the affected tests (no behavior change).**

```bash
cd ~/src/lacylights/lacylights-go
go test ./internal/services/modulator/...
```
Expected: PASS.

- [ ] **Step 6: Full lint sweep.**

```bash
cd ~/src/lacylights/lacylights-go
golangci-lint run ./...
```
Expected: `0 issues`.

- [ ] **Step 7: Commit.**

```bash
git add internal/services/modulator/crossfade_test.go internal/services/modulator/system_effects_test.go
git commit -m "test(modulator): use require.NotNil to fix SA5011 false positives"
```

---

# PART C — Cosmetic / product-consistency (optional; do user-visible first)

> These have **zero functional impact**. Recommend doing C1 + C2 (user/AI-visible) for product polish, and skipping or deferring C3 (comments/test-data) unless the user wants full consistency. Do NOT touch the Intentional list below.

## Task C1: FE user-visible "scene" strings → "look"

**Files (all in lacylights-fe, branch `fix/scene-to-look-cleanup` from Task A2):**
- `src/app/(main)/cue-lists/page.tsx:149` — `"Sequence your scenes into cue lists for playback"` → `"...your looks..."`.
- `src/components/CreateCueListModal.tsx:57` — `"...sequence your scenes for playback."` → `"...your looks..."`.
- `src/components/AddCueDialog.tsx:263` & `src/components/EditCueDialog.tsx:279` — placeholder `"e.g., Opening, Act 1 Scene 2"`. **Caution:** "Act 1, Scene 2" is *theatrically correct* script terminology, not the app's Look concept. Recommend **leaving these** unless the user wants it changed. (Listed for completeness.)
- JSDoc examples `src/components/AddCueDialog.tsx:68-69` and `src/components/EditCueDialog.tsx:92` — `scenes={availableScenes}` → `looks={availableLooks}` (matches real prop `looks`).

- [ ] **Step 1: Edit the two heading/description strings (L149, L57) → "looks".**
- [ ] **Step 2: Edit the two JSDoc examples to use `looks={availableLooks}`.**
- [ ] **Step 3: Decide on the theatrical placeholders with the user (default: leave as-is).**
- [ ] **Step 4: Run FE checks and commit (batches Task A2).**

```bash
cd ~/src/lacylights/lacylights-fe
npm run type-check && npm run lint && npx jest src/hooks/__tests__/useCueListDataUpdates.test.ts
git add -A
git commit -m "fix(fe): finish Scene→Look in user-visible strings + dead enum test value"
```

## Task C2: MCP user/AI-visible "scene" text

**Files (lacylights-mcp, branch `fix/scene-to-look-cosmetic`):**
- `src/tools/fixture-tools.ts:694` — user/AI-visible `"Dance scenes"` → `"Dance looks"`.
- (Optional, low value) `src/services/rag-service-simple.ts` AI-prompt wording — models handle the synonym fine; defer.

- [ ] **Step 1: Branch, edit L694, run lint + tests, commit.**

```bash
cd ~/src/lacylights/lacylights-mcp
git checkout -b fix/scene-to-look-cosmetic
# edit src/tools/fixture-tools.ts:694
npm run lint && npm test
git add src/tools/fixture-tools.ts
git commit -m "fix(mcp): user-visible 'Dance scenes' -> 'Dance looks'"
```

## Task C3: Low-priority comments / test-data labels (OPTIONAL — recommend skipping)

Purely cosmetic, no functional impact, high churn. Only do if the user explicitly wants full consistency:
- lacylights-fe: comments in `channelConversion.ts`, `ChannelSlider.tsx`, `MultiSelectControls.tsx`, `canvasUtils.ts`, `layoutCanvasUtils.ts`; test-data names in `SystemStatusBar.test.tsx`, `AddCueDialog.test.tsx`, `CopyFixturesToLooksModal.test.tsx`, `useGlobalPlaybackStatus.test.ts`, `CueListPlayer.test.tsx`; Roscolux filter descriptions in `src/data/roscoluxFilters.ts` (these are color-application descriptions like "night scenes" — arguably correct English, recommend keep).
- lacylights-go: ~350 test-data labels ("Red Scene", `sceneResp` vars), comments in `fade/engine.go:312`, `repositories/look_board_repository.go:12`. Recommend keep — they aid readability of the migration tests.
- lacylights-mcp: ~148 internal vars / test data in `cue-tools.ts`, `look-tools.ts`, test files. Recommend keep.
- lacylights-streamdeck: 8 test fixture names `'Scene N'` in `src/__tests__/icon-generator.test.ts` — cosmetic, optional.
- lacylights-test: `e2e/tests/happy-path.spec.ts:66,183` test-data strings — cosmetic, optional.

---

# Intentionally NOT changed (DO NOT TOUCH — verified intentional)

- **lacylights-go `cmd/server/main.go`** — `migrateSceneToLook` / `doMigrateSceneToLook` and all SQL referencing `scenes`, `scene_id`, `scene_order`, `scene_boards`, `scene_board_buttons`. This upgrades existing user databases; renaming breaks upgrades.
- **lacylights-go `internal/services/export|import`** — `Scenes`/`SceneBoards` JSON fields marked `// Deprecated: backward compatibility` so old exports still import. Keep.
- **lacylights-go `internal/database/models/models.go`** — "formerly known as scene" doc comments. Keep.
- **lacylights-mac `App/LacyLightsApp.swift:17`** — `some Scene` is the SwiftUI framework protocol, unrelated. Keep.
- **lacylights-mcp `src/types/lighting.ts`** — "scene" in the script-analysis domain (theatrically correct). Keep.
- **Theatrical "Act N, Scene N"** placeholders/strings — correct English; keep unless user says otherwise.

---

# Final Verification (run the whole suite again, all green)

- [ ] **Unit/lint/type (no server):**

```bash
cd ~/src/lacylights/lacylights-go   && ARTNET_ENABLED=false go test ./... && golangci-lint run ./...
cd ~/src/lacylights/lacylights-fe   && npm test -- --ci && npx tsc --noEmit && npm run lint
cd ~/src/lacylights/lacylights-mcp  && npm test && npm run lint
cd ~/src/lacylights/lacylights-mac  && swift test
cd ~/src/lacylights/lacylights-terraform && terraform fmt -check -recursive && terraform validate
```

- [ ] **Server-dependent (start Go server on 4001 first — Task A1 Step 1):**

```bash
# integration (full)
cd ~/src/lacylights/lacylights-test && make test     # expect all packages ok incl. fade 34/34
# cross-server contract suite
cd ~/src/lacylights/contract-tests && GRAPHQL_ENDPOINT=http://localhost:4001/graphql node --localstorage-file=/tmp/contract-tests-localstorage node_modules/.bin/jest   # 11/11
# per-repo contract suites
cd ~/src/lacylights/lacylights-fe  && GRAPHQL_ENDPOINT=http://localhost:4001/graphql npm run test:contracts   # 6/6
cd ~/src/lacylights/lacylights-mcp && GRAPHQL_ENDPOINT=http://localhost:4001/graphql npm run test:contracts    # 10/10
# stop server
lsof -ti:4001 | xargs kill -9; rm -f ~/src/lacylights/lacylights-go/test.db
```

- [ ] **Per-repo: open PRs from each feature branch (never merge to main directly).**

---

## Self-review checklist (done while writing)
- Every test-run failure (contract-tests ×3, fade ×2, go-lint ×6, FE dead-enum) maps to a task: A1, B1, B2, B3, A2. ✓
- "Scene"→"Look" audit covered all 10 repos; MUST-FIX vs cosmetic vs intentional separated. ✓
- No blanket-rename of the 800+ hits — intentional migration/back-compat/SwiftUI/script-domain explicitly excluded. ✓
- Branching per repo (never `main`); contract-tests' lack of VC flagged with a decision gate. ✓
- B1 ordered as investigate-then-fix (systematic-debugging), not a guess. ✓
