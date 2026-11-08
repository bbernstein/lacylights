# Import/Export Screen + CSV/Excel List Export

Tracking issue: https://github.com/bbernstein/lacylights-fe/issues/175 (status: decisions made 2026-10-12, ready for implementation)

## Summary

> **Status:** all open questions answered (see *Decisions*). Ready for implementation.
>
> **Scope:** spans **lacylights-fe** (UI), **lacylights-go** (CSV/XLSX generation and GraphQL API), **lacylights-mac** (binary download bridge) and **lacylights-test** (contract tests). This issue tracks the whole feature; open companion issues or PRs in each repo as the work starts.

Import/export currently lives inside the **Project** dropdown in the header. That menu should be mainly a list of projects, but it now holds 3 import options and 3 export options. We plan to add more formats, including CSV and Excel exports of each data list, so the menu would keep growing.

This issue does three things:
1. Takes the import/export options out of the Project menu and adds a single **Import / Export…** item in their place.
2. Adds a dedicated **Import / Export** screen that has every existing project import and export option.
3. Adds **CSV and Excel (.xlsx) export** for each of the app's data lists.

## Current state

- `src/components/ProjectSelector.tsx` (lines ~99–107) renders `<ImportExportButtons inDropdown />` between the project list and **Manage Projects**.
- `src/components/ImportExportButtons.tsx` (~585 lines) has all the logic:
  - Import: `auto` | `lacylights` (JSON) | `qlcplus` (.qxw) | `eos` (.asc)
  - Export: `lacylights` (JSON) | `qlcplus` (.qxw) | `eos` (.asc)
  - Eos import and export warnings, shown with `EosWarningsList`
  - `downloadFile()`: uses the Mac app's native bridge `window.lacylights.download(content: string, filename)` when it exists, and a Blob download otherwise
- `src/components/ProjectManagementModal.tsx` also uses `ImportExportButtons` twice: once as an import button in the toolbar and once as an `exportOnly` button on each project row.
- GraphQL operations are in `src/graphql/projects.ts`: `importProject`, `importProjectFromQLC`, `importProjectFromEos`, `exportProject`, `exportProjectToQLC`, `exportProjectToEos`.
- Nothing in the app exports CSV or XLSX today, and there are no spreadsheet libraries in `package.json`.

## Part 1: Clean up the Project menu

- Remove `<ImportExportButtons inDropdown />` from `ProjectSelector`.
- Add one item, **Import / Export…** (with an icon such as `ArrowsUpDownIcon`), next to **Manage Projects**. It goes to the new screen.
- The menu then contains: project list → divider → Import / Export… → Manage Projects.
- `inDropdown` mode in `ImportExportButtons` may have no remaining callers. If so, remove it.
- Update `ProjectSelector` tests.

## Part 2: The Import / Export screen

**Route:** `/import-export`, under the `(main)` layout so it gets the header and project context. It should be a full page rather than a modal, so it has room to grow and works well on mobile.

**Layout:** three sections, as cards or tabs:

### A. Import project
- One file picker for `.json`, `.qxw` and `.asc`, which auto-detects the format (same behaviour as the current `auto` option). There should also be an explicit format selector for when detection is wrong.
- Show a short description of each format: LacyLights, QLC+, ETC Eos ASCII.
- After import: show results, including the Eos warnings panel, and offer **Switch to imported project**. The current `handleImportComplete` behaviour switches projects automatically, so we should either keep that or ask the user first.

### B. Export project
- Project picker, defaulting to the current project.
- Format choices: LacyLights JSON, QLC+, Eos ASCII. Each has a short description and an **Export** button.
- Show Eos export warnings on the page.
- Leave room in the layout for more formats later.

### C. Export data (CSV / Excel)
See Part 3.

