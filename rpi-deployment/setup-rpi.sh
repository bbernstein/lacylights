#!/bin/bash
#
# LacyLights Raspberry Pi Initial Setup Script
# Sets up a fresh Raspberry Pi with LacyLights from GitHub releases
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/bbernstein/lacylights/main/rpi-deployment/setup-rpi.sh | sudo bash
#
# Or copy to RPi and run:
#   sudo bash setup-rpi.sh
#

set -e

echo "=========================================="
echo "LacyLights Raspberry Pi Setup"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Configuration
INSTALL_DIR="/opt/lacylights"
DATA_DIR="/var/lib/lacylights"
LACYLIGHTS_USER="lacylights"

# GitHub repos
BACKEND_REPO="bbernstein/lacylights-node"
FRONTEND_REPO="bbernstein/lacylights-fe"
MCP_REPO="bbernstein/lacylights-mcp"

echo "Step 1: Installing system dependencies..."
echo "==========================================="
apt-get update
apt-get install -y \
    nodejs \
    npm \
    nginx \
    sqlite3 \
    curl \
    tar \
    git

echo "✓ System dependencies installed"
echo ""

echo "Step 2: Creating lacylights user..."
echo "==========================================="
if ! id -u "$LACYLIGHTS_USER" > /dev/null 2>&1; then
    useradd -r -m -d "$INSTALL_DIR" -s /bin/bash "$LACYLIGHTS_USER"
    echo "✓ Created user: $LACYLIGHTS_USER"
else
    echo "✓ User already exists: $LACYLIGHTS_USER"
fi
echo ""

echo "Step 3: Creating directories..."
echo "==========================================="
mkdir -p "$INSTALL_DIR"/{backend,frontend-src,mcp,scripts}
mkdir -p "$DATA_DIR"
mkdir -p /var/log/lacylights
chown -R "$LACYLIGHTS_USER:$LACYLIGHTS_USER" "$INSTALL_DIR"
chown -R "$LACYLIGHTS_USER:$LACYLIGHTS_USER" "$DATA_DIR"
chown -R "$LACYLIGHTS_USER:$LACYLIGHTS_USER" /var/log/lacylights
echo "✓ Directories created"
echo ""

echo "Step 4: Downloading update-repos.sh script..."
echo "==========================================="
curl -fsSL "https://raw.githubusercontent.com/bbernstein/lacylights/main/rpi-deployment/update-repos.sh" \
    -o "$INSTALL_DIR/scripts/update-repos.sh"
chmod +x "$INSTALL_DIR/scripts/update-repos.sh"
chown "$LACYLIGHTS_USER:$LACYLIGHTS_USER" "$INSTALL_DIR/scripts/update-repos.sh"
echo "✓ Update script downloaded"
echo ""

echo "Step 5: Downloading latest releases..."
echo "==========================================="

