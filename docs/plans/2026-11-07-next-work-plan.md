# LacyLights — Next Work Plan (cross-repo)

**Date:** 2026-11-07
**Status:** PROPOSED. Nothing in it has been started.
**Source:** a read-only audit of all 10 repos: go, fe, mcp, mac, rpi, terraform, test, streamdeck, web, and the docs repo.
- About 150 findings were checked against GitHub and the code.
- An adversarial verifier re-checked the high-impact ones: 0 refuted, 8 corrected.
- Raw results (`2026-11-07-audit-raw/`, including `go-govulncheck.txt`) are kept locally only and are not versioned, because they contain security-sensitive infrastructure details.

**Standing directives that apply to every step:**
- **Node v26:** any new work in a repo that uses Node also bumps that repo to Node 26 (see §9).
- Never commit to `main`.
- claude-review must pass on the head commit.
- Implement with subagent-driven development.
- In lacylights-go, run `scripts/check-coverage.sh` before every push.

---

## 1. Where things stand

The last big wave (fixture fidelity, GDTF import, new channel types, source model) merged on 2026-10-16. **None of it has been released.** Since then nothing has been pushed in any repo, but three things went wrong in the meantime:

1. **Main CI is red** in go and fe, from test flakes. Neither has been re-run.
2. **Security debt has built up:**
   - **go:** Go 1.25 is out of support (current is 1.27.3/1.26.10). govulncheck reports 48 reachable vulnerabilities, in net/http, crypto/tls, chi, jwt and excelize.
   - **fe:** Next.js 15.5.27 has 2 critical and 2 high alerts.
   - **mcp:** 2 high and 2 moderate production-dependency vulnerabilities.
3. **Some CI gates don't gate.** fe's build job ends with `exit 0`, its `main` requires no status checks, and the `lacylights-test` `ci.yml` is empty and fails on every run.