**Refactor:** split `ImportExportButtons.tsx` into pieces we can reuse:
- `src/lib/importExport/` contains the pure logic: format detection, filename generation, calls to GraphQL mutations or queries, and the download helper.
- `src/components/import-export/` contains the presentational components the new page uses: `ProjectImportPanel`, `ProjectExportPanel` and `DataExportPanel`.
- **Project Management window (decided):**
  - Replace the toolbar's import button with an **Import / Export…** button that opens `/import-export`.
  - Replace each row's export dropdown with a single **Save** icon button (`ArrowDownTrayIcon`). It immediately downloads that project as **LacyLights JSON**, the native save format. Its tooltip and aria-label are "Save project as LacyLights file (.json)". There is no format menu on the row.
  - Other formats (QLC+, Eos) for a project are available through the row's overflow (⋯) menu → **More export options…**, which opens `/import-export?section=export&project=<id>` with that project already selected.

### Navigation (decided)
- The Import / Export page can be reached from the **Project menu** and from the **Manage Projects** window.
- Every other import or export UI must link back to `/import-export`. This includes the per-page Export buttons (Part 3), the Manage Projects Save button's overflow menu, and the fixture library (OFL) import in Settings. The link text is "More import/export options…".
- The page reads query parameters (`section`, `project`, `table`, `scopeId`) so these links open it with the right context already selected.
- The page is **not** added to the main tabs.

## Part 3: CSV / Excel export of lists

### Lists to support

| List | Scope | Suggested columns (draft, to refine) |
|---|---|---|
| Fixture Types | **Default: only definitions used by fixtures in the project.** Option: **entire fixture library** (`FIXTURE_LIBRARY`) | Manufacturer, Model, Mode, Channel count, Type, Source (OFL or custom), Fixtures in project using it (project scope only) |
| Fixtures | Project | Name, Manufacturer, Model, Mode, Universe, Start channel, End channel, Channel count, Tags/Groups, Notes |
| Looks | Project | Name, Description, Fixture count, Created, Updated |
| Look details | One look | **Wide format: one row per fixture.** `Fixture, Manufacturer, Model, Mode, Universe, Start address, Ch 1 … Ch N`. N is the highest channel count of any fixture in the look. Columns past a fixture's own channel count are **blank, not 0**. A real value of 0 is written as `0`. In XLSX, a second sheet called **Channel names** has the same grid with each channel's name (e.g. `Red`, `Dimmer`), so the numbered columns are easy to read. |
| Effects | Project | Name, Type, Waveform, Rate, Depth, Fixture count, … |
| Look Board entries | One board, or all boards | Board, Button label, Look, Position (x, y), Color, Fade time |
| Cue Lists | Project | Name, Description, Cue count, Loop, Created, Updated |
| Cue List details | One cue list | Cue #, Name, Look, Fade in, Fade out, Follow time, Easing, Skip, Notes |

### Approach: backend generation in lacylights-go, frontend UI in lacylights-fe