# Function to download and extract latest release
download_release() {
    local repo="$1"
    local target_dir="$2"

    echo "Downloading latest release of $repo..."

    # Get latest release tag
    local latest_tag=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"tag_name": "v?([^"]+)".*/\1/')

    if [ -z "$latest_tag" ]; then
        echo "Error: Could not determine latest release for $repo"
        return 1
    fi

    echo "  Latest version: $latest_tag"

    # Download tarball
    local temp_dir=$(mktemp -d)
    curl -L -o "$temp_dir/release.tar.gz" \
        "https://github.com/$repo/archive/refs/tags/v${latest_tag}.tar.gz"

    # Extract
    tar -xzf "$temp_dir/release.tar.gz" -C "$temp_dir"

    # Find extracted directory
    local extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d)

    # Move files to target
    mkdir -p "$target_dir"
    cp -r "$extracted_dir"/* "$target_dir/"

    # Write version file
    echo "$latest_tag" > "$target_dir/.lacylights-version"

    # Cleanup
    rm -rf "$temp_dir"

    echo "  ✓ Installed to $target_dir"
}

# Download all three repositories
download_release "$BACKEND_REPO" "$INSTALL_DIR/backend"
download_release "$FRONTEND_REPO" "$INSTALL_DIR/frontend-src"
download_release "$MCP_REPO" "$INSTALL_DIR/mcp"

echo "✓ All releases downloaded"
echo ""

echo "Step 6: Setting up backend..."
echo "==========================================="
cd "$INSTALL_DIR/backend"

# Create .env file
cat > .env <<EOF
# Database
DATABASE_URL="file:$DATA_DIR/db.sqlite"

# Server
PORT=4000
NODE_ENV=production

# DMX
DMX_UNIVERSE_COUNT=4
DMX_REFRESH_RATE=44

# Session
SESSION_SECRET=$(openssl rand -hex 32)
EOF

# Install dependencies
echo "Installing backend dependencies..."
sudo -u "$LACYLIGHTS_USER" npm install --production

# Generate Prisma client
echo "Generating Prisma client..."
sudo -u "$LACYLIGHTS_USER" npx prisma generate

# Run database migrations
echo "Running database migrations..."
sudo -u "$LACYLIGHTS_USER" npx prisma migrate deploy

# Build backend
echo "Building backend..."
sudo -u "$LACYLIGHTS_USER" npm run build

echo "✓ Backend setup complete"
echo ""

echo "Step 7: Setting up frontend..."
echo "==========================================="
cd "$INSTALL_DIR/frontend-src"

# Install dependencies
echo "Installing frontend dependencies..."
sudo -u "$LACYLIGHTS_USER" npm install --production

# Build static export
echo "Building frontend..."
sudo -u "$LACYLIGHTS_USER" npm run build

# Create symlink for nginx
ln -sf "$INSTALL_DIR/frontend-src/out" "$INSTALL_DIR/frontend"

echo "✓ Frontend setup complete"
echo ""

echo "Step 8: Setting up MCP server..."
echo "==========================================="
cd "$INSTALL_DIR/mcp"

# Install dependencies
echo "Installing MCP dependencies..."
sudo -u "$LACYLIGHTS_USER" npm install --production

# Build MCP
echo "Building MCP server..."
sudo -u "$LACYLIGHTS_USER" npm run build

echo "✓ MCP server setup complete"
echo ""

echo "Step 9: Configuring nginx..."
echo "==========================================="

# Download nginx config
curl -fsSL "https://raw.githubusercontent.com/bbernstein/lacylights/main/rpi-deployment/nginx-lacylights.conf" \
    -o /etc/nginx/sites-available/lacylights

# Enable site
ln -sf /etc/nginx/sites-available/lacylights /etc/nginx/sites-enabled/lacylights

# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

# Reload nginx
systemctl reload nginx
systemctl enable nginx

echo "✓ Nginx configured"
echo ""

echo "Step 10: Creating systemd service..."
echo "==========================================="

# Download systemd service file
curl -fsSL "https://raw.githubusercontent.com/bbernstein/lacylights/main/rpi-deployment/lacylights-backend.service" \
    -o /etc/systemd/system/lacylights-backend.service

# Reload systemd
systemctl daemon-reload

# Enable and start service
systemctl enable lacylights-backend
systemctl start lacylights-backend

echo "✓ Backend service installed and started"
echo ""

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "LacyLights is now running on this Raspberry Pi"
echo ""
echo "Access the web interface at:"
echo "  http://$(hostname).local"
echo "  http://$(hostname -I | awk '{print $1}')"
echo ""
echo "Backend GraphQL API:"
echo "  http://$(hostname -I | awk '{print $1}'):4000/graphql"
echo ""
echo "To check service status:"
echo "  sudo systemctl status lacylights-backend"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u lacylights-backend -f"
echo ""
echo "To update to latest releases:"
echo "  sudo $INSTALL_DIR/scripts/update-repos.sh update-all"
echo ""
