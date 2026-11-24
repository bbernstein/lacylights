# Import/Export (#175): handoff for the next session

> **Superseded:** all PRs are merged and #175 is closed. For future work, see `2026-10-12-import-export-followups.md`.

**Written:** 2026-10-12, end of the implementation and go#82 iteration session.
**Goal for the next session:** merge the remaining PRs in order, iterating each one to green first. Plan: `docs/plans/2026-10-12-import-export-screen.md`. Full history: `docs/plans/2026-10-12-import-export-progress.md`.

## Done
- **lacylights-go#82** (CSV/XLSX data export) was **merged** to `main` on 2026-10-12 as squash commit `6f10dde`.
  - The `feat/data-export` branch was kept on purpose because #83 was stacked on it. It can be deleted once #83 is merged.
  - #82 raised the backend to **Go 1.25**, using **golangci-lint v2.6.2** through `golangci-lint-action@v8`. The bump was needed for excelize v2.11.0, which fixes security advisories.

## Merge order (remaining)

| # | PR | Branch / worktree | State at handoff | What to do |
|---|----|-------------------|------------------|------------|
| 1 | **lacylights-go#83** (projectExport* Queries; deprecate export Mutations) | `feat/project-export-queries` @ `c6e5dd2`, worktree `../lacylights-go-dataexport` (that worktree currently has `feat/data-export` checked out; switch it) | Base was automatically retargeted to `main`. **Merge state DIRTY (conflicts).** Only claude-review has run. 0 unresolved threads. | `git fetch`, check out `feat/project-export-queries`, then rebase onto `origin/main`. Expect conflicts in `schema.graphql`, `generated.go`, `schema.resolvers.go`, `CLAUDE.md` and `go.mod`/`go.sum`. Resolve them, run `make generate`, then `golangci-lint run ./...` and `./scripts/check-coverage.sh` with `ARTNET_ENABLED=false`, and force-push with lease. The branch has 5 commits over main, and the #82 commits in it will drop out because they were squashed. Then iterate the PR (Copilot plus CI) and merge with a squash. |
| 2 | **Release lacylights-go** | n/a | n/a | Run the `release.yml` workflow by hand (it is not automatic). The frontend needs a released backend that has #82 and #83. |
| 3 | **lacylights-fe#177** (/import-export page, Project menu, Manage Projects) | `feat/import-export-page` @ `9d13bcc` (no worktree; use `../lacylights-fe`, which is currently on `feat/data-export-ui`) | All CI passes. **5 unresolved Copilot threads**, listed below. BLOCKED. | Address the threads, request a Copilot re-review, iterate, then merge. |
| 4 | **lacylights-fe#178** (Export data panel, Export ▾ buttons, project exports via Queries) | `feat/data-export-ui` @ `dadeca7`, checked out in `../lacylights-fe` | Base is `feat/import-export-page` (stacked). **contract-tests fail**, most likely because the backend `main` used by CI lacked #83's Queries; re-check after #83 merges. | After #177 merges: rebase onto `main`, retarget to `main`, run codegen against a backend that has #82 and #83, then iterate and merge. Also decide the **old-backend fallback** below. |
| 5 | **lacylights-test#28** (data-export contract tests) | `feat/data-export-contracts` @ `d8580e8`, worktree `../lacylights-test-dataexport` | test and e2e fail because CI builds the backend from `main` and needs #83. Workflow already bumped to Go 1.25. **4 unresolved Copilot threads**, listed below. | Re-run CI after #83 merges, address the threads, then merge. |
| 6 | **lacylights-mcp#197** (Eos export via Query, with fallback to the Mutation) | `feat/project-export-queries` @ `32c1339`, worktree `../lacylights-mcp-exportqueries` | Everything passes except **Security Audit**, which fails on the existing transitive deps `@fastify/busboy` and `@graphql-tools/utils`, not on this PR. 0 threads. | Merge after #83 is released. Optionally fix the audit in a separate dependency PR first. |
| 7 | **lacylights-mac#42** (`window.lacylights.downloadBinary` bridge) | `feat/download-binary` @ `2864725` | CLEAN; the repo has no PR CI. | **Manual test needed:** in the running app's web inspector, call `window.lacylights.downloadBinary(btoa('hi'), 'x.txt', 'text/plain')` and confirm the save dialog appears and the bytes are written. Then merge. |

