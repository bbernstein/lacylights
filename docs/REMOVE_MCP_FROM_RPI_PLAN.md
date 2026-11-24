# Plan: Remove lacylights-mcp from Raspberry Pi Distribution

## Overview

The lacylights-mcp server provides AI integration capabilities via the Model Context Protocol. While useful for desktop environments where AI assistants can interact with lighting systems, it adds unnecessary complexity for the turnkey Raspberry Pi hardware product that typically runs on a private lighting network.

**Decision**: Remove MCP from the RPi distribution only. The Mac application will continue to manage MCP locally on desktop machines.

### Deployment Context Comparison

| Feature | Raspberry Pi | macOS Desktop |
|---------|-------------|---------------|
| MCP Server | ❌ Not included | ✅ Fully supported |
| AI Integration | ❌ Not available | ✅ Available |
| Update Management | fe + go only | fe + go + mcp |
| Network Context | Private lighting network | General network with AI access |

---

## Scope of Changes

### Repository Summary

| Repository | Changes Required | Complexity |
|------------|-----------------|------------|
| lacylights-rpi | Major - Remove all MCP installation/update code | High |
| lacylights-go | Medium - Make MCP optional in version service | Medium |
| lacylights-fe | Minor - Handle dynamic repo list from backend | Low |
| lacylights-mac | None - Continues managing MCP independently | None |
| lacylights-mcp | None - Standalone repo unchanged | None |

---

## Phase 1: lacylights-go Changes (Backend)

The backend must dynamically detect which repositories are installed rather than assuming all three exist.

### 1.1 Version Service (`internal/services/version/version.go`)

**Current behavior (line ~93):**
```go
repositoryNames = []string{"lacylights-fe", "lacylights-go", "lacylights-mcp"}
```

**New behavior - detect installed repositories:**

```go
// detectInstalledRepositories returns only repositories that are actually installed
func detectInstalledRepositories() []string {
    repos := []string{}

    // Always include fe and go on RPi
    if _, err := os.Stat("/opt/lacylights/frontend-src/.lacylights-version"); err == nil {
        repos = append(repos, "lacylights-fe")
    }
    if _, err := os.Stat("/opt/lacylights/backend/.lacylights-version"); err == nil {
        repos = append(repos, "lacylights-go")
    }
    // Only include MCP if it's installed
    if _, err := os.Stat("/opt/lacylights/mcp/.lacylights-version"); err == nil {
        repos = append(repos, "lacylights-mcp")
    }

    return repos
}
```

**Alternative: Config-based approach**
- Add `MANAGED_REPOSITORIES` environment variable
- Default to `lacylights-fe,lacylights-go` for RPi
- Mac app can set it to include MCP if needed

### 1.2 Remove MCP-Specific Update Handling

**Current (lines ~311-406):**
```go
if repository == "lacylights-go" || repository == "lacylights-mcp" {
    unitName = "lacylights-mcp-update"
    ...
}
```

**Updated:**
```go
if repository == "lacylights-go" {
    unitName = "lacylights-go-update"
    ...
}
// MCP updates no longer handled by RPi backend
```

### 1.3 Validation Changes

**Current validation (line ~112):**
```go
return fmt.Errorf("invalid repository name: %s (must be one of: lacylights-fe, lacylights-go, lacylights-mcp)", repository)
```

**Updated - validate against detected repos:**
```go
installedRepos := detectInstalledRepositories()
if !slices.Contains(installedRepos, repository) {
    return fmt.Errorf("invalid repository name: %s (must be one of: %s)", repository, strings.Join(installedRepos, ", "))
}
```

### 1.4 Tests to Update

- `internal/services/version/version_test.go` - Test with and without MCP present
- Add test for `detectInstalledRepositories()` function

---

## Phase 2: lacylights-fe Changes (Frontend)

The frontend already dynamically renders whatever repositories the backend returns. Only minor changes needed.

### 2.1 System Update Page (`src/app/(standalone)/system-update/page.tsx`)

**Current (lines 18-19):**
```typescript
const BACKEND_REPOS = ['lacylights-go', 'lacylights-mcp'] as const;
```

**Updated - dynamically determine backend repos:**
```typescript
// Only lacylights-go requires server restart handling
// MCP is managed independently by Mac app, not through this UI
const BACKEND_REPOS = ['lacylights-go'] as const;
```

