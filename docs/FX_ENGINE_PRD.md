# FX Engine Backend PRD (Product Requirements Document)

## Document Version
- **Version**: 1.0
- **Date**: January 2026
- **Status**: Draft

---

## Executive Summary

The FX Engine introduces a **Unified Modulator Architecture** that replaces the existing fade engine with a single, priority-based modulation pipeline. This architecture treats **everything as an effect** - including crossfades, static looks, waveform effects, and system controls like blackout and grand master.

The key innovation is recognizing that a crossfade from Look A to Look B is simply an effect that:
- Targets specific channels
- Uses easing to interpolate from start to end values
- Has CUE priority (higher than user effects)
- Uses OVERRIDE composition mode

This unified approach eliminates special cases, race conditions, and coordination complexity between separate fade and effect systems.

---

## Problem Statement

### Current Architecture Limitations

1. **Separate Fade Engine**: The existing `fade.Engine` handles look transitions independently from any effect system
2. **No Effect Support**: No infrastructure for LFO-based effects (chases, pulses, color cycles)
3. **Coordination Complexity**: Adding effects would require complex coordination between fade engine and effect engine
4. **Race Conditions**: Multiple systems updating the same DMX channels creates timing issues
5. **State Opacity**: No unified view of what's controlling each channel

### Solution

Replace the fade engine with a **Unified Modulator** that:
- Processes all DMX modulation in a single 60Hz update loop
- Uses priority bands to resolve conflicts deterministically
- Supports multiple composition modes (override, additive, multiply)
- Provides full state visibility for debugging and UI feedback

---

## Architecture Overview

### Core Principle: Everything is an Effect

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        UNIFIED MODULATOR ENGINE                             │
│                                                                             │
│   60Hz Update Loop                                                          │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │                                                                       │ │
│   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                │ │
│   │  │ SYSTEM Band  │  │ CUE Band     │  │ USER Band    │                │ │
│   │  │ - Blackout   │  │ - Crossfade  │  │ - Chase      │                │ │
│   │  │ - GrandMaster│  │   Effects    │  │ - Pulse      │                │ │
│   │  │              │  │              │  │ - ColorCycle │                │ │
│   │  └──────────────┘  └──────────────┘  └──────────────┘                │ │
│   │         │                 │                 │                         │ │
│   │         ▼                 ▼                 ▼                         │ │
│   │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│   │  │              Priority-Ordered Effect Processing                  │ │ │
│   │  │              (Low to High, Composition Mode Applied)             │ │ │
│   │  └─────────────────────────────────────────────────────────────────┘ │ │
│   │                              │                                        │ │
│   │                              ▼                                        │ │
│   │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│   │  │              Final DMX Channel Values                            │ │ │
│   │  └─────────────────────────────────────────────────────────────────┘ │ │
│   │                              │                                        │ │
│   └──────────────────────────────┼────────────────────────────────────────┘ │
│                                  ▼                                          │
│                         DMX Service Output                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Priority Band System

Effects are organized into four priority bands, processed from lowest to highest:

| Band   | Value | Purpose                                    | Examples                           |
|--------|-------|--------------------------------------------|------------------------------------|
| BASE   | 0     | Static look values, default state          | Active look base values            |
| USER   | 1     | User-activated effects                     | Chase, pulse, color cycle effects  |
| CUE    | 2     | Cue transitions and crossfades             | Look-to-look crossfades            |
| SYSTEM | 3     | System-level overrides                     | Blackout, grand master, emergency  |

Within each band, effects have a **sub-priority** (0-100) for ordering.

### Composition Modes

Each effect declares how it combines with lower-priority effects:

| Mode     | Behavior                                          | Use Cases                        |
|----------|---------------------------------------------------|----------------------------------|
| OVERRIDE | Higher priority completely replaces lower value   | Crossfades, blackout, cue looks  |
| ADDITIVE | Effect adds its modulation to current value       | Chase pulses, flashes            |
| MULTIPLY | Effect scales current value (0.0-1.0 multiplier)  | Grand master, dimmer curves      |

**Default**: OVERRIDE - ensures crossfades hit exact target values.

### Transition Behaviors

When a cue change occurs, each active effect's behavior is configurable:

