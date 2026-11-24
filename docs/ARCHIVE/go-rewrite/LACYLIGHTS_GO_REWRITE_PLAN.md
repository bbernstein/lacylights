# LacyLights Go Server Implementation Plan

**Project:** lacylights-go
**Goal:** Complete Go rewrite of lacylights-node backend server with 100% GraphQL API compatibility
**Status:** Planning Phase
**Created:** 2025-11-26
**Last Updated:** 2025-11-26

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [L1 Architecture Diagram](#l1-architecture-diagram)
3. [L2 Component Diagrams](#l2-component-diagrams)
4. [Technology Stack](#technology-stack)
5. [Implementation Phases](#implementation-phases)
6. [Contract Testing Strategy](#contract-testing-strategy)
7. [Database Compatibility](#database-compatibility)
8. [Project Structure](#project-structure)
9. [Verification Strategy](#verification-strategy)
10. [Risk Mitigation](#risk-mitigation)
11. [Success Criteria](#success-criteria)

---

## Executive Summary

### Objectives

1. **100% GraphQL API Compatibility**: Implement all 42+ queries, 60+ mutations, and 6 subscriptions from lacylights-node
2. **Database Compatibility**: Read/write the same SQLite database created by lacylights-node
3. **Contract Test Compliance**: Pass all existing contract tests defined in CONTRACT_TESTING_PLAN.md
4. **ArtNet DMX Output**: Identical real-time DMX512 control via Art-Net UDP broadcast
5. **Performance**: Leverage Go's concurrency model for improved real-time performance

### Why Go?

| Benefit | Description |
|---------|-------------|
| **Performance** | Lower latency for real-time DMX at 44Hz transmission |
| **Concurrency** | Native goroutines for parallel DMX, fades, and API handling |
| **Binary Distribution** | Single binary deployment, no Node.js runtime required |
| **Memory Efficiency** | Lower memory footprint on Raspberry Pi |
| **Type Safety** | Strong typing with compile-time verification |

### Compatibility Requirements

- **GraphQL Schema**: Identical schema.graphql (799 lines)
- **Database**: SQLite with exact same schema (17 tables)
- **ArtNet Protocol**: Same packet structure, timing, adaptive rates
- **API Contract**: Frontend and MCP clients work without modification

---

## L1 Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              LacyLights System                                    │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐            │
│  │  lacylights-fe  │     │  lacylights-mcp │     │  External Tools │            │
│  │    (Next.js)    │     │     (MCP)       │     │  (QLC+, etc.)   │            │
│  └────────┬────────┘     └────────┬────────┘     └────────┬────────┘            │
│           │                       │                       │                      │
│           │ GraphQL (HTTP/WS)     │ GraphQL (HTTP)       │ GraphQL              │
│           │ Port 4000             │ Port 4000             │ Port 4000            │
│           │                       │                       │                      │
│           ▼                       ▼                       ▼                      │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                        lacylights-go Server                               │   │
│  │                                                                           │   │
│  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
│  │  │                     GraphQL API Layer                               │  │   │
│  │  │  • 42+ Queries  • 60+ Mutations  • 6 Subscriptions                 │  │   │
│  │  └───────────────────────────┬────────────────────────────────────────┘  │   │
│  │                              │                                            │   │
│  │  ┌───────────────────────────▼────────────────────────────────────────┐  │   │
│  │  │                     Service Layer                                   │  │   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │  │   │
│  │  │  │  DMXService  │  │  FadeEngine  │  │  Playback    │             │  │   │
│  │  │  │  (44Hz UDP)  │  │  (40Hz calc) │  │  Service     │             │  │   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘             │  │   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │  │   │
│  │  │  │   Preview    │  │    WiFi      │  │   Export/    │             │  │   │
│  │  │  │   Service    │  │   Service    │  │   Import     │             │  │   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘             │  │   │
│  │  └───────────────────────────┬────────────────────────────────────────┘  │   │
│  │                              │                                            │   │
│  │  ┌───────────────────────────▼────────────────────────────────────────┐  │   │
│  │  │                     Data Layer (GORM + SQLite)                      │  │   │
│  │  │  17 Tables: projects, fixtures, scenes, cues, settings, etc.       │  │   │
│  │  └────────────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│           │                                                                      │
│           │ Art-Net UDP                                                         │
│           │ Port 6454                                                           │
│           ▼                                                                      │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                       DMX Lighting Network                                │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                     │   │
│  │  │ Universe│  │ Universe│  │ Universe│  │ Universe│                     │   │
│  │  │    1    │  │    2    │  │    3    │  │    4    │                     │   │
│  │  │512 chan │  │512 chan │  │512 chan │  │512 chan │                     │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘                     │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘

Legend:
─────────────────────────────────────────────────────────────────────────────────────
│ Component       │ Technology      │ Port  │ Protocol │ Purpose                   │
├─────────────────┼─────────────────┼───────┼──────────┼───────────────────────────┤
│ GraphQL API     │ gqlgen          │ 4000  │ HTTP/WS  │ Frontend/MCP communication│
│ Database        │ GORM + SQLite   │ N/A   │ File     │ Persistent data storage   │
│ DMX Output      │ net.UDPConn     │ 6454  │ UDP      │ Art-Net DMX broadcast     │
│ WebSocket       │ gorilla/ws      │ 4000  │ WS       │ Real-time subscriptions   │
─────────────────────────────────────────────────────────────────────────────────────
```

---

## L2 Component Diagrams

### L2.1: GraphQL Layer

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                          GraphQL Layer (gqlgen)                                │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         HTTP Server (chi router)                         │  │
│  │                                                                          │  │
│  │  Routes:                                                                 │  │
│  │  • POST /graphql     → GraphQL handler                                  │  │
│  │  • GET  /graphql     → GraphQL Playground                               │  │
│  │  • WS   /graphql     → WebSocket subscriptions                          │  │
│  │  • GET  /health      → Health check endpoint                            │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         Schema (schema.graphql)                          │  │
│  │                                                                          │  │
│  │  Types:                                                                  │  │
│  │  • Project, FixtureInstance, Scene, CueList, Cue                        │  │
│  │  • FixtureDefinition, ChannelDefinition, FixtureMode                    │  │
│  │  • SceneBoard, SceneBoardButton, PreviewSession                         │  │
│  │  • User, ProjectUser, Setting, UniverseOutput                           │  │
│  │  • WiFiNetwork, WiFiStatus, SystemInfo                                  │  │
│  │  • Export/Import types, QLC+ integration types                          │  │
│  │                                                                          │  │
│  │  Enums:                                                                  │  │
│  │  • FixtureType, ChannelType, EasingType                                 │  │
│  │  • UserRole, ProjectRole, WiFiSecurityType                              │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         Resolvers                                        │  │
│  │                                                                          │  │
│  │  Query Resolvers:                                                        │  │
│  │  ├─ project.go        → projects, project                               │  │
│  │  ├─ fixture.go        → fixtureDefinitions, fixtureInstances, etc.      │  │
│  │  ├─ scene.go          → scenes, scene, sceneFixtures, compareScenes     │  │
│  │  ├─ cue.go            → cueLists, cueList, cue, playbackStatus          │  │
│  │  ├─ dmx.go            → dmxOutput, allDmxOutput, currentActiveScene     │  │
│  │  ├─ preview.go        → previewSession                                  │  │
│  │  ├─ settings.go       → settings, setting, systemInfo                   │  │
│  │  ├─ wifi.go           → wifiNetworks, wifiStatus, savedNetworks         │  │
│  │  ├─ search.go         → searchFixtures, searchScenes, searchCues        │  │
│  │  ├─ sceneboard.go     → sceneBoards, sceneBoard, sceneBoardButton       │  │
│  │  └─ qlc.go            → getQLCFixtureMappingSuggestions                 │  │
│  │                                                                          │  │
│  │  Mutation Resolvers:                                                     │  │
│  │  ├─ project.go        → createProject, updateProject, deleteProject     │  │
│  │  ├─ fixture.go        → CRUD fixtures, bulk operations                  │  │
│  │  ├─ scene.go          → CRUD scenes, clone, duplicate, addFixtures      │  │
│  │  ├─ cue.go            → CRUD cues/cueLists, reorder, bulk update        │  │
│  │  ├─ dmx.go            → setChannelValue, setSceneLive, fadeToBlack      │  │
│  │  ├─ playback.go       → startCueList, nextCue, previousCue, goToCue     │  │
│  │  ├─ preview.go        → start/commit/cancel preview, updateChannel      │  │
│  │  ├─ sceneboard.go     → CRUD sceneboards/buttons, activateScene         │  │
│  │  ├─ export.go         → exportProject, importProject                    │  │
│  │  ├─ qlc.go            → importProjectFromQLC, exportProjectToQLC        │  │
│  │  ├─ settings.go       → updateSetting                                   │  │
│  │  └─ wifi.go           → connectWiFi, disconnectWiFi, setWiFiEnabled     │  │
│  │                                                                          │  │
│  │  Subscription Resolvers:                                                 │  │
│  │  ├─ dmxOutputChanged(universe)                                          │  │
│  │  ├─ projectUpdated(projectId)                                           │  │
│  │  ├─ previewSessionUpdated(projectId)                                    │  │
│  │  ├─ cueListPlaybackUpdated(cueListId)                                   │  │
│  │  ├─ systemInfoUpdated                                                   │  │
│  │  └─ wifiStatusUpdated                                                   │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
└───────────────────────────────────────────────────────────────────────────────┘
```

### L2.2: Service Layer

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                              Service Layer                                     │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         DMXService                                       │  │
│  │                                                                          │  │
│  │  State:                                                                  │  │
│  │  • universes: map[int][]uint8     (4 universes × 512 channels)          │  │
│  │  • overrides: map[string]uint8    (channel overrides)                   │  │
│  │  • activeSceneId: *string         (currently active scene)              │  │
│  │  • isDirty: bool                  (change tracking)                     │  │
│  │  • dirtyUniverses: set[int]       (changed universes)                   │  │
│  │                                                                          │  │
│  │  Timing:                                                                 │  │
│  │  • refreshRate: 44 Hz (active)    • idleRate: 1 Hz (idle)              │  │
│  │  • highRateDuration: 2000ms       • currentRate: dynamic                │  │
│  │                                                                          │  │
│  │  Methods:                                                                │  │
│  │  • Initialize() error                                                   │  │
│  │  • SetChannelValue(universe, channel, value)                            │  │
│  │  • SetChannelOverride(universe, channel, value)                         │  │
│  │  • ClearChannelOverride(universe, channel)                              │  │
│  │  • GetUniverseOutput(universe) []uint8                                  │  │
│  │  • GetAllUniverseOutputs() []UniverseOutput                             │  │
│  │  • TriggerChangeDetection()                                             │  │
│  │  • Stop()                                                               │  │
│  │                                                                          │  │
│  │  Goroutines:                                                             │  │
│  │  • transmissionLoop()   → Sends Art-Net packets at dynamic rate         │  │
│  │  • rateController()     → Switches between high/idle rates              │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         FadeEngine                                       │  │
│  │                                                                          │  │
│  │  State:                                                                  │  │
│  │  • activeFades: map[string]*Fade    (concurrent fade tracking)          │  │
│  │  • interpolatedValues: map[key]float64 (smooth interpolation)           │  │
│  │                                                                          │  │
│  │  Timing:                                                                 │  │
│  │  • tickRate: 40 Hz (25ms intervals)                                     │  │
│  │                                                                          │  │
│  │  Easing Functions:                                                       │  │
│  │  • LINEAR              → No easing                                      │  │
│  │  • EASE_IN_OUT_CUBIC   → Cubic polynomial                               │  │
│  │  • EASE_IN_OUT_SINE    → Sinusoidal                                     │  │
│  │  • EASE_OUT_EXPONENTIAL→ Exponential decay                              │  │
│  │  • BEZIER              → Cubic Bezier curve                             │  │
│  │  • S_CURVE             → Sigmoid function                               │  │
│  │                                                                          │  │
│  │  Methods:                                                                │  │
│  │  • FadeChannels(channels, duration, onComplete, easing) string          │  │
│  │  • FadeToScene(sceneChannels, fadeInTime) string                        │  │
│  │  • FadeToBlack(fadeOutTime) string                                      │  │
│  │  • CancelFade(fadeId)                                                   │  │
│  │  • CancelAllFades()                                                     │  │
│  │                                                                          │  │
│  │  Goroutines:                                                             │  │
│  │  • fadeLoop()           → 40Hz interpolation calculation                │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                      PlaybackService                                     │  │
│  │                                                                          │  │
│  │  State:                                                                  │  │
│  │  • playbackStates: map[string]*PlaybackState                            │  │
│  │  • cueListCache: cache with 5-minute TTL                                │  │
│  │                                                                          │  │
│  │  Methods:                                                                │  │
│  │  • GetPlaybackStatus(cueListId) *CueListPlaybackStatus                  │  │
│  │  • StartPlayback(cueListId) error                                       │  │
│  │  • StopPlayback(cueListId) error                                        │  │
│  │  • NextCue(cueListId, fadeOverride) error                               │  │
│  │  • PreviousCue(cueListId, fadeOverride) error                           │  │
│  │  • JumpToCue(cueListId, cueIndex, fadeOverride) error                   │  │
│  │                                                                          │  │
│  │  Events (via PubSub):                                                    │  │
│  │  • PublishPlaybackStatus(cueListId, status)                             │  │
│  │  • Throttled to 100ms minimum between updates                           │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                       Other Services                                     │  │
│  │                                                                          │  │
│  │  PreviewService:                                                         │  │
│  │  • Isolated DMX state per preview session                               │  │
│  │  • Start/Commit/Cancel lifecycle                                        │  │
│  │  • Channel manipulation without affecting live output                   │  │
│  │                                                                          │  │
│  │  WiFiService: (Raspberry Pi)                                            │  │
│  │  • nmcli integration for network management                             │  │
│  │  • List/Connect/Disconnect networks                                     │  │
│  │  • Signal strength, security detection                                  │  │
│  │                                                                          │  │
│  │  ExportService:                                                          │  │
│  │  • JSON export with all project data                                    │  │
│  │  • Selective export (fixtures, scenes, cues)                            │  │
│  │                                                                          │  │
│  │  ImportService:                                                          │  │
│  │  • Create new or merge into existing project                            │  │
│  │  • Conflict resolution strategies                                       │  │
│  │                                                                          │  │
│  │  QLCService:                                                             │  │
│  │  • QLC+ workspace import (XML parsing)                                  │  │
│  │  • QLC+ export with fixture mappings                                    │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
└───────────────────────────────────────────────────────────────────────────────┘
```

### L2.3: Data Layer

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                              Data Layer (GORM)                                 │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         Database Models                                  │  │
│  │                                                                          │  │
│  │  Core Models:                                                            │  │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐            │  │
│  │  │     User       │  │    Project     │  │  ProjectUser   │            │  │
│  │  │ • id           │  │ • id           │  │ • id           │            │  │
│  │  │ • email        │  │ • name         │  │ • userId       │            │  │
│  │  │ • name         │  │ • description  │  │ • projectId    │            │  │
│  │  │ • role         │  │ • createdAt    │  │ • role         │            │  │
│  │  │ • createdAt    │  │ • updatedAt    │  │ • joinedAt     │            │  │
│  │  └────────────────┘  └────────────────┘  └────────────────┘            │  │
│  │                                                                          │  │
│  │  Fixture Models:                                                         │  │
│  │  ┌────────────────────┐  ┌────────────────────┐                        │  │
│  │  │ FixtureDefinition  │  │  FixtureInstance   │                        │  │
│  │  │ • id               │  │ • id               │                        │  │
│  │  │ • manufacturer     │  │ • name             │                        │  │
│  │  │ • model            │  │ • definitionId     │                        │  │
│  │  │ • type             │  │ • projectId        │                        │  │
│  │  │ • isBuiltIn        │  │ • universe         │                        │  │
│  │  │ • channels[]       │  │ • startChannel     │                        │  │
│  │  │ • modes[]          │  │ • tags (JSON)      │                        │  │
│  │  └────────────────────┘  │ • layoutX/Y/Rot    │                        │  │
│  │                          │ • channels[]       │                        │  │
│  │  ┌────────────────────┐  └────────────────────┘                        │  │
│  │  │ ChannelDefinition  │  ┌────────────────────┐                        │  │
│  │  │ • id               │  │  InstanceChannel   │                        │  │
│  │  │ • name             │  │ • id               │                        │  │
│  │  │ • type             │  │ • fixtureId        │                        │  │
│  │  │ • offset           │  │ • offset           │                        │  │
│  │  │ • minValue         │  │ • name             │                        │  │
│  │  │ • maxValue         │  │ • type             │                        │  │
│  │  │ • defaultValue     │  │ • min/max/default  │                        │  │
│  │  └────────────────────┘  └────────────────────┘                        │  │
│  │                                                                          │  │
│  │  ┌────────────────────┐  ┌────────────────────┐                        │  │
│  │  │    FixtureMode     │  │   ModeChannel      │                        │  │
│  │  │ • id               │  │ • id               │                        │  │
│  │  │ • name             │  │ • modeId           │                        │  │
│  │  │ • shortName        │  │ • channelId        │                        │  │
│  │  │ • channelCount     │  │ • offset           │                        │  │
│  │  │ • definitionId     │  │                    │                        │  │
│  │  └────────────────────┘  └────────────────────┘                        │  │
│  │                                                                          │  │
│  │  Scene Models:                                                           │  │
│  │  ┌────────────────────┐  ┌────────────────────┐                        │  │
│  │  │      Scene         │  │   FixtureValue     │                        │  │
│  │  │ • id               │  │ • id               │                        │  │
│  │  │ • name             │  │ • sceneId          │                        │  │
│  │  │ • description      │  │ • fixtureId        │                        │  │
│  │  │ • projectId        │  │ • channelValues    │                        │  │
│  │  │ • createdAt        │  │   (JSON array)     │                        │  │
│  │  │ • updatedAt        │  │ • sceneOrder       │                        │  │
│  │  └────────────────────┘  └────────────────────┘                        │  │
│  │                                                                          │  │
│  │  Cue Models:                                                             │  │
│  │  ┌────────────────────┐  ┌────────────────────┐                        │  │
│  │  │     CueList        │  │       Cue          │                        │  │
│  │  │ • id               │  │ • id               │                        │  │
│  │  │ • name             │  │ • name             │                        │  │
│  │  │ • description      │  │ • cueNumber        │                        │  │
│  │  │ • loop             │  │ • cueListId        │                        │  │
│  │  │ • projectId        │  │ • sceneId          │                        │  │
│  │  │ • createdAt        │  │ • fadeInTime       │                        │  │
│  │  │ • updatedAt        │  │ • fadeOutTime      │                        │  │
│  │  └────────────────────┘  │ • followTime       │                        │  │
│  │                          │ • easingType       │                        │  │
│  │                          │ • notes            │                        │  │
│  │                          └────────────────────┘                        │  │
│  │                                                                          │  │
│  │  SceneBoard Models:                                                      │  │
│  │  ┌────────────────────┐  ┌────────────────────┐                        │  │
│  │  │    SceneBoard      │  │ SceneBoardButton   │                        │  │
│  │  │ • id               │  │ • id               │                        │  │
│  │  │ • name             │  │ • sceneBoardId     │                        │  │
│  │  │ • description      │  │ • sceneId          │                        │  │
│  │  │ • projectId        │  │ • layoutX/Y        │                        │  │
│  │  │ • defaultFadeTime  │  │ • width/height     │                        │  │
│  │  │ • gridSize         │  │ • color/label      │                        │  │
│  │  │ • canvasW/H        │  │                    │                        │  │
│  │  └────────────────────┘  └────────────────────┘                        │  │
│  │                                                                          │  │
│  │  Other Models:                                                           │  │
│  │  ┌────────────────────┐  ┌────────────────────┐                        │  │
│  │  │  PreviewSession    │  │     Setting        │                        │  │
│  │  │ • id               │  │ • id               │                        │  │
│  │  │ • projectId        │  │ • key              │                        │  │
│  │  │ • userId           │  │ • value            │                        │  │
│  │  │ • isActive         │  │ • createdAt        │                        │  │
│  │  │ • createdAt        │  │ • updatedAt        │                        │  │
│  │  └────────────────────┘  └────────────────────┘                        │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                         Repository Pattern                               │  │
│  │                                                                          │  │
│  │  Interfaces:                                                             │  │
│  │  • ProjectRepository      • FixtureRepository                           │  │
│  │  • SceneRepository        • CueRepository                               │  │
│  │  • UserRepository         • SettingRepository                           │  │
│  │  • SceneBoardRepository   • PreviewRepository                           │  │
│  │                                                                          │  │
│  │  Benefits:                                                               │  │
│  │  • Testable (mock repositories for unit tests)                          │  │
│  │  • Database-agnostic (could switch to PostgreSQL)                       │  │
│  │  • Clean separation of concerns                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
└───────────────────────────────────────────────────────────────────────────────┘
```

### L2.4: Art-Net DMX Output

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                          Art-Net DMX Output System                             │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                      Art-Net Packet Structure                            │  │
│  │                                                                          │  │
│  │  Total Size: 530 bytes                                                   │  │
│  │                                                                          │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐    │  │
│  │  │ Bytes 0-7:  "Art-Net\0" (ID string, 8 bytes)                    │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Bytes 8-9:  0x5000 (OpCode for DMX, little-endian)              │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Bytes 10-11: 0x000E (Protocol version 14, big-endian)           │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Byte 12:    Sequence number (0 = disabled)                      │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Byte 13:    Physical port (0)                                   │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Bytes 14-15: Universe (0-based, little-endian)                  │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Bytes 16-17: Data length (512, big-endian)                      │    │  │
│  │  ├─────────────────────────────────────────────────────────────────┤    │  │
│  │  │ Bytes 18-529: DMX channel data (512 bytes, values 0-255)        │    │  │
│  │  └─────────────────────────────────────────────────────────────────┘    │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                              │                                                 │
│                              ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                      Transmission Flow                                   │  │
│  │                                                                          │  │
│  │                    ┌─────────────────────┐                              │  │
│  │                    │   transmitLoop()    │                              │  │
│  │                    │   (goroutine)       │                              │  │
│  │                    └──────────┬──────────┘                              │  │
│  │                               │                                          │  │
│  │                    ┌──────────▼──────────┐                              │  │
│  │                    │  Check dirty flag   │                              │  │
│  │                    └──────────┬──────────┘                              │  │
│  │                               │                                          │  │
│  │           ┌───────────────────┼───────────────────┐                     │  │
│  │           │                   │                   │                     │  │
│  │           ▼                   ▼                   ▼                     │  │
│  │    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐              │  │
│  │    │ High-Rate    │   │ Idle-Rate    │   │ No changes   │              │  │
│  │    │ (44Hz)       │   │ (1Hz)        │   │ Skip frame   │              │  │
│  │    │              │   │              │   │              │              │  │
│  │    │ Send only    │   │ Send all     │   │ Wait for     │              │  │
│  │    │ dirty        │   │ universes    │   │ next tick    │              │  │
│  │    │ universes    │   │ (keep-alive) │   │              │              │  │
│  │    └──────┬───────┘   └──────┬───────┘   └──────────────┘              │  │
│  │           │                   │                                          │  │
│  │           └─────────┬─────────┘                                          │  │
│  │                     ▼                                                    │  │
│  │           ┌─────────────────────┐                                       │  │
│  │           │ Build Art-Net packet│                                       │  │
│  │           │ for each universe   │                                       │  │
│  │           └──────────┬──────────┘                                       │  │
│  │                      │                                                   │  │
│  │                      ▼                                                   │  │
│  │           ┌─────────────────────┐                                       │  │
│  │           │ UDP Broadcast       │                                       │  │
│  │           │ to port 6454        │                                       │  │
│  │           └─────────────────────┘                                       │  │
│  │                                                                          │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                      Rate Adaptation Logic                               │  │
│  │                                                                          │  │
│  │  ┌─────────────┐     change detected     ┌─────────────┐                │  │
│  │  │             │ ──────────────────────► │             │                │  │
│  │  │  Idle Mode  │                         │ High-Rate   │                │  │
│  │  │   (1 Hz)    │ ◄────────────────────── │   Mode      │                │  │
│  │  │             │   2000ms no changes     │  (44 Hz)    │                │  │
│  │  └─────────────┘                         └─────────────┘                │  │
│  │                                                                          │  │
│  │  Benefits:                                                               │  │
│  │  • Reduces network traffic during idle periods                          │  │
│  │  • Maintains real-time responsiveness during fades                      │  │
│  │  • Keep-alive packets prevent fixture timeout                           │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

### Core Technologies

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Language | Go | 1.22+ | Main implementation language |
| GraphQL | gqlgen | 0.17.x | Schema-first GraphQL server |
| Database ORM | GORM | 2.x | SQLite database access |
| HTTP Router | chi | 5.x | REST endpoints, middleware |
| WebSocket | gorilla/websocket | 1.5.x | GraphQL subscriptions |
| PubSub | Custom | - | Subscription event distribution |
| UUID | google/uuid | 1.x | CUID-compatible ID generation |
| Testing | testify | 1.9.x | Test assertions and mocking |

### Development Tools

| Tool | Purpose |
|------|---------|
| golangci-lint | Linting and static analysis |
| go test | Unit and integration testing |
| go generate | gqlgen schema regeneration |
| Air | Hot reload during development |

### Database

- **SQLite 3**: Same database file as lacylights-node
- **Path**: `file:./dev.db` (development) or `/var/lib/lacylights/db.sqlite` (production)
- **Compatibility**: Exact schema match with Prisma-generated tables

---

## Implementation Phases

### Phase Overview

| Phase | Duration | Risk | Dependencies | Deliverables |
|-------|----------|------|--------------|--------------|
| Phase 1 | 1-2 days | Low | None | Project structure, build system |
| Phase 2 | 2-3 days | Low | Phase 1 | Database models, GORM setup |
| Phase 3 | 3-4 days | Medium | Phase 2 | GraphQL schema, basic resolvers |
| Phase 4 | 2-3 days | Medium | Phase 3 | DMX service, Art-Net output |
| Phase 5 | 3-4 days | Medium | Phase 4 | FadeEngine, PlaybackService |
| Phase 6 | 2-3 days | Medium | Phase 5 | All remaining resolvers |
| Phase 7 | 1-2 days | Low | Phase 6 | Subscriptions |
| Phase 8 | 2-3 days | Medium | Phase 7 | Contract tests, compatibility |
| Phase 9 | 1-2 days | Low | Phase 8 | CI/CD, documentation |

**Total Estimated Time: 17-26 days**

---

### Phase 1: Project Setup & Build System

**Goal:** Create the Go project structure with build tooling

**Tasks:**
1. Create `lacylights-go` directory structure
2. Initialize Go module
3. Set up gqlgen configuration
4. Create Makefile with build targets
5. Set up development environment (Air hot reload)
6. Create .env configuration

**Directory Structure:**
```
lacylights-go/
├── cmd/
│   └── server/
│       └── main.go           # Entry point
├── internal/
│   ├── config/
│   │   └── config.go         # Configuration management
│   ├── database/
│   │   ├── models/           # GORM models
│   │   ├── repositories/     # Data access layer
│   │   └── db.go             # Database initialization
│   ├── graphql/
│   │   ├── generated/        # gqlgen output
│   │   ├── resolvers/        # Resolver implementations
│   │   ├── schema/           # .graphql files
│   │   └── dataloader/       # N+1 query optimization
│   ├── services/
│   │   ├── dmx/              # DMX service
│   │   ├── fade/             # Fade engine
│   │   ├── playback/         # Cue list playback
│   │   ├── preview/          # Preview sessions
│   │   ├── wifi/             # WiFi management
│   │   ├── export/           # Export functionality
│   │   └── import/           # Import functionality
│   └── pubsub/               # Subscription events
├── pkg/
│   └── artnet/               # Art-Net protocol
├── test/
│   ├── contracts/            # Contract tests
│   └── integration/          # Integration tests
├── schema.graphql            # Exported schema (for CI/CD)
├── gqlgen.yml                # gqlgen configuration
├── go.mod
├── go.sum
├── Makefile
├── .env.example
├── .air.toml                 # Hot reload config
├── CLAUDE.md                 # Development guidelines
└── README.md
```

**Verification:**
- [ ] `go build ./...` succeeds
- [ ] `go generate ./...` generates GraphQL code
- [ ] `make dev` starts server with hot reload
- [ ] Health check endpoint responds at `/health`

---

### Phase 2: Database Models & GORM Setup

**Goal:** Implement GORM models matching the Prisma schema exactly

**Tasks:**
1. Create GORM models for all 17 tables
2. Configure JSON serialization for array fields
3. Set up database migrations (or verify existing schema)
4. Implement repository interfaces
5. Write model unit tests

**Key Models to Implement:**

```go
// Example: FixtureInstance model
type FixtureInstance struct {
    ID           string  `gorm:"primaryKey;type:text"`
    Name         string  `gorm:"type:text;not null"`
    Description  *string `gorm:"type:text"`
    DefinitionID string  `gorm:"column:definition_id;type:text;not null"`
    Manufacturer *string `gorm:"type:text"`
    Model        *string `gorm:"type:text"`
    Type         *string `gorm:"type:text"`
    ModeName     *string `gorm:"column:mode_name;type:text"`
    ChannelCount *int    `gorm:"column:channel_count"`
    ProjectID    string  `gorm:"column:project_id;type:text;not null"`
    Universe     int     `gorm:"not null"`
    StartChannel int     `gorm:"column:start_channel;not null"`
    Tags         string  `gorm:"type:text;default:'[]'"` // JSON array
    ProjectOrder *int    `gorm:"column:project_order"`
    LayoutX      *float64 `gorm:"column:layout_x"`
    LayoutY      *float64 `gorm:"column:layout_y"`
    LayoutRotation *float64 `gorm:"column:layout_rotation"`
    CreatedAt    time.Time `gorm:"column:created_at;autoCreateTime"`
    UpdatedAt    time.Time `gorm:"column:updated_at;autoUpdateTime"`

    // Relations
    Definition    FixtureDefinition `gorm:"foreignKey:DefinitionID"`
    Project       Project           `gorm:"foreignKey:ProjectID"`
    Channels      []InstanceChannel `gorm:"foreignKey:FixtureID"`
    FixtureValues []FixtureValue    `gorm:"foreignKey:FixtureID"`
}

func (FixtureInstance) TableName() string {
    return "fixture_instances"
}
```

**JSON Array Handling:**
```go
// Custom type for JSON array fields
type StringArray []string

func (a *StringArray) Scan(value interface{}) error {
    if value == nil {
        *a = []string{}
        return nil
    }
    bytes, ok := value.([]byte)
    if !ok {
        return errors.New("failed to unmarshal StringArray")
    }
    return json.Unmarshal(bytes, a)
}

func (a StringArray) Value() (driver.Value, error) {
    return json.Marshal(a)
}
```

**Verification:**
- [ ] All 17 models compile without errors
- [ ] Database opens and reads existing lacylights-node data
- [ ] Foreign key relationships work correctly
- [ ] JSON array fields serialize/deserialize properly
- [ ] Repository methods have >80% test coverage

---

### Phase 3: GraphQL Schema & Basic Resolvers

**Goal:** Implement the GraphQL layer with gqlgen

**Tasks:**
1. Copy schema.graphql from lacylights-node
2. Configure gqlgen.yml for Go types
3. Generate resolver stubs
4. Implement Query resolvers (read operations)
5. Implement field resolvers for relationships

**gqlgen Configuration:**
```yaml
# gqlgen.yml
schema:
  - schema.graphql

exec:
  filename: internal/graphql/generated/generated.go
  package: generated

model:
  filename: internal/graphql/generated/models_gen.go
  package: generated

resolver:
  layout: follow-schema
  dir: internal/graphql/resolvers
  package: resolvers

autobind:
  - "lacylights-go/internal/database/models"

models:
  ID:
    model:
      - github.com/99designs/gqlgen/graphql.ID
  DateTime:
    model:
      - github.com/99designs/gqlgen/graphql.String
```

**Resolver Implementation Order:**
1. **Project resolvers** (foundation)
2. **Fixture resolvers** (most complex)
3. **Scene resolvers**
4. **Cue resolvers**
5. **DMX/System resolvers**
6. **Search resolvers**
7. **SceneBoard resolvers**
8. **WiFi/Settings resolvers**

**Verification:**
- [ ] GraphQL Playground loads at `/graphql`
- [ ] `projects` query returns data
- [ ] `project(id)` query with relations works
- [ ] Pagination works (fixtureInstances, scenes)
- [ ] Field resolvers load related data

---

### Phase 4: DMX Service & Art-Net Output

**Goal:** Implement real-time DMX output identical to lacylights-node

**Tasks:**
1. Implement Art-Net packet builder
2. Create DMXService with 4 universes
3. Implement adaptive transmission rates (44Hz/1Hz)
4. Add dirty flag optimization
5. Implement channel override system
6. Add broadcast address configuration

**Key Implementation:**

```go
// pkg/artnet/packet.go
type ArtNetDMXPacket struct {
    ID          [8]byte  // "Art-Net\0"
    OpCode      uint16   // 0x5000 for DMX
    ProtVersion uint16   // 14
    Sequence    uint8
    Physical    uint8
    Universe    uint16
    Length      uint16   // 512
    Data        [512]byte
}

func BuildDMXPacket(universe int, channels []uint8) []byte {
    packet := make([]byte, 530)
    copy(packet[0:8], []byte("Art-Net\x00"))
    binary.LittleEndian.PutUint16(packet[8:10], 0x5000)
    binary.BigEndian.PutUint16(packet[10:12], 14)
    packet[12] = 0 // Sequence
    packet[13] = 0 // Physical
    binary.LittleEndian.PutUint16(packet[14:16], uint16(universe-1))
    binary.BigEndian.PutUint16(packet[16:18], 512)
    copy(packet[18:530], channels)
    return packet
}
```

```go
// internal/services/dmx/service.go
type DMXService struct {
    universes      map[int][]uint8
    overrides      map[string]uint8
    activeSceneID  *string

    refreshRate    int           // 44 Hz
    idleRate       int           // 1 Hz
    currentRate    int
    highRateDur    time.Duration // 2 seconds

    isDirty        bool
    dirtyUniverses map[int]bool
    lastChangeTime time.Time

    conn           *net.UDPConn
    broadcastAddr  *net.UDPAddr
    enabled        bool

    mu             sync.RWMutex
    stopChan       chan struct{}
}

func (s *DMXService) transmitLoop() {
    ticker := time.NewTicker(time.Second / time.Duration(s.currentRate))
    defer ticker.Stop()

    for {
        select {
        case <-s.stopChan:
            return
        case <-ticker.C:
            s.processTransmission()
            // Adjust ticker rate if needed
            if s.shouldSwitchRate() {
                ticker.Reset(time.Second / time.Duration(s.currentRate))
            }
        }
    }
}
```

**Verification:**
- [ ] Art-Net packets appear in Wireshark
- [ ] Packet structure matches lacylights-node exactly
- [ ] 44Hz rate during active changes
- [ ] 1Hz rate during idle periods
- [ ] Channel overrides work correctly
- [ ] `setChannelValue` mutation updates DMX output

---

### Phase 5: FadeEngine & PlaybackService

**Goal:** Implement smooth lighting transitions and cue list playback

**Tasks:**
1. Implement FadeEngine with 40Hz loop
2. Implement all easing functions
3. Create PlaybackService for cue lists
4. Add cue list state management
5. Implement follow cue timing

**FadeEngine Implementation:**

```go
// internal/services/fade/engine.go
type Fade struct {
    ID            string
    Channels      []FadeChannel
    StartTime     time.Time
    Duration      time.Duration
    EasingType    EasingType
    OnComplete    func()
    Progress      float64
}

type FadeChannel struct {
    Universe    int
    Channel     int
    StartValue  uint8
    TargetValue uint8
}

type FadeEngine struct {
    dmx         *dmx.DMXService
    activeFades map[string]*Fade
    interpVals  map[string]float64  // "universe:channel" -> interpolated value
    mu          sync.Mutex
    stopChan    chan struct{}
}

func (e *FadeEngine) fadeLoop() {
    ticker := time.NewTicker(25 * time.Millisecond) // 40Hz
    defer ticker.Stop()

    for {
        select {
        case <-e.stopChan:
            return
        case <-ticker.C:
            e.processFades()
        }
    }
}

func (e *FadeEngine) applyEasing(t float64, easingType EasingType) float64 {
    switch easingType {
    case EasingLinear:
        return t
    case EasingEaseInOutCubic:
        if t < 0.5 {
            return 4 * t * t * t
        }
        return 1 - math.Pow(-2*t+2, 3)/2
    case EasingEaseInOutSine:
        return -(math.Cos(math.Pi*t) - 1) / 2
    case EasingEaseOutExponential:
        if t == 1 {
            return 1
        }
        return 1 - math.Pow(2, -10*t)
    // ... other easing types
    }
    return t
}
```

**PlaybackService Implementation:**

```go
// internal/services/playback/service.go
type PlaybackState struct {
    CueListID       string
    IsPlaying       bool
    CurrentCueIndex int
    FadeProgress    float64
    LastUpdated     time.Time
    followTimer     *time.Timer
}

type PlaybackService struct {
    states      map[string]*PlaybackState
    cueListCache *cache.Cache[string, *models.CueList]
    fadeEngine  *fade.FadeEngine
    pubsub      *pubsub.PubSub
    db          *gorm.DB
    mu          sync.RWMutex
}

func (s *PlaybackService) NextCue(cueListID string, fadeOverride *float64) error {
    s.mu.Lock()
    defer s.mu.Unlock()

    state := s.states[cueListID]
    if state == nil || !state.IsPlaying {
        return errors.New("cue list not playing")
    }

    cueList, err := s.getCueList(cueListID)
    if err != nil {
        return err
    }

    nextIndex := state.CurrentCueIndex + 1
    if nextIndex >= len(cueList.Cues) {
        if cueList.Loop {
            nextIndex = 0
        } else {
            return s.stopPlayback(cueListID)
        }
    }

    return s.executeCue(cueList, nextIndex, fadeOverride)
}
```

**Verification:**
- [ ] Fades interpolate smoothly (visual check)
- [ ] All 6 easing types work correctly
- [ ] `startCueList` mutation starts playback
- [ ] `nextCue`/`previousCue` navigate correctly
- [ ] Follow cues auto-advance with correct timing
- [ ] Loop functionality works

---

### Phase 6: Remaining Resolvers

**Goal:** Implement all mutation resolvers and remaining queries

**Tasks:**
1. Implement all Create mutations
2. Implement all Update mutations
3. Implement all Delete mutations
4. Implement bulk operations
5. Implement search resolvers
6. Implement QLC+ import/export
7. Implement native import/export

**Resolver Categories:**

| Category | Queries | Mutations |
|----------|---------|-----------|
| Project | 2 | 3 |
| Fixture | 6 | 10 |
| Scene | 7 | 10 |
| Cue | 4 | 8 |
| SceneBoard | 3 | 7 |
| DMX | 3 | 5 |
| Preview | 1 | 5 |
| Settings | 2 | 1 |
| WiFi | 3 | 4 |
| Export | 0 | 2 |
| QLC | 1 | 2 |
| Search | 3 | 0 |
| Version | 2 | 2 |

**Verification:**
- [ ] All 42+ queries work
- [ ] All 60+ mutations work
- [ ] Bulk operations handle partial failures correctly
- [ ] Search returns paginated results
- [ ] QLC+ import creates valid project
- [ ] Native export/import round-trips correctly

---

### Phase 7: Subscriptions

**Goal:** Implement real-time GraphQL subscriptions

**Tasks:**
1. Set up WebSocket handling
2. Implement PubSub system
3. Implement all 6 subscription resolvers
4. Add subscription filtering
5. Implement throttling for high-frequency events

**Subscriptions to Implement:**

```go
type Subscription struct{}

func (r *subscriptionResolver) DmxOutputChanged(ctx context.Context, universe *int) (<-chan *model.UniverseOutput, error) {
    ch := make(chan *model.UniverseOutput, 10)

    subID := r.pubsub.Subscribe("dmx:output", func(data interface{}) {
        output := data.(*model.UniverseOutput)
        if universe == nil || output.Universe == *universe {
            select {
            case ch <- output:
            default:
                // Skip if channel is full
            }
        }
    })

    go func() {
        <-ctx.Done()
        r.pubsub.Unsubscribe(subID)
        close(ch)
    }()

    return ch, nil
}

func (r *subscriptionResolver) CueListPlaybackUpdated(ctx context.Context, cueListID string) (<-chan *model.CueListPlaybackStatus, error) {
    // Throttled to 100ms minimum between updates
    ch := make(chan *model.CueListPlaybackStatus, 1)
    var lastSent time.Time

    subID := r.pubsub.Subscribe(fmt.Sprintf("playback:%s", cueListID), func(data interface{}) {
        if time.Since(lastSent) < 100*time.Millisecond {
            return
        }
        status := data.(*model.CueListPlaybackStatus)
        select {
        case ch <- status:
            lastSent = time.Now()
        default:
        }
    })

    // ... cleanup
}
```

**Verification:**
- [ ] WebSocket connection establishes
- [ ] `dmxOutputChanged` receives updates during fades
- [ ] `cueListPlaybackUpdated` updates during playback
- [ ] `projectUpdated` fires on project changes
- [ ] `previewSessionUpdated` works
- [ ] Filtering works (e.g., specific universe)

---

### Phase 8: Contract Testing & Compatibility

**Goal:** Verify 100% compatibility with lacylights-node

**Tasks:**
1. Port contract tests from lacylights-node
2. Run schema compatibility tests
3. Verify frontend queries work
4. Verify MCP queries work
5. Test database interoperability
6. Performance benchmarking

**Contract Test Suite:**

```go
// test/contracts/schema_compatibility_test.go
func TestFrontendQueries(t *testing.T) {
    // Extract and validate all queries from lacylights-fe/src/graphql/
    frontendDir := "../lacylights-fe/src/graphql"
    files, _ := filepath.Glob(filepath.Join(frontendDir, "*.ts"))

    for _, file := range files {
        t.Run(filepath.Base(file), func(t *testing.T) {
            content, _ := os.ReadFile(file)
            queries := extractGraphQLQueries(string(content))

            for i, query := range queries {
                t.Run(fmt.Sprintf("query_%d", i), func(t *testing.T) {
                    _, err := gqlparser.LoadQuery(schema, query)
                    assert.NoError(t, err)
                })
            }
        })
    }
}

func TestMCPQueries(t *testing.T) {
    // Validate MCP client queries
    mcpClient := "../lacylights-mcp/src/services/graphql-client-simple.ts"
    content, _ := os.ReadFile(mcpClient)
    queries := extractGraphQLQueries(string(content))

    for i, query := range queries {
        t.Run(fmt.Sprintf("mcp_query_%d", i), func(t *testing.T) {
            _, err := gqlparser.LoadQuery(schema, query)
            assert.NoError(t, err)
        })
    }
}
```

**Database Interoperability Test:**

```go
func TestDatabaseInteroperability(t *testing.T) {
    // Create project with lacylights-node
    nodeDB := openDatabase("../lacylights-node/dev.db")

    // Read with lacylights-go
    goClient := createGoGraphQLClient()

    // Verify data matches
    projects, _ := goClient.Query("{ projects { id name } }")

    var nodeProjects []Project
    nodeDB.Find(&nodeProjects)

    assert.Equal(t, len(nodeProjects), len(projects))
}
```

**Verification:**
- [ ] All 27 contract tests pass
- [ ] Schema hash matches lacylights-node
- [ ] Frontend works with Go backend
- [ ] MCP works with Go backend
- [ ] Database written by Go readable by Node (and vice versa)

---

### Phase 9: CI/CD & Documentation

**Goal:** Production-ready deployment

**Tasks:**
1. Create GitHub Actions workflow
2. Add contract test CI step
3. Create Dockerfile
4. Update repository documentation
5. Create migration guide

**GitHub Actions:**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Install dependencies
        run: go mod download

      - name: Generate GraphQL
        run: go generate ./...

      - name: Run tests
        run: go test -v -race -coverprofile=coverage.out ./...

      - name: Run contract tests
        run: go test -v ./test/contracts/...

      - name: Upload coverage
        uses: codecov/codecov-action@v4

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: golangci/golangci-lint-action@v4

  schema-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Check schema compatibility
        run: |
          diff schema.graphql ../lacylights-node/schema.graphql
```

**Verification:**
- [ ] CI passes on all PRs
- [ ] Contract tests run in CI
- [ ] Docker image builds successfully
- [ ] Documentation is complete
- [ ] Migration guide helps users switch backends

---

## Contract Testing Strategy

### Three-Layer Verification

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Contract Testing Pyramid                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                           ┌──────────────────┐                              │
│                           │   Integration    │                              │
│                           │     Tests        │                              │
│                           │  (End-to-End)    │                              │
│                           └────────┬─────────┘                              │
│                                    │                                         │
│                    ┌───────────────┴───────────────┐                        │
│                    │      Contract Tests           │                        │
│                    │  (Schema Validation)          │                        │
│                    │  (Query Validation)           │                        │
│                    └───────────────┬───────────────┘                        │
│                                    │                                         │
│         ┌──────────────────────────┴──────────────────────────┐             │
│         │                   Unit Tests                         │             │
│         │  (Resolvers, Services, Models)                       │             │
│         └──────────────────────────────────────────────────────┘             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Test Categories

1. **Schema Compatibility Tests**
   - Schema hash comparison
   - Type definition validation
   - Field type matching
   - Enum value matching

2. **Query Validation Tests**
   - Frontend query validation
   - MCP query validation
   - Input type validation

3. **Integration Tests**
   - End-to-end GraphQL queries
   - Database read/write compatibility
   - Subscription functionality

### Test Commands

```bash
# Run all tests
make test

# Run contract tests only
make test-contracts

# Run with coverage
make test-coverage

# Run specific test
go test -v ./test/contracts/schema_test.go
```

---

## Database Compatibility

### Table Mapping

| Prisma Table | GORM Model | Notes |
|--------------|------------|-------|
| users | User | role as string |
| projects | Project | |
| project_users | ProjectUser | |
| fixture_definitions | FixtureDefinition | |
| channel_definitions | ChannelDefinition | |
| fixture_modes | FixtureMode | |
| mode_channels | ModeChannel | |
| fixture_instances | FixtureInstance | tags as JSON |
| instance_channels | InstanceChannel | |
| scenes | Scene | |
| fixture_values | FixtureValue | channelValues as JSON |
| cue_lists | CueList | |
| cues | Cue | |
| preview_sessions | PreviewSession | |
| settings | Setting | |
| scene_boards | SceneBoard | |
| scene_board_buttons | SceneBoardButton | |

### JSON Field Handling

Both lacylights-node and lacylights-go store JSON arrays as strings in SQLite:

```go
// channelValues: "[0, 255, 128, 64]"
// tags: "[\"front\", \"blue\"]"
```

The Go implementation must:
1. Deserialize JSON on read
2. Serialize JSON on write
3. Handle empty arrays (`[]`) correctly
4. Handle null/nil values correctly

### CUID Compatibility

Prisma generates CUID identifiers. Go should generate compatible IDs:

```go
import "github.com/lucsky/cuid"

func generateID() string {
    return cuid.New()
}
```

---

## Project Structure

```
lacylights-go/
├── cmd/
│   └── server/
│       └── main.go                 # Application entry point
├── internal/
│   ├── config/
│   │   └── config.go               # Environment configuration
│   ├── database/
│   │   ├── db.go                   # Database initialization
│   │   ├── models/
│   │   │   ├── project.go
│   │   │   ├── fixture.go
│   │   │   ├── scene.go
│   │   │   ├── cue.go
│   │   │   ├── sceneboard.go
│   │   │   ├── preview.go
│   │   │   ├── user.go
│   │   │   └── setting.go
│   │   └── repositories/
│   │       ├── project_repo.go
│   │       ├── fixture_repo.go
│   │       ├── scene_repo.go
│   │       └── ...
│   ├── graphql/
│   │   ├── generated/              # gqlgen output (do not edit)
│   │   │   ├── generated.go
│   │   │   └── models_gen.go
│   │   ├── resolvers/
│   │   │   ├── resolver.go         # Dependency injection
│   │   │   ├── project.go
│   │   │   ├── fixture.go
│   │   │   ├── scene.go
│   │   │   ├── cue.go
│   │   │   ├── dmx.go
│   │   │   ├── playback.go
│   │   │   ├── sceneboard.go
│   │   │   ├── preview.go
│   │   │   ├── search.go
│   │   │   ├── settings.go
│   │   │   ├── wifi.go
│   │   │   ├── export.go
│   │   │   └── subscription.go
│   │   ├── dataloader/
│   │   │   └── loaders.go          # N+1 query optimization
│   │   └── schema/
│   │       └── schema.graphql      # GraphQL schema
│   ├── services/
│   │   ├── dmx/
│   │   │   ├── service.go
│   │   │   └── service_test.go
│   │   ├── fade/
│   │   │   ├── engine.go
│   │   │   ├── easing.go
│   │   │   └── engine_test.go
│   │   ├── playback/
│   │   │   ├── service.go
│   │   │   └── service_test.go
│   │   ├── preview/
│   │   │   └── service.go
│   │   ├── wifi/
│   │   │   └── service.go
│   │   ├── export/
│   │   │   ├── native.go
│   │   │   └── qlc.go
│   │   └── import/
│   │       ├── native.go
│   │       └── qlc.go
│   └── pubsub/
│       └── pubsub.go               # Subscription event distribution
├── pkg/
│   └── artnet/
│       ├── packet.go               # Art-Net packet building
│       └── packet_test.go
├── test/
│   ├── contracts/
│   │   ├── schema_test.go
│   │   └── query_test.go
│   └── integration/
│       └── graphql_test.go
├── schema.graphql                  # Exported for CI/CD validation
├── gqlgen.yml                      # gqlgen configuration
├── go.mod
├── go.sum
├── Makefile
├── Dockerfile
├── .env.example
├── .air.toml
├── .golangci.yml
├── CLAUDE.md
└── README.md
```

---

## Verification Strategy

### Per-Phase Verification

Each phase must pass these gates before proceeding:

| Phase | Gate | Criteria |
|-------|------|----------|
| 1 | Build | `go build ./...` succeeds |
| 2 | Models | All 17 models pass unit tests |
| 3 | GraphQL | Playground loads, basic queries work |
| 4 | DMX | Art-Net packets visible in Wireshark |
| 5 | Fades | Visual verification of smooth transitions |
| 6 | Resolvers | All mutations work via Playground |
| 7 | Subscriptions | WebSocket updates verified |
| 8 | Contracts | All 27 contract tests pass |
| 9 | CI | All CI checks pass |

### Cross-Backend Testing

```bash
# Start lacylights-node
cd lacylights-node && npm start &

# Run frontend against Node backend
cd lacylights-fe && npm test

# Stop Node, start Go backend
kill %1
cd lacylights-go && ./lacylights-go &

# Run same frontend tests against Go backend
cd lacylights-fe && npm test

# Compare results
```

### Performance Benchmarks

| Metric | Node Target | Go Target |
|--------|-------------|-----------|
| Query latency (p99) | <50ms | <25ms |
| DMX jitter | <5ms | <2ms |
| Memory usage | <100MB | <50MB |
| Cold start | <5s | <1s |

---

## Risk Mitigation

### High-Risk Areas

1. **JSON Array Serialization**
   - Risk: Incompatible JSON handling between Node and Go
   - Mitigation: Extensive unit tests for JSON fields
   - Fallback: Use identical JSON library (encoding/json)

2. **CUID Generation**
   - Risk: Generated IDs incompatible with existing data
   - Mitigation: Use proven Go CUID library
   - Fallback: Import existing IDs without regeneration

3. **Real-Time DMX Timing**
   - Risk: Go's GC pauses affect DMX timing
   - Mitigation: Use sync.Pool, minimize allocations
   - Fallback: GOMAXPROCS=1 with goroutine pinning

4. **GraphQL Subscription Performance**
   - Risk: High-frequency subscriptions overwhelm clients
   - Mitigation: Implement throttling (100ms minimum)
   - Fallback: Reduce subscription update rate

### Rollback Plan

If critical issues are discovered:
1. Stop Go server
2. Start Node server (database unchanged)
3. Frontend/MCP work without modification
4. Debug Go implementation
5. Re-deploy when fixed

---

## Success Criteria

### Functional Criteria

- [ ] 100% GraphQL schema compatibility
- [ ] All 42+ queries return identical results
- [ ] All 60+ mutations behave identically
- [ ] All 6 subscriptions work correctly
- [ ] Database read/write compatibility verified
- [ ] Frontend works without modification
- [ ] MCP works without modification

### Performance Criteria

- [ ] Query latency ≤ Node implementation
- [ ] DMX output timing identical (44Hz/1Hz)
- [ ] Memory usage < 50% of Node
- [ ] Binary size < 20MB

### Quality Criteria

- [ ] Test coverage > 80%
- [ ] All contract tests pass
- [ ] No golangci-lint errors
- [ ] Documentation complete

---

## Appendix A: GraphQL Operations Reference

### Queries (42+)

```graphql
# Projects
projects: [Project!]!
project(id: ID!): Project

# Fixtures
fixtureDefinitions(filter: FixtureDefinitionFilter): [FixtureDefinition!]!
fixtureDefinition(id: ID!): FixtureDefinition
fixtureInstances(projectId: ID!, page: Int, perPage: Int, filter: FixtureFilterInput): FixtureInstancePage!
fixtureInstance(id: ID!): FixtureInstance
searchFixtures(projectId: ID!, query: String!, ...): FixtureInstancePage!
channelMap(projectId: ID!, universe: Int): ChannelMapResult!
suggestChannelAssignment(input: ChannelAssignmentInput!): ChannelAssignmentSuggestion!

# Scenes
scenes(projectId: ID!, page: Int, perPage: Int, ...): ScenePage!
scene(id: ID!, includeFixtureValues: Boolean): Scene
sceneFixtures(sceneId: ID!): [SceneFixtureSummary!]!
searchScenes(projectId: ID!, query: String!, ...): ScenePage!
fixtureUsage(fixtureId: ID!): FixtureUsage!
sceneUsage(sceneId: ID!): SceneUsage!
compareScenes(sceneId1: ID!, sceneId2: ID!): SceneComparison!

# SceneBoards
sceneBoards(projectId: ID!): [SceneBoard!]!
sceneBoard(id: ID!): SceneBoard
sceneBoardButton(id: ID!): SceneBoardButton

# Cues
cueLists(projectId: ID!): [CueListSummary!]!
cueList(id: ID!, page: Int, perPage: Int, includeSceneDetails: Boolean): CueList
cue(id: ID!): Cue
cueListPlaybackStatus(cueListId: ID!): CueListPlaybackStatus
searchCues(cueListId: ID!, query: String!, ...): CuePage!

# DMX
dmxOutput(universe: Int!): [Int!]!
allDmxOutput: [UniverseOutput!]!
currentActiveScene: Scene

# Preview
previewSession(sessionId: ID!): PreviewSession

# Settings
settings: [Setting!]!
setting(key: String!): Setting
systemInfo: SystemInfo!
networkInterfaceOptions: [NetworkInterfaceOption!]!

# WiFi
wifiNetworks(rescan: Boolean, deduplicate: Boolean): [WiFiNetwork!]!
wifiStatus: WiFiStatus!
savedWifiNetworks: [WiFiNetwork!]!

# QLC+
getQLCFixtureMappingSuggestions(projectId: ID!): QLCFixtureMappingResult!

# Version
systemVersions: SystemVersionInfo!
availableVersions(repository: String!): [String!]!
```

### Mutations (60+)

```graphql
# Projects
createProject(input: CreateProjectInput!): Project!
updateProject(id: ID!, input: CreateProjectInput!): Project!
deleteProject(id: ID!): Boolean!

# Fixture Definitions
createFixtureDefinition(input: CreateFixtureDefinitionInput!): FixtureDefinition!
importOFLFixture(input: ImportOFLFixtureInput!): FixtureDefinition!
updateFixtureDefinition(id: ID!, input: CreateFixtureDefinitionInput!): FixtureDefinition!
deleteFixtureDefinition(id: ID!): Boolean!

# Fixture Instances
createFixtureInstance(input: CreateFixtureInstanceInput!): FixtureInstance!
updateFixtureInstance(id: ID!, input: UpdateFixtureInstanceInput!): FixtureInstance!
bulkUpdateFixtures(input: BulkFixtureUpdateInput!): [FixtureInstance!]!
bulkCreateFixtures(input: BulkFixtureCreateInput!): [FixtureInstance!]!
deleteFixtureInstance(id: ID!): Boolean!
reorderProjectFixtures(projectId: ID!, fixtureOrders: [FixtureOrderInput!]!): Boolean!
reorderSceneFixtures(sceneId: ID!, fixtureOrders: [FixtureOrderInput!]!): Boolean!
updateFixturePositions(positions: [FixturePositionInput!]!): Boolean!

# Scenes
createScene(input: CreateSceneInput!): Scene!
updateScene(id: ID!, input: UpdateSceneInput!): Scene!
duplicateScene(id: ID!): Scene!
cloneScene(sceneId: ID!, newName: String!): Scene!
deleteScene(id: ID!): Boolean!
addFixturesToScene(sceneId: ID!, fixtureValues: [FixtureValueInput!]!, overwriteExisting: Boolean): Scene!
removeFixturesFromScene(sceneId: ID!, fixtureIds: [ID!]!): Scene!
updateScenePartial(sceneId: ID!, name: String, description: String, fixtureValues: [FixtureValueInput!], mergeFixtures: Boolean): Scene!

# SceneBoards
createSceneBoard(input: CreateSceneBoardInput!): SceneBoard!
updateSceneBoard(id: ID!, input: UpdateSceneBoardInput!): SceneBoard!
deleteSceneBoard(id: ID!): Boolean!
addSceneToBoard(input: CreateSceneBoardButtonInput!): SceneBoardButton!
updateSceneBoardButton(id: ID!, input: UpdateSceneBoardButtonInput!): SceneBoardButton!
removeSceneFromBoard(buttonId: ID!): Boolean!
updateSceneBoardButtonPositions(positions: [SceneBoardButtonPositionInput!]!): Boolean!
activateSceneFromBoard(sceneBoardId: ID!, sceneId: ID!, fadeTimeOverride: Float): Boolean!

# Cue Lists
createCueList(input: CreateCueListInput!): CueList!
updateCueList(id: ID!, input: CreateCueListInput!): CueList!
deleteCueList(id: ID!): Boolean!

# Cues
createCue(input: CreateCueInput!): Cue!
updateCue(id: ID!, input: CreateCueInput!): Cue!
deleteCue(id: ID!): Boolean!
reorderCues(cueListId: ID!, cueOrders: [CueOrderInput!]!): Boolean!
bulkUpdateCues(input: BulkCueUpdateInput!): [Cue!]!

# Preview
startPreviewSession(projectId: ID!): PreviewSession!
commitPreviewSession(sessionId: ID!): Boolean!
cancelPreviewSession(sessionId: ID!): Boolean!
updatePreviewChannel(sessionId: ID!, fixtureId: ID!, channelIndex: Int!, value: Int!): Boolean!
initializePreviewWithScene(sessionId: ID!, sceneId: ID!): Boolean!

# DMX Control
setChannelValue(universe: Int!, channel: Int!, value: Int!): Boolean!
setSceneLive(sceneId: ID!): Boolean!
playCue(cueId: ID!, fadeInTime: Float): Boolean!
fadeToBlack(fadeOutTime: Float!): Boolean!
startCueList(cueListId: ID!, startFromCue: Int): Boolean!
nextCue(cueListId: ID!, fadeInTime: Float): Boolean!
previousCue(cueListId: ID!, fadeInTime: Float): Boolean!
goToCue(cueListId: ID!, cueIndex: Int!, fadeInTime: Float): Boolean!
stopCueList(cueListId: ID!): Boolean!

# Export/Import
exportProject(projectId: ID!, options: ExportOptionsInput): ExportResult!
importProject(jsonContent: String!, options: ImportOptionsInput!): ImportResult!
importProjectFromQLC(xmlContent: String!, originalFileName: String!): QLCImportResult!
exportProjectToQLC(projectId: ID!, fixtureMappings: [FixtureMappingInput!]): QLCExportResult!

# Settings
updateSetting(input: UpdateSettingInput!): Setting!

# WiFi
connectWiFi(ssid: String!, password: String): WiFiConnectionResult!
disconnectWiFi: WiFiConnectionResult!
setWiFiEnabled(enabled: Boolean!): WiFiStatus!
forgetWiFiNetwork(ssid: String!): Boolean!

# Version
updateRepository(repository: String!, version: String): UpdateResult!
updateAllRepositories: [UpdateResult!]!
```

### Subscriptions (6)

```graphql
dmxOutputChanged(universe: Int): UniverseOutput!
projectUpdated(projectId: ID!): Project!
previewSessionUpdated(projectId: ID!): PreviewSession!
cueListPlaybackUpdated(cueListId: ID!): CueListPlaybackStatus!
systemInfoUpdated: SystemInfo!
wifiStatusUpdated: WiFiStatus!
```

---

## Appendix B: Environment Variables

```bash
# Database
DATABASE_URL="file:./dev.db"

# Server
PORT=4000
GIN_MODE=release  # or debug

# DMX Output
DMX_UNIVERSE_COUNT=4
DMX_REFRESH_RATE=44
DMX_IDLE_RATE=1
DMX_HIGH_RATE_DURATION=2000

# Art-Net
ARTNET_ENABLED=true
ARTNET_PORT=6454
ARTNET_BROADCAST=  # Auto-detected if not set

# Timing Monitoring
DMX_DRIFT_THRESHOLD=50
DMX_DRIFT_THROTTLE=5000

# Non-Interactive Mode (for Docker/CI)
NON_INTERACTIVE=false
```

---

**Document Version:** 1.0
**Status:** Ready for Review
**Author:** Claude (AI Assistant)
**Reviewer:** <owner>
