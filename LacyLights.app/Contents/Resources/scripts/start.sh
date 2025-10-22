#!/bin/bash

# LacyLights Start Script
# This script starts all components of the LacyLights platform

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the paths configuration
source "$SCRIPT_DIR/paths.sh"

# Change to the repositories directory
cd "$LACYLIGHTS_REPOS"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Process tracking
PIDS=()
LOGS_DIR="$LACYLIGHTS_LOGS"

# Function to print colored output
print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to cleanup on exit
cleanup() {
    print_status "Shutting down services..."

    # Kill all child processes
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            print_status "Stopping process $pid..."
            kill "$pid" 2>/dev/null || true
        fi
    done

    print_success "All services stopped"
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Function to check and install dependencies if needed
ensure_dependencies() {
    local repo_name="$1"
    local repo_dir="$2"

    if [ ! -d "$repo_dir" ]; then
        return 1
    fi

    if [ ! -f "$repo_dir/package.json" ]; then
        return 0  # No package.json, skip
    fi

    # Check if node_modules exists and has content
    if [ ! -d "$repo_dir/node_modules" ] || [ -z "$(ls -A "$repo_dir/node_modules" 2>/dev/null)" ]; then
        print_status "Installing dependencies for $repo_name (node_modules missing)..."
        (cd "$repo_dir" && npm install) || {
            print_error "Failed to install dependencies for $repo_name"
            return 1
        }
        print_success "Dependencies installed for $repo_name"
        return 0
    fi

    # Quick check: verify package-lock.json is in sync with node_modules
    # This catches cases where dependencies were updated but not installed
    if [ -f "$repo_dir/package-lock.json" ]; then
        if [ "$repo_dir/package-lock.json" -nt "$repo_dir/node_modules/.package-lock.json" ] 2>/dev/null; then
            print_status "Updating dependencies for $repo_name (package-lock.json changed)..."
            (cd "$repo_dir" && npm ci) || {
                print_warning "npm ci failed, falling back to npm install..."
                (cd "$repo_dir" && npm install) || {
                    print_error "Failed to install dependencies for $repo_name"
                    return 1
                }
            }
            print_success "Dependencies updated for $repo_name"
        fi
    fi

    return 0
}

# Function to start the backend
start_backend() {
    print_status "Starting backend server..."

    if [ -d "lacylights-node" ]; then
        # Ensure dependencies are installed
        ensure_dependencies "lacylights-node" "lacylights-node" || {
            print_error "Cannot start backend without dependencies"
            return 1
        }

        cd lacylights-node

        # Create logs directory if it doesn't exist
        mkdir -p "$LOGS_DIR"

        # Start the backend
        print_status "Starting lacylights-node on port 4000..."
        npm run dev > "$LOGS_DIR/backend.log" 2>&1 &
        local backend_pid=$!
        PIDS+=($backend_pid)
        
        # Wait for backend to be ready
        print_status "Waiting for backend to be ready..."
        for i in {1..30}; do
            if curl -s http://localhost:4000/health >/dev/null 2>&1; then
                print_success "Backend is running (PID: $backend_pid)"
                cd ..
                return 0
            fi
            sleep 1
        done
        
        print_error "Backend failed to start"
        cd ..
        return 1
    else
        print_error "lacylights-node directory not found"
        return 1
    fi
}

# Function to start the frontend
start_frontend() {
    print_status "Starting frontend..."

    if [ -d "lacylights-fe" ]; then
        # Ensure dependencies are installed
        ensure_dependencies "lacylights-fe" "lacylights-fe" || {
            print_error "Cannot start frontend without dependencies"
            return 1
        }

        cd lacylights-fe

        # Create logs directory if it doesn't exist
        mkdir -p "$LOGS_DIR"

        # Start the frontend
        print_status "Starting lacylights-fe on port 3000..."
        npm run dev > "$LOGS_DIR/frontend.log" 2>&1 &
        local frontend_pid=$!
        PIDS+=($frontend_pid)
        
        # Wait a moment for the process to start
        sleep 2
        
        if kill -0 "$frontend_pid" 2>/dev/null; then
            print_success "Frontend is starting (PID: $frontend_pid)"
        else
            print_error "Frontend failed to start"
            cd ..
            return 1
        fi
        
        cd ..
    else
        print_error "lacylights-fe directory not found"
        return 1
    fi
}

# Function to start MCP server (optional)
start_mcp() {
    if [ "$1" = "--with-mcp" ] || [ "$1" = "-m" ]; then
        print_status "Starting MCP server..."

        if [ -d "lacylights-mcp" ]; then
            # Ensure dependencies are installed
            ensure_dependencies "lacylights-mcp" "lacylights-mcp" || {
                print_error "Cannot start MCP server without dependencies"
                return 1
            }

            cd lacylights-mcp

            # Check if OpenAI API key is set
            if [ -f ".env" ] && grep -q "OPENAI_API_KEY=your-api-key-here" ".env"; then
                print_warning "OpenAI API key not configured in lacylights-mcp/.env"
                print_warning "MCP server will start but AI features won't work"
            fi

            # Build if needed
            if [ ! -d "dist" ]; then
                print_status "Building MCP server..."
                npm run build || {
                    print_error "Failed to build MCP server"
                    cd ..
                    return 1
                }
            fi
            
            # Start MCP server
            print_status "Starting lacylights-mcp..."
            npm start > "$LOGS_DIR/mcp.log" 2>&1 &
            local mcp_pid=$!
            PIDS+=($mcp_pid)
            
            sleep 2
            
            if kill -0 "$mcp_pid" 2>/dev/null; then
                print_success "MCP server is running (PID: $mcp_pid)"
            else
                print_error "MCP server failed to start"
            fi
            
            cd ..
        else
            print_error "lacylights-mcp directory not found"
        fi
    fi
}

# Function to open the browser
open_browser() {
    local url="http://localhost:3000"
    
    print_status "Opening browser..."
    
    # Wait a bit for frontend to be fully ready
    sleep 3
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        open "$url" || true
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        xdg-open "$url" 2>/dev/null || true
    fi
    
    print_success "Browser opened at $url"
}

# Function to show logs
show_logs() {
    echo ""
    print_status "Services are running. Logs are available in the $LOGS_DIR directory:"
    echo "  - Backend:  tail -f $LOGS_DIR/backend.log"
    echo "  - Frontend: tail -f $LOGS_DIR/frontend.log"
    if [ "$1" = "--with-mcp" ] || [ "$1" = "-m" ]; then
        echo "  - MCP:      tail -f $LOGS_DIR/mcp.log"
    fi
    echo ""
    echo "Press Ctrl+C to stop all services"
    echo ""
}

# Main start flow
main() {
    echo "LacyLights Platform Launcher"
    echo "============================"
    echo ""

    # Start backend
    start_backend
    echo ""

    # Start frontend
    start_frontend
    echo ""

    # Start MCP if requested
    start_mcp "$1"
    echo ""

    # Open browser
    open_browser

    # Show logs info
    show_logs "$1"

    # Wait for interrupt
    wait
}

# Run main function
main "$@"