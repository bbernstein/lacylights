# Import/Export (#175): follow-up plan

**Written:** 2026-10-12, at the end of the session that merged every #175 PR. **Last updated:** 2026-10-14.
**Purpose:** a starting point for future sessions. Each item below has a GitHub issue; the issue has the full detail. This doc adds suggested order, dependencies, and how to start.

## Where things stand (2026-10-14)

### Released versions; every checkout is on `main` and up to date
| Repo | Version | Note |
|---|---|---|
| lacylights-go | **v0.4.1** | OFL import fix (go#85) + ref_id test indexes (go#86). Release notes tell users to re-import fixtures. |
| lacylights-fe | **v0.10.0** | `main` matches the release. |
| lacylights-mac | **v1.3.6** | Native binary save (mac#42) + `.asc` file picker fix (mac#43). |
| lacylights-mcp | v1.6.16 | **19 unreleased commits on `main`**, including the data-export tools (mcp#200) and the Eos query export. **An MCP release is needed** before the Mac app gets them. Ask the user first. |
| lacylights-rpi | v0.2.19 | 3 unreleased commits (device auth #72, docs). |

### Done since 2026-10-12
- **go#85**: PR go#89. OFL import failures went from 269 to 0.
- **go#86**: PR go#90. Option (a): test helpers now set RefID; no production change.
- **mcp#199**: PR mcp#200.
- **mac#43**: PR mac#44. The native open panel takes its types from `<input accept>` through the JS bridge.
- **Mac releases**:
  - v1.3.5 needed a renewed Developer ID cert.
  - Tags v1.3.3 and v1.3.4 belong to failed runs and have no releases.

### Suggested order (agreed starting point, 2026-10-14 session 3)
Live check on 2026-10-14: the branch cleanup is done (only the 5 June-7 branches remain), `lacylights-mac-wt-43/` is gone, and every checkout is clean on `main` except terraform's untracked files.

1. **Quick wins (one session, in parallel):**
   - Terraform: add `*.tfstate*` and `.build/` to `.gitignore` (PR).
   - Open PRs for the 5 June-7 branches. Rebase each on `main` first. `fix/snap-end-startvalue` together with test `fix/fade-snap-test-timing` should remove the fade flake, which makes CI quieter for everything after it.
2. **go#91: `.qxw` import fails.** This bug is visible to users. It needs the UI error, `~/Library/Logs/LacyLights/backend.log` or the `.qxw` file from the user.
3. **MCP release**, which needs the user's OK.
   - First triage **mcp#176** ("MCP Server does not start on Mac with bundled application"). It was opened 2026-03-09 against Mac 1.3.2 and has 1 comment. Check whether it still reproduces on Mac v1.3.6, because the release only helps if the bundled MCP starts.
   - Then release MCP (19 commits).
4. **Dependabot backlog:**
   - mcp has 9 PRs (#187–#195): actions bumps to v7, @apollo/client 4.2, graphql 16.14 and others. Batch them into one PR after the MCP release.
   - fe#176 (18 npm updates) fails lint/type-check, contract-tests and claude-review. Investigate it separately.
5. **fe#180:** manual touch QA. The user can do it any time it's convenient.
6. **fe#179:** the go part, then a go release, then fe.
7. **go#88:** only with the public demo work.
8. **go#87:** last, after the deployed versions are confirmed.
9. **Calendar:** the Mac Developer ID cert expires 2027-02-01. Start the renewal by mid-January.

### Orchestrated execution (started 2026-10-14, session 3)
The user asked to work every item above in parallel, with agents.

**Phase 1** (workflow run `wf_6125ed31-bc5`, script `lacylights-followups-phase1`):
- Each item gets a worktree at `<repo>-wt-<slug>` under the project root, then a PR, then an independent review agent, then a Copilot review request.
- No merges and no releases.
- Built-in dependencies:
  - fe#179: the go agent runs first, then the fe and test agents. The test PR is a draft.
  - go#87: the fe, mcp, go and test PRs are all drafts marked "[DO NOT MERGE before go#87 rollout]". A separate readiness check runs alongside them.
  - MCP release: a readiness report only. The release itself needs the user's OK.
  - go#88: Part 1 (opt-in env limits) gets a PR. Part 2 (streaming) is measured but not implemented.
- Local backend ports are assigned per agent to avoid clashes: go91 4110, fe180 4120/3120, fe179 4130, go88 4140, snap 4115.

**Decisions from the user (2026-10-14):**
- **MCP release:** show the readiness report and the mcp#176 triage first, then get the user's final OK before triggering `release.yml`.
- **go#91:** the real failing file is `funhome-2025-09-14.qxw` in the project root. It contains a personal name, so **never commit it**; fixtures must be sanitized. A separate agent is reproducing the bug with it.
- **Cert reminder:** DONE. A Google Calendar event is set for 2027-01-15 (item 9).

**go#91 root cause (reproduced with the real file, 2026-10-14):**
- **The cause:** QLC+ import was **never implemented in Go**. `ImportProjectFromQlc` (`internal/graphql/resolvers/schema.resolvers.go:~4600`) has been a stub since the initial commit. It returns "QLC+ import not available on this platform" for any input, on both v0.4.1 and main.
- **Why CI missed it:** the contract tests in lacylights-test (`contracts/importexport/importexport_test.go:~588` and `~676`) `t.Skip` on "not available".
- **QLC+ export (`project_export_helpers.go:117`) is a stub too.** It needs its own issue; ask the user before opening one.
- **The fe needs no change:** it sends the raw XML, and parsing is server-side.
- **Requirements from the real file** (QLC+ 4.13.1):
  - 15 fixtures with no exact OFL match:
    - Chauvet "SlimPAR Pro Q USB", mode "4 Channel": OFL only has the QZ12.
    - ETC "ColorSource PAR", mode "3-channel (RGB)": in OFL the mode is named "RGB".
    - The importer needs channel-count or fuzzy matching, plus a generic fallback with warnings.
  - 99 Scenes become Looks, and 3 Chasers with 182 steps become cue lists.
  - `Hold="4294967294"` (0xFFFFFFFE, infinite) appears on 180 steps. It must be parsed as uint32 or int64 and mapped to "no follow".
  - Scenes are reused across steps. Addresses are 0-based.
  - Ignore the IO map, VirtualConsole and SimpleDesk sections.
- **Sanitized minimal fixture:** `scratchpad/go91-real/out/minimal.qxw` (the session scratchpad).
- **Phase-2 check:** an agent must import the real file through the new importer on a local backend and confirm 15 fixtures, 99 looks, 3 cue lists, 182 cues and the correct holds.
- **Contract tests:** the importexport contract test must stop skipping on "not available" for import.

**User decision (2026-10-14): defer QLC+ import/export to a separate future effort.**
- DONE: the go issue is **go#97** (Node pointers, format/mapping, fixture matching, Go design, test plan; §5 and §8 are in its first comment because of GitHub's body size limit).
- Whatever the go#91 agent produces in phase 1 becomes a **draft head-start PR** linked from the new issue. It is **excluded from phase-2 iteration**.
- go#91 **stays open** (user decision). DONE: a comment on go#91 links to #97, and the draft head start go#95 now says "Refs #91" and links #97.

**Phase 1 results (completed 2026-10-14; 39 agents, 0 errors):**
| Item | PR(s) | Notes |
|---|---|---|
| terraform `.gitignore` | terraform#14 | |
| June-7 fade snap | go#96, test#31 | test#31 merges after go#96. The flake fix is a frame/retire race fix (2/430 failures down to 0/430). |
| June-7 golangci | none | Not needed: lint is clean on main, and the exclusion would hide real bugs. The local branch and worktree `lacylights-go-wt-golangci-sa5011` are kept. Ask the user whether to delete them. |
| June-7 fe scene→look | fe#181 | |
| June-7 mcp scene→look | mcp#201 | |
| go#91 `.qxw` | go#95 (**DRAFT head start**) | Full Go QLC+ importer. Body changed to "Refs #91". Excluded from phase 2. |
| mcp#176 | mcp#203 | Two real defects: `run-mcp.js` missing from the tarball, and an OPENAI_API_KEY problem. Needs an MCP release. A Mac UX issue remains: the MCP status card is always grey. |
| MCP release readiness | none | Ready as v1.7.0 (minor): `gh workflow run release.yml -R bbernstein/lacylights-mcp --ref main -f version_bump=minor -f is_prerelease=false`. A CheckDevice `lastSeen` bug should be fixed first (phase 2 PR). Older broken tools: the 7 `bulk_delete_*` tools and `set_fade_update_rate`. |
| mcp deps | mcp#202 | Merge after the MCP release, then close #187–#195. |
| fe#176 deps | fe#183 | 4 unlisted major bumps were reverted. Close #176 after #183 merges. |
| fe#180 touch QA | fe#185, test#32 | test#32 merges after fe#185. Real-device QA remains. |
| fe#179 | go#92, fe#184, test#30 (draft) | Order: go#92, then the go release, then fe#184. test#30 waits for go#92. |
| go#88 | go#94 | Part 1 env limits. Part 2 measured: data exports are small; only project JSON is large (about 6.6× its file size in RAM). |
| go#87 | fe#182, mcp#204, go#93, test#29 (all **DRAFT**) | NO-GO for now. The public demo at app.lacylights.com runs go v0.3.0. |

**Phase 2** (workflow `wf_cf96796c-2a9`): iterates the 13 non-draft PRs and adds a new mcp PR for the CheckDevice `lastSeenAt` fix.

**Phase 2 results (completed 2026-10-14):**
- **Ready for merge** (CI green, Copilot reviewed the latest commit, 0 open threads, CLEAN, "ready" comment posted): terraform#14, go#96, go#92, go#94, fe#181, fe#183, fe#184, mcp#201, mcp#203, mcp#205 (new: CheckDevice `lastSeenAt`), mcp#202.
- **test#31:** green and CLEAN, but merge it only after go#96 and a go release.
- **fe#185:** needs the user to decide on `justOpenedRef` (Copilot thread PRRT_kwDOO7ol0s6sW1VQ is open). It also needs approval for an `any-pointer:coarse` test-assertion edit.
- **test#32:** its e2e check fails until fe#185 merges. Then rerun run 38584388257.

**Merge order:**
1. Any order: terraform#14, go#96, go#92, go#94, fe#181, fe#183 (then close fe#176), mcp#201, mcp#203, mcp#205.
2. **go release** (contains #92, #94 and #96). Then merge test#31 and fe#184. Take test#30 out of draft and rerun its CI.
3. **MCP v1.7.0 release** (after #201, #203 and #205). Then merge mcp#202 and close dependabot #187–#195.
4. fe#185 (after the user's decision), then rerun e2e on test#32, then merge test#32.
5. An **fe release** (#181, #183, #184 and #185), so Mac and Pi users get them.

Later merges may leave other PRs behind main. Re-check them, and rebase if needed, before each merge.

**User decisions (2026-10-14, after phase 2):**
- **Test edits on fe#181, fe#184 and fe#185:** APPROVED.
- **`justOpenedRef`:** REMOVE. Phase 3 (`wf_ca928336-f4c`) is doing it on fe#185.
- **Follow-up issues:** open all of them. Phase 3 is filing 16 after verifying each one.
- **Public demo:** rebuild it.
  - It ran go v0.3.0. The in-place `scripts/deploy-app.sh` keeps the database.
  - The auto-mode classifier blocked remote SSM writes, so **the user runs the backup and deploy**.
- **Lint-exclusion branch and worktree:** DELETED.
- **`.terraform.lock.hcl`:** stays untracked.
- **mcp#176:** reply POSTED.
- **go#88 Part 2:** CLOSED (won't do; a comment on #88 has the measurements). go#94 now says "Fixes #88".
- **go#96:** MERGED on 2026-10-14 (squash `b16bb2f`). Its worktree and local branch are removed. test#31 now waits only on a go release. go#92 MERGED (`987d192`). go#94 MERGED (`e2ba95b`) and closed #88. go `main` is now 3 commits ahead of v0.4.1, so a **go release is the next step** (needs the user's OK). It unblocks test#31 and fe#184.

**Phase 3 results (2026-10-14):**
- **fe#185:** `justOpenedRef` removed. Ready for merge (CLEAN, Copilot clean). Merge it before test#32, then rerun test#32's e2e.
- **16 follow-up issues filed:**
  - mcp: #206 (device auto-registration; land with/after #205 and before v1.7.0), #207 (release Node 20), #208 (validate ops against the go schema; 9 of 104 ops invalid), #209 (bulk_delete_* and fade-rate tools).
  - go: #98 (`Project.lookBoards` empty), #99 (effect intensity fades can leave an effect stuck forever: a real clock-read race), #100 (dmx coverage flake).
  - mac: #45 (MCP card always grey).
  - fe: #186 (release Node 20), #187 (codegen 7), #188 (ContextMenu height-only resize), #189 (Tailwind 4), #190 (Export menu under the bottom nav on cue list and look editor), #191 (claude-review fails on Dependabot PRs, also in go and mcp), #192 (Next 16).
  - terraform: #15 (`*.tfvars.json` and others not ignored).

**Phase 2 follow-ups (now filed, see above):**
- mcp device auto-registration gap: for an unregistered device, the backend returns PENDING with device null, and `checkDeviceStatus` never registers it.
- go `internal/services/dmx` coverage is flaky in CI (86.4% vs the 88% threshold).
- fe `release.yml` uses Node 20 (EOL), and `eslint-config-next` 15.0.3 is behind.
- go#96: confirm that interrupting a fade drops the old SNAP_END target (this matches the legacy engine). an iteration workflow that addresses Copilot and CI feedback until each PR is ready for merge, per the global CLAUDE.md rules. After that, the user merges in dependency order and approves the releases.

### Open loose ends
1. **DONE (verified 2026-10-14): local branch cleanup.** About 55 squash-merged local branches are left. The auto-mode classifier blocked `git branch -D`, so the user needs to run `sh docs/plans/2026-10-14-delete-merged-branches.sh`. If the branch list has changed since, regenerate the script:
   - Take every local branch except `main` and the 5 below.
   - Before deleting, check that each one's PR is MERGED and that its tip equals the PR's `headRefOid`.
   - Also remove the leftover `lacylights-mac-wt-43/` folder, which only contains `.swiftpm`.
2. **Five unmerged branches from 2026-06-07** (one commit each, no PR). **Keep them** and ask the user whether to open PRs. All checkouts were moved off them to `main`.
   - go `fix/snap-end-startvalue`: implements SNAP_END fade behavior. Probably fixes the `TestFadeToLook_SnapEnd` / `TestLookBoardFadeBehavior` 199-vs-200 flake.
   - go `fix/golangci-exclude-sa5011-tests`: lint config change.
   - fe `fix/scene-to-look-cleanup` and mcp `fix/scene-to-look-cosmetic`: Scene→Look wording changes.
   - test `fix/fade-snap-test-timing`: SNAP timing test fix.
   - See `2026-06-07-scene-to-look-cleanup-and-test-fixes.md`.
3. **The MCP release** (see the table above).
4. **lacylights-terraform** has an untracked `terraform.tfstate.*.backup` and `.build/`. Suggest adding `*.tfstate*` to `.gitignore`, since tfstate may contain secrets. **Never commit them.**
5. **The Mac Developer ID cert expires 2027-02-01** (fingerprint <redacted>).
   - Renew it and update the `MACOS_CERTIFICATE` and `MACOS_CERTIFICATE_PWD` secrets in lacylights-mac.
   - Export the **Developer ID Application** entry; the user exported "Apple Development" by mistake twice.
   - Before releasing, check the cert with a throwaway `push`-triggered workflow on a temp branch, because `release.yml` tags the version before it signs.
6. **New work goes in a `git worktree add` off `origin/main`.** Delete the worktree after its PR merges.

History: `2026-10-12-import-export-handoff.md` (with the session 2 log) and `2026-10-12-import-export-progress.md`.

## Follow-up issues

| # | Issue | Repo(s) | Size | Priority | Depends on |
|---|---|---|---|---|---|
| ✅ | Mac release, go#85, go#86, mcp#199, mac#43 | — | — | DONE 2026-10-13/14 | — |
| 9 | [lacylights-go#91](https://github.com/bbernstein/lacylights-go/issues/91): QLC+ `.qxw` import fails (Mac app, go v0.4.1; `.json` and `.asc` work) | go or fe (unclear) | S–M | **Next**: a bug users can see | capture the error first (UI message, `~/Library/Logs/LacyLights/backend.log`, or the user's `.qxw` file) |
| 3 | [lacylights-fe#180](https://github.com/bbernstein/lacylights-fe/issues/180): check the Export ▾ and row ⋯ menus on real touch devices | fe | S (QA) | Medium | fe v0.10.0 deployed, or `npm run dev` on the LAN |
| 5 | [lacylights-fe#179](https://github.com/bbernstein/lacylights-fe/issues/179): `scopeRequired` + names-only picker queries | go + fe (+ test) | M | Low | go part first, then a release, then fe |
| 6 | [lacylights-go#88](https://github.com/bbernstein/lacylights-go/issues/88): `EXPORT_MAX_*` env config + streaming endpoint | go (+ fe, mac for streaming) | S / L | Low; Part 1 only with the public demo, Part 2 only if measured as needed | public demo work |
| 7 | [lacylights-go#87](https://github.com/bbernstein/lacylights-go/issues/87): remove the deprecated export Mutations and client fallbacks | fe → mcp → go → test | M | Last | every Mac/Pi deployment on go ≥ 0.4.0 and fe ≥ 0.10.0 |

Some follow-ups were combined. The original list had 8 items plus the Mac release:
- `scopeRequired` and the names-only picker queries became one issue (#179), since both change the same Export panel.
- The env-var size limits and the streaming endpoint became one issue (#88), since both are about very large exports.

## Notes per item

### 1. go#85: OFL validation failures (DONE, go#89)
- Code: `internal/services/ofl/service.go`.
  - `validateOFLFixture` (around line 175) rejects fixtures with no categories or no availableChannels.
  - The mode-channel lookup in `ImportFixture` and `ImportFixtureWithHash` (around lines 141 and 566) rejects channels not found in `availableChannels`.
  - Mode channels are parsed as strings, so object entries, which are OFL matrix insert blocks, fail.
- Failure breakdown, measured 2026-10-12 with the importer's 10-line log cap lifted in a local build:
  - 161: a mode references a channel that isn't in `availableChannels`. Likely causes are template channels (`$pixelKey`), fine-channel aliases (`Dimmer fine`) or `switchChannels`.
  - 91: mode channels are objects (matrix `insert` blocks).
  - 13: no categories.
  - 4: no channels.
- Approach:
  1. Add an importer summary log or debug flag that lists every failure by category.
  2. Resolve fine-channel aliases and `switchChannels` against `availableChannels`.
  3. Expand OFL matrix/template channels, or skip `null` and insert entries in a way that keeps DMX offsets right. Check the OFL schema docs before choosing.
  4. Default missing categories to `Other`.
  5. Skip fixtures with no channels and log them; this is legitimate.
- Test with real OFL JSON fixtures from the bundled library, one per category. Target: the failure count drops sharply on a fresh DB with `OFL_IMPORT_ENABLED=true`. Measure before and after with the e2e approach from go#84.
- Watch out: changing how channels map may change DMX offsets for fixtures that already imported. Only new or updated definitions should be affected; existing instances keep their stored channels.

### 2. go#86: ref_id indexes in the test DB (DONE, go#90)
- Call `migrations.CreateRefIDIndexes` (`internal/database/migrations/refid_migration.go`) from `testutil.SetupTestDB` (`internal/services/testutil/testutil.go`) and from the other shared test setups (repository tests, auth tests).
- Any test that starts failing points at a real create path that skips RefID. If the test itself looks wrong, **ask the user before changing it** (global CLAUDE.md rule).
- Optional: a `BeforeCreate` hook on the 5 models with a unique ref_id. Discuss it with the user first, since no model uses GORM hooks today.

### 3. fe#180: touch-device QA
- This is a manual check, done by the user or with computer-use on a real device. If it finds a bug: use pointer events for outside-click handling, add a unit test, and consider a Playwright mobile-viewport e2e test in lacylights-test.

### 4. mcp#199: data-export MCP tools (DONE, mcp#200; not released yet)
- Tools: `list_data_export_tables`, `export_data_table` and `export_data_workbook`.
  - Return CSV inline, truncated when large.
  - Write XLSX to a file and return its path.
  - On older backends, return an "update LacyLights" message using `isUnknownQueryFieldError` from mcp#197.
- Use `export_eos_ascii` as the pattern.

### 5. fe#179: scopeRequired + picker queries
- Order: add `scopeRequired: Boolean!` in go, with a contract assertion in lacylights-test `dataexport_test.go`, then release go. Then fe drops its hard-coded scope rules (`DataExportPanel`, `ExportMenuButton`) and uses lightweight `id`/`name` picker queries.
- The fe change must tolerate older backends that lack `scopeRequired`, using the same fallback pattern as `backendCompat.ts`.

### 6. go#88: large exports
- **Size limits stay opt-in.** No default caps (memory `feedback_export_size_limits.md`, go#82 decision). Part 1 is env vars that default to unlimited. Part 2 (streaming endpoint) needs measurement first.

### 8. mac#43: Mac file picker rejects `.asc` (DONE, mac#44, v1.3.6)
- Reported 2026-10-13 on Mac v1.3.5. Importing `.asc` files works in the browser, but the Mac app's file picker greys them out.
- Cause: `LacyLights/Controllers/WebViewController.swift`, in `runOpenPanelWith` (around line 320), hard-codes `allowedContentTypes = [.json, qxw]`. It doesn't use the page's `accept` attribute.
- Fix: drop the allow-list, or build it from the input's `accept` through the JS bridge, so future formats work without a Mac change. Pull the type logic out so it can be unit-tested. A Mac release is then needed. The Developer ID cert expires 2027-02-01.

### 7. go#87: remove the deprecated Mutations
- Do this last, and only after confirming what versions are deployed in the field.
- Order:
  1. fe: remove `backendCompat` fallback and `LEGACY_EXPORT_PROJECT*`.
  2. mcp: remove the Eos Mutation fallback.
  3. go: delete the Mutations and run `make generate`.
  4. test: remove `deprecated_export_test.go`.
  5. Coordinated release, called out as a breaking change.

## Process reminders (from the #175 sessions)
- **PR iteration rules** are in the global CLAUDE.md:
  - Iterate until there are no pending reviewers, all threads are resolved, all checks are green and the merge state is CLEAN.
  - Post the "ready for merge" comment.
  - **Never merge without asking.**
  - The user prefers a **Copilot review** before merging. When the Copilot quota is exhausted, re-request it hourly rather than skipping it.
- Run iterations in parallel with agents, one worktree per PR, and have the orchestrator handle cross-repo order.
- Known flakes:
  - go `TestLookBoardFadeBehavior` (199 vs 200)
  - go `internal/middleware` `TestAuthenticate_DeviceWithGroupMemberships` (seen once in CI)
  - lacylights-test `contracts/fade` timing tests
- lacylights-go needs Go 1.25 and golangci-lint v2.6.2. Contract-test workflows in fe, mcp and test build the backend from go `main`.
- Locally, mcp jest fails on Node 25; use Node 22 or 24 (nvm).
- Mac web inspector: `swift run LacyLights`, then **Safari → Develop → <Mac> → LacyLights**. The docked "Inspect Element" inspector renders black when the app runs unbundled. Debug builds set `isInspectable` (mac#42).

**Merges and release (2026-10-14, user-approved):**
- **MERGED:** fe#183 (`68dc5d5`; superseded dependabot fe#176 CLOSED), mcp#203 (`e2a79b2`), terraform#14 (`f6a3faf`). Their worktrees are removed.
- **go v0.5.0:** release triggered (`release.yml`, minor bump, run 38595575278, head `e2ba95b`).
- **Workflow `wf_f3cd5741-216`:**
  - fe lane: update and merge fe#181, then fe#185, then rerun test#32's e2e.
  - mcp lane: update and merge mcp#205, then mcp#201.
  - A release-check agent verifies the v0.5.0 artifacts on GitHub and dist.
- **Not merged yet (need the user's OK):** test#31 and fe#184 (unblocked once v0.5.0 is out); test#32 (after fe#185 and a green e2e); mcp#202 (after the MCP release).

**Completed (2026-10-14, workflow `wf_f3cd5741-216`):**
- **MERGED:** fe#181 (`bbc68d5`), fe#185 (`db0c455`), mcp#205 (`20b0812`), mcp#201 (`566e5aa`). Each was merged at a head with all checks green and a Copilot review of that exact commit. Their worktrees are removed.
- **go v0.5.0 RELEASED** (tag on `e2ba95b`).
  - On dist (`latest.json` and `versions.json`), checksums are verified, and the Mac and RPi pickers list it.
  - No CloudFront invalidation runs after a release, so dist serves stale metadata for up to 5 minutes.
- **test#32:** the e2e rerun PASSED after fe#185 merged. It is ready to merge.

**Remaining (each needs the user's OK):**
1. Merge test#31, fe#184 and test#32. All are unblocked now.
2. Decide on mcp#206 (device registration): fix it before MCP v1.7.0, or after?
3. Release MCP v1.7.0 (`gh workflow run release.yml -R bbernstein/lacylights-mcp --ref main -f version_bump=minor -f is_prerelease=false`). Then merge mcp#202 and close dependabot #187–#195.
4. Release fe (#181, #183, #184 and #185).
5. The user runs the demo backup and `deploy-app.sh`, which now installs go 0.5.0.
6. Leave these drafts as they are: the go#87 drafts, and go#95 (the QLC head start for go#97).

**2026-10-14:** test#31 MERGED (`041ca8d`). Workflow `wf_c6746655-f8f` is updating and merging test#32 and fe#184 (fe#184 conflicts expected with fe#185 in ExportMenuButton).

**2026-10-14 (later):**
- **MERGED:**
  - test#32 (`d4bbfb8`)
  - fe#184 (`bf7315c`). It closed fe#179. Its ExportMenuButton conflict with fe#185 was resolved keeping both sides, and contract tests passed against go v0.5.0.
- **Remaining:**
  - test#30, the draft contract test for scopeRequired: take it out of draft and iterate. go#92 is released.
  - Decide on mcp#206.
  - MCP v1.7.0, then mcp#202 and close dependabot #187–#195.
  - fe release.
  - The user runs the demo deploy.
  - Leave the go#87 drafts and the go#95 draft as they are.

**2026-10-14, user: "fix mcp#206 first, then release MCP v1.7.0".**
- Workflow `wf_1f52171a-16e` implements, reviews, iterates and merges the mcp#206 fix. The merge is user-authorized.
- After it merges, the orchestrator triggers `gh workflow run release.yml -R bbernstein/lacylights-mcp --ref main -f version_bump=minor -f is_prerelease=false` (expected v1.7.0) and verifies dist.
- mcp#202 (deps batch) still needs the user's OK to merge after the release.

**mcp#206 fix: PR mcp#210** (head `b279256`).
- 14/14 checks green, Copilot recommends approval with 0 findings, CLEAN, independently reviewed (2 low issues fixed).
- The merge was BLOCKED by the auto-mode classifier ("Merge Without Review"). It **needs the user's explicit OK** to merge (`gh pr merge 210 -R bbernstein/lacylights-mcp --squash --match-head-commit b279256fdd44505e663cd4aeaa4fcb5f048cb21e`).
- Then: release MCP v1.7.0 and clean up the `lacylights-mcp-wt-mcp206` worktree.
- New follow-up (not filed): go `registerDevice` should treat a unique-fingerprint conflict as "already exists" (race when two MCP processes start at once).

**2026-10-14 (evening): MCP v1.7.0 RELEASED**
- The go `registerDevice` race is filed as go#101. mcp#210 MERGED (`c412e20`), closing mcp#206.
- The first release run (38631498031) FAILED. Its version-bump push to `main` was rejected with GH013, because mcp `main` classic branch protection had `enforce_admins=true` (fe has it false). Nothing was published.
- User OK'd option 1: `enforce_admins` was DISABLED on mcp `main`. PRs and the required checks are still enforced for non-admins.
- The user re-triggered the release (the classifier blocks Claude from running `gh workflow run`). Run 38637229287 succeeded.
- **Verified:**
  - Tag v1.7.0 is on `095242c` ("chore: bump version to 1.7.0", parent `c412e20`).
  - The GitHub release is non-draft with notes and the asset `lacylights-mcp-1.7.0.tar.gz` (8,495,399 bytes).
  - dist `releases/mcp/latest.json` and `versions.json` show 1.7.0, with sha256 `ed06621d…98be7`. The S3 and GitHub tarballs both match it.
  - The tarball contains `lacylights-mcp/run-mcp.js` (the mcp#176 fix), and its package.json says 1.7.0.
- **Remaining (each needs the user's OK):**
  - Comment on and close mcp#176.
  - Merge mcp#202, then close dependabot #187–#195.
  - test#30 out of draft.
  - fe release.
  - The user runs the demo deploy.
  - Leave the go#87 drafts and go#95 as they are.

**2026-10-14 (night):**
- mcp#176 CLOSED, with a comment pointing to v1.7.0.
- mcp#202 MERGED (`f05c05b`) after an update-branch, 13/13 checks green, a Copilot review on `c948411` (0 findings) and state CLEAN.
  - Its new actions (checkout, setup-node, setup-go and codecov, all @v7) are exercised by CI, except in `release.yml`, which first runs at the next MCP release.
- Dependabot #187–#195 closed as superseded.
- The `mcp-deps` worktree and branch were removed.
- **Remaining (needs the user's OK):** test#30 out of draft; fe release; the user runs the demo deploy; leave the go#87 drafts and go#95 as they are.
- **test#30 MERGED** (`d4e683d`). Its worktree and branch are removed.

**2026-10-14: fe v0.11.0 RELEASED** (user OK)
- Run 38643308543 succeeded. Tag v0.11.0 is on `4b87c44` (the bump commit, parent `bf7315c`). It ships fe#181, #183, #184 and #185.
- The GitHub release has two assets: `lacylights-fe-static-v0.11.0.tar.gz` and `lacylights-fe-server-v0.11.0.tar.gz`.
- dist `releases/fe-static/` and `releases/fe-server/` `latest.json` show 0.11.0, and `versions.json` lists 0.11.0 first. The sha256 of the dist and GitHub tarballs match `latest.json` (static `4a47ab5c…`, server `9167f044…`).
- Note: fe 0.11.0's export pickers read `scopeRequired`, which go ≥ 0.5.0 provides.
- **Remaining:** the user runs the demo backup and `deploy-app.sh`, which now installs go 0.5.0 + fe 0.11.0. Leave the go#87 drafts and go#95 parked. The go#87 rollout precondition is still go ≥ 0.4.0 and fe ≥ 0.10.0 everywhere.

**2026-10-14: public demo deployed by the user.** Verified:
- app.lacylights.com `buildInfo` is v0.5.0 (`e2ba95b`), and `dataExportTables` returns `scopeRequired`.
- The frontend build ID matches fe-server v0.11.0's `BUILD_ID`.
- The backup was not independently verified.
- **This initiative's active work is complete.**
- **Parked:**
  - the go#87 drafts (precondition: every deployment runs go ≥ 0.4.0 and fe ≥ 0.10.0)
  - QLC+ (go#97 / go#95 draft)
  - the filed follow-up issues
- **User manual items:** fe#180 real-device touch QA; fade contract tests locally.
