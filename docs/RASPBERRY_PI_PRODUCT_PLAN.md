# LacyLights Raspberry Pi Hardware Product Implementation Plan

> **Note**: This plan was originally written when lacylights-node was the backend.
> The implementation has been completed using **lacylights-go** as the backend.
> References to lacylights-node below are historical and should be read as lacylights-go.
> The deployment scripts are now in the **lacylights-rpi** repository.

**Goal**: Create a turnkey Raspberry Pi-based hardware product that runs both the LacyLights backend and frontend, accessible at `http://lacylights.local` on the local network.

**Status**: Largely Complete
**Started**: 2025-10-06
**Backend**: lacylights-go (Go/GORM/SQLite)

---

## Architecture Overview

```
Raspberry Pi (lacylights.local:80)
├── nginx - Reverse proxy & static file server
│   ├── / → Next.js static export (HTML/CSS/JS)
│   ├── /graphql → Proxy to backend:4000
│   └── /ws → WebSocket proxy with upgrade headers
├── Go Backend (localhost:4000)
│   ├── GraphQL API + subscriptions
│   ├── DMX/Art-Net control (40Hz)
│   └── Fade engine
└── SQLite Database (/var/lib/lacylights/db.sqlite)
    └── Single-file, auto-backup
```

---

## Key Decisions

### 1. Database: SQLite (Not PostgreSQL in Docker)
**Rationale**:
- **CPU Efficiency**: No separate process, ~50-70% less memory usage
- **Perfect Fit**: Single-device use case, small dataset (MB not GB)
- **Simpler Backups**: Single file copy
- **Lower Power**: Crucial for 24/7 Raspberry Pi operation
- **Prisma Native Support**: Already in the stack

**Trade-offs**:
- No built-in replication (not needed for single-device product)
- Concurrent write limitations (not an issue for single-user lighting control)

### 2. Remove Redis Dependency
**Finding**: Redis is defined in docker-compose.yml but not actually used anywhere in the codebase.

**Action**: Remove from docker-compose.yml and deployment scripts.

### 3. Frontend: Next.js Static Export (Not SSR)
**Rationale**:
- 80% of frontend is client-side React components
- GraphQL handles all dynamic data
- Static export reduces Node.js memory usage by ~50MB
- nginx serves static files more efficiently than Node.js
- Simpler deployment and caching

**Implementation**:
```typescript
// next.config.ts
output: 'export'
distDir: 'out'
```

### 4. Auto-Update: Pull-based (Option A)
**Approach**: Cron job checks for updates daily at 3am
- Safer than push-based (controlled timing)
- Rollback on test failure
- User-configurable via environment variable

---

## Implementation Steps

### Step 1: Write Plan & Update Documentation ✓
- [x] Create this plan document
- [ ] Update CLAUDE.md to reference plan

### Step 2: Convert Database to SQLite
**Files to modify**:
- `lacylights-node/prisma/schema.prisma`
- `lacylights-node/.env.example`
- `lacylights-node/docker-compose.yml` (remove postgres & redis)

**Tasks**:
- [ ] Update Prisma schema datasource to sqlite
- [ ] Create migration script for existing data
- [ ] Update environment variables
- [ ] Remove docker services we don't need
- [ ] Test migrations
- [ ] Update documentation

**Testing**:
```bash
npm run db:generate
npm run db:migrate
npm test
```

### Step 3: Configure Next.js for Static Export
**Files to modify**:
- `lacylights-fe/next.config.ts`
- `lacylights-fe/.env.local` (or create .env.production)
- `lacylights-fe/package.json` (add export script)

**Tasks**:
- [ ] Add `output: 'export'` to next.config.ts
- [ ] Configure GraphQL endpoints for relative paths
- [ ] Add image optimization config
- [ ] Create build script for static export
- [ ] Test build locally
- [ ] Verify all routes work in static mode

**Testing**:
```bash
npm run build
npx serve out  # Test static build locally
```

### Step 4: Create nginx Configuration
**Files to create**:
- `lacylights-node/deploy/nginx/lacylights.conf`
- `lacylights-node/scripts/setup-nginx.sh`

**Configuration**:
- Static file serving from `/var/www/lacylights`
- Reverse proxy for GraphQL at `/graphql`
- WebSocket upgrade headers for `/ws`
- Gzip compression
- Proper MIME types
- Cache headers for static assets