| Behavior          | Description                                    | Use Cases                         |
|-------------------|------------------------------------------------|-----------------------------------|
| FADE_OUT          | Effect fades to 0 over cue's fadeInTime        | Default for most effects          |
| PERSIST           | Effect continues unchanged                     | Ambient effects, blackout         |
| SNAP_OFF          | Effect stops immediately                       | Strobe effects, precise timing    |
| CROSSFADE_PARAMS  | Parameters smoothly transition to new values   | Same effect with different speed  |

**Default**: FADE_OUT - provides smooth visual transitions.

---

## Effect Types

### 1. CROSSFADE Effect

Replaces the existing fade engine's primary function.

**Characteristics**:
- Priority: CUE band
- Composition: OVERRIDE
- Lifetime: Duration-based (auto-removes when complete)

**Easing Types**:
- `LINEAR` - Constant rate
- `EASE_IN_OUT_SINE` - Smooth acceleration/deceleration (default)
- `EASE_IN_OUT_CUBIC` - More dramatic than sine
- `EASE_OUT_EXPONENTIAL` - Quick start, gradual finish
- `S_CURVE` - Extended ease-in and ease-out

**Processing**:
```
progress = elapsed / duration
easedProgress = applyEasing(progress, easingType)
channelValue = lerp(fromValue, toValue, easedProgress)
```

### 2. WAVEFORM Effect

LFO-based continuous modulation.

**Characteristics**:
- Priority: USER band (typically)
- Composition: ADDITIVE or OVERRIDE
- Lifetime: Until explicitly stopped or cue change

**Waveform Types**:
- `SINE` - Smooth oscillation (default)
- `COSINE` - Sine shifted 90 degrees
- `SQUARE` - On/off pulse
- `SAWTOOTH` - Ramp up, snap down
- `TRIANGLE` - Linear up and down
- `RANDOM` - Random values per cycle

**Parameters**:
- `frequency` - Oscillation rate in Hz
- `amplitude` - Modulation range (0-100%)
- `offset` - Baseline value (0-100%)
- `phaseOffset` - Initial phase (0-360 degrees)

**Per-Fixture Customization**:
- Phase offset per fixture (creates chase patterns)
- Amplitude scale per fixture
- Channel type targeting (intensity, color, etc.)

### 3. STATIC Effect

Fixed channel values without modulation.

**Characteristics**:
- Priority: Any band
- Composition: OVERRIDE
- Use case: Base look values, system blackout

### 4. MASTER Effect

Multiplier for intensity scaling.

**Characteristics**:
- Priority: SYSTEM band
- Composition: MULTIPLY
- Use case: Grand master fader

---

## Data Model

### New Database Tables

