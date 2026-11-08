# Import/Export (#175) — implementation progress

> **Next session: start with `2026-10-12-import-export-handoff.md`.**

| Plan PR | Repo | Branch | PR | Status |
|---|---|---|---|---|
| 1 + Manage Projects changes | lacylights-fe | feat/import-export-page | bbernstein/lacylights-fe#177 | Open; lint/type/test/build:static pass |
| 2+3 data export | lacylights-go | feat/data-export (worktree ../lacylights-go-dataexport) | bbernstein/lacylights-go#82 | MERGED 2026-10-12 (squash `6f10dde`); branch kept for #83 |
| 8 (go) export Queries | lacylights-go | feat/project-export-queries (stacked on #82) | bbernstein/lacylights-go#83 | Open; retarget to main after #82 merges |
| 5 Mac downloadBinary | lacylights-mac | feat/download-binary | bbernstein/lacylights-mac#42 | Open; needs manual save-panel check |
| 4, 7, 8 (fe) | lacylights-fe | feat/data-export-ui (stacked on feat/import-export-page) | bbernstein/lacylights-fe#178 | Open; lint/type/test/build:static pass; needs go #82/#83 released before main |
| 6, 8 (test) | lacylights-test | feat/data-export-contracts (worktree ../lacylights-test-dataexport) | bbernstein/lacylights-test#28 | Open; test-ci + lint pass locally vs go feat/project-export-queries; CI uses go main so fails until go #82/#83 merge |
| 8 (mcp) | lacylights-mcp | feat/project-export-queries (worktree ../lacylights-mcp-exportqueries) | bbernstein/lacylights-mcp#197 | Open; lint/build/660 tests pass; falls back to legacy mutation on old backends |

## FE hooks for the data-export follow-up (from PR #177)
- `src/lib/importExport`: `downloadBase64(base64, filename, mimeType)` (uses Mac `downloadBinary` when present, else Blob), `downloadFile`, `exportProjectAs(client, projectId, format)` (switch to Query.projectExport* in PR 8).
- Page logic: `src/components/import-export/ImportExportPage.tsx`. To add the data section: add `'data'` to `ImportExportSectionId`/`IMPORT_EXPORT_SECTION_IDS`, push a `{id:'data', title:'Export data (CSV / Excel)', content:<DataExportPanel .../>}` entry to `sections`; `params.table`/`params.scopeId` are already parsed.
- ExportMenuButton "More import/export options…" → `/import-export?section=data&table=…&scopeId=…&project=…`.
- Mac bridge JS: `window.lacylights.downloadBinary(base64, filename, mimeType): void`.

## Backend notes (from go PRs)
- Package `internal/services/export_tables` (pkg `exporttables`); resolvers in `internal/graphql/resolvers/data_export_resolvers.go`.
- Scopes: FIXTURE_LIBRARY none (projectId optional); LOOK_DETAILS look (scopeId required); CUE_LIST_DETAILS cueList (required); LOOK_BOARD_ENTRIES lookBoard (optional; omit = all boards); others project.
- Workbook default tables: Fixture Types, Fixtures, Looks, Effects, Look Board Entries, Cue Lists.
- Deviations: Fixtures use Description (no Notes), separate Tags/Groups columns; Effects use Frequency/Amplitude; Look board uses board default fade time.
- Suggested follow-up: add `scopeRequired: Boolean!` to DataExportTableInfo.
- Local server for codegen: `cd ../lacylights-go-dataexport && ARTNET_ENABLED=false OFL_IMPORT_ENABLED=false go run ./cmd/server` (port 4000).

## Status 2026-10-12 (end of implementation session)
All plan PRs 1–8 are open. Remaining:
- Review/merge order: go#82 → retarget go#83 to main and merge → release go → fe#177 → fe#178 (retarget to main) → test#28 (CI green once go merged) → mcp#197 → mac#42 (after manual save-panel check).
- fe#177 CI type-check fixed (MockedResponse typing) and origin/main merged; merged into fe#178.
- mcp#197 "Security Audit" fails on pre-existing transitive deps (@fastify/busboy, @graphql-tools/utils), not from this PR.
- Plan PR 9 follow-ups not started: MCP `export_data_table` tool; remove deprecated export Mutations in go; optional `scopeRequired` on DataExportTableInfo; lighter names-only scope-picker queries in fe.

## go#82 iteration outcome (2026-10-12)
- Many review rounds; final head `31314f4`. Go bumped to 1.25 (excelize v2.11.0 security fix); CI lint now golangci-lint-action v8 / golangci-lint v2.6.2.
- Size limits are OPT-IN (user decision): Service.MaxRows/MaxCells/MaxBytes default 0 = unlimited; MaxExport* constants are suggestions for the public demo. Env-var config (EXPORT_MAX_*) deferred to demo work.
- Next: merge #82 → rebase/retarget #83 onto main (it was stacked on an older #82 commit) → release → fe#177 → fe#178 → test#28 (already bumped to Go 1.25) → mcp#197.
- Follow-ups: bump Go in lacylights-fe and lacylights-mcp contract-tests.yml; streaming download endpoint; FE fallback to legacy export mutations for older backends (offered to user, not yet done).
