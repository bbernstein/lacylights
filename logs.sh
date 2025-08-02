#!/bin/bash

# LacyLights Logs Viewer
# This script helps view logs from all LacyLights services

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOGS_DIR="logs"

print_header() {
    echo -e "${BLUE}$1${NC}"
    echo "================================"
}

# Check if logs directory exists
if [ ! -d "$LOGS_DIR" ]; then
    echo "No logs directory found. Services may not be running."
    exit 1
fi

# Parse command line arguments
case "$1" in
    backend|be)
        print_header "Backend Logs"
        tail -f "$LOGS_DIR/backend.log"
        ;;
    frontend|fe)
        print_header "Frontend Logs"
        tail -f "$LOGS_DIR/frontend.log"
        ;;
    mcp)
        print_header "MCP Server Logs"
        if [ -f "$LOGS_DIR/mcp.log" ]; then
            tail -f "$LOGS_DIR/mcp.log"
        else
            echo "MCP server logs not found. MCP may not be running."
        fi
        ;;
    all)
        # Use multitail if available, otherwise fall back to tail
        if command -v multitail >/dev/null 2>&1; then
            multitail "$LOGS_DIR/backend.log" "$LOGS_DIR/frontend.log" "$LOGS_DIR/mcp.log" 2>/dev/null
        else
            print_header "All Logs (Backend + Frontend)"
            tail -f "$LOGS_DIR/backend.log" "$LOGS_DIR/frontend.log"
        fi
        ;;
    *)
        echo "LacyLights Logs Viewer"
        echo "====================="
        echo ""
        echo "Usage: ./logs.sh [service]"
        echo ""
        echo "Services:"
        echo "  backend  | be  - View backend logs"
        echo "  frontend | fe  - View frontend logs"
        echo "  mcp           - View MCP server logs"
        echo "  all           - View all logs"
        echo ""
        echo "Examples:"
        echo "  ./logs.sh backend"
        echo "  ./logs.sh all"
        echo ""
        echo "Available log files:"
        ls -la "$LOGS_DIR"/*.log 2>/dev/null || echo "No log files found"
        ;;
esac