#!/bin/bash

# LacyLights Update Script
# This script updates all LacyLights repositories to the latest version

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPOS=(
    "lacylights-fe"
    "lacylights-node"
    "lacylights-mcp"
)

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

# Function to check if services are running
check_running_services() {
    local running=0
    
    for port in 3000 4000; do
        if lsof -ti:$port >/dev/null 2>&1; then
            running=1
            break
        fi
    done
    
    if [ $running -eq 1 ]; then
        print_warning "LacyLights services are currently running"
        echo "It's recommended to stop services before updating."
        echo -n "Stop services now? [Y/n] "
        read -r response
        
        if [[ "$response" =~ ^([yY][eE][sS]|[yY]|"")$ ]]; then
            ./stop.sh
            echo ""
        fi
    fi
}

# Function to update a repository
update_repo() {
    local repo=$1
    print_status "Updating $repo..."
    
    if [ ! -d "$repo" ]; then
        print_error "$repo directory not found"
        return 1
    fi
    
    cd "$repo"
    
    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        print_error "$repo is not a git repository"
        cd ..
        return 1
    fi
    
    # Check for uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        print_warning "Uncommitted changes in $repo"
        echo "Options:"
        echo "  1) Stash changes and continue"
        echo "  2) Skip this repository"
        echo "  3) Abort update"
        echo -n "Choose [1-3]: "
        read -r choice
        
        case $choice in
            1)
                print_status "Stashing changes..."
                git stash push -m "Stashed by update script $(date)"
                ;;
            2)
                print_warning "Skipping $repo"
                cd ..
                return 0
                ;;
            *)
                print_error "Update aborted"
                cd ..
                exit 1
                ;;
        esac
    fi
    
    # Fetch and pull latest changes
    print_status "Fetching latest changes..."
    git fetch origin || {
        print_error "Failed to fetch from origin"
        cd ..
        return 1
    }
    
    # Get current branch
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    
    # Pull latest changes
    print_status "Pulling latest changes for branch $BRANCH..."
    git pull origin "$BRANCH" || {
        print_error "Failed to pull changes"
        cd ..
        return 1
    }
    
    # Update dependencies
    if [ -f "package.json" ]; then
        print_status "Updating dependencies..."
        npm install || {
            print_warning "Failed to update dependencies"
        }
    fi
    
    # Run any post-update tasks
    if [ "$repo" == "lacylights-node" ] && [ -f "package.json" ]; then
        if grep -q "db:migrate" package.json; then
            print_status "Running database migrations..."
            npm run db:migrate 2>/dev/null || {
                print_warning "No pending migrations or migration failed"
            }
        fi
    fi
    
    cd ..
    print_success "$repo updated successfully"
    echo ""
}

# Main update flow
main() {
    echo "LacyLights Update Tool"
    echo "====================="
    echo ""
    
    # Check if services are running
    check_running_services
    
    # Update each repository
    for repo in "${REPOS[@]}"; do
        update_repo "$repo"
    done
    
    print_success "All repositories updated!"
    echo ""
    echo "You can now start the services with: ./start.sh"
    echo ""
}

# Run main function
main "$@"