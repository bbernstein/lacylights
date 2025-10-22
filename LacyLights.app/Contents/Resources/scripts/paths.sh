#!/bin/bash

# LacyLights macOS Standard Paths
# This script defines all standard directory paths following macOS best practices

# Get the app bundle path
if [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    export LACYLIGHTS_APP_BUNDLE="$( cd "$SCRIPT_DIR/../../.." && pwd )"
    export LACYLIGHTS_RESOURCES="$LACYLIGHTS_APP_BUNDLE/Contents/Resources"
else
    # Fallback if sourced in a different way
    export LACYLIGHTS_APP_BUNDLE="/Applications/LacyLights.app"
    export LACYLIGHTS_RESOURCES="$LACYLIGHTS_APP_BUNDLE/Contents/Resources"
fi

# Convenience aliases for shorter variable names
export RESOURCES_DIR="$LACYLIGHTS_RESOURCES"

# Standard macOS user directories
export LACYLIGHTS_APP_SUPPORT="$HOME/Library/Application Support/LacyLights"
export LACYLIGHTS_LOGS="$HOME/Library/Logs/LacyLights"
export LACYLIGHTS_CACHE="$HOME/Library/Caches/LacyLights"

# Application data subdirectories
export LACYLIGHTS_REPOS="$LACYLIGHTS_APP_SUPPORT/repos"
export LACYLIGHTS_CONFIG="$LACYLIGHTS_APP_SUPPORT/config"

# Individual repository paths
export LACYLIGHTS_NODE_DIR="$LACYLIGHTS_REPOS/lacylights-node"
export LACYLIGHTS_FE_DIR="$LACYLIGHTS_REPOS/lacylights-fe"
export LACYLIGHTS_MCP_DIR="$LACYLIGHTS_REPOS/lacylights-mcp"

# Function to create all required directories
create_directories() {
    mkdir -p "$LACYLIGHTS_APP_SUPPORT"
    mkdir -p "$LACYLIGHTS_REPOS"
    mkdir -p "$LACYLIGHTS_CONFIG"
    mkdir -p "$LACYLIGHTS_LOGS"
    mkdir -p "$LACYLIGHTS_CACHE"
}

# Function to check if required repositories are missing
repos_missing() {
    if [ ! -d "$LACYLIGHTS_NODE_DIR" ] || [ ! -d "$LACYLIGHTS_FE_DIR" ]; then
        return 0  # true - repos missing
    else
        return 1  # false - repos present
    fi
}

# Automatically create directories when sourced
create_directories