### Unresolved threads at handoff
**fe#177** (all from Copilot):
- `ProjectManagementModal.tsx:485`: the row ⋯ menu portal (`rowMenu` state) isn't cleared when the modal closes by X, backdrop, Escape or swipe.
- `ProjectManagementModal.tsx:486`: the portaled menu sits outside the BottomSheet focus trap, and `ContextMenu` doesn't move focus, which is a keyboard accessibility problem.
- `ProjectImportPanel.tsx:88`: a refetch failure after a successful import is reported as "Failed to import project".
- `ProjectImportPanel.tsx:101`: a rejected switch-project or refetch promise is never caught, so it surfaces as an unhandled rejection.
- `lib/importExport/filenames.ts:38`: `sanitizeFilename()` can return 255 characters before `.json`, `.qxw` or `.asc` is appended.

**test#28** (all from Copilot):
- `dataexport_test.go:524`: the CSV escaping test only seeds `=`; also cover `+ - @ TAB CR` and LF.
- `seed_test.go:99`: the helper soft-deletes the project, leaving 2 global fixture definitions behind on each run.
- `deprecated_export_test.go:143`: the test compares only project IDs; it should compare the Query and Mutation content.
- `deprecated_export_test.go:167`: `require.Error` is too loose; assert the specific "not available" error.

## Open decisions for the user
- **Frontend fallback for older backends:** this was offered and not yet decided. fe#178 moved project exports to the new Queries with **no fallback**. A newer frontend talking to an older backend (the Mac and Pi update components separately) would break JSON/QLC+/Eos project export. The proposal is to retry with the legacy Mutation on `Cannot query field`, as mcp#197 does, and to hide or explain the data-export UI when `dataExportTables` doesn't exist.
- **Env-var configuration of export size limits** (`EXPORT_MAX_*`): deferred until the public demo deployment.

## Follow-ups (not started)
- Plan PR 9: an MCP `export_data_table` tool; removing the deprecated export Mutations from go after old frontends are gone.
- Bump Go in the `contract-tests.yml` of **lacylights-fe** (pins 1.21) and **lacylights-mcp** (pins 1.24). They build the backend, which now requires Go 1.25.
- A streaming HTTP download endpoint, if exports ever get very large.
- `scopeRequired` on `DataExportTableInfo`; lighter, names-only queries behind the frontend's look, cue list and board pickers.
- Delete the leftover branch `feat/data-export` and the worktrees `../lacylights-go-dataexport`, `../lacylights-test-dataexport` and `../lacylights-mcp-exportqueries` once their PRs merge.

## Lessons from this session (apply next time)
- **The user's PR iteration rules** are in the global CLAUDE.md. Address the comments, re-request Copilot, wait for checks, and repeat until there are no pending reviewers, all threads are resolved, all checks are green and the merge state is `CLEAN`. Then post a "ready for merge" comment. **Never merge without being asked.**
- **Export size limits are opt-in.** There must be no default caps on large projects; favour speed (see memory `feedback_export_size_limits.md`). Decline reviewer pushes for default caps and cite the go#82 comment explaining the decision.
- **Review loops:** Copilot finds new edge cases every round. After a few rounds of only minor edge cases, ask the user whether to keep iterating, as was done for go#82.
- **Monitoring PRs:** use `gh api --paginate` for reviews and comments. The reviews API returns 30 per page, and a missed second page stalled a monitor once. Match new reviews by `submitted_at`, not by commit SHA, and also watch the count of unresolved threads.
- **Failing tests:** if a change makes a pre-existing test fail, ask the user before changing the test (global CLAUDE.md).
- **Known flake:** `TestLookBoardFadeBehavior` in lacylights-go (DMX fade timing, 199 vs 200) fails intermittently and is unrelated to export work. The user's `fix/snap-end-startvalue` branch looks related.
- The main checkouts of lacylights-go, lacylights-test and lacylights-mcp are on **unrelated in-progress branches**. Always use the worktrees and never switch those main checkouts.

