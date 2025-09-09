#!/bin/bash

# LacyLights Repository Update Script
# This script checks for updates in all three LacyLights repositories and updates them

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if repo has uncommitted changes
has_uncommitted_changes() {
    local repo_dir="$1"
    if [ -d "$repo_dir/.git" ]; then
        cd "$repo_dir"
        if ! git diff --quiet || ! git diff --cached --quiet; then
            cd ..
            return 0  # Has uncommitted changes
        fi
        cd ..
    fi
    return 1  # No uncommitted changes
}

# Function to check if repo has unpushed commits
has_unpushed_commits() {
    local repo_dir="$1"
    if [ -d "$repo_dir/.git" ]; then
        cd "$repo_dir"
        local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")
        if [ ! -z "$upstream" ]; then
            local local_commit=$(git rev-parse HEAD)
            local remote_commit=$(git rev-parse "$upstream" 2>/dev/null || echo "")
            if [ "$local_commit" != "$remote_commit" ]; then
                cd ..
                return 0  # Has unpushed commits
            fi
        fi
        cd ..
    fi
    return 1  # No unpushed commits
}

# Function to check for updates in a repository
check_repo_updates() {
    local repo_name="$1"
    local repo_dir="$2"
    
    print_status "Checking $repo_name for updates..."
    
    if [ ! -d "$repo_dir" ]; then
        print_warning "$repo_name not found at $repo_dir"
        return 1
    fi
    
    if [ ! -d "$repo_dir/.git" ]; then
        print_warning "$repo_name is not a git repository"
        return 1
    fi
    
    cd "$repo_dir"
    
    # Fetch latest changes from remote
    git fetch origin >/dev/null 2>&1 || {
        print_error "Failed to fetch updates for $repo_name"
        cd ..
        return 1
    }
    
    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Check if there are updates available
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")
    
    if [ -z "$remote_commit" ]; then
        print_warning "No remote branch origin/$current_branch found"
        cd ..
        return 0
    fi
    
    if [ "$local_commit" = "$remote_commit" ]; then
        print_success "$repo_name is up to date"
        cd ..
        return 0
    fi
    
    # Count commits behind
    local commits_behind=$(git rev-list --count HEAD..origin/"$current_branch")
    print_warning "$repo_name is $commits_behind commit(s) behind origin/$current_branch"
    
    cd ..
    return 2  # Updates available
}

# Function to update a repository
update_repo() {
    local repo_name="$1"
    local repo_dir="$2"
    local auto_update="$3"
    
    print_status "Updating $repo_name..."
    
    cd "$repo_dir"
    
    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Check for uncommitted changes
    if has_uncommitted_changes "."; then
        print_error "$repo_name has uncommitted changes"
        print_warning "Please commit or stash your changes before updating"
        cd ..
        return 1
    fi
    
    # Pull latest changes
    print_status "Pulling latest changes for $repo_name..."
    if git pull origin "$current_branch"; then
        print_success "$repo_name updated successfully"
        
        # Install dependencies if package.json changed
        if git diff HEAD~1 HEAD --name-only | grep -q "package.json"; then
            print_status "Package.json changed, installing dependencies..."
            if [ -f "package-lock.json" ]; then
                npm ci || npm install
            else
                npm install
            fi
            print_success "Dependencies updated"
        fi
        
        # Rebuild if necessary (for TypeScript projects)
        if [ -f "tsconfig.json" ] && [ -f "package.json" ]; then
            if grep -q '"build"' package.json; then
                print_status "Rebuilding $repo_name..."
                npm run build || true
            fi
        fi
        
        cd ..
        return 0
    else
        print_error "Failed to update $repo_name"
        cd ..
        return 1
    fi
}

# Function to check all repositories
check_all_repos() {
    local has_updates=false
    local repos_with_updates=()
    
    echo ""
    print_status "Checking for repository updates..."
    echo ""
    
    # Check each repository
    for repo in lacylights-fe lacylights-node lacylights-mcp; do
        if check_repo_updates "$repo" "$repo"; then
            continue
        elif [ $? -eq 2 ]; then
            has_updates=true
            repos_with_updates+=("$repo")
        fi
    done
    
    echo ""
    
    if [ "$has_updates" = true ]; then
        print_warning "Updates are available for: ${repos_with_updates[*]}"
        return 0
    else
        print_success "All repositories are up to date"
        return 1
    fi
}

# Function to update all repositories
update_all_repos() {
    local auto_update="$1"
    
    echo ""
    print_status "Updating all repositories..."
    echo ""
    
    local failed_repos=()
    
    for repo in lacylights-fe lacylights-node lacylights-mcp; do
        if [ -d "$repo" ]; then
            if ! update_repo "$repo" "$repo" "$auto_update"; then
                failed_repos+=("$repo")
            fi
        fi
        echo ""
    done
    
    if [ ${#failed_repos[@]} -gt 0 ]; then
        print_error "Failed to update: ${failed_repos[*]}"
        return 1
    else
        print_success "All repositories updated successfully"
        return 0
    fi
}

# Function to prompt for update
prompt_for_update() {
    if [ "$1" = "--auto" ] || [ "$1" = "-y" ]; then
        return 0
    fi
    
    echo ""
    echo -n "Would you like to update now? [Y/n] "
    read -r response
    
    if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
        return 1
    fi
    
    return 0
}

# Main function
main() {
    local auto_update=false
    local check_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto|-y)
                auto_update=true
                shift
                ;;
            --check|-c)
                check_only=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --auto, -y     Automatically update without prompting"
                echo "  --check, -c    Check for updates only, don't update"
                echo "  --help, -h     Show this help message"
                echo ""
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    echo "LacyLights Repository Update Manager"
    echo "===================================="
    
    # Check for updates
    if check_all_repos; then
        if [ "$check_only" = true ]; then
            exit 0
        fi
        
        # Prompt for update
        if [ "$auto_update" = true ]; then
            update_all_repos "$auto_update"
        else
            if prompt_for_update; then
                update_all_repos "$auto_update"
            else
                print_warning "Skipping updates"
            fi
        fi
    fi
    
    echo ""
}

# Run main function
main "$@"