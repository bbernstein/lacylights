#!/bin/bash

# LacyLights Repository Update Script
# This script checks for updates in all three LacyLights repositories and updates them

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

# Function to get the current installed version
get_installed_version() {
    local repo_dir="$1"
    if [ -f "$repo_dir/.lacylights-version" ]; then
        cat "$repo_dir/.lacylights-version"
    else
        echo "unknown"
    fi
}

# Function to get the latest release version from GitHub
get_latest_release_version() {
    local org="$1"
    local repo="$2"
    local api_url="https://api.github.com/repos/$org/$repo/releases/latest"

    # Use jq for robust JSON parsing if available
    if command_exists jq; then
        local response_file=$(mktemp)
        if [ -z "$response_file" ]; then
            echo "unknown"
            return
        fi

        local http_code=$(curl -s -w "%{http_code}" -o "$response_file" "$api_url")

        if [ "$http_code" -ne 200 ]; then
            rm -f "$response_file"
            echo "unknown"
            return
        fi

        local version=$(jq -r '.tag_name // empty' "$response_file")
        rm -f "$response_file"

        if [ -z "$version" ] || [ "$version" = "null" ]; then
            echo "unknown"
        else
            echo "$version"
        fi
    else
        # Fallback to grep/cut if jq not available
        local version=$(curl -s "$api_url" | grep '"tag_name"' | cut -d '"' -f 4)
        if [ -z "$version" ]; then
            # Log warning to help debug version detection failures (network issues, rate limiting, etc.)
            echo "Warning: Failed to detect latest version for $org/$repo. Check your network connection or GitHub API rate limits (https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)" >&2
            echo "unknown"
        else
            echo "$version"
        fi
    fi
}

# Function to check for updates in a repository
check_repo_updates() {
    local repo_name="$1"
    local repo_dir="$2"
    local org="${3:-bbernstein}"

    print_status "Checking $repo_name for updates..."

    if [ ! -d "$repo_dir" ]; then
        print_warning "$repo_name not found at $(pwd)/$repo_dir"
        return 1
    fi

    # Get installed version
    local installed_version=$(get_installed_version "$repo_dir")

    # Get latest release version
    local latest_version=$(get_latest_release_version "$org" "$repo_name")

    if [ "$latest_version" = "unknown" ]; then
        print_warning "Could not determine latest version for $repo_name"
        return 1
    fi

    if [ "$installed_version" = "unknown" ]; then
        print_warning "$repo_name version unknown (no .lacylights-version file), considering it outdated"
        return 2  # Updates available
    fi

    # Compare versions
    if [ "$installed_version" = "$latest_version" ]; then
        print_success "$repo_name is up to date ($installed_version)"
        return 0
    fi

    print_warning "$repo_name has an update available: $installed_version → $latest_version"
    return 2  # Updates available
}

