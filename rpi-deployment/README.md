# LacyLights Raspberry Pi Deployment

This directory contains scripts and configuration files for deploying LacyLights to a Raspberry Pi as a turnkey hardware product.

## Prerequisites

### Hardware
- Raspberry Pi 4 (2GB RAM minimum, 4GB recommended)
- MicroSD card (16GB minimum, 32GB recommended)
- Network connection (Ethernet recommended for Art-Net)

### Software
- Raspberry Pi OS Lite (64-bit) - Latest version
- SSH access enabled
- Internet connection

## Quick Start: Fresh Raspberry Pi Setup

For a brand new Raspberry Pi, follow these steps:

### 1. Prepare Raspberry Pi OS

Flash Raspberry Pi OS Lite (64-bit) to your microSD card using [Raspberry Pi Imager](https://www.raspberrypi.com/software/):

1. Choose "Raspberry Pi OS Lite (64-bit)"
2. Configure settings (click gear icon):
   - Enable SSH
   - Set hostname: `lacylights` (recommended)
   - Set username/password
   - Configure Wi-Fi if needed
3. Flash to SD card

### 2. Boot and Update

Insert SD card and boot the Raspberry Pi:

```bash
# SSH into the Pi
ssh pi@lacylights.local  # or use IP address

# Update system packages
sudo apt-get update
sudo apt-get upgrade -y
sudo reboot
```

### 3. Run Initial Setup

After reboot, run the setup script:

```bash
# Download and run setup script
curl -fsSL https://raw.githubusercontent.com/bbernstein/lacylights/main/rpi-deployment/setup-rpi.sh | sudo bash
```

This will:
- Install all system dependencies (Node.js, nginx, SQLite, etc.)
- Create `lacylights` system user
- Download latest releases of all three LacyLights repositories
- Set up database and run migrations
- Build backend, frontend, and MCP server
- Configure nginx as reverse proxy
- Install and start systemd service
- Enable version management

The setup takes 10-15 minutes depending on your Pi and network speed.

### 4. Access LacyLights

Once complete, access the web interface at:
- `http://lacylights.local` (if hostname is set to lacylights)
- `http://[raspberry-pi-ip]` (IP shown at end of setup)

## Version Management

### Viewing Current Versions

```bash
/opt/lacylights/scripts/update-repos.sh versions
```

### Updating to Latest Releases

Update all repositories:
```bash
sudo /opt/lacylights/scripts/update-repos.sh update-all
```

Update specific repository:
```bash
sudo /opt/lacylights/scripts/update-repos.sh update lacylights-node
sudo /opt/lacylights/scripts/update-repos.sh update lacylights-fe
sudo /opt/lacylights/scripts/update-repos.sh update lacylights-mcp
```

Update to specific version:
```bash
sudo /opt/lacylights/scripts/update-repos.sh update lacylights-node 1.3.5
```

### Web UI Version Management

You can also manage versions through the web interface:
1. Navigate to Settings page
2. Scroll to "Version Management" section
3. View installed and available versions
4. Click "Update" to update individual repositories
5. Click "Update All" to update everything

## File Structure

After installation:

```
/opt/lacylights/
├── backend/              # lacylights-node (backend server)
├── frontend-src/         # lacylights-fe (source + build)
│   └── out/             # Static export served by nginx
├── frontend -> frontend-src/out/  # Symlink for nginx
├── mcp/                 # lacylights-mcp (MCP server)
└── scripts/
    └── update-repos.sh  # Version management script

/var/lib/lacylights/
├── db.sqlite           # SQLite database
└── logs/               # Application logs

/etc/nginx/sites-available/
└── lacylights          # Nginx configuration

/etc/systemd/system/
└── lacylights-backend.service  # Systemd service
```

## Service Management

### Backend Service

```bash
# Check status
sudo systemctl status lacylights-backend

# Start/stop/restart
sudo systemctl start lacylights-backend
sudo systemctl stop lacylights-backend
sudo systemctl restart lacylights-backend

# View logs
sudo journalctl -u lacylights-backend -f

# Enable/disable auto-start
sudo systemctl enable lacylights-backend
sudo systemctl disable lacylights-backend
```

### Nginx

```bash
# Check status
sudo systemctl status nginx

# Test configuration
sudo nginx -t

# Reload configuration
sudo systemctl reload nginx
```

## Troubleshooting

### Backend won't start

```bash
# Check logs
sudo journalctl -u lacylights-backend -n 50

# Check if port 4000 is in use
sudo lsof -i :4000

# Verify database exists
ls -la /var/lib/lacylights/db.sqlite

# Try manual start to see errors
cd /opt/lacylights/backend
sudo -u lacylights node dist/index.js
```

### Frontend shows old version

```bash
# Rebuild frontend
cd /opt/lacylights/frontend-src
sudo -u lacylights npm run build

# Verify nginx is serving from correct location
ls -la /opt/lacylights/frontend

# Clear browser cache or try incognito mode
```

### Database issues

```bash
# Check database permissions
ls -la /var/lib/lacylights/db.sqlite

# Re-run migrations
cd /opt/lacylights/backend
sudo -u lacylights npx prisma migrate deploy

# Regenerate Prisma client
sudo -u lacylights npx prisma generate
```

### Version management not showing

```bash
# Verify update script exists and is executable
ls -la /opt/lacylights/scripts/update-repos.sh

# Test script manually
/opt/lacylights/scripts/update-repos.sh versions json

# Check backend logs for errors
sudo journalctl -u lacylights-backend | grep -i version
```

## Manual Deployment (Advanced)

If you prefer manual control or need to customize the deployment:

1. Install system dependencies:
   ```bash
   sudo apt-get install nodejs npm nginx sqlite3 curl tar
   ```

2. Create user and directories:
   ```bash
   sudo useradd -r -m -d /opt/lacylights -s /bin/bash lacylights
   sudo mkdir -p /opt/lacylights/{backend,frontend-src,mcp,scripts}
   sudo mkdir -p /var/lib/lacylights
   sudo chown -R lacylights:lacylights /opt/lacylights /var/lib/lacylights
   ```

3. Download latest releases manually from GitHub:
   - https://github.com/bbernstein/lacylights-node/releases/latest
   - https://github.com/bbernstein/lacylights-fe/releases/latest
   - https://github.com/bbernstein/lacylights-mcp/releases/latest

4. Extract to respective directories and follow build steps in each repo's README

## Security Considerations

- The setup script creates a dedicated `lacylights` user with limited permissions
- The systemd service runs with security restrictions (`ProtectSystem`, `ProtectHome`, etc.)
- Nginx acts as a reverse proxy, only exposing necessary endpoints
- SQLite database is stored in `/var/lib/lacylights` with restricted permissions
- No passwords or secrets are committed to the repositories

## Network Configuration

### Art-Net Setup

Configure Art-Net broadcast address through the web UI:
1. Go to Settings → Art-Net Configuration
2. Select your network interface
3. The system will broadcast DMX data to that subnet

### Port Usage

- **Port 80 (HTTP)**: Nginx serves frontend and proxies API
- **Port 4000**: Backend GraphQL API (proxied by nginx)
- **Port 6454 (UDP)**: Art-Net broadcast (DMX output)

### Firewall

If you have a firewall enabled, allow:
```bash
sudo ufw allow 80/tcp
sudo ufw allow 6454/udp
```

## Contributing

To improve the deployment scripts:
1. Fork the [lacylights repository](https://github.com/bbernstein/lacylights)
2. Make changes in the `rpi-deployment/` directory
3. Test on a fresh Raspberry Pi
4. Submit a pull request

## Support

For issues or questions:
- GitHub Issues: https://github.com/bbernstein/lacylights/issues
- Backend Issues: https://github.com/bbernstein/lacylights-node/issues
- Frontend Issues: https://github.com/bbernstein/lacylights-fe/issues
