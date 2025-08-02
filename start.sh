#!/bin/bash

# LacyLights Start Script
# This script starts all components of the LacyLights platform

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Process tracking
PIDS=()
LOGS_DIR="logs"

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
    
    # Stop Docker containers
    if [ -d "lacylights-node" ]; then
        cd lacylights-node
        if [ -f "docker-compose.yml" ]; then
            docker-compose down 2>/dev/null || true
        fi
        cd ..
    fi
    
    print_success "All services stopped"
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Function to check if Docker is running
check_docker() {
    print_status "Checking Docker..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed"
        print_warning "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        print_warning "Please start Docker Desktop and try again"
        
        # On macOS, try to open Docker Desktop
        if [[ "$OSTYPE" == "darwin"* ]]; then
            print_status "Attempting to start Docker Desktop..."
            open -a Docker || true
            
            # Wait for Docker to start
            print_status "Waiting for Docker to start (up to 60 seconds)..."
            for i in {1..60}; do
                if docker info >/dev/null 2>&1; then
                    print_success "Docker is now running"
                    return 0
                fi
                sleep 1
            done
            
            print_error "Docker failed to start"
            exit 1
        else
            exit 1
        fi
    fi
    
    print_success "Docker is running"
}

# Function to start database containers
start_database() {
    print_status "Starting database containers..."
    
    if [ -d "lacylights-node" ]; then
        cd lacylights-node
        
        # Check if docker-compose.yml exists
        if [ -f "docker-compose.yml" ]; then
            print_status "Starting PostgreSQL and Redis..."
            docker-compose up -d postgres redis || {
                print_error "Failed to start database containers"
                cd ..
                return 1
            }
            
            # Wait for PostgreSQL to be ready
            print_status "Waiting for PostgreSQL to be ready..."
            for i in {1..30}; do
                if docker-compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
                    print_success "PostgreSQL is ready"
                    break
                fi
                sleep 1
            done
        else
            print_warning "No docker-compose.yml found, skipping database setup"
        fi
        
        cd ..
    else
        print_error "lacylights-node directory not found"
        return 1
    fi
}

# Function to start the backend
start_backend() {
    print_status "Starting backend server..."
    
    if [ -d "lacylights-node" ]; then
        cd lacylights-node
        
        # Create logs directory if it doesn't exist
        mkdir -p "../$LOGS_DIR"
        
        # Start the backend
        print_status "Starting lacylights-node on port 4000..."
        npm run dev > "../$LOGS_DIR/backend.log" 2>&1 &
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
        cd lacylights-fe
        
        # Create logs directory if it doesn't exist
        mkdir -p "../$LOGS_DIR"
        
        # Start the frontend
        print_status "Starting lacylights-fe on port 3000..."
        npm run dev > "../$LOGS_DIR/frontend.log" 2>&1 &
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
    if [ "$1" == "--with-mcp" ] || [ "$1" == "-m" ]; then
        print_status "Starting MCP server..."
        
        if [ -d "lacylights-mcp" ]; then
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
            npm start > "../$LOGS_DIR/mcp.log" 2>&1 &
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
    if [ "$1" == "--with-mcp" ] || [ "$1" == "-m" ]; then
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
    
    # Check Docker
    check_docker
    echo ""
    
    # Start database
    start_database
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