**Rationale:** When running on RPi, MCP won't be in the list anyway. When running with Mac backend, MCP updates are handled by the Mac app directly, not through the web UI.

### 2.2 No Changes Needed

- `VersionManagement.tsx` - Already renders dynamically from backend data
- GraphQL queries - Schema unchanged, backend controls data

### 2.3 Tests to Update

Update test mocks to only include fe + go:
- `src/app/(main)/settings/__tests__/VersionManagement.test.tsx`
- `src/app/(standalone)/system-update/__tests__/*.test.tsx`

---

## Phase 3: lacylights-rpi Changes (Major)

### 3.1 Installation Script (`scripts/setup-new-pi.sh`)

**Remove all MCP-related code:**

| Lines (approx) | Description | Action |
|----------------|-------------|--------|
| ~44, 57, 148 | MCP version parameter support | Remove |
| ~637-638 | Download MCP from GitHub | Remove |
| ~772-776 | Extract MCP from offline bundle | Remove |
| ~801-809 | Extract MCP dependencies | Remove |
| ~833-841 | Extract MCP build artifacts | Remove |
| ~916-921 | Build MCP server (ONLINE) | Remove |
| ~938-942 | Rebuild MCP native modules (OFFLINE) | Remove |

**Expected:** ~50-60 lines removed

### 3.2 Update Script (`scripts/update-repos.sh`)

**Remove:**

| Lines (approx) | Description | Action |
|----------------|-------------|--------|
| ~143-148 | MCP case in `get_dist_component()` | Remove |
| ~1023-1113 | Entire `deploy_mcp()` function | Remove |
| ~1235-1262 | MCP update restart handling | Remove |

**Expected:** ~100 lines removed

### 3.3 Secure Update Runner (`scripts/run-update.sh`)

**Modify repository validation:**
```bash
# Before
case "$REPOSITORY" in
    lacylights-go|lacylights-mcp|lacylights-fe)

# After
case "$REPOSITORY" in
    lacylights-go|lacylights-fe)
```

### 3.4 Deploy Script (`scripts/deploy.sh`)

**Remove:**

| Item | Description |
|------|-------------|
| `MCP_REMOTE` variable | Line ~29 |
| `--mcp-only` option | Line ~58 |
| `DEPLOY_MCP` flag logic | Throughout |
| MCP build section | Lines ~466-486 |
| MCP rsync deployment | Lines ~623-653 |

**Expected:** ~80 lines removed

### 3.5 Sudoers Configuration (`config/sudoers.d/lacylights`)

**Remove:**
- Line ~69: `lacylights-mcp-update` systemd unit permission
- Line ~83: MCP directory chown permission

### 3.6 Documentation

**Update these files:**
- `README.md` - Remove MCP from component list and installation examples
- `docs/DEPLOYMENT.md` - Remove `--mcp-only` option

---

## Phase 4: lacylights-mac (No Changes)

The Mac application manages MCP independently:

### Current MCP Integration (Preserved)

| Feature | Location | Status |
|---------|----------|--------|
| MCP Repository enum | `PathConfiguration.swift` | ✅ Keep |
| MCP Process management | `ProcessInfo.swift` | ✅ Keep |
| MCP Startup | `StartupCoordinator.swift` | ✅ Keep |
| MCP Updates | `UpdateManager.swift` | ✅ Keep |
| MCP Version UI | `UpdateView.swift`, `VersionPickerView.swift` | ✅ Keep |
| MCP Setup | `SetupCoordinator.swift` | ✅ Keep |

### Mac vs RPi Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS Desktop                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ lacylights- │  │ lacylights- │  │ lacylights- │          │
│  │     fe      │  │     go      │  │    mcp      │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│         │               │                │                   │
│         └───────────────┴────────────────┘                   │
│                         │                                    │
│              ┌──────────┴──────────┐                        │
│              │   lacylights-mac    │  ← Manages all three   │
│              │    (Native App)     │                        │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Raspberry Pi                              │
│  ┌─────────────┐  ┌─────────────┐                           │
│  │ lacylights- │  │ lacylights- │   ❌ No MCP              │
│  │     fe      │  │     go      │                           │
│  └─────────────┘  └─────────────┘                           │
│         │               │                                    │
│         └───────┬───────┘                                    │
│                 │                                            │
│      ┌──────────┴──────────┐                                │
│      │   Web UI (Settings) │  ← Manages fe + go only        │
│      └─────────────────────┘                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Order

