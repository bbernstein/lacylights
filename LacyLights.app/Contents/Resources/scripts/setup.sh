#!/bin/bash

# LacyLights Setup Script
# This script sets up the complete LacyLights platform by downloading sub-repositories
# and installing dependencies to ~/Library/Application Support/LacyLights

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

# Configuration
GITHUB_ORG=""  # Will be auto-detected or provided by user
REPOS=(
    "lacylights-fe"
    "lacylights-node"
    "lacylights-mcp"
)

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

# Function to check if OpenAI API key needs to be set
needs_openai_api_key() {
    local env_file="$1"

    # Check if API key is default placeholder, empty, or missing
    if grep -q "OPENAI_API_KEY=your-api-key-here" "$env_file" || \
       grep -E -q '^OPENAI_API_KEY=(""|)$' "$env_file" || \
       ! grep -q "OPENAI_API_KEY=" "$env_file"; then
        return 0  # true - needs API key
    else
        return 1  # false - has valid API key
    fi
}

# Function to get tarball URL from GitHub release with error handling
get_release_tarball_url() {
    local org="$1"
    local repo="$2"
    local api_url="https://api.github.com/repos/$org/$repo/releases/latest"

    # Check if jq is available for robust JSON parsing
    if command_exists jq; then
        local response_file=$(mktemp)
        if [ -z "$response_file" ]; then
            print_error "Failed to create temporary file"
            echo ""
            return 1
        fi

        local http_code=$(curl -s -w "%{http_code}" -o "$response_file" "$api_url")

        if [ "$http_code" -ne 200 ]; then
            print_warning "GitHub API returned HTTP $http_code for $org/$repo"
            rm -f "$response_file"
            echo ""
            return 1
        fi

        local tarball_url=$(jq -r '.tarball_url // empty' "$response_file")
        rm -f "$response_file"

        if [ -z "$tarball_url" ] || [ "$tarball_url" = "null" ]; then
            echo ""
            return 1
        fi

        echo "$tarball_url"
        return 0
    else
        # Fallback to grep/cut if jq not available
        local tarball_url=$(curl -s "$api_url" | grep '"tarball_url"' | cut -d '"' -f 4)
        if [ -z "$tarball_url" ]; then
            echo ""
            return 1
        fi
        echo "$tarball_url"
        return 0
    fi
}

# Function to check if lacylights-node directory exists and cd into it
lacylights_node_exists() {
    if [ -d "lacylights-node" ]; then
        return 0
    else
        return 1
    fi
}

# Function to detect GitHub organization from current repo
detect_github_org() {
    local org=""
    
    # Check if we're in a git repository
    if [ -d ".git" ] && command_exists git; then
        # Get the remote URL
        local remote_url=$(git config --get remote.origin.url 2>/dev/null)
        
        if [ ! -z "$remote_url" ]; then
            # Extract organization from different URL formats
            # https://github.com/ORG/REPO.git
            # git@github.com:ORG/REPO.git
            # https://github.com/ORG/REPO
            
            if [[ "$remote_url" =~ github\.com[:/]([^/]+)/[^/]+\.git$ ]]; then
                org="${BASH_REMATCH[1]}"
            elif [[ "$remote_url" =~ github\.com[:/]([^/]+)/[^/]+ ]]; then
                org="${BASH_REMATCH[1]}"
            fi
        fi
    fi
    
    echo "$org"
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    local missing_requirements=0
    
    # Check Node.js
    if command_exists node; then
        NODE_VERSION=$(node -v)
        print_success "Node.js installed: $NODE_VERSION"
    else
        print_error "Node.js is not installed"
        missing_requirements=1
    fi
    
    # Check npm
    if command_exists npm; then
        NPM_VERSION=$(npm -v)
        print_success "npm installed: $NPM_VERSION"
    else
        print_error "npm is not installed"
        missing_requirements=1
    fi
    
    # Check Git
    if command_exists git; then
        GIT_VERSION=$(git --version)
        print_success "Git installed: $GIT_VERSION"
    else
        print_error "Git is not installed"
        missing_requirements=1
    fi

    if [ $missing_requirements -eq 1 ]; then
        print_error "Please install missing requirements before continuing."
        exit 1
    fi
    
    echo ""
}