```sql
-- Effect definitions
CREATE TABLE effects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    project_id TEXT NOT NULL REFERENCES projects(id),

    -- Type and behavior
    effect_type TEXT NOT NULL DEFAULT 'WAVEFORM',  -- WAVEFORM, CROSSFADE, STATIC, MASTER
    priority_band TEXT NOT NULL DEFAULT 'USER',    -- BASE, USER, CUE, SYSTEM
    priority_sub INTEGER NOT NULL DEFAULT 50,      -- 0-100
    composition_mode TEXT NOT NULL DEFAULT 'OVERRIDE',
    on_cue_change TEXT NOT NULL DEFAULT 'FADE_OUT',
    fade_duration REAL,  -- Override cue fadeInTime

    -- Easing (for CROSSFADE type)
    easing_type TEXT DEFAULT 'EASE_IN_OUT_SINE',

    -- Waveform parameters (for WAVEFORM type)
    waveform TEXT DEFAULT 'SINE',
    frequency REAL DEFAULT 1.0,
    amplitude REAL DEFAULT 100.0,
    offset REAL DEFAULT 50.0,
    phase_offset REAL DEFAULT 0.0,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Fixtures targeted by an effect
CREATE TABLE effect_fixtures (
    id TEXT PRIMARY KEY,
    effect_id TEXT NOT NULL REFERENCES effects(id) ON DELETE CASCADE,
    fixture_id TEXT NOT NULL REFERENCES fixture_instances(id) ON DELETE CASCADE,

    -- Per-fixture overrides
    phase_offset REAL,        -- Override effect's phase_offset
    amplitude_scale REAL,     -- Scale effect's amplitude (0-200%)
    effect_order INTEGER,     -- For auto-phase distribution

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(effect_id, fixture_id)
);

-- Channel targeting within effect fixtures
CREATE TABLE effect_channels (
    id TEXT PRIMARY KEY,
    effect_fixture_id TEXT NOT NULL REFERENCES effect_fixtures(id) ON DELETE CASCADE,

    -- Target by offset OR type (not both)
    channel_offset INTEGER,   -- Specific DMX channel offset
    channel_type TEXT,        -- INTENSITY, RED, GREEN, BLUE, PAN, TILT, etc.

    -- Per-channel overrides
    amplitude_scale REAL,     -- Scale amplitude for this channel
    frequency_scale REAL,     -- Scale frequency for this channel

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Multiple looks per cue (new capability)
CREATE TABLE cue_looks (
    id TEXT PRIMARY KEY,
    cue_id TEXT NOT NULL REFERENCES cues(id) ON DELETE CASCADE,
    look_id TEXT NOT NULL REFERENCES looks(id) ON DELETE CASCADE,

    priority INTEGER NOT NULL DEFAULT 50,  -- 0-100, higher wins on overlap

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(cue_id, look_id)
);

-- Effects attached to cues
CREATE TABLE cue_effects (
    id TEXT PRIMARY KEY,
    cue_id TEXT NOT NULL REFERENCES cues(id) ON DELETE CASCADE,
    effect_id TEXT NOT NULL REFERENCES effects(id) ON DELETE CASCADE,

    -- Runtime parameter overrides
    intensity REAL DEFAULT 100.0,   -- 0-100%
    speed REAL DEFAULT 1.0,         -- Speed multiplier

    -- Override transition behavior for this cue
    on_cue_change TEXT,  -- NULL = use effect's default

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(cue_id, effect_id)
);

-- Indexes
CREATE INDEX idx_effects_project_id ON effects(project_id);
CREATE INDEX idx_effect_fixtures_effect_id ON effect_fixtures(effect_id);
CREATE INDEX idx_effect_channels_effect_fixture_id ON effect_channels(effect_fixture_id);
CREATE INDEX idx_cue_looks_cue_id ON cue_looks(cue_id);
CREATE INDEX idx_cue_effects_cue_id ON cue_effects(cue_id);
```

### Modified Cues Table

```sql
-- Add to existing cues table
ALTER TABLE cues ADD COLUMN look_id_deprecated TEXT;  -- Keep for migration, remove later
-- The look_id column is replaced by cue_looks relationship
```

---

## Go Service Architecture

### Package Structure

```
internal/services/modulator/
├── engine.go           # Core engine: 60Hz loop, effect management
├── types.go            # Core types: ChannelKey, ActiveEffect, ChannelState
├── priority.go         # PriorityBand, EffectPriority, sorting
├── composition.go      # CompositionMode resolution
├── transition.go       # TransitionBehavior handling
├── effects.go          # Effect struct, EffectType enum
├── waveforms.go        # Waveform generation functions
├── easing.go           # Easing functions (migrate from fade/)
├── crossfade.go        # CROSSFADE effect implementation
├── system_effects.go   # Blackout, GrandMaster built-in effects
├── fade_api.go         # Compatibility: FadeToLook, FadeToBlack
└── engine_test.go      # Unit tests
```

### Core Types

```go
// ChannelKey uniquely identifies a DMX channel
type ChannelKey struct {
    Universe int
    Channel  int
}

// ChannelState tracks current value and its source
type ChannelState struct {
    Value           int
    OwnerEffectID   string
    CompositionMode CompositionMode
}

// ActiveEffect is a running effect instance
type ActiveEffect struct {
    Effect    *Effect
    StartTime time.Time

    // Runtime state
    Intensity float64  // Current intensity (may be fading)
    Phase     float64  // Current phase for waveforms

    // For crossfades
    FromValues map[ChannelKey]int
    ToValues   map[ChannelKey]int
    Duration   time.Duration

    // Intensity fading
    IntensityFade *FadeTransition
}

// FadeTransition represents an ongoing intensity fade
type FadeTransition struct {
    StartValue  float64
    EndValue    float64
    Duration    time.Duration
    StartTime   time.Time
    EasingType  EasingType
}

// Engine is the unified modulator
type Engine struct {
    mu sync.RWMutex

    dmxService *dmx.Service

    // All active effects, sorted by priority
    activeEffects []*ActiveEffect

    // Control
    stopChan   chan struct{}
    doneChan   chan struct{}
    running    bool
    updateRate time.Duration  // Default: 16.67ms (60Hz)

    // Timing
    lastUpdate time.Time

    // Callbacks
    onEffectComplete func(effectID string)
    onStateChange    func()
}
```