The CSV and XLSX files are **generated on the server** in lacylights-go. Reasons:
- The column definitions live in one place, so the frontend, the MCP server and any future clients produce the same files.
- Go has a well-established XLSX library ([`excelize`](https://github.com/qax-os/excelize)), so the frontend bundle doesn't need a large spreadsheet library.
- The server already has the full data model (channel values, fade behavior, definitions) and doesn't need to fetch everything through many GraphQL round trips.

#### Backend (lacylights-go)
- **New package** `internal/services/export_tables/`:
  - A **table registry**. Each table has an `ID`, `Label`, `Scope` (project, look, cueList or lookBoard), `Columns []Column{Key, Header}`, and `Rows(ctx, projectID, scopeID) ([][]any, error)`.
  - A **CSV writer** (`encoding/csv`) that writes a UTF-8 BOM and protects against formula injection by escaping cells that start with `=`, `+`, `-`, `@`, tab or CR.
  - An **XLSX writer** (excelize) with a bold, frozen header row, column widths sized to the content, and correctly typed numbers.
  - **Workbook mode:** all project-scoped tables in one `.xlsx` file, one sheet per table.
- **GraphQL** (`internal/graphql/schema/schema.graphql`):
  ```graphql
  enum DataExportFormat { CSV XLSX }
  enum DataExportTable { FIXTURE_TYPES FIXTURE_LIBRARY FIXTURES LOOKS LOOK_DETAILS EFFECTS LOOK_BOARD_ENTRIES CUE_LISTS CUE_LIST_DETAILS }

  type DataExportTableInfo { table: DataExportTable! label: String! scope: String! columns: [String!]! }
  type DataExportResult { filename: String! mimeType: String! contentBase64: String! rowCount: Int! }

  # Exports are read-only, so they are Queries (see "GraphQL conventions" below).
  extend type Query {
    dataExportTables: [DataExportTableInfo!]!   # lets the UI build its picker from the server
    # projectId may be null only for FIXTURE_LIBRARY
    exportDataTable(projectId: ID, table: DataExportTable!, format: DataExportFormat!, scopeId: ID): DataExportResult!
    exportDataWorkbook(projectId: ID!, tables: [DataExportTable!]): DataExportResult!
  }
  ```
- Enforce access in the resolvers with `ensureProjectAccess()` and the group checks, the same way the existing project export resolvers do. Also check that `scopeId` belongs to `projectId`.
- The server generates the filename: `<project>-<table>[-<item>]-YYYY-MM-DD.(csv|xlsx)`, with each part sanitized.
- **Payload (decided):** return the file inline as base64 in the GraphQL response.

#### GraphQL conventions (decided): exports are Queries, imports are Mutations
GraphQL's rule is that **Queries must not change state and Mutations may**. It is not that matching operations such as import and export must use the same type. Following that rule:
- **Imports stay Mutations.** They create projects and records.
- **Exports become Queries.** They are read-only. We checked: `exportProject`, `exportProjectToQLC` and `exportProjectToEos` don't write anything.
- What makes the API consistent is that "every read-only operation is a Query", rather than "import and export are the same type". This is also what the GraphQL spec and the Apollo, GitHub and Shopify guidelines recommend.
- Practical benefits:
  - Queries can run in parallel. Mutations run one after another.
  - Queries can be retried safely.
  - Read-only API keys and roles can be limited to Queries.
  - MCP tools that only read can avoid mutations.
- **Caching caveat:** Apollo Client would otherwise keep large base64 payloads in its cache. Run every export with `useLazyQuery` / `client.query` and `fetchPolicy: 'no-cache'`, and enforce this in a shared helper.
- **Migrating the existing project exports without breaking anything:**
  1. Add Query fields that do the same thing, sharing one resolver implementation: `projectExport(projectId, options)`, `projectExportQLC(projectId, fixtureMappings)` and `projectExportEos(projectId)`. The names must differ from the current Mutation fields so the generated code doesn't collide.
  2. Mark the three Mutations `@deprecated(reason: "Use Query.projectExport*")`.
  3. Move lacylights-fe, lacylights-mcp (`graphql-client-simple.ts`) and lacylights-test (`contracts/importexport/*`) to the Queries.
  4. Remove the deprecated Mutations in a later release, after the Mac and RPi builds that ship older frontends have been updated.

#### Frontend (lacylights-fe)
- Add `src/graphql/dataExport.ts` with the new operations, then run codegen.
- Add a `DataExportPanel` on the Import/Export page with:
  - a table picker built from `dataExportTables`
  - a picker for the specific look, cue list or board when the table needs one
  - a CSV/XLSX toggle
  - **Export** and **Export all (workbook)** buttons
- Decode base64 to a Blob before downloading. Update the download helper so it handles both text and binary content.
- **Per-page Export buttons (decided, required):** every page that shows a list gets an **Export ▾** button. Its menu has **CSV**, **Excel** and **More import/export options…**, where the last item links to `/import-export` with the page's context. A shared `<ExportMenuButton table=… scopeId=…/>` component calls the `exportDataTable` query.

  | Page | Table(s) | Context |
  |---|---|---|
  | `/fixtures` | Fixtures, Fixture Types (project) | project |
  | `/looks` | Looks | project |
  | `/looks/[lookId]` | Look details | look |
  | `/effects` | Effects | project |
  | `/look-board/[id]` | Look Board entries | board |
  | `/cue-lists` | Cue Lists | project |
  | `/cue-lists/[id]` | Cue List details | cue list |
  | Settings → OFL Management | Fixture library (all definitions) | none |

  If another list page is added later (e.g. Groups), it gets the same button once a table is registered for it.

#### MCP (lacylights-mcp), follow-up
- Expose an `export_data_table` tool that wraps the same GraphQL operation. This gives AI clients spreadsheet export for free.

### Mac app bridge
`window.lacylights.download(content: string, filename)` accepts only a string, but XLSX files are binary. Recommendation: add a `downloadBinary(base64, filename, mimeType)` bridge method in **lacylights-mac**. The frontend should check whether it exists and fall back to a Blob download, so older Mac builds still work.

## Testing
- **Go:** tests for each table's columns and rows, using `testutil` fixtures. Also test the CSV writer (quoting, newlines, commas, BOM, formula-injection escaping), the XLSX writer (generate a file, read it back with excelize, check sheet names, headers and rows), filename sanitizing, and resolver access control (a user outside the group is rejected, and a `scopeId` from another project is rejected).
- **Frontend:** tests for base64 decoding and binary download, and for the `DataExportPanel` (picker, scope selection, mocked mutation).
- Component tests: the Project menu shows only projects plus the two action items, and the Import / Export page's sections. Move or adapt the existing import/export tests rather than deleting them.
- Coverage should not decrease.
- **lacylights-test:** contract tests for `dataExportTables` / `exportDataTable` / `exportDataWorkbook`. Parse the CSV and XLSX output and check the headers and row counts against a seeded project.

## Suggested PR breakdown
1. **fe: refactor plus new page.** Extract the logic from `ImportExportButtons`, add `/import-export` with project import/export, and slim down the Project menu. Behaviour stays the same; it is only moved.
2. **go: data export framework.** Table registry, CSV and XLSX writers, GraphQL schema and resolvers, and the Fixtures, Looks and Cue Lists tables.
3. **go: remaining tables.** Fixture Types, Look details, Effects, Look Board entries, Cue List details, plus the workbook export.
4. **fe: Export Data panel.** Uses the new operations, adds binary download, and adds the Manage Projects changes (Save icon, Import / Export… button).
5. **mac: `downloadBinary` bridge method.**
6. **test: contract tests** in lacylights-test.
7. **fe:** `ExportMenuButton` added to every list and detail page in the table above.
8. **go + fe + mcp + test: move project exports to Queries.** Add the Query fields, deprecate the Mutations, and update all callers.
9. *(Follow-up)* **mcp:** `export_data_table` tool. **go:** remove the deprecated export Mutations.

## Decisions (2026-10-12)
1. **Manage Projects:** the toolbar's **Import / Export…** button opens the page. Each project row has a **Save** icon that downloads LacyLights JSON with one click. The row's overflow menu has **More export options…**, which opens the page with that project selected.
2. **Per-page Export buttons:** yes, on every list and detail page, so each export has the right context.
3. **Fixture Types:** only the project's fixture types by default, with an option to export the entire library (`FIXTURE_LIBRARY`).
4. **Look details:** wide format, one row per fixture and `Ch 1…Ch N` columns, where N is the highest channel count of any fixture in the look. Unused trailing cells are blank, not 0.
5. **CSV/Excel import:** out of scope. It needs separate design work.
6. **Navigation:** the page is reached from the Project menu and Manage Projects. Every other import/export UI links back to it. It is not added to the main tabs.
7. **GraphQL:** exports are Queries and imports are Mutations. Existing export Mutations are deprecated and moved to Queries, as described in Part 3.
8. **Payload:** the file is sent inline as base64 in the GraphQL response.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_013A6PYX812rrpbvx2NuubYr
