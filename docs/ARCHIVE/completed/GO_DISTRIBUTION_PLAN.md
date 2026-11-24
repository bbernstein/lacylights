# Go Backend Distribution Coordination Plan

## Problem Summary

Three critical issues with the current Go backend distribution:

### Issue 1: Version Overwriting in lacylights-go
**Current behavior**: Archives are named without version numbers (`lacylights-darwin-arm64.tar.gz`)
**Problem**: Each release OVERWRITES the previous binary, making downgrades impossible
**Expected**: Archives should include version (`lacylights-darwin-arm64-v0.1.3.tar.gz`)

### Issue 2: lacylights-mac Installation Failing
**Current state**: Mac app expects `latest.json` with platform-specific archive URLs
**Problem**: URLs point to non-versioned archives which get overwritten
**Also**: May need error handling improvements for download failures

### Issue 3: lacylights-rpi Incompatible URL Pattern
**Current expectation**: Direct binary URLs like `lacylights-server-v0.1.3-arm64` (NOT tar.gz)
**Problem**: lacylights-go only produces tar.gz archives, not raw binaries
**Also**: RPi scripts use different naming convention than what's published

---

## Solution Overview

### Phase 1: Fix lacylights-go Release Workflow
1. Add version to archive filenames: `lacylights-{os}-{arch}-v{version}.tar.gz`
2. Upload BOTH tar.gz archives AND raw binaries for flexibility
3. Update metadata JSON with versioned URLs
4. Keep old releases accessible (no overwriting)

### Phase 2: Update lacylights-mac
1. Update URL parsing to handle versioned filenames
2. Improve error handling and logging
3. Add version validation

### Phase 3: Update lacylights-rpi
1. Update download logic to match new URL patterns
2. Support both tar.gz and raw binary downloads
3. Align naming conventions with lacylights-go output

---

## Detailed Implementation

### lacylights-go Changes

**File**: `.github/workflows/release.yml`

#### Archive Naming (Current → Fixed)
```
# Current (WRONG - overwrites):
lacylights-darwin-arm64.tar.gz
URL: https://dist.lacylights.com/releases/go/lacylights-darwin-arm64.tar.gz

# Fixed (version preserved):
lacylights-darwin-arm64-v0.1.3.tar.gz
URL: https://dist.lacylights.com/releases/go/v0.1.3/lacylights-darwin-arm64.tar.gz
```

#### Additional Raw Binary Upload for RPi
```
# Also upload raw binaries (in addition to archives):
lacylights-server-v0.1.3-linux-arm64
lacylights-server-v0.1.3-linux-arm
URL: https://dist.lacylights.com/releases/go/v0.1.3/lacylights-server-linux-arm64
```

#### latest.json Structure (Updated)
```json
{
  "version": "0.1.3",
  "releaseDate": "2025-12-08T...",
  "isPrerelease": false,
  "platforms": [
    {
      "os": "darwin",
      "arch": "arm64",
      "archiveUrl": "https://dist.lacylights.com/releases/go/v0.1.3/lacylights-darwin-arm64.tar.gz",
      "binaryUrl": "https://dist.lacylights.com/releases/go/v0.1.3/lacylights-darwin-arm64",
      "sha256": "...",
      "fileSize": 12345
    },
    {
      "os": "linux",
      "arch": "arm64",
      "archiveUrl": "https://dist.lacylights.com/releases/go/v0.1.3/lacylights-linux-arm64.tar.gz",
      "binaryUrl": "https://dist.lacylights.com/releases/go/v0.1.3/lacylights-linux-arm64",
      "sha256Binary": "...",
      "sha256Archive": "...",
      "fileSize": 12345
    }
  ]
}
```

### lacylights-mac Changes

**File**: `LacyLights/Managers/SetupCoordinator.swift`

1. Update URL parsing to handle new versioned URLs
2. Use `archiveUrl` field from platforms array
3. Add retry logic for failed downloads
4. Better error messages for debugging

### lacylights-rpi Changes

**Files**: `scripts/setup-new-pi.sh`, `scripts/setup-local-pi.sh`, `scripts/migrate-to-go.sh`

1. Update URL construction to use new pattern
2. Use `binaryUrl` field from `latest.json` for direct downloads
3. Or download archive and extract (more portable)
4. Update architecture mapping (arm64 vs armhf/arm)

---

## URL Structure (Proposed)

```
dist.lacylights.com/
└── releases/
    └── go/
        ├── latest.json                              # Points to latest stable
        ├── v0.1.3.json                              # Version-specific metadata
        └── v0.1.3/                                  # Version directory
            ├── lacylights-darwin-arm64.tar.gz       # macOS Apple Silicon archive
            ├── lacylights-darwin-arm64              # macOS Apple Silicon binary
            ├── lacylights-darwin-amd64.tar.gz       # macOS Intel archive
            ├── lacylights-darwin-amd64              # macOS Intel binary
            ├── lacylights-linux-arm64.tar.gz        # Linux ARM64 archive
            ├── lacylights-linux-arm64               # Linux ARM64 binary
            ├── lacylights-linux-arm.tar.gz          # Linux ARM32 archive
            ├── lacylights-linux-arm                 # Linux ARM32 binary
            ├── lacylights-linux-amd64.tar.gz        # Linux x64 archive
            ├── lacylights-linux-amd64               # Linux x64 binary
            └── checksums.txt                        # SHA256 checksums
```

---

## Implementation Order

1. **FIRST**: lacylights-go - Fix release workflow (source of truth)
2. **SECOND**: lacylights-mac - Update to new URL patterns
3. **THIRD**: lacylights-rpi - Update to new URL patterns
4. **FINALLY**: Test end-to-end with a new release

---

## Backwards Compatibility

- Keep supporting `latest.json` with same basic structure
- Existing releases will remain at old URLs (but may get overwritten on next release)
- New releases will use versioned URLs
- Both Mac and RPi clients will need updates before working with new releases

---

## Testing Checklist

- [ ] New release creates versioned directory structure
- [ ] Archives have version in filename
- [ ] Raw binaries uploaded alongside archives
- [ ] latest.json updated with correct versioned URLs
- [ ] Old versions remain accessible
- [ ] lacylights-mac successfully downloads and installs
- [ ] lacylights-rpi successfully downloads and installs
- [ ] Version downgrade works
