# LacyLights RPi Repository Proposal

## Overview

Create a new repository `lacylights-rpi` to contain all Raspberry Pi-specific deployment, setup, and configuration code for the LacyLights hardware product.

## Why a Separate Repository?

### Current Structure
```
lacylights/           # General documentation and links
lacylights-node/      # Backend application code
lacylights-fe/        # Frontend application code
lacylights-mcp/       # MCP server code
lacylights/           # Umbrella docs (this repo)
```

### Problem
- No centralized place for RPi-specific deployment tooling
- Deployment scripts mixed with application code
- Setup instructions scattered across repos
- No version control for systemd services and configs

### Solution: `lacylights-rpi` Repository

A dedicated repository for everything related to deploying and running LacyLights on Raspberry Pi hardware.

---

## Proposed Repository Structure

```
lacylights-rpi/
├── README.md                          # Main documentation
├── scripts/
│   ├── deploy.sh                      # General deployment script
│   ├── setup-new-pi.sh               # Initial Pi setup
│   ├── install-dependencies.sh       # Install system dependencies
│   ├── update-service.sh             # Update and restart service
│   └── backup.sh                     # Backup configuration and data
├── systemd/
│   ├── lacylights.service            # Systemd service file
│   └── lacylights-mcp.service        # MCP server service (if separate)
├── config/
│   ├── .env.example                  # Environment variables template
│   ├── nginx.conf.example            # Nginx reverse proxy config
│   └── sudoers.d/lacylights         # Sudoers configuration for WiFi
├── setup/
│   ├── 01-system-setup.sh           # OS configuration
│   ├── 02-network-setup.sh          # NetworkManager setup
│   ├── 03-database-setup.sh         # PostgreSQL setup
│   ├── 04-permissions-setup.sh      # User permissions
│   └── 05-service-install.sh        # Install services
├── docs/
│   ├── DEPLOYMENT.md                 # Deployment guide
│   ├── INITIAL_SETUP.md             # New Pi setup guide
│   ├── TROUBLESHOOTING.md           # Common issues
│   ├── WIFI_SETUP.md                # WiFi configuration
│   └── UPDATING.md                  # Update procedures
├── utils/
│   ├── check-health.sh              # Health check script
│   ├── view-logs.sh                 # Log viewer helper
│   └── wifi-diagnostic.sh           # WiFi troubleshooting
└── tests/
    ├── test-deployment.sh           # Test deployment process
    └── test-services.sh             # Test all services running
```

---

## Key Scripts

### `scripts/deploy.sh` - General Deployment Script

**Purpose:** Deploy latest code from development machine to RPi

**Features:**
- Deploy backend, frontend, and MCP server
- Type checking before deployment
- Automatic rebuild on Pi
- Service restart
- Health verification
- Works for ANY code changes (not feature-specific)

**Usage:**
```bash
./scripts/deploy.sh                    # Deploy all components
./scripts/deploy.sh --backend-only     # Deploy only backend
./scripts/deploy.sh --frontend-only    # Deploy only frontend
./scripts/deploy.sh --skip-rebuild     # Sync files only, no rebuild
```

### `scripts/setup-new-pi.sh` - Initial Setup

**Purpose:** Complete setup of a fresh Raspberry Pi for LacyLights

**Features:**
- Install all system dependencies
- Configure NetworkManager for WiFi
- Setup PostgreSQL database
- Create systemd services
- Configure permissions
- Clone and build all repos
- One-command setup for new devices

**Usage:**
```bash
./scripts/setup-new-pi.sh pi@lacylights.local
```

### `scripts/install-dependencies.sh` - System Dependencies

**Purpose:** Install all required system packages

**Installs:**
- Node.js (v20+)
- PostgreSQL
- NetworkManager
- Nginx (optional)
- Build tools
- Git

### `scripts/update-service.sh` - Service Management

**Purpose:** Update and restart LacyLights services

**Usage:**
```bash
./scripts/update-service.sh             # Update all services
./scripts/update-service.sh backend     # Update only backend
```

---

## Configuration Files

### `systemd/lacylights.service`

Complete systemd service definition:
```ini
[Unit]
Description=LacyLights Stage Lighting Control
After=network.target postgresql.service

[Service]
Type=simple
User=lacylights
Group=lacylights
WorkingDirectory=/opt/lacylights/backend
Environment="NODE_ENV=production"
Environment="PORT=4000"
EnvironmentFile=/opt/lacylights/backend/.env
ExecStart=/usr/bin/node /opt/lacylights/backend/dist/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### `config/sudoers.d/lacylights`

WiFi permissions:
```
# LacyLights WiFi management permissions
lacylights ALL=(ALL) NOPASSWD: /usr/bin/nmcli device wifi *
lacylights ALL=(ALL) NOPASSWD: /usr/bin/nmcli connection *
lacylights ALL=(ALL) NOPASSWD: /usr/bin/nmcli radio wifi *
```

### `config/.env.example`

Environment variables template:
```bash
# Database
DATABASE_URL="postgresql://lacylights:password@localhost:5432/lacylights"