### Step 5: Create systemd Service Files
**Files to create**:
- `lacylights-node/deploy/systemd/lacylights.service`
- `lacylights-node/scripts/setup-systemd.sh`

**Configuration**:
- Auto-start on boot
- Auto-restart on failure
- Proper working directory
- Environment variables
- Logging to systemd journal

### Step 6: Build Auto-Update System
**Files to create**:
- `lacylights-node/scripts/auto-update.sh`
- `lacylights-node/scripts/setup-auto-update.sh`
- `lacylights-node/deploy/config/update.conf` (config file)

**Features**:
- Daily check at 3am (configurable)
- Git pull from main branch
- npm install & build
- Run tests before restart
- Rollback on failure
- Configurable enable/disable
- Logging to `/var/lib/lacylights/logs/update.log`

### Step 7: Create Enhanced Deployment Scripts
**Files to create/modify**:
- `lacylights-node/scripts/deploy-pi-full.sh` (enhanced from existing)
- `lacylights-node/scripts/migrate-to-sqlite.sh`
- `lacylights-node/scripts/install-nginx.sh`

**Deployment Flow**:
1. Check SSH connection
2. Install system dependencies (nginx, sqlite3)
3. Clone/update repositories (both backend & frontend)
4. Build backend
5. Build frontend static export
6. Deploy frontend to `/var/www/lacylights`
7. Migrate database to SQLite
8. Configure nginx
9. Configure systemd
10. Setup auto-update
11. Start services

### Step 8: Deploy to Raspberry Pi
**Target**: lacylights.local
**Prerequisites**:
- SSH access configured
- Raspberry Pi on network
- Internet connection for dependencies

**Execution**:
```bash
cd lacylights-node
./scripts/deploy-pi-full.sh
```

**Post-deployment verification**:
- [ ] Backend accessible at http://lacylights.local/graphql
- [ ] Frontend loads at http://lacylights.local
- [ ] WebSocket subscriptions work
- [ ] DMX output working
- [ ] Auto-update configured
- [ ] Services auto-start on reboot

---

## File System Layout (Target on Pi)

```
/opt/lacylights/
├── backend/                       # lacylights-node repository
│   ├── dist/                     # Built Node.js server
│   ├── prisma/                   # Database schema
│   ├── scripts/                  # Utility scripts
│   └── package.json
├── frontend/                      # lacylights-fe repository
│   └── out/                      # Built static files
└── scripts/                       # Shared deployment scripts

/var/lib/lacylights/
├── db.sqlite                      # SQLite database
├── db.sqlite-wal                 # Write-ahead log
├── db.sqlite-shm                 # Shared memory
├── backups/                       # Daily automatic backups
│   ├── db-2025-10-06.sqlite
│   └── ...
└── logs/
    ├── backend.log
    ├── update.log
    └── nginx-access.log -> /var/log/nginx/lacylights-access.log

/var/www/lacylights/               # Frontend static files (symlink)
├── index.html
├── _next/
│   ├── static/
│   └── ...
└── ...

/etc/lacylights/
└── config.json                    # User-editable configuration
    {
      "auto_update_enabled": true,
      "auto_update_time": "03:00",
      "artnet_broadcast": "255.255.255.255",
      "dmx_universes": 4,
      "backup_retention_days": 30
    }

/etc/nginx/sites-available/
└── lacylights.conf               # nginx configuration

/etc/systemd/system/
└── lacylights.service            # systemd service
```

---

## Environment Variables (Production)

**Backend (.env)**:
```bash
NODE_ENV=production
DATABASE_URL=file:/var/lib/lacylights/db.sqlite
PORT=4000
NON_INTERACTIVE=true
ARTNET_BROADCAST=255.255.255.255
DMX_UNIVERSE_COUNT=4
DMX_REFRESH_RATE=44
DMX_IDLE_RATE=1
```

**Frontend (build time)**:
```bash
NEXT_PUBLIC_GRAPHQL_HTTP=/graphql
NEXT_PUBLIC_GRAPHQL_WS=/ws
```

---

## Testing Strategy

### Unit Tests
- Run existing test suites in both repos
- All tests must pass before deployment