## Session 2 (2026-10-12, parallel iteration) — live status
- User decisions: **add the FE old-backend fallback** in fe#178 (retry legacy Mutation on `Cannot query field`; hide/explain data-export UI when `dataExportTables` missing). **mac#42: user will run the manual save-panel test themselves** — hold until they report.
- Parallel agents launched: go#83 (rebase + iterate, worktree ../lacylights-go-dataexport), fe#177 (threads, new worktree ../lacylights-fe-importpage), test#28 (threads; CI blocked on go#83), mcp#197 (Go 1.25 bump in contract-tests, audit fix as separate `chore/security-audit-deps` PR), fe#178 (fallback + Go 1.25 bump in contract-tests, in ../lacylights-fe).
- Merges still require explicit user permission for each PR.
- fe#177: green at `f3b228d` (worktree ../lacylights-fe-importpage). **User: wait for a Copilot re-review before merging.** Copilot quota is exhausted ("reached their quota limit"); an hourly re-request poller is running.
- mcp#197 at `71eb526`: everything passes except Security Audit. It fixed a real 422 fallback bug and pins Go 1.25. **mcp#198** (`chore/security-audit-deps`, worktree ../lacylights-mcp-audit) fixes the audit and is CLEAN. **User: wait for Copilot before merging #198.** Then update #197.
- User approved deferring `URL.revokeObjectURL` in downloadBlob in fe#178 and updating download.test.ts to match.
- **go#83 MERGED** 2026-10-12 (squash `64a0a6b`, from head 82aab79). **The release is on hold until the user approves it.** Downstream changes: per-field deprecation strings, max 2 concurrent project exports, Eos checks access first, and the FE should use fetchPolicy no-cache for exports.
- test#28 at `6800c22`: all threads are resolved and Copilot recommended approval. **e2e fails because of an existing go bug:** the OFL importer doesn't set RefID, so 657 of 658 imports fail on unique ref_id. A new go PR `fix/ofl-ref-id` is being made in worktree ../lacylights-go-dataexport. Once it merges, re-run test#28 e2e.
- **mcp#198 MERGED** (`3a41040`). mcp#197 was updated from main (head `7160451`): all green, CLEAN, ready-for-merge comment posted.
- fe#177 final at `67fa254`: Copilot found 0 open findings after 2 real fixes (a Set of saving IDs; `allProjects` for cross-group deep links). Manual checks remain: Mac save panel, and mobile row-menu position.
- **fe#177 MERGED** (`837b3f5`) and **mcp#197 MERGED** (`de37b4e`), both with user approval. fe#178 (head bae6e7c) is being retargeted to main and iterated. **User: release lacylights-go only after the OFL RefID fix merges.**
- **go#84 MERGED** (`b1c7cda`, OFL RefID fix). The release.yml **minor** release (v0.4.0) is running, run 38303594834. Issue go#85 was opened for the 269 OFL validation failures. test#28 CI was re-run.
- **v0.4.0 released.** **test#28 MERGED.** Remaining: fe#178 (agent iterating) and mac#42 (user's manual test).
- **fe#178 MERGED** (`92b3b0d`). The user chose to keep `tables: []` → null as it is.

### Final state (end of session 2)
Merged: go#83 `64a0a6b`, go#84 `b1c7cda` (OFL RefID), go **v0.4.0 released**, mcp#198 `3a41040`, mcp#197 `de37b4e`, fe#177 `837b3f5`, fe#178 `92b3b0d`, test#28 `79ada82`. All export worktrees have been removed.
**Remaining:**
- **mac#42**: waiting on the user's manual `downloadBinary` save-panel test, then merge.
- A new lacylights-fe release, so Mac and Pi pick up the UI.
- Optional cleanup: delete the remote branch `feat/data-export` in lacylights-go.
- Follow-ups: go#85 (269 OFL validation failures); plan PR 9 (MCP `export_data_table` tool, removing the deprecated Mutations later); add the ref_id indexes to `testutil.SetupTestDB`; check on a touch device that tapping outside closes the Export menu.

### Session 2 wrap-up
- **lacylights-fe v0.10.0 released** (minor; release.yml run 38322313962).
- Leftover branches: the remote branches were already auto-deleted on merge. All 8 local branches were deleted after checking each tip matched its merged PR head. The lacylights-fe main checkout was switched to `main`.
- mac#42: `swift build` and `swift test` pass (78 tests). The user is running the manual test from source (`swift run LacyLights`), using right-click → Inspect Element (developerExtrasEnabled).
- mac#42: the docked Inspect Element inspector renders black under `swift run`. Pushed `5d3d916`, which sets `isInspectable = true` in DEBUG builds so Safari → Develop can attach. The user is re-testing that way.
- **mac#42 MERGED** (`2923964`) after the user's manual test passed. The local branch was deleted and lacylights-mac is on main. **All #175 PRs are merged.** Remaining: a Mac app release (needs the user's go-ahead), plus the follow-ups.
