# LacyLights System Architecture

## Overview

LacyLights is a theatrical lighting control system consisting of multiple repositories that work together to provide DMX fixture control, scene management, and AI-powered lighting design.

## Repository Categories

### Application Components
These are the core applications that make up the LacyLights system:

| Repository | Purpose | Language |
|------------|---------|----------|
| **lacylights-go** | Backend API server (GraphQL, DMX/Art-Net, SQLite) | Go |
| **lacylights-fe** | Web frontend (lighting console UI) | TypeScript/Next.js |
| **lacylights-mcp** | AI integration server (MCP protocol) | TypeScript |

### Production Deployment Platforms
These are hardware-specific platforms that host the application components in production:

| Platform | Hosts | Description |
|----------|-------|-------------|
| **lacylights-mac** | Frontend + Backend + MCP | Native macOS app with embedded servers |
| **lacylights-rpi** | Frontend + Backend | Raspberry Pi turnkey lighting controller |

Both platforms serve the same purpose: running LacyLights in production on specific hardware. They download releases from the distribution infrastructure and manage the application lifecycle.

### Infrastructure & Testing

| Repository | Purpose |
|------------|---------|
| **lacylights-terraform** | Production release distribution (S3, CloudFront, DynamoDB) |
| **lacylights-test** | Cross-repository integration and contract tests |

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEVELOPMENT (any OS)                             │
│  Developer runs lacylights-go, lacylights-fe, lacylights-mcp locally    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ git push → CI/CD builds
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    DISTRIBUTION (lacylights-terraform)                   │
│                                                                          │
│   S3 Bucket ──▶ CloudFront CDN ──▶ dist.lacylights.com                  │
│   (releases)      (global)           (download endpoint)                 │
│                                                                          │
│   DynamoDB (version metadata)                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│   PRODUCTION: macOS Platform  │   │  PRODUCTION: Raspberry Pi     │
│      (lacylights-mac)         │   │      (lacylights-rpi)         │
│                               │   │                               │
│  ┌─────────────────────────┐  │   │  ┌─────────────────────────┐  │
│  │    lacylights-fe        │  │   │  │    lacylights-fe        │  │
│  │    (Next.js static)     │  │   │  │    (Next.js static)     │  │
│  └───────────┬─────────────┘  │   │  └───────────┬─────────────┘  │
│              │ GraphQL        │   │              │ GraphQL        │
│  ┌───────────▼─────────────┐  │   │  ┌───────────▼─────────────┐  │
│  │    lacylights-go        │  │   │  │    lacylights-go        │  │
│  │    (Backend binary)     │  │   │  │    (Backend binary)     │  │
│  └───────────┬─────────────┘  │   │  └───────────┬─────────────┘  │
│              │ Art-Net/DMX    │   │              │ Art-Net/DMX    │
│  ┌───────────▼─────────────┐  │   │  ┌───────────▼─────────────┐  │
│  │    lacylights-mcp       │  │   │  │                         │  │
│  │    (AI Server) ✓        │  │   │  │    (not available)      │  │
│  └─────────────────────────┘  │   │  └─────────────────────────┘  │
└───────────────────────────────┘   └───────────────────────────────┘
              │                                   │
              └───────────────┬───────────────────┘
                              ▼
                    ┌─────────────────┐
                    │  DMX Fixtures   │
                    │  (via Art-Net)  │
                    └─────────────────┘
```

## Data Flow

### User Interaction Flow
1. User opens web UI (served by **lacylights-fe**)
2. Frontend sends GraphQL queries/mutations to **lacylights-go**
3. Backend processes requests, updates SQLite database
4. Backend sends DMX data via Art-Net to physical fixtures
5. Real-time updates pushed via WebSocket subscriptions

### AI Integration Flow (macOS only)
1. AI assistant (Claude) calls **lacylights-mcp** tools via MCP protocol
2. MCP server translates to GraphQL calls
3. Calls **lacylights-go** backend
4. Optional: Uses OpenAI for scene generation
5. Returns results to AI assistant

### Release Distribution Flow
1. Code changes pushed to component repos (go, fe, mcp)
2. CI/CD builds, tests, and creates release artifacts
3. Releases uploaded to **lacylights-terraform** infrastructure (S3/CloudFront)
4. Production platforms download updates:
   - **lacylights-mac**: Downloads and installs via app update mechanism
   - **lacylights-rpi**: Downloads via install.sh or deployment scripts
5. Applications restart with new versions

## Key Technologies

| Component | Language | Key Technologies |
|-----------|----------|------------------|
| lacylights-go | Go | gqlgen, SQLite, Art-Net UDP |
| lacylights-fe | TypeScript | Next.js, React, Apollo Client, Tailwind |
| lacylights-mcp | TypeScript | MCP SDK, OpenAI API |
| lacylights-test | Go | GraphQL client, Art-Net receiver |
| lacylights-terraform | HCL | AWS S3, CloudFront, DynamoDB, Route53 |
| lacylights-rpi | Bash | systemd, NetworkManager, nginx |
| lacylights-mac | Swift | SwiftUI, WKWebView, Foundation.Process |

## Services and Ports

| Service | Port | Protocol | Component |
|---------|------|----------|-----------|
| GraphQL API | 4000 (dev) / 4001 (test) | HTTP | lacylights-go |
| WebSocket | 4000 | WS | lacylights-go |
| Art-Net DMX | 6454 | UDP | lacylights-go |
| Web Frontend | 3000 | HTTP | lacylights-fe |
| MCP Server | stdio | - | lacylights-mcp |

## Database

- **SQLite** (single-file database)
- Located at `DATABASE_URL` (default: `file:./dev.db`)
- Managed by lacylights-go

## GraphQL Schema

The **source of truth** for API contracts is:
```
lacylights-go/internal/graph/schema.graphqls
```

All consumers must update when schema changes:
- lacylights-fe: Run `npm run codegen`
- lacylights-mcp: Update GraphQL queries manually
- lacylights-test: Update test queries

## Platform Comparison

| Feature | macOS (lacylights-mac) | Raspberry Pi (lacylights-rpi) |
|---------|------------------------|-------------------------------|
| Frontend | ✓ Embedded in app | ✓ Static files via nginx |
| Backend | ✓ Managed process | ✓ systemd service |
| MCP Server | ✓ Optional | ✗ Not available |
| Update mechanism | App-based | Script-based |
| Target users | Individual designers | Permanent installations |
| Network | WiFi/Ethernet | Dual-network (DMX + Internet) |

## Development vs Production

**Development** (any OS - macOS, Linux, Windows):
- Clone repos and run components directly
- Uses local development servers
- Hot reload, debugging, etc.

**Production** (specific hardware platforms):
- **lacylights-mac**: Native app manages all components
- **lacylights-rpi**: systemd services, turnkey appliance
- Both download releases from dist.lacylights.com
