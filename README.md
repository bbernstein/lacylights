# LacyLights - Theatrical Lighting Control System

LacyLights is a comprehensive theatrical lighting control system composed of three integrated components that work together to provide powerful, AI-enhanced lighting design and control capabilities.

## System Architecture

The LacyLights system consists of three main components:

### 🎭 lacylights-node - Backend Engine
A professional stage lighting control system built with Node.js, GraphQL, and TypeScript. This server provides:
- **GraphQL API** with real-time subscriptions
- Multi-universe DMX512 control with priority system
- Scene and cue list management with preview capabilities
- Fixture library with built-in and custom fixture definitions
- Multi-user collaboration with role-based permissions
- SQLite database with Prisma ORM for lightweight, portable storage

**Repository**: [lacylights-node](https://github.com/bbernstein/lacylights-node)

### 🖥️ lacylights-fe - Frontend Web Interface
A Next.js 15-based web frontend built with TypeScript and Tailwind CSS. It provides:
- Real-time lighting control interface
- Fixture management and DMX patching
- Visual scene creation with channel controls
- Cue list sequencing and playback
- Live DMX output monitoring
- Apollo Client for GraphQL integration with WebSocket subscriptions
- Responsive design for various devices

**Repository**: [lacylights-fe](https://github.com/bbernstein/lacylights-fe)

### 🤖 lacylights-mcp - AI Integration Server
An MCP (Model Context Protocol) server that provides AI-powered theatrical lighting design capabilities:
- **Fixture Analysis** - Query and analyze lighting fixture capabilities
- **Scene Generation** - AI-powered scene creation based on script context and artistic intent
- **Script Analysis** - Extract lighting cues and moments from theatrical scripts
- **Cue Management** - Generate and optimize complete cue sequences for acts
- **RAG System** - Vector-based pattern matching for intelligent lighting suggestions
- Integration with Claude and other AI assistants via MCP protocol

**Repository**: [lacylights-mcp](https://github.com/bbernstein/lacylights-mcp)

### 🍎 lacylights-mac - Native macOS Application
A native Swift/SwiftUI application for macOS that provides turnkey setup and management:
- **One-Click Setup** - Automated repository cloning and dependency installation
- **Service Management** - Start/stop backend, frontend, and MCP with health monitoring
- **Embedded Web View** - Integrated browser for the lighting control interface
- **Update Management** - Check for and install updates across all repositories
- **Console Monitoring** - Real-time log viewing for all services
- **Menu Bar Integration** - Quick access to common operations

**Repository**: [lacylights-mac](https://github.com/bbernstein/lacylights-mac)

## How It Works

```
┌─────────────────┐        ┌──────────────────┐     ┌─────────────────┐
│                 │        │                  │     │                 │
│  lacylights-fe  │───────▶│ lacylights-node  │────▶│  DMX Hardware   │
│   (Frontend)    │GraphQL │    (Backend)     │ DMX │   (Fixtures)    │
│                 │   +    │                  │     │                 │
└─────────────────┘   WS   └──────────────────┘     └─────────────────┘
                                  │
                                  │ GraphQL
                                  ▼
                           ┌──────────────────┐
                           │                  │
                           │  lacylights-mcp  │
                           │  (AI Bridge)     │
                           │                  │
                           └──────────────────┘
                                  │
                                  │ MCP
                                  ▼
                           ┌──────────────────┐
                           │                  │
                           │  AI Assistants   │
                           │    (Claude)      │
                           │                  │
                           └──────────────────┘
```

1. **Frontend Control**: Users interact with the web interface (lacylights-fe) to manually control fixtures, create scenes, and manage cue lists. The frontend uses Apollo Client to communicate via GraphQL queries, mutations, and subscriptions.

2. **Backend Processing**: The frontend communicates with the backend engine (lacylights-node) via GraphQL API with WebSocket support for real-time updates. The backend manages all lighting state, processes commands, and outputs DMX signals to physical lighting fixtures.

3. **AI Enhancement**: The MCP server (lacylights-mcp) connects to the same GraphQL API and provides an additional control path, allowing AI assistants to:
   - Analyze theatrical scripts and suggest lighting designs
   - Generate scenes based on natural language descriptions
   - Optimize existing lighting setups
   - Provide intelligent automation for complex lighting sequences

## Getting Started

### Raspberry Pi Deployment (Recommended for Production)

**LacyLights is designed to run as a turnkey hardware product on Raspberry Pi.**

For complete Raspberry Pi deployment instructions, see:
📖 **[Raspberry Pi Deployment Guide](https://github.com/bbernstein/lacylights-node/blob/main/deploy/DEPLOYMENT.md)**

Quick deployment steps:
```bash
# 1. Copy deployment script to Raspberry Pi
scp lacylights-node/deploy/deploy.sh pi@lacylights.local:/tmp/

# 2. SSH into Raspberry Pi
ssh pi@lacylights.local

# 3. Run deployment (installs everything automatically)
sudo bash /tmp/deploy.sh
```

After deployment, access LacyLights at `http://lacylights.local`

**Features:**
- Automated installation and configuration
- Static export frontend with nginx
- SQLite database (no Docker required)
- Systemd service management
- Art-Net DMX output support
- ~350MB RAM footprint

### Development Setup (macOS/Linux)

#### Quick Start with Scripts

The easiest way to get started for development is using our automated scripts:

```bash
# Initial setup - clones all repositories and installs dependencies
./setup.sh [your-github-username]

# Check for updates across all repositories
./update.sh --check

# Update all repositories to latest versions
./update.sh

# Start all services
./start.sh

# Start with AI integration
./start.sh --with-mcp
```

#### Native macOS Application (Recommended for macOS Users)

For the best experience on macOS, use the native LacyLights application:

**Download**: [Latest Release](https://github.com/bbernstein/lacylights-mac/releases)

The native app provides:
- One-click setup wizard with automatic dependency installation
- Service management with health monitoring
- Embedded web interface (no separate browser needed)
- Real-time console logs for all services
- Update checking and automatic repository updates
- Menu bar integration for quick access

**Quick Start**:
1. Download `LacyLights-X.X.X-macOS.zip` from releases
2. Extract and move to Applications folder
3. Right-click and "Open" (first time only)
4. Follow the setup wizard
5. Click "Start Services" and you're ready!

See the [lacylights-mac repository](https://github.com/bbernstein/lacylights-mac) for detailed documentation.

#### Manual Development Setup

To run the complete LacyLights system manually:

1. **Start the Backend Engine**:
   ```bash
   cd lacylights-node
   npm install

   # Set up the database (SQLite - no Docker required)
   npm run db:generate
   npm run db:migrate

   # Start development server
   npm run dev
   ```
   The GraphQL playground will be available at `http://localhost:4000/graphql`

2. **Launch the Frontend**:
   ```bash
   cd lacylights-fe
   npm install

   # Copy environment configuration
   cp .env.example .env.local

   # Start development server
   npm run dev
   ```
   Open `http://localhost:3000` in your browser

3. **Enable AI Integration** (optional):
   ```bash
   cd lacylights-mcp
   npm install

   # Set up environment
   cp .env.example .env
   # Edit .env to add your OPENAI_API_KEY

   # Build and start
   npm run build
   npm start
   ```
   Then add the MCP server to your Claude configuration

## Use Cases

- **Theater Productions**: Design and control lighting for plays and musicals
- **Live Events**: Manage lighting for concerts, conferences, and performances
- **Educational**: Teaching lighting design with AI-assisted learning
- **Automated Shows**: Create intelligent lighting that responds to scripts and cues

## Contributing

Each component has its own repository with specific contribution guidelines. Please refer to the individual READMEs for development setup and contribution instructions.

## License

See individual component repositories for licensing information.