### Engine Interface

```go
type ModulatorEngine interface {
    // Lifecycle
    Start() error
    Stop() error
    IsRunning() bool

    // Effect management
    AddEffect(effect *Effect, intensity float64, fadeInTime float64) string
    RemoveEffect(effectID string, fadeOutTime float64)
    UpdateEffectIntensity(effectID string, intensity float64, fadeTime float64)
    UpdateEffectParameters(effectID string, params EffectParams, fadeTime float64)

    // Cue transitions
    ExecuteCueTransition(ctx context.Context, fromCue, toCue *Cue, fadeTime float64, easing EasingType) error

    // System controls
    ActivateBlackout(fadeTime float64)
    ReleaseBlackout(fadeTime float64)
    SetGrandMaster(value float64)  // 0.0-1.0

    // State queries
    GetActiveEffects() []ActiveEffectInfo
    GetChannelState(universe, channel int) ChannelStateInfo
    GetModulationStatus() ModulationStatus

    // Compatibility (wraps crossfade effects)
    FadeToLook(channels []LookChannel, duration time.Duration, easing EasingType) string
    FadeToBlack(duration time.Duration) string
    CancelFade(fadeID string)

    // Configuration
    GetUpdateRateHz() int
    SetUpdateRate(rateHz int) error
}
```

---

## Processing Pipeline

### Update Loop (60Hz)

```go
func (e *Engine) updateLoop() {
    ticker := time.NewTicker(e.updateRate)
    defer ticker.Stop()

    for {
        select {
        case <-e.stopChan:
            close(e.doneChan)
            return
        case <-ticker.C:
            e.processModulation()
        }
    }
}

func (e *Engine) processModulation() {
    e.mu.Lock()
    defer e.mu.Unlock()

    now := time.Now()
    elapsed := now.Sub(e.lastUpdate)
    e.lastUpdate = now

    // Initialize channel values
    channelValues := make(map[ChannelKey]ChannelState)

    // Process effects in priority order (lowest to highest)
    for _, active := range e.activeEffects {
        e.processEffect(active, elapsed, channelValues)
    }

    // Write to DMX
    for key, state := range channelValues {
        e.dmxService.SetChannelValue(key.Universe, key.Channel, byte(state.Value))
    }

    e.dmxService.TriggerChangeDetection()
    e.cleanupCompletedEffects()
}
```

### Effect Processing

```go
func (e *Engine) processEffect(active *ActiveEffect, elapsed time.Duration, channels map[ChannelKey]ChannelState) {
    // Update intensity fade
    if active.IntensityFade != nil {
        progress := time.Since(active.IntensityFade.StartTime).Seconds() /
                    active.IntensityFade.Duration.Seconds()
        progress = clamp(progress, 0, 1)

        easedProgress := applyEasing(progress, active.IntensityFade.EasingType)
        active.Intensity = lerp(active.IntensityFade.StartValue,
                                active.IntensityFade.EndValue, easedProgress)

        if progress >= 1.0 {
            active.IntensityFade = nil
            if active.Intensity == 0 {
                return // Will be cleaned up
            }
        }
    }

    if active.Intensity == 0 {
        return
    }

    // Calculate effect values by type
    var effectValues map[ChannelKey]int
    switch active.Effect.EffectType {
    case EffectTypeCrossfade:
        effectValues = e.calculateCrossfadeValues(active)
    case EffectTypeWaveform:
        effectValues = e.calculateWaveformValues(active, elapsed)
    case EffectTypeStatic:
        effectValues = e.calculateStaticValues(active)
    case EffectTypeMaster:
        effectValues = e.calculateMasterValues(active, channels)
    }

    // Apply composition mode
    for key, effectValue := range effectValues {
        existing, hasExisting := channels[key]
        finalValue := e.applyComposition(existing, effectValue,
                                         active.Effect.CompositionMode, hasExisting)

        channels[key] = ChannelState{
            Value:           finalValue,
            OwnerEffectID:   active.Effect.ID,
            CompositionMode: active.Effect.CompositionMode,
        }
    }
}
```

