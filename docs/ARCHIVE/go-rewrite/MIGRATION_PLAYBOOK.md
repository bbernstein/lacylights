# LacyLights Migration Playbook
## Node.js → Go Backend Migration Guide

**Status:** Ready to Execute
**Risk Level:** 🟢 LOW
**Estimated Downtime:** 0 minutes (zero-downtime migration possible)

---

## Pre-Flight Checklist

### ✅ Prerequisites Verified
- [x] Schema compatibility confirmed (100% match)
- [x] Go can read Node's SQLite database
- [x] Foreign keys and constraints are identical
- [x] Data types are compatible
- [x] WAL mode enabled for concurrent access

### ⏳ Prerequisites To Complete
- [ ] Go write operations tested successfully
- [ ] CUID generation compatibility verified
- [ ] Timestamp format consistency confirmed
- [ ] Performance benchmarks acceptable
- [ ] Backup procedures tested

---

## Migration Strategies

### Strategy 1: Instant Cutover (Fastest, Higher Risk)

**Duration:** ~5 minutes
**Downtime:** ~30 seconds
**Best for:** Low-traffic systems, testing environments

#### Steps:
```bash
# 1. Backup database
cd ~/src/lacylights/lacylights-node/prisma
sqlite3 dev.db ".backup dev-backup-$(date +%Y%m%d-%H%M%S).db"

# 2. Stop Node backend
cd ~/src/lacylights/lacylights-node
npm run stop

# 3. Copy database to Go directory
cp prisma/dev.db ../lacylights-go/dev.db

# 4. Start Go backend
cd ~/src/lacylights/lacylights-go
DATABASE_URL="file:./dev.db" ./bin/server

# 5. Verify health
curl http://localhost:4000/health
```

**Rollback:**
```bash
# Stop Go, restore backup, start Node
cd ~/src/lacylights/lacylights-go && pkill -f server
cd ~/src/lacylights/lacylights-node
cp prisma/dev-backup-*.db prisma/dev.db
npm start
```

---

### Strategy 2: Shared Database (Zero Downtime, Gradual)

**Duration:** 1-2 weeks
**Downtime:** 0 seconds
**Best for:** Production systems, risk-averse migrations

#### Steps:

##### Week 1: Setup Shared Database
```bash
# 1. Backup Node database
cd ~/src/lacylights/lacylights-node/prisma
sqlite3 dev.db ".backup dev-backup-$(date +%Y%m%d).db"

# 2. Create shared database location
mkdir -p ~/src/lacylights/shared
cp dev.db ~/src/lacylights/shared/lacylights.db

# 3. Point Node to shared database
cd ~/src/lacylights/lacylights-node
echo "DATABASE_URL=\"file:../shared/lacylights.db\"" > .env.migration
npm run stop
DATABASE_URL="file:../shared/lacylights.db" npm start

# 4. Point Go to shared database (read-only initially)
cd ~/src/lacylights/lacylights-go
echo "DATABASE_URL=\"file:../shared/lacylights.db\"" > .env.migration
echo "READ_ONLY_MODE=true" >> .env.migration
# Start Go backend on different port
PORT=4001 DATABASE_URL="file:../shared/lacylights.db" ./bin/server

# 5. Verify both can read
curl http://localhost:4000/health  # Node
curl http://localhost:4001/health  # Go
```

##### Week 2: Enable Go Writes
```bash
# 1. Remove read-only mode from Go
cd ~/src/lacylights/lacylights-go
sed -i '' '/READ_ONLY_MODE/d' .env.migration

# 2. Restart Go backend
pkill -f "bin/server"
DATABASE_URL="file:../shared/lacylights.db" ./bin/server

# 3. Use feature flags to route traffic
# - Route 10% of queries to Go
# - Monitor for errors
# - Gradually increase to 50%, then 100%
```

##### Week 3: Full Cutover
```bash
# 1. Route 100% traffic to Go
# 2. Keep Node running for 48 hours as hot standby
# 3. Monitor logs and metrics

# 4. After 48 hours, stop Node
cd ~/src/lacylights/lacylights-node
npm run stop

# 5. Archive Node backend
cd ~/src/lacylights
tar czf node-backend-archive-$(date +%Y%m%d).tar.gz lacylights-node/
```

---

### Strategy 3: Blue-Green Deployment (Most Robust)

**Duration:** 1 day
**Downtime:** ~5 seconds (DNS/routing switch)
**Best for:** Critical production systems

#### Steps:

##### Phase 1: Setup Green (Go) Environment
```bash
# 1. Copy production database to green environment
scp user@prod:/path/to/lacylights.db ./lacylights-go/prod.db

# 2. Start Go backend on separate port
cd ~/src/lacylights/lacylights-go
DATABASE_URL="file:./prod.db" PORT=4001 ./bin/server

# 3. Run smoke tests
curl http://localhost:4001/health
# Run integration test suite
make test-integration
```

##### Phase 2: Parallel Testing
```bash
# 1. Send duplicate read traffic to both backends
# - Use load balancer to split traffic
# - Compare responses for consistency

# 2. Monitor for differences
# - Log mismatches
# - Fix any discrepancies in Go

# 3. Run for 24 hours
```

##### Phase 3: Cutover
```bash
# 1. Stop writes to blue (Node)
# 2. Copy final database state to green (Go)
# 3. Switch load balancer to green
# 4. Keep blue running as backup for 48 hours
# 5. Decommission blue
```

---

## Critical Commands Reference

### Database Operations

#### Backup
```bash
# Online backup (safe during operation)
sqlite3 dev.db ".backup backup.db"

# Filesystem copy (stop writes first)
cp dev.db backup.db

# Compressed backup with timestamp
sqlite3 dev.db ".backup /dev/stdout" | gzip > backup-$(date +%Y%m%d-%H%M%S).db.gz
```

#### Restore
```bash
# From .db file
cp backup.db dev.db

# From compressed backup
gunzip -c backup.db.gz > dev.db

# From SQL dump
sqlite3 new.db < dump.sql
```

#### Verify Integrity
```bash
# Check for corruption
sqlite3 dev.db "PRAGMA integrity_check;"

# Check foreign keys
sqlite3 dev.db "PRAGMA foreign_key_check;"

# Get database size
ls -lh dev.db
```

### Service Management

#### Node Backend
```bash
# Start
cd ~/src/lacylights/lacylights-node
npm start

# Stop
npm run stop

# Restart
npm run stop && npm start

# Check status
ps aux | grep "node.*index.js"

# View logs
tail -f logs/app.log
```

#### Go Backend
```bash
# Build
cd ~/src/lacylights/lacylights-go
make build

# Start
./bin/server

# Start with custom port
PORT=4001 ./bin/server

# Start in background
nohup ./bin/server > logs/server.log 2>&1 &

# Stop
pkill -f "bin/server"

# Check status
ps aux | grep "bin/server"
```

### Health Checks

#### Node
```bash
# Health endpoint
curl http://localhost:4000/health

# GraphQL introspection
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{__schema{types{name}}}"}'
```

#### Go
```bash
# Health endpoint
curl http://localhost:4000/health

# GraphQL introspection
curl -X POST http://localhost:4000/query \
  -H "Content-Type: application/json" \
  -d '{"query": "{__schema{types{name}}}"}'
```

### Database Monitoring

#### Active Connections
```bash
# Check for locks
sqlite3 dev.db ".timeout 1000" "BEGIN IMMEDIATE; ROLLBACK;"

# Show WAL file size
ls -lh dev.db-wal

# Checkpoint WAL
sqlite3 dev.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

#### Performance Metrics
```bash
# Query analysis
sqlite3 dev.db "EXPLAIN QUERY PLAN SELECT * FROM scenes WHERE project_id = 'xxx';"

# Table sizes
sqlite3 dev.db "SELECT name, SUM(pgsize) as size FROM dbstat GROUP BY name ORDER BY size DESC;"

# Index usage
sqlite3 dev.db "SELECT * FROM sqlite_stat1;"
```

---

## Monitoring & Validation

### Key Metrics to Track

#### Database Metrics
- [ ] Database file size
- [ ] WAL file size (should be < 10MB normally)
- [ ] Query latency (p50, p95, p99)
- [ ] Lock contention (SQLITE_BUSY errors)
- [ ] Checkpoint frequency

#### Application Metrics
- [ ] Request latency
- [ ] Error rate
- [ ] Throughput (requests/second)
- [ ] Memory usage
- [ ] CPU usage

#### Correctness Metrics
- [ ] CUID format validation
- [ ] Timestamp format consistency
- [ ] JSON serialization errors
- [ ] Foreign key violations

### Validation Queries

#### Data Integrity
```sql
-- Count records in each table
SELECT 'users' as table_name, COUNT(*) as count FROM users
UNION ALL SELECT 'projects', COUNT(*) FROM projects
UNION ALL SELECT 'scenes', COUNT(*) FROM scenes
UNION ALL SELECT 'fixture_instances', COUNT(*) FROM fixture_instances
UNION ALL SELECT 'cue_lists', COUNT(*) FROM cue_lists;