# Function to download and extract a release archive
setup_repo() {
    local repo=$1
    print_status "Setting up $repo..."

    if [ -d "$repo" ]; then
        print_status "Repository directory exists, will update if newer release available..."
        # Directory exists, we'll let update-repos.sh handle updates
        print_success "$repo directory found"
        echo ""
        return 0
    fi

    print_status "Downloading latest release for $repo..."

    # Default to bbernstein org if no org specified
    local org="${GITHUB_ORG:-bbernstein}"

    # Create temporary directory for download
    local temp_dir=$(mktemp -d)
    if [ -z "$temp_dir" ] || [ ! -d "$temp_dir" ]; then
        print_error "Failed to create temporary directory for $repo"
        return 1
    fi

    local archive_file="$temp_dir/${repo}.tar.gz"
    local tarball_url=""

    # Try to download using gh CLI first (preferred)
    if command_exists gh; then
        print_status "Downloading using gh CLI..."
        if gh release download --repo "$org/$repo" --pattern "*.tar.gz" --dir "$temp_dir" 2>/dev/null; then
            # Find the downloaded archive
            archive_file=$(find "$temp_dir" -name "*.tar.gz" | head -1)
        fi
    fi

    # If gh CLI didn't work or didn't find archive, try GitHub API
    if [ -z "$archive_file" ] || [ ! -f "$archive_file" ]; then
        print_status "Downloading using GitHub API..."
        tarball_url=$(get_release_tarball_url "$org" "$repo")
        if [ -z "$tarball_url" ]; then
            print_error "Could not find release for $repo in $org organization"
            rm -rf "$temp_dir"
            return 1
        fi

        curl -sL "$tarball_url" -o "$archive_file" || {
            print_error "Failed to download from $tarball_url"
            rm -rf "$temp_dir"
            return 1
        }
    fi

    # Check if download succeeded
    if [ ! -f "$archive_file" ] || [ ! -s "$archive_file" ]; then
        print_error "Failed to download release for $repo"
        rm -rf "$temp_dir"
        return 1
    fi

    # Extract archive
    print_status "Extracting $repo..."
    mkdir -p "$temp_dir/extract"
    tar -xzf "$archive_file" -C "$temp_dir/extract" --strip-components=1 || {
        print_error "Failed to extract archive for $repo"
        rm -rf "$temp_dir"
        return 1
    }

    # Move extracted content to final location
    mv "$temp_dir/extract" "$repo" || {
        print_error "Failed to move extracted files for $repo"
        rm -rf "$temp_dir"
        return 1
    }

    # Write version file
    local api_url="https://api.github.com/repos/$org/$repo/releases/latest"
    local version=""

    if command_exists jq; then
        version=$(curl -s "$api_url" | jq -r '.tag_name // empty')
    else
        version=$(curl -s "$api_url" | grep '"tag_name"' | cut -d '"' -f 4)
    fi

    if [ -n "$version" ] && [ "$version" != "null" ]; then
        echo "$version" > "$repo/.lacylights-version"
    else
        print_warning "Could not determine version for $repo"
    fi

    # Clean up
    rm -rf "$temp_dir"

    print_success "$repo is ready"
    echo ""
}

# Function to install dependencies for a repo
install_dependencies() {
    local repo=$1
    print_status "Installing dependencies for $repo..."
    
    if [ -d "$repo" ]; then
        cd "$repo"
        
        if [ -f "package.json" ]; then
            npm install || {
                print_error "Failed to install dependencies for $repo"
                cd ..
                return 1
            }
            print_success "Dependencies installed for $repo"
        else
            print_warning "No package.json found in $repo"
        fi
        
        cd ..
    else
        print_error "$repo directory not found"
        return 1
    fi
    
    echo ""
}