---

## Cue Transition Algorithm

When `ExecuteCueTransition()` is called:

### Step 1: Handle Existing Effects

```go
for _, active := range e.activeEffects {
    if active.Effect.Priority.Band >= PriorityBandCue {
        continue  // CUE and SYSTEM effects handled separately
    }

    // Apply USER effect's transition behavior
    switch active.Effect.OnCueChange {
    case TransitionFadeOut:
        duration := fadeTime
        if active.Effect.FadeDuration != nil {
            duration = *active.Effect.FadeDuration
        }
        active.IntensityFade = &FadeTransition{
            StartValue: active.Intensity,
            EndValue:   0,
            Duration:   time.Duration(duration * float64(time.Second)),
            StartTime:  time.Now(),
            EasingType: easing,
        }

    case TransitionPersist:
        // No action - effect continues

    case TransitionSnapOff:
        active.Intensity = 0  // Immediate stop

    case TransitionCrossfadeParams:
        // Check if same effect in new cue
        if newParams := findEffectInCue(toCue, active.Effect.ID); newParams != nil {
            e.crossfadeEffectParams(active, newParams, fadeTime)
        } else {
            // Not in new cue, fade out
            active.IntensityFade = &FadeTransition{...}
        }
    }
}
```

### Step 2: Capture Current State

```go
fromValues := make(map[ChannelKey]int)
for _, active := range e.activeEffects {
    if active.Effect.EffectType == EffectTypeCrossfade {
        // Use crossfade's current interpolated values
        for key := range active.ToValues {
            fromValues[key] = e.getCurrentChannelValue(key)
        }
    }
}
// Also capture any channels from base state
```

### Step 3: Build Target Values

```go
toValues := make(map[ChannelKey]int)

// Process looks in priority order (lowest first)
sort.Slice(toCue.Looks, func(i, j int) bool {
    return toCue.Looks[i].Priority < toCue.Looks[j].Priority
})

for _, cueLook := range toCue.Looks {
    look := loadLook(ctx, cueLook.LookID)
    for _, fv := range look.FixtureValues {
        for _, ch := range fv.Channels {
            key := ChannelKey{
                Universe: fv.Fixture.Universe,
                Channel:  fv.Fixture.StartChannel + ch.Offset,
            }
            // Higher priority look overwrites lower
            toValues[key] = ch.Value
        }
    }
}
```

### Step 4: Create Crossfade Effect

```go
// Remove any existing crossfade
e.removeEffectsByType(EffectTypeCrossfade)

// Create new crossfade
crossfade := &Effect{
    ID:              generateID("crossfade"),
    EffectType:      EffectTypeCrossfade,
    Priority:        EffectPriority{Band: PriorityBandCue, SubPriority: 50},
    CompositionMode: ComposeModeOverride,
    EasingType:      easing,
}

active := &ActiveEffect{
    Effect:     crossfade,
    StartTime:  time.Now(),
    Intensity:  100,
    FromValues: fromValues,
    ToValues:   toValues,
    Duration:   time.Duration(fadeTime * float64(time.Second)),
}

e.activeEffects = append(e.activeEffects, active)
e.sortEffects()
```

### Step 5: Activate New Cue Effects

```go
for _, cueEffect := range toCue.Effects {
    effect := loadEffect(ctx, cueEffect.EffectID)

    // Override parameters from cue
    if cueEffect.Speed != 1.0 {
        effect.Frequency *= cueEffect.Speed
    }

    // Start with intensity 0, fade in
    e.activateEffect(effect, 0, fadeTime)
    e.updateEffectIntensity(effect.ID, cueEffect.Intensity, fadeTime)
}
```

---

## GraphQL API

### Types

