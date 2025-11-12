#!/bin/bash
#
# LacyLights Version Management Script
# Manages updates for lacylights-node, lacylights-fe, and lacylights-mcp repositories
#

set -e

# Configuration
LACYLIGHTS_BASE="/opt/lacylights"
BACKEND_DIR="${LACYLIGHTS_BASE}/backend"
FRONTEND_DIR="${LACYLIGHTS_BASE}/frontend-src"
MCP_DIR="${LACYLIGHTS_BASE}/mcp"

# GitHub repository information
declare -A REPOS
REPOS[lacylights-node]="bbernstein/lacylights-node"
REPOS[lacylights-fe]="bbernstein/lacylights-fe"
REPOS[lacylights-mcp]="bbernstein/lacylights-mcp"

declare -A REPO_DIRS
REPO_DIRS[lacylights-node]="${BACKEND_DIR}"
REPO_DIRS[lacylights-fe]="${FRONTEND_DIR}"
REPO_DIRS[lacylights-mcp]="${MCP_DIR}"

# Get installed version from package.json
get_installed_version() {
    local repo="$1"
    local dir="${REPO_DIRS[$repo]}"
    
    if [ ! -f "${dir}/package.json" ]; then
        echo "unknown"
        return
    fi
    
    grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${dir}/package.json" | \
        sed 's/"version"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/'
}

# Get latest version from GitHub releases
get_latest_version() {
    local repo="$1"
    local github_repo="${REPOS[$repo]}"
    
    # Use GitHub API to get latest release
    local latest=$(curl -s "https://api.github.com/repos/${github_repo}/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"tag_name": "v?([^"]+)".*/\1/')
    
    if [ -z "$latest" ]; then
        echo "unknown"
    else
        echo "$latest"
    fi
}

# Get available versions (last 10 releases)
get_available_versions() {
    local repo="$1"
    local github_repo="${REPOS[$repo]}"
    
    curl -s "https://api.github.com/repos/${github_repo}/releases?per_page=10" | \
        grep '"tag_name":' | sed -E 's/.*"tag_name": "v?([^"]+)".*/\1/'
}

# Get versions for all repos in JSON format
get_versions_json() {
    echo "{"
    local first=true
    for repo in "${!REPOS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        
        local installed=$(get_installed_version "$repo")
        local latest=$(get_latest_version "$repo")
        
        echo "  \"$repo\": {"
        echo "    \"installed\": \"$installed\","
        echo "    \"latest\": \"$latest\""
        echo -n "  }"
    done
    echo ""
    echo "}"
}

# Download and extract release
download_release() {
    local repo="$1"
    local version="$2"
    local github_repo="${REPOS[$repo]}"
    local dir="${REPO_DIRS[$repo]}"
    local temp_dir="/tmp/lacylights-update-${repo}"
    
    echo "Downloading ${repo} v${version}..."
    
    # Clean temp directory
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Download release tarball
    local download_url="https://github.com/${github_repo}/archive/refs/tags/v${version}.tar.gz"
    if ! curl -L -f -o "${temp_dir}/release.tar.gz" "$download_url"; then
        echo "Error: Failed to download release"
        return 1
    fi
    
    # Extract
    tar -xzf "${temp_dir}/release.tar.gz" -C "$temp_dir"
    
    # Find extracted directory (GitHub adds repo name prefix)
    local extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d)
    
    if [ -z "$extracted_dir" ]; then
        echo "Error: Failed to find extracted directory"
        return 1
    fi
    
    echo "$extracted_dir"
}

# Update a repository
update_repository() {
    local repo="$1"
    local version="$2"
    local dir="${REPO_DIRS[$repo]}"
    
    # Get current version
    local current_version=$(get_installed_version "$repo")
    
    # If no version specified, use latest
    if [ -z "$version" ] || [ "$version" = "latest" ]; then
        version=$(get_latest_version "$repo")
    fi
    
    echo "Updating ${repo} from ${current_version} to ${version}..."
    
    # Download and extract
    local extracted_dir=$(download_release "$repo" "$version")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Backup current directory
    local backup_dir="${dir}.backup"
    if [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir"
    fi
    cp -r "$dir" "$backup_dir"
    
    # Remove old files (except node_modules and .env)
    find "$dir" -mindepth 1 -maxdepth 1 ! -name 'node_modules' ! -name '.env' ! -name 'prisma' -exec rm -rf {} +
    
    # Copy new files
    cp -r "${extracted_dir}"/* "$dir/"
    
    # Install dependencies
    cd "$dir"
    if [ -f "package.json" ]; then
        echo "Installing dependencies..."
        npm install --production
    fi
    
    # For backend, run database migrations
    if [ "$repo" = "lacylights-node" ]; then
        echo "Running database migrations..."
        npx prisma migrate deploy || true
        npx prisma generate || true
    fi
    
    # For backend or MCP, rebuild
    if [ "$repo" = "lacylights-node" ] || [ "$repo" = "lacylights-mcp" ]; then
        echo "Building..."
        npm run build || true
    fi
    
    # For frontend, build static export
    if [ "$repo" = "lacylights-fe" ]; then
        echo "Building frontend..."
        npm run build || true
    fi
    
    # Clean up
    rm -rf "/tmp/lacylights-update-${repo}"
    rm -rf "$backup_dir"
    
    echo "Successfully updated ${repo} to ${version}"
}

# Main command handler
case "$1" in
    versions)
        if [ "$2" = "json" ]; then
            get_versions_json
        else
            for repo in "${!REPOS[@]}"; do
                installed=$(get_installed_version "$repo")
                latest=$(get_latest_version "$repo")
                echo "${repo}: installed=${installed}, latest=${latest}"
            done
        fi
        ;;
    
    available)
        if [ -z "$2" ]; then
            echo "Usage: $0 available <repository>"
            exit 1
        fi
        get_available_versions "$2"
        ;;
    
    update)
        if [ -z "$2" ]; then
            echo "Usage: $0 update <repository> [version]"
            exit 1
        fi
        update_repository "$2" "$3"
        ;;
    
    update-all)
        for repo in "${!REPOS[@]}"; do
            update_repository "$repo" "latest"
        done
        ;;
    
    *)
        echo "LacyLights Version Management Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  versions [json]          - Show installed and latest versions"
        echo "  available <repo>         - List available versions for repository"
        echo "  update <repo> [version]  - Update repository to specific version (or latest)"
        echo "  update-all               - Update all repositories to latest"
        echo ""
        echo "Repositories:"
        echo "  lacylights-node  - Backend server"
        echo "  lacylights-fe    - Frontend application"
        echo "  lacylights-mcp   - MCP server"
        exit 1
        ;;
esac