# Function to setup environment files
setup_environment() {
    print_status "Setting up environment files..."
    
    # lacylights-node environment
    if [ -d "lacylights-node" ] && [ ! -f "lacylights-node/.env" ]; then
        if [ -f "lacylights-node/.env.example" ] && [ -s "lacylights-node/.env.example" ]; then
            cp "lacylights-node/.env.example" "lacylights-node/.env"
            print_success "Created lacylights-node/.env from example"
        else
            # Fallback: create minimal .env with SQLite defaults when .env.example is missing or empty
            cat > "lacylights-node/.env" << EOF
# Database (SQLite)
DATABASE_URL="file:./dev.db"

# Server Configuration
PORT=4000
NODE_ENV=development

# CORS Configuration
CORS_ORIGIN=http://localhost:3000

# DMX Configuration
DMX_UNIVERSE_COUNT=4
DMX_REFRESH_RATE=44

# Session Configuration
SESSION_SECRET=your-session-secret-here
EOF
            print_success "Created default lacylights-node/.env"
        fi
    fi
    
    # lacylights-fe environment
    if [ -d "lacylights-fe" ] && [ ! -f "lacylights-fe/.env.local" ]; then
        if [ -f "lacylights-fe/.env.example" ]; then
            cp "lacylights-fe/.env.example" "lacylights-fe/.env.local"
            print_success "Created lacylights-fe/.env.local from example"
        else
            cat > "lacylights-fe/.env.local" << EOF
# GraphQL Endpoint
NEXT_PUBLIC_GRAPHQL_ENDPOINT=http://localhost:4000/graphql
NEXT_PUBLIC_WS_ENDPOINT=ws://localhost:4000/graphql
EOF
            print_success "Created default lacylights-fe/.env.local"
        fi
    fi
    
    # lacylights-mcp environment
    if [ -d "lacylights-mcp" ]; then
        local needs_api_key=false
        
        if [ ! -f "lacylights-mcp/.env" ]; then
            if [ -f "lacylights-mcp/.env.example" ]; then
                cp "lacylights-mcp/.env.example" "lacylights-mcp/.env"
                print_success "Created lacylights-mcp/.env from example"
            else
                cat > "lacylights-mcp/.env" << EOF
# OpenAI API Key
OPENAI_API_KEY=your-api-key-here

# GraphQL Endpoint
GRAPHQL_ENDPOINT=http://localhost:4000/graphql
EOF
                print_success "Created default lacylights-mcp/.env"
            fi
            needs_api_key=true
        else
            # Check if API key is still the default or empty
            if needs_openai_api_key "lacylights-mcp/.env"; then
                needs_api_key=true
            fi
        fi
        
        # Prompt for OpenAI API key if needed
        if [ "$needs_api_key" = true ]; then
            echo ""
            print_status "AI Integration Setup (Optional)"
            echo "The MCP server enables AI-powered lighting design features."
            echo "Would you like to configure your OpenAI API key now?"
            echo -n "Configure OpenAI API key? [y/N] "
            read -r response
            
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                echo -n "Enter your OpenAI API key: "
                read -r api_key
                
                if [ ! -z "$api_key" ]; then
                    # Update or add the API key
                    if grep -q "OPENAI_API_KEY=" "lacylights-mcp/.env"; then
                        # Replace existing line
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            sed -i '' "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=$api_key/" "lacylights-mcp/.env"
                        else
                            sed -i "s/OPENAI_API_KEY=.*/OPENAI_API_KEY=$api_key/" "lacylights-mcp/.env"
                        fi
                    else
                        # Add new line
                        echo "OPENAI_API_KEY=$api_key" >> "lacylights-mcp/.env"
                    fi
                    print_success "OpenAI API key configured"
                else
                    print_warning "No API key entered. You can configure it later in lacylights-mcp/.env"
                fi
            else
                print_status "Skipping AI configuration. You can configure it later in lacylights-mcp/.env"
            fi
        fi
    fi
    
    echo ""
}

# Function to setup database
setup_database() {
    print_status "Setting up database..."
    
    if lacylights_node_exists; then
        (
            cd "lacylights-node"
            
            # Generate Prisma client
            if [ -f "package.json" ] && grep -q "prisma" "package.json"; then
                print_status "Generating Prisma client..."
                npm run db:generate 2>/dev/null || npx prisma generate || {
                    print_warning "Could not generate Prisma client"
                }
                
                # Run migrations
                print_status "Running database migrations..."
                npm run db:migrate 2>/dev/null || npx prisma migrate deploy || {
                    print_warning "Could not run migrations. You may need to run them manually."
                }
            fi
        )
    fi
    
    echo ""
}