-- Check for orphaned records
SELECT COUNT(*) FROM fixture_instances fi
LEFT JOIN projects p ON fi.project_id = p.id
WHERE p.id IS NULL;

-- Verify foreign keys
PRAGMA foreign_key_check;

-- Check unique constraints
SELECT scene_id, fixture_id, COUNT(*)
FROM fixture_values
GROUP BY scene_id, fixture_id
HAVING COUNT(*) > 1;
```

#### Schema Validation
```bash
# Compare schemas between Node and Go databases
diff <(sqlite3 node/dev.db ".schema") <(sqlite3 go/dev.db ".schema")

# Verify pragmas
sqlite3 dev.db "PRAGMA journal_mode; PRAGMA synchronous;"
```

---

## Testing Checklist

### Phase 1: Read Operations ✅ COMPLETED
- [x] Read all tables
- [x] Traverse foreign keys
- [x] Parse JSON fields
- [x] Load related entities

### Phase 2: Write Operations ⏳ REQUIRED
- [ ] Create new records
- [ ] Update existing records
- [ ] Delete records
- [ ] Test cascade deletes
- [ ] Verify CUID generation
- [ ] Test transactions
- [ ] Test concurrent writes

### Phase 3: Performance ⏳ RECOMMENDED
- [ ] Benchmark read latency
- [ ] Benchmark write latency
- [ ] Test with large datasets
- [ ] Test concurrent operations
- [ ] Measure memory usage
- [ ] Profile CPU usage

### Phase 4: Edge Cases ⏳ RECOMMENDED
- [ ] Test with NULL values
- [ ] Test with empty JSON arrays
- [ ] Test with long strings
- [ ] Test with special characters
- [ ] Test with maximum values
- [ ] Test constraint violations

---

## Troubleshooting Guide

### Issue: "database is locked"

**Cause:** Multiple writers, no WAL mode, or busy timeout too low

**Solution:**
```bash
# Verify WAL mode is enabled
sqlite3 dev.db "PRAGMA journal_mode;"
# Should return: wal

# If not WAL, enable it
sqlite3 dev.db "PRAGMA journal_mode=WAL;"

# Increase busy timeout
sqlite3 dev.db "PRAGMA busy_timeout=10000;"
```

### Issue: "foreign key constraint failed"

**Cause:** Trying to insert/delete records with invalid foreign keys

**Solution:**
```bash
# Check which constraint failed
sqlite3 dev.db "PRAGMA foreign_key_check;"

# Disable foreign keys temporarily (NOT RECOMMENDED for production)
sqlite3 dev.db "PRAGMA foreign_keys=OFF;"
```

### Issue: "UNIQUE constraint failed"

**Cause:** Trying to insert duplicate values in unique column

**Solution:**
```bash
# Find duplicate records
sqlite3 dev.db "SELECT email, COUNT(*) FROM users GROUP BY email HAVING COUNT(*) > 1;"

# Fix duplicates before migration
```

### Issue: "malformed database"

**Cause:** Corruption, incomplete write, or interrupted migration

**Solution:**
```bash
# Try to recover
sqlite3 dev.db ".recover" > recovered.sql
sqlite3 new.db < recovered.sql

# If recovery fails, restore from backup
cp backup.db dev.db
```

### Issue: Go can't parse timestamps

**Cause:** Timestamp format mismatch between Node and Go

**Solution:**
```go
// In Go, parse timestamps flexibly
t, err := time.Parse(time.RFC3339, timestampStr)
if err != nil {
    // Try alternative format
    t, err = time.Parse("2006-01-02 15:04:05", timestampStr)
}
```

### Issue: CUIDs look different

**Cause:** Different CUID generation libraries

**Solution:**
```bash
# Verify CUID format (should be 25 chars, start with 'c')
sqlite3 dev.db "SELECT id FROM users LIMIT 5;"

# Both should produce valid CUIDs
# Node: uses @paralleldrive/cuid2
# Go: use github.com/lucsky/cuid
```

---

## Performance Optimization

### SQLite Tuning

```bash
# Apply these pragmas for better performance
sqlite3 dev.db << EOF
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;
PRAGMA cache_size=-64000;  -- 64MB cache
PRAGMA temp_store=MEMORY;
PRAGMA mmap_size=30000000000;  -- 30GB mmap
PRAGMA page_size=4096;
EOF
```

### GORM Optimizations

```go
// In database connection setup
db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{
    PrepareStmt:            true,  // Cache prepared statements
    SkipDefaultTransaction: true,  // Better read performance
    Logger:                 logger.Default.LogMode(logger.Silent),
})

