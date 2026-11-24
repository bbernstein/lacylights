# Embedded Claude Code Terminal in LacyLights Mac

**Date:** 2026-03-04
**Status:** Design
**Scope:** lacylights-mac

## Summary

Add a full terminal emulator to the LacyLights Mac app that runs Claude Code, enabling AI-assisted lighting design directly within the app. The terminal is configured to use the lacylights MCP server, giving Claude access to all lighting tools (fixture management, look generation, cue programming, script analysis, etc.).

Users authenticate via Claude Code's built-in OAuth flow (Claude Max/Pro subscription), which is permitted since Claude Code is an official Anthropic product. The Mac app simply hosts the terminal — it does not implement its own Claude API integration.

## Problem

Currently, users must run Claude.app separately alongside the LacyLights Mac app, with a manually configured MCP server connection. This creates a fragmented workflow: switch to Claude.app to describe lighting intent, switch back to LacyLights to see results, switch back to Claude to iterate. The MCP server configuration must also be maintained manually.

## Solution

Embed a PTY-based terminal emulator (SwiftTerm) in a split pane alongside the LacyLights web view. The Mac app auto-generates MCP configuration so Claude Code connects to the correct backend server. The user sees lighting changes in real-time while chatting with Claude.

## Architecture

### Configurable Backend Server

The backend (lacylights-go) may run locally (managed by the Mac app) or remotely (e.g., on a Raspberry Pi in a theatre). A new **Server Configuration** system lets the user choose where the backend lives:

```
┌─────────────────────────────────────────────────┐
│ Server Configuration                            │
│                                                 │
│ ○ Local (this Mac)     ← default                │
│   Backend managed by this app                   │
│                                                 │
│ ○ Remote server                                 │
│   Host: [ lacylights.local          ]           │
│   Port: [ 4000                      ]           │
│   Protocol: HTTP ▾                              │
│   [ Test Connection ]                           │
│                                                 │
│ GraphQL endpoint: http://lacylights.local:4000  │
└─────────────────────────────────────────────────┘
```

**Impact of server selection:**
- **Frontend (WKWebView):** The `GRAPHQL_URL` and `GRAPHQL_WS_URL` env vars change to point at the selected server
- **MCP config:** The `.mcp.json` `LACYLIGHTS_GRAPHQL_ENDPOINT` env var changes to point at the selected server
- **Local services:** When "Remote" is selected, the Mac app does not need to start the Go backend (and optionally skips the frontend too, loading the remote frontend directly)

**Server configuration is stored in `UserDefaults`** and surfaced in the existing Settings view. It is also presented during first launch (SetupView) as a step before service startup.

### Split Pane Layout

```
┌──────────────────────────────────────────────────┐
│  LacyLights Mac App                              │
│  ┌─────────────────────┬────────────────────────┐│
│  │                     │                        ││
│  │   LacyLights Web    │   Claude Code          ││
│  │   (WKWebView)       │   Terminal             ││
│  │                     │   (SwiftTerm PTY)      ││
│  │   - See lighting    │                        ││
│  │     changes live    │   - Chat with Claude   ││
│  │   - Control board   │   - Uses Max/Pro sub   ││
│  │   - Look boards     │   - MCP tools for      ││
│  │                     │     lighting control    ││
│  │                     │                        ││
│  └─────────────────────┴────────────────────────┘│
└──────────────────────────────────────────────────┘
```

- `NSSplitView` (or `HSplitView`) with resizable divider
- Left pane: existing `WebViewContainer` (LacyLights frontend)
- Right pane: new `ClaudeTerminalView` (SwiftTerm `LocalProcessTerminalView`)
- Terminal pane is collapsible — can be hidden to get the original full-width web view
- Toggle via toolbar button and/or keyboard shortcut (e.g., Cmd+T or Cmd+Shift+C)

### Data Flow

```
User types in Claude Code terminal
    │
    ▼
Claude Code (running in SwiftTerm PTY)
    │ authenticates via Claude Max OAuth (built-in)
    │
    │ spawns via stdio (.mcp.json config)
    ▼
lacylights-mcp (Node.js child process of Claude Code)
    │
    │ HTTP POST GraphQL
    ▼
lacylights-go backend (local or remote)
    │
    │ Art-Net UDP
    ▼
DMX Fixtures
    │
    │ changes reflected in
    ▼
LacyLights Web UI (left pane updates via GraphQL subscriptions)
```

### MCP Auto-Configuration

When the backend is ready (local startup complete, or remote server configured), the Mac app generates a `.mcp.json` file in a dedicated Claude Code workspace directory:

```
~/Library/Application Support/LacyLights/claude-workspace/.mcp.json
```

Contents:

```json
{
  "mcpServers": {
    "lacylights": {
      "command": "/opt/homebrew/bin/node",
      "args": ["<path-to-mcp>/run-mcp.js"],
      "env": {
        "LACYLIGHTS_GRAPHQL_ENDPOINT": "http://<server-host>:<server-port>/graphql"
      }
    }
  }
}
```

- `<path-to-mcp>` is `~/Library/Application Support/LacyLights/repos/lacylights-mcp/run-mcp.js`
- `<server-host>:<server-port>` comes from the server configuration (localhost + dynamic port for local, or the configured remote host/port)
- The `node` path is resolved from PATH at generation time
- The file is regenerated whenever the server configuration or backend port changes

Claude Code is launched with `claude-workspace` as its working directory so it picks up the `.mcp.json` automatically.

### MCP Instance Management

- Claude Code manages its own lacylights-mcp instance (spawns via stdio as a child process)
- The Mac app does NOT need to run a separate MCP server when the terminal is active
- If no terminal is active and the user wants MCP for other clients (e.g., separate Claude.app), the existing optional MCP startup remains available
- No changes needed to lacylights-mcp itself — it works as-is

### Claude Code Lifecycle

1. **Terminal creation:** SwiftTerm `LocalProcessTerminalView` opens a PTY running the user's default shell (e.g., `/bin/zsh`)
2. **Starting Claude:** User types `claude` or clicks a "Start Claude" toolbar button that sends the command to the PTY
3. **Authentication:** First-time only — Claude Code's built-in OAuth flow handles login. Credentials are cached by Claude Code in `~/.claude/`
4. **Conversation:** User interacts with Claude Code normally. Claude uses lacylights MCP tools to control lighting
5. **Shutdown:** On app quit, the PTY process tree receives SIGHUP when the terminal closes. Claude Code handles graceful shutdown

### Claude Code Installation

Claude Code must be installed on the system. The Mac app should:
- Check if `claude` is available in PATH at startup
- If not found, show a message with installation instructions (link to claude.ai/download or `npm install -g @anthropic-ai/claude-code`)
- Do not attempt to install it automatically — Claude Code has its own installer and update mechanism

## New Components

| File | Type | Purpose |
|------|------|---------|
| `ClaudeTerminalView.swift` | View | SwiftTerm NSView wrapper, PTY configuration, process launch |
| `ClaudeWorkspaceManager.swift` | Manager | Generates `.mcp.json`, manages workspace directory, regenerates on config change |
| `ServerConfiguration.swift` | Model | Server connection model (local vs remote, host, port, protocol) |
| `ServerConfigurationView.swift` | View | UI for selecting and configuring the backend server |

## Modified Components

| File | Change |
|------|--------|
| `Package.swift` | Add SwiftTerm SPM dependency |
| `ContentView.swift` | Replace full-width web view with split pane on LacyLights tab |
| `UserPreferences.swift` | Add server configuration properties (serverMode, remoteHost, remotePort) |
| `StartupCoordinator.swift` | After backend ready, trigger workspace config generation; skip backend start if remote mode |
| `SetupView.swift` | Add server selection step to first-run wizard |
| `PathConfiguration.swift` | Add `claudeWorkspace` directory path |
| `WebViewContainer.swift` | Use configured server URL for GraphQL instead of assuming localhost |

## What We Are NOT Building

- No custom chat UI or message parsing — Claude Code provides the full experience
- No API key management — Claude Code handles its own OAuth
- No custom MCP protocol handling — standard `.mcp.json` config
- No modifications to lacylights-mcp — works as-is
- No modifications to lacylights-go — works as-is
- No auto-installation of Claude Code — user installs it themselves

## Dependencies

| Dependency | Source | Purpose |
|------------|--------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Swift Package Manager | Terminal emulator with PTY support |
| Claude Code | User-installed CLI | AI assistant (runs inside terminal) |

SwiftTerm is the only new Swift dependency. The app currently has zero SPM dependencies, so this would be the first.

## Testing Strategy

- Unit tests for `ServerConfiguration` model (serialization, validation, URL construction)
- Unit tests for `ClaudeWorkspaceManager` (`.mcp.json` generation with various server configs)
- Unit test for `UserPreferences` server configuration persistence
- Manual testing for terminal integration (PTY interaction is difficult to unit test)
- Integration test: verify `.mcp.json` content matches expected format for Claude Code

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Claude Code changes its MCP config format | `.mcp.json` is a stable MCP standard, not Claude-specific |
| SwiftTerm doesn't render Claude Code's TUI correctly | SwiftTerm has full VT100/Xterm support; Claude Code uses standard terminal output |
| User doesn't have Claude Code installed | Detect at startup, show clear installation instructions |
| Remote server unreachable | "Test Connection" button in server config; health check before generating MCP config |
| Dynamic port changes after MCP config written | Regenerate `.mcp.json` on port change; user may need to restart Claude Code session |