```graphql
# Enums
enum EffectType {
  WAVEFORM
  CROSSFADE
  STATIC
  MASTER
}

enum PriorityBand {
  BASE
  USER
  CUE
  SYSTEM
}

enum CompositionMode {
  OVERRIDE
  ADDITIVE
  MULTIPLY
}

enum TransitionBehavior {
  FADE_OUT
  PERSIST
  SNAP_OFF
  CROSSFADE_PARAMS
}

enum WaveformType {
  SINE
  COSINE
  SQUARE
  SAWTOOTH
  TRIANGLE
  RANDOM
}

enum ChannelType {
  INTENSITY
  RED
  GREEN
  BLUE
  WHITE
  AMBER
  UV
  PAN
  TILT
  ZOOM
  FOCUS
  IRIS
  GOBO
  PRISM
  FROST
  STROBE
  COLOR_WHEEL
  MACRO
  OTHER
}

# Main types
type Effect {
  id: ID!
  name: String!
  description: String
  project: Project!

  effectType: EffectType!
  priorityBand: PriorityBand!
  prioritySub: Int!
  compositionMode: CompositionMode!
  onCueChange: TransitionBehavior!
  fadeDuration: Float

  # Easing (for CROSSFADE)
  easingType: EasingType

  # Waveform parameters
  waveform: WaveformType
  frequency: Float
  amplitude: Float
  offset: Float
  phaseOffset: Float

  fixtures: [EffectFixture!]!

  createdAt: String!
  updatedAt: String!
}

type EffectFixture {
  id: ID!
  fixture: FixtureInstance!
  phaseOffset: Float
  amplitudeScale: Float
  effectOrder: Int
  channels: [EffectChannel!]!
}

type EffectChannel {
  id: ID!
  channelOffset: Int
  channelType: ChannelType
  amplitudeScale: Float
  frequencyScale: Float
}

type ActiveEffectInfo {
  effectId: ID!
  effectName: String!
  effectType: EffectType!
  priorityBand: PriorityBand!
  prioritySub: Int!
  compositionMode: CompositionMode!
  intensity: Float!
  isFading: Boolean!
  fadeProgress: Float
  targetChannelCount: Int!
}

type ChannelStateInfo {
  universe: Int!
  channel: Int!
  finalValue: Int!
  ownerEffectId: ID
  ownerEffectName: String
  compositionMode: CompositionMode
  contributingEffects: [ContributingEffect!]!
}

type ContributingEffect {
  effectId: ID!
  effectName: String!
  rawValue: Int!
  compositionMode: CompositionMode!
}

type ModulationStatus {
  activeEffectCount: Int!
  effectsByBand: EffectsByBand!
  hasActiveCrossfade: Boolean!
  crossfadeProgress: Float
  blackoutActive: Boolean!
  grandMasterValue: Float!
  updateRateHz: Int!
}

type EffectsByBand {
  base: Int!
  user: Int!
  cue: Int!
  system: Int!
}
```

### Queries

```graphql
type Query {
  # Effect definitions
  effects(projectId: ID!): [Effect!]!
  effect(id: ID!): Effect

  # Runtime state
  activeEffects: [ActiveEffectInfo!]!
  channelState(universe: Int!, channel: Int!): ChannelStateInfo!
  modulationStatus: ModulationStatus!
}
```

### Mutations