### Integration Tests
1. **Database Migration**: Export test data from Postgres, import to SQLite, verify data integrity
2. **Frontend Build**: Verify all pages render in static export mode
3. **nginx Proxy**: Test GraphQL queries and WebSocket subscriptions through nginx
4. **Auto-update**: Run update script in dry-run mode

### End-to-End Tests
1. Deploy to test Raspberry Pi
2. Verify full lighting control workflow:
   - Create project
   - Add fixtures
   - Create looks
   - Build cue list
   - Run playback
   - Verify DMX output

---

## Rollback Plan

### Database Rollback
- Keep Postgres docker-compose.yml commented out
- Migration script creates backup before conversion
- Can restore to Postgres if needed

### Application Rollback
- Auto-update script automatically rolls back on test failure
- Git tags for each release
- Manual rollback: `git reset --hard <previous-tag> && npm install && npm run build`

---

## Future Enhancements (Post-MVP)

### Phase 2: Product Packaging
- [ ] Create SD card image builder
- [ ] First-boot setup wizard
- [ ] Web-based configuration UI
- [ ] Network configuration helper
- [ ] Backup/restore UI

### Phase 3: Advanced Features
- [ ] Remote access via VPN/tunnel
- [ ] Multi-device synchronization
- [ ] Cloud backup integration
- [ ] Analytics and usage tracking
- [ ] Remote diagnostics

### Phase 4: Production Hardening
- [ ] Read-only filesystem with overlay
- [ ] Watchdog timer
- [ ] Health monitoring
- [ ] Automatic log rotation
- [ ] Security hardening

---

## Success Criteria

### Minimum Viable Product (MVP)
- [x] Plan documented
- [ ] SQLite database working
- [ ] Static frontend export working
- [ ] nginx configuration complete
- [ ] systemd auto-start working
- [ ] Auto-update system functional
- [ ] Successfully deployed to test Pi
- [ ] Full lighting control workflow verified
- [ ] All unit tests passing
- [ ] Documentation updated

### Production Ready
- [ ] 72-hour continuous operation test
- [ ] Reboot recovery test (10x)
- [ ] Auto-update test with rollback
- [ ] Performance benchmarks documented
- [ ] User guide written
- [ ] Backup/restore tested

---

## Resources Used

### Memory Footprint (Target)
- Node.js Backend: ~100MB
- SQLite: ~10-20MB
- nginx: ~5MB
- OS + Services: ~200MB
- **Total**: ~350MB (leaves 650MB+ free on 1GB Pi)

### Disk Space (Target)
- Backend: ~100MB
- Frontend: ~50MB
- Database: ~10MB (grows with data)
- Logs: ~100MB (rotated)
- Backups: ~300MB (30 days retention)
- **Total**: ~560MB

### Network Usage
- Art-Net: ~22KB/s during active playback (44Hz × 512 bytes)
- Art-Net: ~0.5KB/s idle (1Hz keep-alive)
- WebSocket: ~1-5KB/s per connected client

---

## Maintenance & Operations

### Daily Automated Tasks
- 03:00 - Check for updates (if enabled)
- 04:00 - Database backup
- 05:00 - Log rotation

### Weekly Tasks
- Clean old logs (retain 7 days)
- Clean old backups (retain 30 days)

### Manual Monitoring
- Check `/var/lib/lacylights/logs/` for errors
- Monitor disk space: `df -h`
- Check service status: `systemctl status lacylights`

---

## Known Limitations

1. **Single User**: No multi-user authentication (single lighting operator assumed)
2. **No Clustering**: Single device, no high availability
3. **Local Network Only**: No built-in remote access
4. **SQLite Concurrency**: Single writer (not an issue for this use case)
5. **Manual Network Config**: No automatic network setup wizard (Phase 2)

---

## Notes & Decisions Log

**2025-10-06**: Initial plan created
- Chose SQLite over Postgres for efficiency
- Chose static export over SSR for simplicity
- Chose pull-based updates for safety
- Removed Redis (unused dependency)

---

## References

- [Next.js Static Export Docs](https://nextjs.org/docs/app/building-your-application/deploying/static-exports)
- [Prisma SQLite Provider](https://www.prisma.io/docs/concepts/database-connectors/sqlite)
- [nginx Reverse Proxy Guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Raspberry Pi OS Documentation](https://www.raspberrypi.com/documentation/computers/os.html)