# Function to update a repository
update_repo() {
    local repo_name="$1"
    local repo_dir="$2"
    local auto_update="$3"
    local org="${4:-bbernstein}"

    print_status "Updating $repo_name..."

    if [ ! -d "$repo_dir" ]; then
        print_error "$repo_name directory not found"
        return 1
    fi

    # Get latest release version
    local latest_version=$(get_latest_release_version "$org" "$repo_name")
    if [ "$latest_version" = "unknown" ]; then
        print_error "Could not determine latest version for $repo_name"
        return 1
    fi

    # Preserve .env files and other config
    local temp_backup=$(mktemp -d)
    if [ -z "$temp_backup" ] || [ ! -d "$temp_backup" ]; then
        print_error "Failed to create backup directory"
        return 1
    fi

    if [ -f "$repo_dir/.env" ]; then
        cp "$repo_dir/.env" "$temp_backup/.env"
    fi
    if [ -f "$repo_dir/.env.local" ]; then
        cp "$repo_dir/.env.local" "$temp_backup/.env.local"
    fi

    # Create temporary directory for download
    local temp_dir=$(mktemp -d)
    if [ -z "$temp_dir" ] || [ ! -d "$temp_dir" ]; then
        print_error "Failed to create temporary directory"
        rm -rf "$temp_backup"
        return 1
    fi

    local archive_file="$temp_dir/${repo_name}.tar.gz"

    # Download the release archive
    print_status "Downloading $repo_name $latest_version..."
    local api_url="https://api.github.com/repos/$org/$repo_name/releases/latest"
    local tarball_url=""

    if command_exists jq; then
        local response_file=$(mktemp)
        if [ -n "$response_file" ]; then
            local http_code=$(curl -s -w "%{http_code}" -o "$response_file" "$api_url")
            if [ "$http_code" -eq 200 ]; then
                tarball_url=$(jq -r '.tarball_url // empty' "$response_file")
            fi
            rm -f "$response_file"
        fi
    else
        tarball_url=$(curl -s "$api_url" | grep '"tarball_url"' | cut -d '"' -f 4)
    fi

    if [ -z "$tarball_url" ] || [ "$tarball_url" = "null" ]; then
        print_error "Could not find release tarball URL"
        rm -rf "$temp_dir" "$temp_backup"
        return 1
    fi

    curl -sL "$tarball_url" -o "$archive_file" || {
        print_error "Failed to download $repo_name"
        rm -rf "$temp_dir" "$temp_backup"
        return 1
    }

    # Extract to temporary location
    print_status "Extracting $repo_name..."
    mkdir -p "$temp_dir/extract"
    tar -xzf "$archive_file" -C "$temp_dir/extract" --strip-components=1 || {
        print_error "Failed to extract archive"
        rm -rf "$temp_dir" "$temp_backup"
        return 1
    }

    # Remove old directory and replace with new
    # Validate path before deletion to prevent accidents
    if [ -z "$repo_dir" ] || [ "$repo_dir" = "/" ] || [ "$repo_dir" = "." ] || [[ "$repo_dir" =~ (^|/)\.\.(/|$) ]]; then
        print_error "Invalid repository directory path: $repo_dir"
        rm -rf "$temp_dir" "$temp_backup"
        return 1
    fi

    rm -rf "$repo_dir"
    mv "$temp_dir/extract" "$repo_dir" || {
        print_error "Failed to move extracted files"
        rm -rf "$temp_dir" "$temp_backup"
        return 1
    }

    # Restore .env files
    if [ -f "$temp_backup/.env" ]; then
        cp "$temp_backup/.env" "$repo_dir/.env"
    fi
    if [ -f "$temp_backup/.env.local" ]; then
        cp "$temp_backup/.env.local" "$repo_dir/.env.local"
    fi

    # Write version file
    echo "$latest_version" > "$repo_dir/.lacylights-version"

    # Clean up
    rm -rf "$temp_dir" "$temp_backup"

    print_success "$repo_name updated to $latest_version"

    # Install dependencies
    if [ -f "$repo_dir/package.json" ]; then
        print_status "Installing dependencies for $repo_name..."
        pushd "$repo_dir" >/dev/null
        if [ -f "package-lock.json" ]; then
            if ! npm ci; then
                print_warning "npm ci failed, falling back to npm install..."
                npm install
            fi
        else
            npm install
        fi
        popd >/dev/null
        print_success "Dependencies installed for $repo_name"
    fi

    # Rebuild if necessary (for TypeScript projects)
    if [ -f "$repo_dir/tsconfig.json" ] && [ -f "$repo_dir/package.json" ]; then
        if grep -q '"build"' "$repo_dir/package.json"; then
            print_status "Rebuilding $repo_name..."
            pushd "$repo_dir" >/dev/null
            if npm run build; then
                print_success "Build succeeded for $repo_name"
            else
                print_error "Build failed for $repo_name"
            fi
            popd >/dev/null
        fi
    fi

    # Run database migrations for lacylights-node
    if [ "$repo_name" = "lacylights-node" ] && [ -f "$repo_dir/prisma/schema.prisma" ]; then
        print_status "Running database migrations for $repo_name..."
        pushd "$repo_dir" >/dev/null
        if npx prisma migrate deploy; then
            print_success "Database migrations completed for $repo_name"
        else
            print_warning "Database migrations failed for $repo_name - you may need to run manually"
        fi
        popd >/dev/null
    fi

    return 0
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
        # Updates are available
        if [ "$check_only" = true ]; then
            exit 0  # Exit with success when updates are available
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
    else
        # No updates available
        if [ "$check_only" = true ]; then
            exit 1  # Exit with failure when no updates are available
        fi
    fi
    
    echo ""
}

# Run main function
main "$@"