```graphql
type Mutation {
  # Effect CRUD
  createEffect(input: CreateEffectInput!): Effect!
  updateEffect(id: ID!, input: UpdateEffectInput!): Effect!
  deleteEffect(id: ID!): Boolean!
  duplicateEffect(id: ID!, name: String!): Effect!

  # Effect fixtures
  addFixtureToEffect(effectId: ID!, fixtureId: ID!, input: EffectFixtureInput): EffectFixture!
  addFixturesToEffect(effectId: ID!, fixtureIds: [ID!]!, channelType: ChannelType): [EffectFixture!]!
  removeFixtureFromEffect(effectId: ID!, fixtureId: ID!): Boolean!
  updateEffectFixture(id: ID!, input: UpdateEffectFixtureInput!): EffectFixture!
  distributePhase(effectId: ID!, distribution: PhaseDistribution!): [EffectFixture!]!

  # Effect channels
  addChannelToEffectFixture(effectFixtureId: ID!, input: EffectChannelInput!): EffectChannel!
  removeChannelFromEffectFixture(id: ID!): Boolean!

  # Playback control
  activateEffect(effectId: ID!, intensity: Float, fadeTime: Float): ActiveEffectInfo!
  stopEffect(effectId: ID!, fadeTime: Float): Boolean!
  updateEffectParameters(effectId: ID!, params: EffectParametersInput!): ActiveEffectInfo!

  # System controls
  activateBlackout(fadeTime: Float): ModulationStatus!
  releaseBlackout(fadeTime: Float): ModulationStatus!
  setGrandMaster(value: Float!): ModulationStatus!

  # Bulk operations
  bulkCreateEffects(effects: [CreateEffectInput!]!): [Effect!]!
  bulkDeleteEffects(ids: [ID!]!, confirmDelete: Boolean!): BulkDeleteResult!
}

# Input types
input CreateEffectInput {
  name: String!
  description: String
  projectId: ID!
  effectType: EffectType
  priorityBand: PriorityBand
  prioritySub: Int
  compositionMode: CompositionMode
  onCueChange: TransitionBehavior
  fadeDuration: Float
  easingType: EasingType
  waveform: WaveformType
  frequency: Float
  amplitude: Float
  offset: Float
  phaseOffset: Float
}

input UpdateEffectInput {
  name: String
  description: String
  effectType: EffectType
  priorityBand: PriorityBand
  prioritySub: Int
  compositionMode: CompositionMode
  onCueChange: TransitionBehavior
  fadeDuration: Float
  easingType: EasingType
  waveform: WaveformType
  frequency: Float
  amplitude: Float
  offset: Float
  phaseOffset: Float
}

input EffectFixtureInput {
  phaseOffset: Float
  amplitudeScale: Float
  effectOrder: Int
}

input UpdateEffectFixtureInput {
  phaseOffset: Float
  amplitudeScale: Float
  effectOrder: Int
}

input EffectChannelInput {
  channelOffset: Int
  channelType: ChannelType
  amplitudeScale: Float
  frequencyScale: Float
}

input EffectParametersInput {
  intensity: Float
  speed: Float
  frequency: Float
  amplitude: Float
  offset: Float
}

enum PhaseDistribution {
  LINEAR          # 0, 90, 180, 270 for 4 fixtures
  REVERSE_LINEAR  # 270, 180, 90, 0
  RANDOM          # Random distribution
  PAIRS           # 0, 0, 180, 180
  ALTERNATING     # 0, 180, 0, 180
}
```

### Subscriptions

```graphql
type Subscription {
  # Effect playback status
  activeEffectsUpdated: [ActiveEffectInfo!]!

  # Overall engine status
  modulationStatusUpdated: ModulationStatus!

  # Channel-level debugging
  channelStateUpdated(universe: Int!, channel: Int!): ChannelStateInfo!
}
```

---

## Success Criteria

### Functional Requirements

1. **Cue Transitions**: All existing cue transitions work identically to current fade engine
2. **Waveform Effects**: Sine, square, sawtooth, triangle, random waveforms modulate channels
3. **Priority Resolution**: Higher priority effects always win on channel conflicts
4. **Composition Modes**: Override, additive, multiply modes work correctly
5. **Transition Behaviors**: Effects fade out, persist, snap off, or crossfade params on cue change
6. **System Controls**: Blackout overrides everything, grand master scales intensity
7. **Multiple Looks**: Cues can contain multiple looks with priority ordering

### Non-Functional Requirements

1. **Performance**: Single 60Hz loop processes 100+ effects without frame drops
2. **Latency**: Effect changes visible within 2 update cycles (33ms)
3. **Memory**: Completed effects cleaned up immediately
4. **Thread Safety**: All operations safe under concurrent access
5. **Backward Compatibility**: FadeToLook/FadeToBlack APIs continue to work

### Testing Requirements

1. **Unit Tests**: 90%+ coverage of modulator package
2. **Integration Tests**: All cue transition scenarios tested
3. **Performance Tests**: Verified at 100 concurrent effects
4. **Regression Tests**: Existing fade behavior unchanged

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Performance regression | High | Benchmark against existing fade engine before migration |
| Timing precision | Medium | Use monotonic clock, test under load |
| Memory leaks | Medium | Comprehensive cleanup tests, leak detection in CI |
| State corruption | High | Mutex protection, immutable effect copies |
| Migration breakage | High | Compatibility layer, gradual rollout |

---

## Dependencies

### Internal
- `dmx.Service` - DMX channel output
- `playback.Service` - Cue playback orchestration
- Database models - Effect persistence

### External
- None (all Go standard library)

---

## Out of Scope

- Audio-reactive effects (BPM sync)
- Custom waveform editor
- MIDI clock synchronization
- Effect macros/presets
- Effect groups with synchronized phase

These are documented in the FX Engine plan as future enhancements.
