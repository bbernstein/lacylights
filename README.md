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
- PostgreSQL database with Prisma ORM
- Docker support for easy deployment

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

To run the complete LacyLights system:

1. **Start the Backend Engine**:
   ```bash
   cd lacylights-node
   npm install

   # Start PostgreSQL and Redis with Docker (recommended)
   npm run docker:db

   # Set up the database
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