### Step 1: lacylights-go (Backend)
1. Create new branch `fix/remove-mcp-from-rpi`
2. Implement `detectInstalledRepositories()` function
3. Remove MCP-specific systemd unit handling
4. Update validation to use detected repos
5. Update tests
6. Run linter and tests
7. Create PR, iterate until approved
8. Merge to main

### Step 2: lacylights-fe (Frontend)
1. Create new branch `fix/remove-mcp-from-rpi`
2. Update `BACKEND_REPOS` constant
3. Update test mocks
4. Run linter and tests
5. Create PR, iterate until approved
6. Merge to main

### Step 3: lacylights-rpi (Deployment)
1. Create new branch `fix/remove-mcp-from-rpi`
2. Remove MCP from `setup-new-pi.sh`
3. Remove MCP from `update-repos.sh`
4. Remove MCP from `run-update.sh`
5. Remove MCP from `deploy.sh`
6. Update sudoers configuration
7. Update documentation
8. Test full installation flow
9. Create PR, iterate until approved
10. Merge to main

---

## Testing Plan

### Unit Tests
- [ ] lacylights-go: `detectInstalledRepositories()` returns correct repos
- [ ] lacylights-go: Version service works without MCP directory
- [ ] lacylights-go: Update validation rejects unknown repos
- [ ] lacylights-fe: System update page renders with 2 repos
- [ ] lacylights-fe: Settings page version display works

### Integration Tests
- [ ] RPi installation completes without MCP
- [ ] RPi update-repos.sh works for fe and go only
- [ ] Web UI shows only fe + go in version management
- [ ] Updates via web UI work correctly

### Manual Testing (RPi)
- [ ] Fresh installation (ONLINE mode) - verify no MCP directory created
- [ ] Fresh installation (OFFLINE mode) - verify no MCP artifacts
- [ ] Deploy script without `--mcp-only` option
- [ ] Version management UI shows 2 repositories
- [ ] Update fe via UI
- [ ] Update go via UI (triggers restart)
- [ ] Verify `/opt/lacylights/mcp` does NOT exist

### Manual Testing (Mac)
- [ ] Verify Mac app still manages MCP correctly
- [ ] MCP startup/shutdown works
- [ ] MCP version updates work via Mac UI

---

## File Change Summary

### lacylights-go
| File | Changes |
|------|---------|
| `internal/services/version/version.go` | Add detection, remove MCP handling |
| `internal/services/version/version_test.go` | Add/update tests |

### lacylights-fe
| File | Changes |
|------|---------|
| `src/app/(standalone)/system-update/page.tsx` | Update BACKEND_REPOS |
| `src/app/(main)/settings/__tests__/VersionManagement.test.tsx` | Update mocks |
| `src/app/(standalone)/system-update/__tests__/*.test.tsx` | Update mocks |

### lacylights-rpi
| File | Changes |
|------|---------|
| `scripts/setup-new-pi.sh` | Remove ~50 lines |
| `scripts/update-repos.sh` | Remove ~100 lines |
| `scripts/run-update.sh` | Remove MCP from validation |
| `scripts/deploy.sh` | Remove ~80 lines |
| `config/sudoers.d/lacylights` | Remove 2 lines |
| `README.md` | Update docs |
| `docs/DEPLOYMENT.md` | Update docs |

### lacylights-mac
No changes required.

---

## Rollback Plan

If issues arise after deployment:

1. **Immediate**: Revert commits in affected repos
2. **Redeploy**: Push reverted code to test Pi
3. **Investigate**: Identify root cause
4. **Fix forward**: Address issues and re-attempt

---

## Open Questions

1. **Distribution server cleanup?**
   - MCP releases remain on dist.lacylights.com for Mac app
   - No changes to lacylights-terraform needed

2. **Future RPi MCP support?**
   - Not planned - users who want AI integration can use Mac app
   - Advanced users could manually install MCP if desired

---

## Approval Checklist

- [ ] Plan reviewed and approved
- [ ] Implementation order confirmed
- [ ] Testing plan adequate
- [ ] Ready to begin implementation