# Function to check and import fixture definitions
check_and_import_fixtures() {
    print_status "Checking fixture definitions..."
    
    if lacylights_node_exists; then
        (
            cd "lacylights-node"
            
            # Allow user to override the fixture script path via environment variable
            FIXTURE_SCRIPT_PATHS=()
            if [ -n "$FIXTURE_SCRIPT_PATH" ]; then
                FIXTURE_SCRIPT_PATHS+=("$FIXTURE_SCRIPT_PATH")
            fi
            # Add default possible locations
            FIXTURE_SCRIPT_PATHS+=("scripts/check-and-import-fixtures.ts" "check-and-import-fixtures.ts")
            
            FOUND_FIXTURE_SCRIPT=""
            for path in "${FIXTURE_SCRIPT_PATHS[@]}"; do
                if [ -f "$path" ]; then
                    FOUND_FIXTURE_SCRIPT="$path"
                    break
                fi
            done
            
            if [ -n "$FOUND_FIXTURE_SCRIPT" ]; then
                print_status "Checking for existing fixture definitions using $FOUND_FIXTURE_SCRIPT..."
                
                # Run the fixture check and import script, capturing output
                OUTPUT_MSG=$(npx tsx "$FOUND_FIXTURE_SCRIPT" 2>&1)
                local exit_code=$?
                
                if [ $exit_code -eq 0 ]; then
                    # Show success output if there's meaningful content
                    if echo "$OUTPUT_MSG" | grep -q "fixtures imported\|fixtures already exist\|fixtures found\|fixtures loaded"; then
                        print_success "Fixture definitions processed successfully"
                        echo "$OUTPUT_MSG" | grep -E "imported|\bexist\b|added|found|loaded" || true
                    else
                        print_success "Fixture check completed"
                    fi
                else
                    print_warning "Could not check/import fixtures. You may need to import them manually."
                    echo -e "${YELLOW}Fixture import failed with the following error:${NC}\n${OUTPUT_MSG}"
                    # Exit subshell with error status to signal failure to parent
                    exit 1
                fi
            else
                print_warning "Fixture import script not found in any known location. Skipping fixture import."
            fi
        )
        
        # Check if subshell failed (exit 1 in subshell sets $? to 1)
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    echo ""
}

# Main setup flow
main() {
    echo "LacyLights Platform Setup"
    echo "========================="
    echo ""
    
    # Check requirements
    check_requirements
    
    # Detect or get GitHub organization
    if [ -n "$1" ]; then
        # Organization provided as argument
        GITHUB_ORG="$1"
        print_status "Using GitHub organization: $GITHUB_ORG"
    else
        # Try to detect from current repo
        local detected_org=$(detect_github_org)
        
        if [ ! -z "$detected_org" ]; then
            print_status "Detected GitHub organization: $detected_org"
            echo -n "Use this organization for cloning repositories? [$detected_org] "
            read -r user_org
            
            # Use detected org if user just pressed enter
            if [ -z "$user_org" ]; then
                GITHUB_ORG="$detected_org"
            else
                GITHUB_ORG="$user_org"
            fi
        else
            # No organization detected, ask user
            echo "Could not detect GitHub organization from current repository."
            echo -n "Enter GitHub organization name (or press Enter to skip): "
            read -r user_org
            GITHUB_ORG="$user_org"
        fi
        
        if [ ! -z "$GITHUB_ORG" ]; then
            print_status "Using GitHub organization: $GITHUB_ORG"
        else
            print_status "No GitHub organization specified. Will prompt for full URLs."
        fi
    fi
    
    # Setup repositories
    for repo in "${REPOS[@]}"; do
        setup_repo "$repo"
    done
    
    # Install dependencies
    for repo in "${REPOS[@]}"; do
        install_dependencies "$repo"
    done
    
    # Setup environment files
    setup_environment

    # Setup database
    setup_database
    
    # Check and import fixture definitions
    check_and_import_fixtures

    print_success "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Launch the LacyLights app via the LacyLights.app bundle in your Applications folder"
    echo "2. Open http://localhost:3000 in your browser"
    echo ""
    echo "Development mode (optional):"
    echo "- Run scripts directly from the app bundle's Resources/scripts directory"
    echo "- Or use the launcher script from the repository for development"
    echo ""
}

# Run main function
main "$@"