# Server
PORT=4000
NODE_ENV=production

# DMX/Art-Net
ARTNET_ENABLED=true
ARTNET_BROADCAST=192.168.1.255
DMX_UNIVERSE_COUNT=4

# WiFi
WIFI_ENABLED=true
WIFI_DEVICE=wlan0
```

---

## Setup Scripts

### Complete Initial Setup Workflow

```bash
# 1. Clone the RPi repository
git clone https://github.com/bbernstein/lacylights-rpi.git
cd lacylights-rpi

# 2. Run complete setup on new Pi
./scripts/setup-new-pi.sh pi@lacylights.local

# This script will:
# - Install all dependencies
# - Setup database
# - Clone all repos (node, fe, mcp)
# - Build all projects
# - Install systemd services
# - Configure permissions
# - Start services
```

### Regular Deployment Workflow

```bash
# After making changes to any repo, deploy to Pi:
cd lacylights-rpi
./scripts/deploy.sh

# Or for specific components:
./scripts/deploy.sh --backend-only
./scripts/deploy.sh --frontend-only
```

---

## Benefits

### 1. **Single Source of Truth**
- All RPi-specific code in one place
- Version controlled deployment scripts
- Documented setup procedures

### 2. **Reusability**
- Deploy script works for ANY code changes
- Setup script works for ANY new Pi
- No feature-specific scripts needed

### 3. **Team Collaboration**
- Easy for others to deploy to their own Pi
- Standardized setup process
- Shared configuration templates

### 4. **Product Focus**
- RPi as a product has its own repo
- Separate from application code
- Infrastructure as Code

### 5. **Testing**
- Test deployment process separately
- Verify health checks work
- Validate setup scripts

### 6. **Documentation**
- Centralized deployment docs
- Troubleshooting guides
- WiFi setup instructions

---

## Migration Plan

### Phase 1: Create Repository
```bash
# On GitHub, create new repo: bbernstein/lacylights-rpi
# Then locally:
cd ~/src/lacylights
mkdir lacylights-rpi
cd lacylights-rpi
git init
git remote add origin https://github.com/bbernstein/lacylights-rpi.git
```

### Phase 2: Create Initial Structure
- Copy deployment script as `scripts/deploy.sh`
- Create systemd service files
- Create setup scripts
- Add documentation

### Phase 3: Test Deployment
- Test deploy.sh against your Pi
- Verify all services work
- Document any issues

### Phase 4: Create Setup Script
- Build setup-new-pi.sh for fresh installs
- Test on a clean Pi (or Pi image)
- Document the process

### Phase 5: Polish
- Add utilities (logs, health checks)
- Add troubleshooting docs
- Create README with quick start

---

## Example Usage

### Developer Workflow

**Day 1: Initial Setup**
```bash
git clone https://github.com/bbernstein/lacylights-rpi.git
cd lacylights-rpi
./scripts/setup-new-pi.sh pi@lacylights.local
# Wait 10-15 minutes for complete setup
# Visit http://lacylights.local
```

**Day 2: Make Code Changes**
```bash
cd lacylights-node
# Make changes to backend
git commit -m "Add new feature"

cd ../lacylights-rpi
./scripts/deploy.sh
# Changes deployed in ~2 minutes
```

**Day 3: Debugging**
```bash
cd lacylights-rpi
./utils/view-logs.sh          # View service logs
./utils/check-health.sh       # Check system health
./utils/wifi-diagnostic.sh    # Debug WiFi issues
```

---

## Immediate Next Steps

1. **Create GitHub Repository**
   - Repository name: `lacylights-rpi`
   - Description: "Raspberry Pi deployment and setup for LacyLights stage lighting control"
   - Public or Private: Your choice

2. **Create Local Structure**
   - Initialize repository
   - Create directory structure
   - Move deployment script

3. **Test First Deployment**
   - Use new deploy.sh script
   - Verify it works with current Pi
   - Document any issues

4. **Add to Documentation**
   - Update main lacylights README
   - Link to RPi repository
   - Document deployment workflow

---

## Questions to Consider

1. **Service Architecture**
   - Run backend + frontend in one service? (current)
   - Or separate services? (more flexible)

2. **MCP Server**
   - Run as part of backend service?
   - Or separate systemd service?
   - Or on-demand only?

3. **Database**
   - PostgreSQL on Pi? (current)
   - Or SQLite for simplicity?

4. **Reverse Proxy**
   - Direct access to ports?
   - Or Nginx reverse proxy?

5. **Auto-Updates**
   - Manual deployment only?
   - Or auto-update from GitHub releases?

---

## Conclusion

A dedicated `lacylights-rpi` repository will:
- ✅ Provide general-purpose deployment tools
- ✅ Centralize all RPi-specific code
- ✅ Make setup reproducible and documented
- ✅ Separate product infrastructure from application code
- ✅ Enable easy collaboration and testing

This is a much better architecture than feature-specific deployment scripts scattered across repos!

**Ready to create the repository?**
