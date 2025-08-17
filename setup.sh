#!/bin/bash

# LacyLights Setup Script
# This script sets up the complete LacyLights platform by cloning/updating sub-repositories
# and installing dependencies

set -e  # Exit on error

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
    
    # Check Docker
    if command_exists docker; then
        DOCKER_VERSION=$(docker --version)
        print_success "Docker installed: $DOCKER_VERSION"
        
        # Check if Docker is running
        if ! docker info >/dev/null 2>&1; then
            print_warning "Docker is installed but not running."
            
            # On macOS, try to start Docker Desktop
            if [[ "$OSTYPE" == "darwin"* ]]; then
                print_status "Attempting to start Docker Desktop..."
                open -a Docker 2>/dev/null || true
                
                # Wait for Docker to start
                print_status "Waiting for Docker to start (up to 60 seconds)..."
                local docker_started=false
                for i in {1..60}; do
                    if docker info >/dev/null 2>&1; then
                        docker_started=true
                        break
                    fi
                    printf "."
                    sleep 1
                done
                echo ""
                
                if [ "$docker_started" = true ]; then
                    print_success "Docker is now running"
                else
                    print_error "Docker failed to start. Please start Docker Desktop manually and run setup again."
                    missing_requirements=1
                fi
            else
                print_warning "Please start Docker and run setup again."
                missing_requirements=1
            fi
        else
            print_success "Docker is running"
        fi
    else
        print_error "Docker is not installed. You'll need it for the database."
        print_warning "Download Docker Desktop from: https://www.docker.com/products/docker-desktop"
        missing_requirements=1
    fi
    
    if [ $missing_requirements -eq 1 ]; then
        print_error "Please install missing requirements before continuing."
        exit 1
    fi
    
    echo ""
}

# Function to clone or update a repository
setup_repo() {
    local repo=$1
    print_status "Setting up $repo..."
    
    if [ -d "$repo" ]; then
        print_status "Repository exists, updating..."
        cd "$repo"
        
        # Check if it's a git repository
        if [ -d ".git" ]; then
            # Stash any local changes
            if ! git diff --quiet || ! git diff --cached --quiet; then
                print_warning "Stashing local changes in $repo..."
                git stash push -m "Stashed by setup script $(date)"
            fi
            
            # Pull latest changes
            print_status "Pulling latest changes..."
            git pull origin main || git pull origin master || {
                print_error "Failed to pull changes. Please check the repository."
                cd ..
                return 1
            }
        else
            print_error "$repo exists but is not a git repository"
            cd ..
            return 1
        fi
        
        cd ..
    else
        print_status "Cloning $repo..."
        
        # If we have a GitHub org, try that first
        if [ ! -z "$GITHUB_ORG" ]; then
            if git clone "https://github.com/${GITHUB_ORG}/${repo}.git" 2>/dev/null; then
                print_success "Cloned from https://github.com/${GITHUB_ORG}/${repo}.git"
            else
                print_warning "Could not clone from https://github.com/${GITHUB_ORG}/${repo}.git"
                echo "Please enter the Git repository URL for $repo:"
                read -r repo_url
                git clone "$repo_url" "$repo" || {
                    print_error "Failed to clone $repo"
                    return 1
                }
            fi
        else
            # No GitHub org, ask for full URL
            echo "Please enter the Git repository URL for $repo:"
            read -r repo_url
            git clone "$repo_url" "$repo" || {
                print_error "Failed to clone $repo"
                return 1
            }
        fi
    fi
    
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
        if [ -f "lacylights-node/.env.example" ]; then
            cp "lacylights-node/.env.example" "lacylights-node/.env"
            print_success "Created lacylights-node/.env from example"
        else
            cat > "lacylights-node/.env" << EOF
# Database
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/lacylights"

# Redis
REDIS_URL="redis://localhost:6379"

# Server
PORT=4000
NODE_ENV=development

# CORS
CORS_ORIGIN="http://localhost:3000"
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
            # Check if API key is still the default
            if grep -q "OPENAI_API_KEY=your-api-key-here" "lacylights-mcp/.env" || grep -q "OPENAI_API_KEY=$" "lacylights-mcp/.env" || ! grep -q "OPENAI_API_KEY=" "lacylights-mcp/.env"; then
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
                    echo -e "${YELLOW}Error output:${NC}\n${OUTPUT_MSG}"
                    # Note: Using 'exit 1' here is correct - it exits the subshell with error status,
                    # and $? is set to the subshell's exit code immediately after the subshell finishes
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

# Function to start database containers
start_database_containers() {
    print_status "Starting database containers..."
    
    if lacylights_node_exists; then
        (
            cd "lacylights-node"
            
            # Check if docker-compose.yml exists
            if [ -f "docker-compose.yml" ]; then
                print_status "Starting PostgreSQL and Redis containers..."
                docker-compose up -d postgres redis >/dev/null 2>&1 || {
                    print_warning "Could not start database containers"
                    # Note: Using 'exit 1' here is correct - it exits the subshell with error status
                    exit 1
                }
                
                # Wait for PostgreSQL to be ready
                print_status "Waiting for PostgreSQL to be ready..."
                local db_ready=false
                for i in {1..30}; do
                    if docker-compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
                        db_ready=true
                        break
                    fi
                    printf "."
                    sleep 1
                done
                echo ""
                
                if [ "$db_ready" = true ]; then
                    print_success "Database containers are running"
                else
                    print_warning "PostgreSQL is taking longer than expected to start"
                fi
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
    
    # Start database containers if Docker is running
    if command_exists docker && docker info >/dev/null 2>&1; then
        start_database_containers
    fi
    
    # Setup database
    setup_database
    
    # Check and import fixture definitions
    check_and_import_fixtures
    
    # Ensure all scripts are executable
    for script in start.sh stop.sh logs.sh update.sh; do
        if [ -f "$script" ]; then
            chmod +x "$script"
        fi
    done
    
    print_success "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Run ./start.sh to start the platform"
    echo "2. Open http://localhost:3000 in your browser"
    echo ""
    echo "Optional:"
    echo "- Run './start.sh --with-mcp' to include AI features"
    echo "- Run './logs.sh' to view service logs"
    echo "- Run './update.sh' to update all components"
    echo ""
}

# Run main function
main "$@"