# LacyLights.app macOS Directory Structure

LacyLights now follows macOS best practices for application directory structure.

## Application Bundle

**Location**: `/Applications/LacyLights.app/`

The application bundle contains only read-only resources:

```
LacyLights.app/
├── Contents/
│   ├── Info.plist                 # App metadata
│   ├── MacOS/
│   │   └── LacyLights             # Main executable (launcher script)
│   └── Resources/
│       ├── AppIcon.icns           # Application icon
│       └── scripts/               # All shell scripts
│           ├── paths.sh           # Path configuration
│           ├── setup.sh           # First-run setup
│           ├── start.sh           # Service startup
│           ├── stop.sh            # Service shutdown
│           └── update-repos.sh    # Update checker
```

## User Data Directories

Following macOS standards, user data is stored in standard locations:

### Application Support
**Location**: `~/Library/Application Support/LacyLights/`

Contains all application data:

```
~/Library/Application Support/LacyLights/
├── repos/                          # Downloaded repositories
│   ├── lacylights-node/           # Backend server
│   ├── lacylights-fe/             # Frontend web app
│   └── lacylights-mcp/            # AI integration server
└── config/                         # User configuration files
```

### Logs
**Location**: `~/Library/Logs/LacyLights/`

Contains all application logs:

```
~/Library/Logs/LacyLights/
├── backend.log                     # Backend server logs
├── frontend.log                    # Frontend server logs
└── mcp.log                         # MCP server logs (if enabled)
```

### Cache
**Location**: `~/Library/Caches/LacyLights/`

Reserved for temporary files and downloads (currently unused; available for future use).

## Environment Variables

The `paths.sh` script defines these environment variables:

- `LACYLIGHTS_APP_BUNDLE` - Path to the .app bundle
- `LACYLIGHTS_RESOURCES` - Path to Resources directory
- `LACYLIGHTS_APP_SUPPORT` - Application Support directory
- `LACYLIGHTS_LOGS` - Logs directory
- `LACYLIGHTS_CACHE` - Cache directory
- `LACYLIGHTS_REPOS` - Repository storage directory
- `LACYLIGHTS_CONFIG` - Configuration directory
- `LACYLIGHTS_NODE_DIR` - Backend repository path
- `LACYLIGHTS_FE_DIR` - Frontend repository path
- `LACYLIGHTS_MCP_DIR` - MCP repository path

## Benefits

1. **Self-Contained**: App bundle contains only scripts, no user data
2. **Distributable**: Can copy .app to /Applications without modifications
3. **Multi-User**: Each user gets their own data in their Library folder
4. **Standard**: Follows Apple Human Interface Guidelines
5. **Clean Uninstall**: Easy to remove all data by deleting folders
6. **Backup-Friendly**: Time Machine automatically backs up Library folders

## Migration from Old Structure

If you have an existing installation with data in the old location (inside the repository directory):

1. The app will detect this is a first run and prompt for setup
2. Run setup to download fresh copies to the new location
3. Manually migrate any custom .env files if needed:
   - Old: `lacylights/lacylights-node/.env`
   - New: `~/Library/Application Support/LacyLights/repos/lacylights-node/.env`

## Development vs Production

### Development
When developing, you can still run scripts directly from the repository:
```bash
cd ~/src/lacylights/lacylights
./setup.sh
./start.sh
```

### Production (macOS App)
Double-click `LacyLights.app` or run from Applications folder. All data goes to standard macOS locations automatically.
