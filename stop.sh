#!/bin/bash

# LacyLights Stop Script
# This script gracefully stops all LacyLights services

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Stop all Node.js processes
print_status "Stopping LacyLights services..."

# Find and kill processes on specific ports
for port in 3000 4000; do
    PID=$(lsof -ti:$port)
    if [ ! -z "$PID" ]; then
        print_status "Stopping service on port $port (PID: $PID)..."
        kill $PID 2>/dev/null || true
        sleep 1
    fi
done

print_success "All services stopped"