// For read-heavy operations, use connection pooling
sqlDB, _ := db.DB()
sqlDB.SetMaxIdleConns(10)
sqlDB.SetMaxOpenConns(100)
sqlDB.SetConnMaxLifetime(time.Hour)
```

### Query Optimization

```go
// Use Preload for relationships
db.Preload("Fixtures").Preload("Scenes").Find(&projects)

// Use Select to limit columns
db.Select("id", "name").Find(&projects)

// Use pagination
db.Limit(100).Offset(0).Find(&scenes)
```

---

## Rollback Procedures

### Rollback During Migration (Strategy 1)

**Time Window:** Within 5 minutes of cutover

```bash
# 1. Stop Go backend immediately
cd ~/src/lacylights/lacylights-go
pkill -f "bin/server"

# 2. Restore database from backup
cd ~/src/lacylights/lacylights-node/prisma
cp dev-backup-*.db dev.db

# 3. Restart Node backend
cd ~/src/lacylights/lacylights-node
npm start

# 4. Verify health
curl http://localhost:4000/health

# 5. Investigate issue
cd ~/src/lacylights/lacylights-go
tail -100 logs/server.log
```

### Rollback After Dual-Backend (Strategy 2)

**Time Window:** Within 2 weeks of migration

```bash
# 1. Stop Go backend
cd ~/src/lacylights/lacylights-go
pkill -f "bin/server"

# 2. Point Node to shared database (it's already there)
# 3. Route all traffic back to Node
# 4. Keep shared database, don't restore backup

# 5. Investigate and fix Go issues
cd ~/src/lacylights/lacylights-go
make test
go run ./cmd/server
```

### Data Recovery

```bash
# If corruption detected
sqlite3 corrupt.db ".dump" | sqlite3 recovered.db

# If partial data loss
# 1. Stop both backends
# 2. Restore from most recent backup
# 3. Replay transactions from WAL if available

sqlite3 dev.db ".backup backup.db"
sqlite3 backup.db "PRAGMA wal_checkpoint(FULL);"
```

---

## Success Criteria

### Migration is Successful When:
- [ ] Go backend serves all traffic for 48 hours
- [ ] Zero data corruption detected
- [ ] Error rate < 0.1%
- [ ] P95 latency < 100ms (or equal to Node)
- [ ] No foreign key violations
- [ ] All integration tests pass
- [ ] Database size remains stable
- [ ] WAL checkpointing occurs regularly

### Migration Can Be Finalized When:
- [ ] All success criteria met
- [ ] Team confidence is high
- [ ] Rollback plan tested and ready
- [ ] Node backend archived
- [ ] Documentation updated
- [ ] Stakeholders notified

---

## Post-Migration Tasks

### Immediate (Day 1-7)
- [ ] Monitor error logs daily
- [ ] Check database integrity daily
- [ ] Verify backup procedures
- [ ] Update documentation
- [ ] Train team on Go backend operations

### Short-term (Week 2-4)
- [ ] Optimize slow queries
- [ ] Add monitoring dashboards
- [ ] Set up alerting
- [ ] Performance tuning
- [ ] Decommission Node backend

### Long-term (Month 2+)
- [ ] Archive Node codebase
- [ ] Update deployment procedures
- [ ] Migrate CI/CD pipelines
- [ ] Update runbooks
- [ ] Post-mortem review

---

## Emergency Contacts

### Escalation Path
1. **Primary:** Check logs and metrics
2. **Secondary:** Rollback to Node backend
3. **Tertiary:** Restore from backup
4. **Last Resort:** Contact database expert

### Key Files and Locations
```
Database:        ~/src/lacylights/shared/lacylights.db
Node Backend:    ~/src/lacylights/lacylights-node/
Go Backend:      ~/src/lacylights/lacylights-go/
Backups:         ~/src/lacylights/backups/
Logs:            ./logs/server.log
Config:          .env.migration
```

---

## Quick Reference Commands

```bash
# Backup database
sqlite3 dev.db ".backup backup-$(date +%Y%m%d).db"

# Check database health
sqlite3 dev.db "PRAGMA integrity_check; PRAGMA foreign_key_check;"

# Start Node backend
cd lacylights-node && npm start

# Start Go backend
cd lacylights-go && ./bin/server

# Stop all backends
pkill -f "node.*index" && pkill -f "bin/server"

# View logs
tail -f lacylights-node/logs/app.log
tail -f lacylights-go/logs/server.log

# Health check
curl http://localhost:4000/health
```

---

**Last Updated:** 2025-11-30
**Version:** 1.0
**Status:** Ready for execution after Phase 2 testing
