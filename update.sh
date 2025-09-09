#!/bin/bash

# LacyLights Update Command
# This script provides a simple way to update all LacyLights repositories

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change to the lacylights directory
cd "$SCRIPT_DIR"

# Check if update-repos.sh exists
if [ ! -f "update-repos.sh" ]; then
    echo "Error: update-repos.sh not found"
    echo "Please ensure you're in the lacylights directory"
    exit 1
fi

# Run the update script with all arguments passed through
./update-repos.sh "$@"