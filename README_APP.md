# LacyLights Mac App

The `LacyLights.app` bundle provides a convenient double-click launcher for the entire LacyLights platform on macOS.

## Features

- **First-run setup wizard** - Automatically guides through repository setup on first launch
- **API key configuration** - Prompts for OpenAI API key configuration when needed
- **Terminal integration** - Launches services in Terminal for full visibility
- **Process management** - Handles all three services with proper cleanup

## Usage

### First Time Setup

1. Double-click `LacyLights.app`
2. Click "Setup" when prompted
3. Enter your GitHub organization name (or leave blank to enter URLs manually)
4. The setup script will run in Terminal and clone all necessary repositories
5. Optionally configure your OpenAI API key when prompted

### Regular Launch

1. Double-click `LacyLights.app`
2. Choose whether to start with AI integration (MCP) or not
3. The platform will launch in a Terminal window
4. Your browser will automatically open to http://localhost:3000

### Stopping the Platform

In the Terminal window running LacyLights, press `Ctrl+C` to stop all services gracefully.

## App Structure

```
LacyLights.app/
├── Contents/
│   ├── Info.plist          # App metadata
│   ├── MacOS/
│   │   └── LacyLights      # Main executable script
│   └── Resources/
│       └── AppIcon.icns    # App icon
```

## Customization

You can customize the app by:
- Replacing the icon in `Contents/Resources/AppIcon.icns`
- Modifying the launcher script in `Contents/MacOS/LacyLights`
- Updating `Info.plist` with your organization details

## Troubleshooting

- **App won't open**: Right-click and select "Open" to bypass Gatekeeper on first run
- **Setup fails**: Check the Terminal window for error messages
- **Services won't start**: Run `./setup.sh` manually in Terminal from the lacylights directory