Shipped products that are broken for users:
- 9 MCP tools call GraphQL operations the backend doesn't have (mcp#209).
- QLC+ import/export is advertised in the UI but is a stub in the backend (go#91).
- OFL fixture updates orphan definitions and leave patched fixtures pointing at deleted IDs.
- The website's "All releases" link returns 403.

| Component | Latest release | On dist `latest.json` | Unreleased on main |
|---|---|---|---|
| lacylights-go | v0.5.0 (10-14) | 0.5.0 | 5: #102 channel types, #103 source model, #104 GDTF, #105, #106 |
| lacylights-fe | v0.11.0 (10-14) | 0.11.0 | 3: #194, #195, #196 |
| lacylights-mcp | v1.7.0 (10-14) | 1.7.0 | 3: #202, #211, #212 |
| lacylights-mac | v1.3.6 (10-14) | 1.3.6 | 1: #46 folder picker |
| lacylights-rpi | v0.2.19 (**01-07**) | 0.2.19 | 4, including #72 device auth (Feb) |
| streamdeck / web / test / terraform | none | — | — |

---

## 2. Decisions needed from you

These block or reshape later steps. Each has a recommendation.

| # | Decision | Recommendation |
|---|---|---|
| D1 | **go#107**, an outside PR from `CityBuilderBot-Tech`. It changes Art-Net universe 1 from port-address 0 to 1. Its CI has never run, it has no tests on hardware, and the author couldn't run `go test`. | **Decline and close it**, with a polite explanation: 1→0 is the console convention (Eos and QLC+), and the change would silently move every existing rig. If offsets are wanted, open an issue for an opt-in `ARTNET_UNIVERSE_OFFSET` or a per-universe map. Don't approve its fork workflows without reading the diff. |
| D2 | **go#87.** Are all real installs (your Macs and Pis) on go v0.4.0 or later? This can't be checked from code: there's no telemetry, and updates are user-initiated. | If yes, land the 4 parked drafts in Phase 5 (order: fe#182 → mcp#204 → go#93 → test#29). If unsure, first add a min-backend-version warning to the fe. |
| D3 | **Review gate.** Restore Copilot review now that it's November and the quota has reset? | Your call. Memory says ask in November. |
| D4 | **Version the planning docs.** `docs/`, STATUS.md, the plans and `.claude/` at the workspace root are in no git repo, and Time Machine (<backup-volume>) is failing to mount. | Move them into the `bbernstein/lacylights` docs repo via a PR. Exclude show files (`OTBPA*`, `.qxw`), `.env` and `dev.db`, and gitignore them. |
| D5 | **Beads** (`.beads/`, AGENTS.md). It's unused, and AGENTS.md tells agents to `bd sync`/push from a directory that isn't a repo. | Remove beads and point AGENTS.md at GitHub issues and STATUS.md. |
| D6 | **Stream Deck plugin.** Is it a product? It's a private repo with no releases, no distribution and protocol drift. | If yes, do Phase 6c. If no, mark it personal and limit work to compatibility fixes. |
| D7 | **QLC+.** Finish go#95 (import) now, or hide the QLC+ format card until the backend supports it? | Hide QLC+ export now (that's the bigger job). Finish import via #95 in Phase 6. |
| D8 | **Terraform state** is local-only (`terraform.tfstate`, 55 resources). The S3 bucket named in the commented backend block doesn't exist. | Back up the state file today. Then create the S3 bucket and DynamoDB lock table and migrate (Phase 1). |
| D9 | **Manual GitHub settings** I can't change for you (repo settings):<br>• Turn on Dependabot alerts and security updates in **go** and **mcp**.<br>• Require status checks on **fe** `main`.<br>• Add a `CLAUDE_CODE_OAUTH_TOKEN` *Dependabot* secret in go, fe, mcp, test and rpi (fe#191). | Do these alongside Phase 1. |
| D10 | **Mac signing cert.** The Developer ID Application cert expires **2027-02-01** (issued 2026-10-13). | Check whether that's your Apple Developer membership renewal date, and renew by mid-January. Apps already signed and notarized keep working; only new releases would be blocked. |

---

## 3. Phase 1: Stop the bleeding (security, red CI, broken gates)

Goal: every main branch is green, every gate really gates, and no known critical or high vulnerability ships in the next release. **Each step is one PR per repo**, and each PR includes that repo's Node 26 bump (§9).

### 1a. lacylights-go: toolchain, vulnerabilities, red main (P0/P1, S–M)
- Fix the middleware test flake. `TestAuthenticate_DeviceWithGroupMemberships` (run 38953965987) fails with `no such table` because `:memory:` SQLite uses a multi-connection pool. Add `SetMaxOpenConns(1)` in `createTestDBWithDevice` and in the other ~18 `:memory:` test helpers under `internal/`.
- Toolchain: set `go.mod` to `go 1.26` and build with **Go 1.27.x** in CI and release. Locally you're on go1.25.4; upgrade it too.
- Dependency bumps: chi v5.3.0, golang-jwt v5.2.2, x/net v0.60, x/text v0.39. Move excelize to a fixed version (the fixes are post-v2.11.0) and run the data-export xlsx tests.
- Add `.github/dependabot.yml` (gomod plus github-actions) and a `govulncheck` CI step.
- Done when: main CI is green, the coverage gate passes, and govulncheck reports 0 reachable vulnerabilities.

### 1b. lacylights-fe: real gates, security bump, flake (P1, S)
- `ci.yml`:
  - Remove the `exit 0` wrapper on "Build application (informational)" (lines 61–70) and also run `npm run build:static`, which is what the RPi build ships.
  - Make `npm audit --omit=dev --audit-level=high` fail the job (line 133).
- Bump **next → 15.5.29**, the `backport` tag. It's still a patch release: images are already unoptimized, there are no Server Actions, and sharp is pinned. This doesn't clear the nested postcss 8.4.31 alerts; that waits for Next 16 (fe#192).
- Fix the GdtfImportPanel flake (`GdtfImportPanel.test.tsx:199`): wait for the files-read state before `findByRole`, or give it a longer timeout.
- Add `.github/dependabot.yml` with groups, and ignore semver-majors for next, eslint-config-next, tailwindcss and `@graphql-codegen/*`. Twice now (#176, #193), grouped security PRs have smuggled in build-breaking majors.
- **Close Dependabot PR #193**, superseded by #187 and #189. It silently bumps Tailwind 4 and codegen 7, and `next build` fails on it.
- Done when: main CI is green on Node 26 and branch protection requires `test`, `lint` and `build` (D9).

### 1c. lacylights-mcp: production vulnerabilities, then mcp#209 (P1, S–M)
- PR 1:
  - bump zod to ≥4.6.6 and run `npm audit fix` for body-parser, fast-uri and qs
  - fold in the dev-dependency Dependabot PRs #213, #215, #216 and #217 as one human-authored batch PR (so claude-review runs), then close those 4 PRs
  - **openai 7 (#214):** take it here only if the openai usage tests pass on Node 26; otherwise leave it for a separate PR
  - add the Security Audit job to the required "All Checks Passed" aggregate
- PR 2, **mcp#209**:
  - point the 7 `bulk_delete_*` tools at `deletedCount`/`deletedIds`
  - change `set_fade_update_rate` to `updateFadeUpdateRate(rateHz)`
  - fix `get_fade_update_rate`
  - add tests
- Done when: `npm audit --omit=dev` is clean, and the 9 tools work against go main.

### 1d. Fix claude-review on Dependabot PRs: fe#191, in go/fe/mcp/test/rpi (P2, S)
- Add `allowed_bots: dependabot[bot]` to the claude-review workflow in each repo, plus the Dependabot secret (D9).

### 1e. lacylights-test: fix the always-red workflow (P3, S)
- `.github/workflows/ci.yml` is a 1-byte file, and all 37 of its runs have failed. Delete it (the real workflow is `test.yml`).

### 1f. Infrastructure safety (P2, S)
- Back up `lacylights-terraform/terraform.tfstate` now, off the laptop.
- Then (D8) create the state bucket and lock table, enable the backend in `main.tf:11-18`, and run `terraform init -migrate-state`.
- Fold in terraform#15 (gitignore `*.tfvars.json`, `*.tfplan`, overrides).
- Look into why Time Machine fails to mount the backup volume. It's outside the repos, but it's currently the only backup of the state file and the plan docs.

---

## 4. Phase 2: User-facing bugs (fix before the release train)

| Step | Repo | Item | Effort |
|---|---|---|---|
| 2a | go | **OFL orphans (data integrity), P1.**<br>• `ofl/service.go:59-63` (replace) deletes only the definition row.<br>• Both import paths re-create definitions under a new `cuid`, so in-use `fixture_instances.definition_id` ends up dangling (`manager.go:463-478`).<br>• SQLite foreign keys aren't enforced; the DSN at `database.go:61` lacks `_foreign_keys`.<br>**Fix:** update definitions in place (keep the ID, replace the children in one transaction). Add a cleanup migration for existing orphans. Decide whether to turn on FK enforcement; audit for violations first. | M |
| 2b | go + test | **Redo of fixture creation fails** with `UNIQUE instance_channels.id`. `FixtureRepository.Delete` (`fixture_repository.go:88-95`) doesn't delete `instance_channels`. **File an issue**, fix it, and remove the `t.Skip` at `lacylights-test/contracts/undo/undo_test.go:1361,1390`. | S |
| 2c | go | **go#99:** effect intensity fades read the clock twice, which strands blackouts and effects (`modulator/effects.go:268-275`, `219-232`). Pass the tick time; snap to EndValue on completion. | S–M |
| 2d | go | **Definition-mutation auth policy.** Only `importGdtfFixtures` requires auth. Apply the same guard (authenticated, or admin, since definitions are global) to `create`/`update`/`delete`/`bulkCreateFixtureDefinitions`, `importOFLFixture` and `triggerOFLImport`. | S |
| 2e | fe | **QLC+ card (D7).** Hide QLC+ export (and import, unless 6a lands first) in `src/lib/importExport/formats.ts:57-61` and the ImportExportPage:102 description. | S |
| 2f | fe | **fe#190:** the Export ▾ menu renders under the mobile bottom nav. Fold in **fe#188** (ContextMenu dismissing on height-only resizes); same component area. | S |
| 2g | web | **dist root 403.** `public/index.html:170,193` link to `https://dist.lacylights.com/`, which returns 403. Point them at `/releases/mac/` and `/releases/rpi/`, which return 200, or add an index page via terraform. | S |
| 2h | mac | **mac#45:** the MCP card is always grey. Replace it with an availability indicator (installed version / not installed / Node missing, "started on demand by your MCP client"). Remove the dead `startMCP` path. Combine with the Node 26 path change (§9). | M |
| 2i | go | Small bugs: **go#98** (`Project.lookBoards` resolver: `gqlgen.yml` entry plus a repository call) and **go#101** (`registerDevice` race: re-read on unique-constraint error). Close **go#100**, fixed by #105 / `fa1cc89`. | S |

---

## 5. Phase 3: Release train

Order matters: platforms download components through `latest.json`, and fe/mcp degrade gracefully on old backends but work best on the new one. Get your OK before each release (all are `workflow_dispatch`).

0. **lacylights-test against go main** (P1). The integration suite last ran on 10-14 and has never run against #102–#106. Run `make test-ci` locally against go main, and also run `contracts/dmx` and `contracts/fade` with `ARTNET_BROADCAST=127.0.0.1`. Fix anything it finds before releasing.
1. **go v0.6.0** (minor), built with Go 1.27. Release notes must say:
   - re-import OFL to get the new channel types
   - an unreadable source-precedence setting now fails project import
2. **mcp v1.8.0** (minor): GDTF tool, channel types, #209 fix, security fixes, Node 26.
3. **fe v0.12.0** (minor): channel types, source badges, GDTF UI, next 15.5.29, Node 26 release build.
4. **mac v1.3.7**: folder picker #46, Node 26 path discovery, mac#45 card. **This must ship with or before** the fe/mcp releases if their `engines` require Node 26 (see §9 caution). Signing is healthy (fixed 10-13).
5. **rpi v0.2.20**:
   - device-auth installer (#72), unreleased since February
   - the first real run of the download-page step (#73)
   - NodeSource `setup_26.x`
   - MCP leftovers removed (Phase 4)
6. **Demo (terraform `deploy-app.sh`)**: redeploy go/fe to the EC2 demo. It is the only internet-facing server-mode fe, so it's the one that matters for the Next.js CVE.
7. Smoke-test on a real Mac and a real Pi. That should include the WiFi AP end-to-end checklist, which has never been run on hardware (rpi plan Phase 4).

---

## 6. Phase 4: Test hub and CI hardening (lacylights-test and friends)

| Step | Item | Effort |
|---|---|---|
| 4a | Add a nightly `schedule:` run against go, fe and mcp main, with a failure notification. Optionally have the go/fe release workflows dispatch lacylights-test before publishing. | S |
| 4b | Add a non-required CI job that starts go with Art-Net on loopback and runs `contracts/dmx`, `contracts/fade` and `contracts/effects`. They never run in CI today; that's how go#107-style mapping changes would slip through. Promote it to required once it's stable. Retire the "2 timing-sensitive fade tests" exclusion if they pass after the SNAP fixes. | M |
| 4c | **PR G:** a contract test for `importGdtfFixtures` and source precedence. Also cover the COLOR_TEMPERATURE, HUE, SATURATION and SPEED channel types. | M |
| 4d | **mcp#208:** validate every MCP GraphQL operation against go `schema.graphql` at a pinned ref, in mcp CI and/or lacylights-test. This stops mcp#209-type drift from recurring. | M |
| 4e | Contract tests for open or just-fixed go bugs (#98, #101, redo), for auth/multi-tenant access control, and for at least one subscription. | M |
| 4f | Fix the dead S3 distribution tests (wrong default URL, outdated `latest.json` schema). They always skip silently. | S |
| 4g | Make QLC+ tests fail instead of skip once go supports QLC+; skip-on-"not available" is what hid go#91. Remove the leftover Node-vs-Go compatibility skips. | S |
| 4h | E2E gaps: the Import/Export screen, GDTF upload, data-export download, login, settings. Also **fe#180** (manual touch-device QA). | M |
| 4i | **mac CI gate:** there are no PR test, lint or claude-review checks on lacylights-mac. Add them. Fix `build-app.sh:32`, which calls the removed `swift package generate-xcodeproj`; the SPM rewrite is in mac `stash@{0}` (8a48201), so turn it into a PR. | S–M |
| 4j | Terraform `fmt`/`validate` and shellcheck in CI. | S |

---

## 7. Phase 5: Hygiene and cleanup (can run in parallel with Phases 3–4; all S)

**Parked deprecation (needs D2):** go#87, via fe#182 → mcp#204 → go#93 → test#29. fe#182 now conflicts with main; go#93 is 8 behind but has no conflicts.

**Local branches and checkouts.** All were verified as squash-merged with nothing unique, so it's safe to delete them and fast-forward `main`.

| Repo | Delete these local branches | Other |
|---|---|---|
| go | `feat/channel-types-cct-hue-sat-speed`, `feat/gdtf-import`, `feat/fixture-source-model` | Also delete the remote branches `copilot/sub-pr-58`, `-72` and `-72-again`. |
| fe | `feat/channel-types-cct-hue-sat-speed`, `feat/fixture-source-badges`, `feat/gdtf-import-ui` | Currently checked out on `feat/gdtf-import-ui`; switch to `main`. |
| mcp | `feat/channel-types-cct-hue-sat-speed`, `feat/gdtf-import-tool` | Currently checked out on `feat/gdtf-import-tool`; local `main` is 2 behind. |
| mac | `feat/open-panel-directories` | Merged as #46. |
| streamdeck | all 7 local branches and 1 remote branch | All squash-merged leftovers. |
| rpi, terraform, test | — | Prune stale remote-tracking refs. |

Reuse `docs/plans/2026-10-14-delete-merged-branches.sh`.

**Worktrees** (all clean, nothing unpushed):
- `lacylights-{go,fe,mcp,test}-wt-*87-deprecated` and `lacylights-go-wt-go91-qxw`.
- Remove the go#87 ones once D2 is resolved. Remove `go91-qxw` when #95 work resumes in a fresh worktree.

**Stashes:**

| Repo | Drop | Keep / convert |
|---|---|---|
| go | `stash@{2}` (obsolete scene-board work), `stash@{1}` | `stash@{0}`: a `projects(groupId:)` filter, ~450 test lines. Keep only if you want that filter as a small PR; otherwise drop it. |
| mcp | both | — |
| mac | — | Convert to a PR (see 4i). |
| docs repo | both (old) | — |

**Code cleanup:**
- go: delete the dead `internal/services/fade` package (1,564 lines) and its threshold in `check-coverage.sh:22`.
- rpi: remove the MCP leftovers in `prepare-offline.sh:115-165,287`, `04-permissions-setup.sh:64`, `lacylights-sudoers:13` and `deploy-offline.sh`.
- Archive the obsolete root-level `contract-tests/`, which lacylights-test supersedes.
- Delete the expired `certs/developerID_application.cer` (expired 2026-06-17).
- Clean up mac release hygiene: orphan tags v1.3.3/v1.3.4 and a leftover temporary signing-cert workflow.

**Docs refresh:**
- STATUS.md: both "active initiatives" have shipped, and its versions are stale.
- RPi plan and STATUS entries show shipped work as Not Started.
- Archive the implemented Caddy-migration, embedded-terminal and MCP-auth plans.
- Docs repo branch `docs/mcp-authentication-plan` (7a09adf): pushed with no PR, and the plan is already implemented. Open a PR and merge it as historical record, or delete it.
- Fix `IMPORT_EXPORT_FORMATS.md`: it says QLC+ works, and it omits GDTF and CSV/XLSX.
- Refresh `lacylights-test/docs/TESTING_PLAN.md`.
- Root CLAUDE.md: add **lacylights-streamdeck** and **lacylights-web**, fix broken links, and update "Current Implementation Project".
- Update the stale memory files.

---

## 8. Phase 6: Features and migrations backlog (prioritized)

| # | Item | Repos | Effort | Notes |
|---|---|---|---|---|
| 6a | **QLC+ import (go#91), from draft #95** | go, test, mcp | M | Rebase onto the source model. Use the precedence-aware definition lookup and `FixtureSourceSynthesized` instead of `USER`. Fix the 4 Copilot threads (Tempo=Beats timing, transactional writes, canceled-ctx cleanup, mode reuse). Add an `import_qlc` coverage threshold. Then un-hide import in the fe. |
| 6b | **QLC+ export (go#97)** | go, fe | M–L | `projectExportQLC`, fixture mappings, mapping suggestions. |
| 6c | **Stream Deck (if D6 = product)** | streamdeck, fe, terraform | M | Fix protocol drift: `CUE_SET_FADE_IN/OUT` and `EFFECT_START/STOP` are unhandled by the fe (`bridge-manager.ts:67,71`). Implement the fe GLOBAL_FTB and GLOBAL_SET_MASTER stubs (`StreamDockContext.tsx:1233-1261`); the backend has `fadeToBlack`, `activateBlackout` and `setGrandMaster`. Add a release workflow that builds `.streamDeckPlugin` and uploads to dist, then sign off the hardware checklist. |
| 6d | **MCP effect tools** | mcp, test | M | list/create/activate/stop effects, blackout, grand master. Build on 4d schema validation. |
| 6e | **fe#192 Next.js 16** | fe | L | ESLint flat config, eslint-config-next 16, React Compiler lint. Clears the nested-postcss alerts. |
| 6f | **fe#187 codegen cli 7 / plugins 6** | fe | M | Clears the `@graphql-tools/utils` dev advisory. |
| 6g | **fe#189 Tailwind 4** | fe | L | After 6e. |
| 6h | Fixture-definition hardening | go | S–M | A partial unique index on (source, source_id) with a dedupe migration first, plus a (manufacturer, model) index. `Omit("source_payload")` in list queries. Put a GDTF mapper version into the source hash. |
| 6i | GDTF follow-ups | fe, mcp | S–M | Port the MCP's chunked, header-independent zip reader to the browser and lower the client caps. Add an MCP path allow-list for `import_gdtf_fixtures`. |
| 6j | **Fixture fidelity Stream 2: OFL capability ranges** (ChannelCapability table and UI labels) | go, fe, mcp | L | Needs a design pass and your input. |
| 6k | FixtureGroup MCP tools and fe group-management UI (deferred from Eos 14c) | mcp, fe | M | |
| 6l | Undo/redo gaps: DuplicateLook, FixtureGroup mutations, atomic bulk undo | go | M | |
| 6m | FX engine remaining phases: multiple looks per cue, effect buttons on look boards, effect status subscriptions | go, fe | L | |
| 6n | Configurable Art-Net universe offset / map (only if D1 says so) | go, fe | M | Default must equal today's mapping. |
| 6o | Website content refresh and deploy hygiene | web, terraform | S | Fingerprint `styles.css`, which is cached for a year as immutable with a fixed name. Switch to OIDC instead of static AWS keys. Remove the content duplicated across two repos. |
| 6p | RPi production hardening and readiness criteria (TESTING_PLAN Phase 5) | rpi, test | L | |
| 6q | Eos `$ParamType` IDs for COLOR_TEMPERATURE and SPEED, which export as 999 today | go | S | Needs Eos reference verification. |
| 6r | Auth feature stubs: password reset, email verify, Apple Sign-In, device authorize, auth settings, group-derived permissions | go, fe | M each | Make sure the fe and MCP don't expose them until they're implemented. |

---

## 9. Node v26 rollout (applies within every step above)

Rule: whenever a step touches a repo that uses Node, the same PR moves it to **Node 26**:
- CI matrix: `26.x`, optionally with `24.x` as a floor
- the release workflow
- `engines`
- `.nvmrc` with `26`
- contract-test workflows

Your local Node is v26.13.0.

| Repo | Current | Change | First PR it rides in |
|---|---|---|---|
| lacylights-fe | CI 22/24, contract tests 24, **release 20**, no `engines` | All → 26. Add `engines` and `.nvmrc`. Close **fe#186** as done. | 1b |
| lacylights-mcp | CI 22/24, contract tests 22, **release 20**, `engines >=18` | All → 26. Set `engines`. Close **mcp#207** as done. | 1c |
| lacylights-test | e2e on 22 | → 26 | 1e / 4a |
| lacylights-mac | hardcoded `/opt/homebrew/opt/node@20` (`PathConfiguration.swift:174`, `ClaudeWorkspaceManager.swift:149`) | Discover `node@26`, falling back to `node` on PATH. Show "Node missing/too old" in the 2h card. | 2h / release 4 |
| lacylights-rpi | `setup/01-system-setup.sh:94` uses NodeSource `setup_20.x` | `setup_26.x` (confirm arm64 Debian builds exist) and enforce a minimum version. The fe on the Pi is a static export, so Node is only needed at build time. | release 5 |
| lacylights-streamdeck | CI 20.x; `manifest.json` and `src/adapters/elgato/manifest.json` use `"Nodejs": {"Version": "20"}` | Move CI to 26. The manifest value selects the Stream Deck app's **bundled runtime**: check which versions Elgato and Stream Dock support before changing it, and keep the highest supported version if 26 isn't available. | 6c (or a standalone S PR) |
| lacylights-terraform (demo EC2) | `dnf install nodejs` (Amazon Linux 2023 default) | Install Node 26 explicitly. If AL2023 doesn't package 26, use NodeSource or the official tarball. | release 6 |
| go, web, docs | no Node | — | — |

**Caution, release order:** if fe/mcp set `engines.node >=26`, a Mac whose Homebrew Node is older will fail at runtime. Ship mac v1.3.7's Node 26 discovery (and Homebrew `node@26` guidance) **with or before** fe v0.12/mcp v1.8.

---

## 10. Issue / PR disposition (all open items as of 2026-11-07)

| Item | Disposition |
|---|---|
| go#107 | D1: decline and close (recommended) |
| go#95 (draft) | 6a |
| go#93 (draft) | Phase 5, after D2 |
| go#101, #98 | 2i |
| go#100 | Close: fixed by #105 / `fa1cc89` |
| go#99 | 2c |
| go#97 | 6b |
| go#91 | 6a (2e hides the card meanwhile) |
| go#87 | D2 / Phase 5 |
| fe#193 (Dependabot) | Close: superseded (1b) |
| fe#182 (draft) | Phase 5, after D2 (needs a rebase) |
| fe#192 | 6e |
| fe#191 | 1d |
| fe#190, #188 | 2f |
| fe#189 | 6g |
| fe#187 | 6f |
| fe#186 | 1b (Node 26) |
| fe#180 | 4h |
| mcp#213, #215, #216, #217 | Batch into 1c, then close |
| mcp#214 (openai 7) | 1c or a separate PR |
| mcp#204 (draft) | Phase 5, after D2 |
| mcp#209 | 1c |
| mcp#208 | 4d |
| mcp#207 | 1c (Node 26) |
| test#29 (draft) | Phase 5, after D2 |
| terraform#15 | 1f |
| mac#45 | 2h |
| Not yet filed | Redo UNIQUE bug (2b), OFL orphans (2a), definition auth policy (2d), dist 403 (2g), fe build gate (1b), mac CI gate (4i). File these as issues when work starts. |

---

## 11. Suggested first session

1. Answer D1, D2 and D4–D8. D9 and D10 are things to do yourself.
2. Back up `terraform.tfstate` (1f).
3. Run 1a, 1b and 1c in parallel. They're independent repos, each with Node 26 where it applies. Then do 1d and 1e.
4. Then 2a–2i, then the test run against go main (Phase 3 step 0), then the release train.
