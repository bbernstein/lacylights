# FX Engine Implementation Plan for LacyLights

> **Related Documentation**:
> - [FX_ENGINE_INDEX.md](FX_ENGINE_INDEX.md) - Documentation index and quick start
> - [FX_ENGINE_PRD.md](FX_ENGINE_PRD.md) - Product Requirements Document
> - [FX_ENGINE_BACKEND_IMPLEMENTATION.md](FX_ENGINE_BACKEND_IMPLEMENTATION.md) - Phased backend implementation
> - [FX_ENGINE_TESTING_PLAN.md](FX_ENGINE_TESTING_PLAN.md) - Unit and integration test specifications
> - [FX_ENGINE_GRAPHQL_API.md](FX_ENGINE_GRAPHQL_API.md) - Complete GraphQL API contract

## Overview

Add an FX (Effects) Engine to LacyLights that enables LFO-based dynamic effects for modulating DMX channel values. Effects can run as part of cues or be activated standalone (like looks).

> **Architecture Note**: This plan implements effects using a **Unified Modulator Architecture** that
> replaces the existing fade engine with a single layered modulation pipeline. This ensures that
> scene change fades and waveform effects are coordinated through a single 60Hz update loop,
> eliminating race conditions and providing deterministic state at any point in time.
> See the "Unified Modulator Architecture" section at the end of this document for full details.

## Key Design Decisions

1. **Single Effect**: Only one effect runs at a time (like looks)
2. **Effect Modulates Look**: When cue has both look + effect, look provides base values and effect modulates on top
3. **Standalone + Cue**: Effects can be triggered via look board/direct activation OR as part of cues
4. **Channel Targeting**: Default to channel type selection (intensity, color) with option to override individual channels
5. **Effect Intensity Fades**: Effect intensity fades like a channel during cue transitions

---

## Cue Transition Behavior

When transitioning between cues, the effect engine must handle several scenarios smoothly. The key insight is that **effect intensity is treated like a fadeable parameter** (similar to a DMX channel value).

### Transition Scenarios

| From Cue | To Cue | Behavior |
|----------|--------|----------|
| Look only | Look + Effect | Look fades normally. Effect intensity fades from 0% → target% over fadeInTime. |
| Look + Effect | Look only | Look fades normally. Effect intensity fades from current% → 0% over fadeInTime. Effect stops when intensity reaches 0. |
| Effect A | Effect B (same) | Effect continues running. Parameters (speed, intensity, frequency) crossfade to new values. |
| Effect A | Effect B (different) | Effect A intensity fades to 0%. Effect B starts with intensity at 0% and fades up. Crossfade. |
| Effect only | Look only | Effect intensity fades to 0%. Look fades in normally. |
| Look only | Effect only | Look fades normally (to black if no look in target cue, or stays if effect has no look). Effect fades in from 0%. |

### Implementation Details

**Effect Engine Additions:**
```go
type ActiveEffect struct {
    // ... existing fields ...
    TargetIntensity  float64  // What we're fading to (0-100)
    CurrentIntensity float64  // Current interpolated value
    IntensityFadeStart float64  // Starting intensity for fade
    IntensityFadeStartTime time.Time
    IntensityFadeDuration time.Duration
}

// Called each update tick
func (e *Engine) processEffects() {
    // Calculate current intensity (interpolated)
    if active.IntensityFadeDuration > 0 {
        elapsed := time.Since(active.IntensityFadeStartTime)
        progress := elapsed.Seconds() / active.IntensityFadeDuration.Seconds()
        progress = clamp(progress, 0, 1)

        // Apply easing (use same easing as cue)
        easedProgress := applyEasing(progress, active.EasingType)
        active.CurrentIntensity = lerp(active.IntensityFadeStart, active.TargetIntensity, easedProgress)

        // Stop effect when fade out completes
        if progress >= 1.0 && active.TargetIntensity == 0 {
            e.activeEffect = nil
            return
        }
    }

    // Use CurrentIntensity in waveform calculation
    scaledValue := waveValue * amplitude * (active.CurrentIntensity / 100) * 255
}
```

**Playback Service Modifications:**

When `ExecuteCueDmx()` is called for a cue with an effect:
1. Check if an effect is already running
2. If same effect: update parameters with fade
3. If different effect or no effect: fade out current, fade in new
4. Coordinate timing with look fade (use same fadeInTime)

```go
func (s *Service) ExecuteCueDmx(ctx context.Context, cue *Cue, fadeInTime float64) {
    // Handle look fade (existing logic)
    if cue.Look != nil {
        s.fadeEngine.FadeToLook(...)
    }

    // Handle effect transition
    currentEffect := s.effectEngine.GetActiveEffect()
    newEffect := cue.Effect

    if currentEffect != nil && newEffect == nil {
        // Fade out current effect
        s.effectEngine.FadeIntensity(0, fadeInTime, cue.EasingType)
    } else if currentEffect == nil && newEffect != nil {
        // Start new effect at 0, fade in
        targets := s.buildEffectTargets(ctx, newEffect, cue.Look)
        intensity := cue.EffectIntensity or 100
        s.effectEngine.StartEffectWithFade(newEffect, targets, 0, intensity, fadeInTime, cue.EasingType)
    } else if currentEffect != nil && newEffect != nil {
        if currentEffect.ID == newEffect.ID {
            // Same effect - update parameters with fade
            s.effectEngine.FadeParameters(cue.EffectSpeed, cue.EffectIntensity, fadeInTime)
        } else {
            // Different effects - crossfade
            s.effectEngine.CrossfadeToEffect(newEffect, targets, fadeInTime, cue.EasingType)
        }
    }
}
```

### Visual Representation

```
Cue 1 (Look A + Effect @ 100%)  →  Cue 2 (Look B, no effect)
        |                                    |
        |  fadeInTime (3s)                   |
        |←——————————————————————————————————→|

Look:   [A]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[B]   (crossfade)
Effect:  [100%]━━━━━━━━━━━━━━━━━━━━━━━━━[0%]     (fade out)
                                         ↑
                                    effect stops
```

```
Cue 1 (Look A)  →  Cue 2 (Look B + Effect @ 100%)
        |                         |
        |  fadeInTime (3s)        |
        |←———————————————————————→|

Look:   [A]━━━━━━━━━━━━━━━━━━━━━[B]   (crossfade)
Effect:  [0%]━━━━━━━━━━━━━━━━━[100%]   (fade in)
              ↑
         effect starts (intensity 0)
```

### Edge Cases

1. **Follow cue during effect fade**: If a follow cue triggers while effect is still fading, interrupt and start new fade from current intensity
2. **Manual GO during fade**: Same as above - start new transition from current state
3. **Stop/blackout**: Effect intensity immediately goes to 0 (or fades with blackout fade time)
4. **Effect-only cue to effect-only cue**: Base values for modulation come from current DMX state (captured at cue start)

---

## Data Model

### New Tables

```
effects
├── id (CUID, PK)
├── name
├── description
├── project_id (FK)
├── waveform (SINE, COSINE, SQUARE, SAWTOOTH, TRIANGLE, RANDOM)
├── frequency (Hz, default 1.0)
├── amplitude (0-100%, default 100)
├── offset (0-100% baseline, default 50)
├── phase_offset (0-360 degrees, default 0)
├── created_at, updated_at

effect_fixtures
├── id (CUID, PK)
├── effect_id (FK)
├── fixture_id (FK)
├── phase_offset (override, nullable)
├── amplitude_scale (0-200%, nullable)
├── effect_order (for auto-phase distribution)

effect_channels
├── id (CUID, PK)
├── effect_fixture_id (FK)
├── channel_offset (specific channel) OR
├── channel_type (INTENSITY, RED, GREEN, BLUE, etc.)
├── amplitude_scale (per-channel override)
├── frequency_scale (per-channel override)
```

### Modified Tables

```
cues (modifications)
├── look_id (NOW NULLABLE)
├── effect_id (NEW, nullable FK)
├── effect_speed (NEW, runtime speed multiplier)
├── effect_intensity (NEW, runtime intensity 0-100)
```

---

## GraphQL Schema Additions

### Types
- `Effect` - Main effect definition with parameters
- `EffectFixture` - Fixture instance in an effect with phase offset
- `EffectChannel` - Channel targeting (by type or offset)
- `EffectPlaybackStatus` - Runtime status for subscriptions
- `EffectWaveform` enum (SINE, COSINE, SQUARE, SAWTOOTH, TRIANGLE, RANDOM)
- `ChannelType` enum (INTENSITY, RED, GREEN, BLUE, PAN, TILT, etc.)

### Queries
- `effects(projectId: ID!)` - List effects in project
- `effect(id: ID!)` - Get single effect
- `effectPlaybackStatus` - Current running effect status

### Mutations
- CRUD: `createEffect`, `updateEffect`, `deleteEffect`, `duplicateEffect`
- Fixtures: `addFixtureToEffect`, `removeFixtureFromEffect`, `updateEffectFixture`
- Bulk: `addFixturesToEffect(effectId, fixtureIds, channelType)`, `distributePhase`
- Playback: `activateEffect`, `stopEffect`, `updateEffectParameters`

### Subscriptions
- `effectPlaybackUpdated` - Real-time effect status

---

## Go Services

### New: `/internal/services/modulator/` (Unified Modulator)

> **Note**: The unified modulator treats **everything as an effect**, including crossfades.
> This eliminates special cases and provides a single, priority-based system for all
> DMX modulation. See the "Unified Modulator Architecture" section for full details.

```
modulator/
├── engine.go           # Unified engine with single 60Hz update loop
├── effects.go          # Effect struct, EffectType, CompositionMode, TransitionBehavior
├── priority.go         # PriorityBand, EffectPriority, sorting
├── waveforms.go        # Waveform generation (sine, square, etc.)
├── crossfade.go        # Crossfade effect implementation
├── system_effects.go   # Blackout, Grand Master built-in effects
├── composition.go      # Composition mode resolution (OVERRIDE, ADDITIVE, MULTIPLY)
├── transition.go       # Cue transition handling, effect lifecycle
├── fade_api.go         # FadeToLook, FadeToBlack compatibility API
└── *_test.go           # Unit tests
```

**Engine Key Methods:**
- `Start()` / `Stop()` - Control single update loop
- `AddEffect(effect, intensity, fadeInTime)` - Add any effect with priority
- `RemoveEffect(effectID)` - Remove effect (with optional fade out)
- `ExecuteCueTransition(fromCue, toCue, fadeTime, easing)` - Full cue change
- `ActivateBlackout()` / `ReleaseBlackout()` - System-level blackout
- `SetGrandMaster(value)` - System-level intensity scaling
- `GetChannelState(universe, channel)` - Query channel with contributing effects
- `GetActiveEffects()` - List all active effects by priority
- `GetModulationStatus()` - Overall engine state

**Effect Processing (priority order, low to high):**
```go
// Effects sorted by (Band, SubPriority), processed low to high
// Higher priority effects apply their composition mode to lower priority results
for _, active := range e.activeEffects {
    effectValues := e.calculateEffectValues(active, elapsed)
    for key, value := range effectValues {
        channels[key] = e.applyComposition(channels[key], value, active.CompositionMode)
    }
}
```

**Composition Mode Resolution:**
```go
switch effect.CompositionMode {
case ComposeModeOverride:
    finalValue = effectValue  // Higher priority wins completely
case ComposeModeAdditive:
    finalValue = clamp(existing + effectValue, 0, 255)  // Add modulation
case ComposeModeMultiply:
    finalValue = int(float64(existing) * (float64(effectValue) / 255.0))  // Scale
}
```

### Modified: `/internal/services/playback/service.go`

- Replace `fadeEngine` with `modulator` (unified modulator)
- `ExecuteCueDmx()` becomes `ExecuteCueTransition()` - handles:
  - Multiple looks per cue (layered by priority)
  - Effect transition behaviors (FADE_OUT, PERSIST, SNAP_OFF, CROSSFADE_PARAMS)
  - Automatic crossfade effect creation
  - New cue effect activation

### Deprecated: `/internal/services/fade/engine.go`

- Replaced by unified modulator's crossfade effect system
- Compatibility wrapper available: `FadeToLook()` creates a CROSSFADE effect

### New: `/internal/database/repositories/effect_repository.go`

- Standard CRUD operations for effects
- `FindByProjectID()`, `FindWithFixtures()`
- `FindByType(effectType)` - Find effects by type (WAVEFORM, STATIC, etc.)
- `FindSystemEffects()` - Find SYSTEM priority effects

---

## Frontend Components

### New Components

```
/components/effects/
├── EffectEditor.tsx           # Main effect programming UI
│   ├── Waveform selector (dropdown with icons)
│   ├── Parameter sliders (frequency, amplitude, offset, phase)
│   ├── Fixture selection list with phase offsets
│   ├── Channel type filter checkboxes
│   └── Live preview toggle
├── EffectWaveformPreview.tsx  # Animated waveform visualization
├── EffectFixtureList.tsx      # Fixtures in effect with phase controls
├── EffectParameterSliders.tsx # Runtime speed/intensity controls
└── EffectPlaybackBadge.tsx    # Small indicator showing running effect
```

### New Pages

```
/app/(main)/effects/page.tsx           # Effect list
/app/(main)/effects/[id]/edit/page.tsx # Effect editor
```

### Modified Components

**CueListUnifiedView.tsx**
- Add effect selector dropdown alongside look selector
- Show effect badge on cues with effects
- Effect runtime parameter overrides in cue properties

**CueListPlayer.tsx**
- Display effect status when running
- Optional speed/intensity adjustment during playback

**LookBoardClient.tsx**
- Support effect buttons (activate effect like activating look)
- Different visual style for effect buttons

**Navigation**
- Add "Effects" to sidebar navigation

---

## Implementation Phases

> **Note**: This plan uses the **Unified Modulator Architecture** described at the end of this document.
> The unified modulator treats **everything as an effect** (including crossfades) with priority bands,
> composition modes, and configurable transition behaviors.

### Phase 1: Database & Models
**Files:**
- `lacylights-go/internal/database/models/models.go` - Add Effect, EffectFixture, EffectChannel, CueLook
- `lacylights-go/internal/database/models/models.go` - Modify Cue (add cue_looks relation, add effects)
- Create migration file

**Tasks:**
1. Add Effect struct with new fields:
   - `effect_type` (WAVEFORM, CROSSFADE, STATIC, MASTER)
   - `priority_band` (BASE, USER, CUE, SYSTEM)
   - `priority_sub` (0-100)
   - `composition_mode` (OVERRIDE, ADDITIVE, MULTIPLY) - default OVERRIDE
   - `on_cue_change` (FADE_OUT, PERSIST, SNAP_OFF, CROSSFADE_PARAMS) - default FADE_OUT
   - `fade_duration` (nullable override)
2. Add EffectFixture, EffectChannel structs
3. Add CueLook struct for multiple looks per cue with priority
4. Modify Cue struct (add CueLooks relation, deprecate single look_id)
5. Write and run migration
6. Add indexes for foreign keys

### Phase 2: Unified Modulator Engine - Core
**Files:**
- `lacylights-go/internal/services/modulator/engine.go` (new)
- `lacylights-go/internal/services/modulator/effects.go` (new)
- `lacylights-go/internal/services/modulator/priority.go` (new)
- `lacylights-go/internal/services/modulator/composition.go` (new)

**Tasks:**
1. Create core types: `ChannelKey`, `ChannelState`, `ActiveEffect`
2. Create `PriorityBand` enum and `EffectPriority` struct with comparison
3. Create `CompositionMode` enum (OVERRIDE, ADDITIVE, MULTIPLY)
4. Create `TransitionBehavior` enum (FADE_OUT, PERSIST, SNAP_OFF, CROSSFADE_PARAMS)
5. Build `Engine` with single 60Hz update loop
6. Implement priority-sorted effect list management
7. Implement composition mode resolution in `processModulation()`
8. Write comprehensive unit tests for priority ordering and composition

### Phase 3: Effect Types Implementation
**Files:**
- `lacylights-go/internal/services/modulator/waveforms.go` (new)
- `lacylights-go/internal/services/modulator/crossfade.go` (new)
- `lacylights-go/internal/services/modulator/system_effects.go` (new)

**Tasks:**
1. Implement waveform functions (sine, cosine, square, sawtooth, triangle, random)
2. Implement `EffectTypeWaveform` calculation with phase, amplitude, frequency
3. Implement `EffectTypeCrossfade` - interpolation from captured state to target
4. Implement `EffectTypeStatic` - fixed channel values
5. Implement `EffectTypeMaster` - multiplier effect for grand master
6. Create built-in `BlackoutEffect` (SYSTEM priority, OVERRIDE)
7. Create built-in `GrandMasterEffect` (SYSTEM priority, MULTIPLY)
8. Write unit tests for each effect type

### Phase 4: Cue Transition System
**Files:**
- `lacylights-go/internal/services/modulator/transition.go` (new)
- `lacylights-go/internal/services/modulator/fade_api.go` (new)

**Tasks:**
1. Implement `ExecuteCueTransition()` with full lifecycle:
   - Apply transition behaviors to existing USER effects
   - Capture current DMX state for crossfade
   - Build target values from multiple cue looks (priority-ordered)
   - Create CROSSFADE effect at CUE priority
   - Activate new cue's effects
2. Implement effect parameter crossfade (for CROSSFADE_PARAMS behavior)
3. Create `FadeToLook()` compatibility wrapper
4. Create `FadeToBlack()` using crossfade effect
5. Write integration tests for all transition scenarios

### Phase 5: Migrate Playback Service
**Files:**
- `lacylights-go/internal/services/playback/service.go` (modify)
- `lacylights-go/internal/services/fade/engine.go` (deprecate)

**Tasks:**
1. Replace `fadeEngine` dependency with `modulator`
2. Update `ExecuteCueDmx()` to call `modulator.ExecuteCueTransition()`
3. Add support for multiple looks per cue
4. Handle effect transition behaviors during cue changes
5. Update resolvers that directly use fade engine
6. Run existing tests against new modulator
7. Remove old fade engine after validation

### Phase 6: Effect Repository & Data Layer
**Files:**
- `lacylights-go/internal/database/repositories/effect_repository.go` (new)

**Tasks:**
1. Create effect repository with CRUD operations
2. Implement `FindByProjectID()`, `FindWithFixtures()`
3. Implement `FindByType(effectType)`
4. Implement `FindSystemEffects()`
5. Write repository tests

### Phase 7: GraphQL API
**Files:**
- `lacylights-go/internal/graphql/schema/schema.graphql`
- `lacylights-go/internal/graphql/resolvers/effect_resolvers.go` (new)

**Tasks:**
1. Add GraphQL types and enums:
   - `Effect`, `EffectType`, `EffectPriority`, `PriorityBand`
   - `CompositionMode`, `TransitionBehavior`
   - `ActiveEffectInfo`, `ChannelStateInfo`, `ModulationStatus`
2. Add queries: `effects`, `effect`, `activeEffects`, `channelState`, `modulationStatus`
3. Add mutations: CRUD + `activateEffect`, `stopEffect`, `activateBlackout`, `setGrandMaster`
4. Add subscriptions: `effectPlaybackUpdated`, `modulationStatusUpdated`
5. Update cue mutations for multiple looks
6. Write integration tests

### Phase 8: Frontend - Core
**Files:**
- `lacylights-fe/src/graphql/effects.ts` (new)
- `lacylights-fe/src/components/effects/EffectEditor.tsx` (new)
- `lacylights-fe/src/app/(main)/effects/` (new pages)

**Tasks:**
1. Run GraphQL codegen
2. Create effect list page with priority band grouping
3. Create EffectEditor with:
   - Effect type selector
   - Priority band and sub-priority controls
   - Composition mode selector
   - Transition behavior selector
   - Waveform parameters (for WAVEFORM type)
4. Add fixture selection to effect editor
5. Implement channel type selection

### Phase 9: Frontend - Waveform Preview
**Files:**
- `lacylights-fe/src/components/effects/EffectWaveformPreview.tsx` (new)

**Tasks:**
1. Create animated SVG waveform visualization
2. Show multiple fixtures with phase offsets
3. Add playback indicator (current phase marker)
4. Show composition mode impact preview

### Phase 10: Frontend - Cue Integration
**Files:**
- `lacylights-fe/src/components/CueListUnifiedView.tsx` (modify)
- `lacylights-fe/src/components/CueListPlayer.tsx` (modify)
- `lacylights-fe/src/components/AddCueDialog.tsx` (modify)
- `lacylights-fe/src/components/EditCueDialog.tsx` (modify)

**Tasks:**
1. Add multiple look selector with priority ordering
2. Add effect selector with transition behavior override
3. Show effect badges with composition mode indicators
4. Display active effects panel in player
5. Add blackout and grand master controls

### Phase 11: Frontend - Look Board
**Files:**
- `lacylights-fe/src/components/LookBoardClient.tsx` (modify)

**Tasks:**
1. Support adding effect buttons to look boards
2. Different visual style by effect type and priority band
3. Activate effect on button press with priority indication

### Phase 12: Testing & Polish
**Tasks:**
1. End-to-end testing with real fixtures
2. Test all composition mode combinations
3. Test all transition behavior scenarios
4. Test priority conflict resolution
5. Test multiple looks per cue
6. Test blackout and grand master
7. Performance testing (single 60Hz loop with many effects)
8. State inspection/debugging tools
9. UI/UX refinements

---

## Verification Steps

1. **Unit Tests**: Run `make test` in lacylights-go
2. **Integration Tests**: Add effect API tests to lacylights-test
3. **Manual Testing - Basic**:
   - Create effect with sine wave on intensity
   - Add 4 fixtures with auto-distributed phase (chase effect)
   - Create cue with look + effect, verify modulation
   - Activate effect standalone via look board
   - Verify effect stops when different look activated
4. **Manual Testing - Cue Transitions**:
   - Create Cue 1 (look only) → Cue 2 (look + effect): Verify effect fades in
   - Create Cue 2 (look + effect) → Cue 3 (look only): Verify effect fades out
   - Create Cue 3 → Cue 4 (different effect): Verify crossfade between effects
   - Create Cue 4 → Cue 5 (same effect, different intensity): Verify smooth parameter transition
   - Test rapid GO presses during fade: Verify no glitches
   - Test fade to black during effect: Verify effect fades out with blackout
5. **Frontend**: Run `npm run build` in lacylights-fe to verify no TypeScript errors

---

## Critical Files Summary

| Purpose | File Path |
|---------|-----------|
| Models | `lacylights-go/internal/database/models/models.go` |
| Unified Modulator Engine | `lacylights-go/internal/services/modulator/engine.go` |
| Modulation Layers | `lacylights-go/internal/services/modulator/layers.go` |
| Waveform Functions | `lacylights-go/internal/services/modulator/waveforms.go` |
| Fade Engine (deprecated, reference) | `lacylights-go/internal/services/fade/engine.go` |
| Playback Integration | `lacylights-go/internal/services/playback/service.go` |
| GraphQL Schema | `lacylights-go/internal/graphql/schema/schema.graphql` |
| Frontend Editor | `lacylights-fe/src/components/effects/EffectEditor.tsx` |
| Cue Integration | `lacylights-fe/src/components/CueListUnifiedView.tsx` |

---

## Unified Modulator Architecture

### Core Principle: Everything is an Effect

The unified modulator treats **all DMX modulation as effects**, including crossfades. This eliminates special cases and creates a single, consistent system for all channel modifications.

**Key insight**: A crossfade from Look A to Look B is just an effect that:
- Targets the channels in Look B
- Uses configurable easing (default: `EASE_IN_OUT_SINE`) to interpolate from start to end
- Has CUE priority (higher than user effects)
- Uses OVERRIDE composition mode

### EasingType vs WaveformType

The unified modulator uses two distinct function types for shaping values:

| Aspect | EasingType | WaveformType |
|--------|------------|--------------|
| **Purpose** | Shape one-shot transitions | Generate continuous oscillation |
| **Input** | Progress (0→1, then done) | Phase (cycles 0°→360°→0°...) |
| **Output** | Position along transition | Periodic modulation value |
| **Use case** | Crossfades, intensity fades | Chases, pulses, color cycles |
| **Default** | `EASE_IN_OUT_SINE` | `SINE` |

**EasingType** (for CROSSFADE effects):
```go
type EasingType string

const (
    EasingLinear         EasingType = "LINEAR"
    EasingInOutCubic     EasingType = "EASE_IN_OUT_CUBIC"
    EasingInOutSine      EasingType = "EASE_IN_OUT_SINE"      // Default
    EasingOutExponential EasingType = "EASE_OUT_EXPONENTIAL"
    EasingBezier         EasingType = "BEZIER"
    EasingSCurve         EasingType = "S_CURVE"
)
```

**WaveformType** (for WAVEFORM effects):
```go
type WaveformType string

const (
    WaveformSine     WaveformType = "SINE"      // Default - smooth oscillation
    WaveformCosine   WaveformType = "COSINE"    // Sine shifted 90°
    WaveformSquare   WaveformType = "SQUARE"    // On/off pulse
    WaveformSawtooth WaveformType = "SAWTOOTH"  // Ramp up, snap down
    WaveformTriangle WaveformType = "TRIANGLE"  // Linear up and down
    WaveformRandom   WaveformType = "RANDOM"    // Random values
)
```

Both use smooth mathematical functions but serve fundamentally different purposes:
- Easing transforms progress for transitions that have a defined start and end
- Waveforms generate ongoing periodic modulation that cycles continuously

### Priority System

Effects are organized into **priority bands** with **sub-priorities** within each band:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRIORITY BANDS                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   SYSTEM (3)  ─────────────────────────────────────────────────────────  │
│   │  Blackout, Emergency Stop, Grand Master                             │
│   │  Sub-priority: 0-100 for ordering within band                       │
│   │                                                                      │
│   CUE (2)  ────────────────────────────────────────────────────────────  │
│   │  Crossfade effects, Cue-level look transitions                      │
│   │  Sub-priority: 0-100 for ordering within band                       │
│   │                                                                      │
│   USER (1)  ───────────────────────────────────────────────────────────  │
│   │  Chase effects, Pulses, Color cycles, User-activated effects        │
│   │  Sub-priority: 0-100 for ordering within band                       │
│   │                                                                      │
│   BASE (0)  ───────────────────────────────────────────────────────────  │
│       Static look values, Default state                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

```go
type PriorityBand int

const (
    PriorityBandBase   PriorityBand = 0  // Static look values
    PriorityBandUser   PriorityBand = 1  // User-activated effects
    PriorityBandCue    PriorityBand = 2  // Cue crossfades and transitions
    PriorityBandSystem PriorityBand = 3  // Blackout, emergency, grand master
)

type EffectPriority struct {
    Band        PriorityBand  // Major ordering
    SubPriority int           // 0-100, ordering within band (higher = more priority)
}

// Compare returns true if p has higher priority than other
func (p EffectPriority) Compare(other EffectPriority) int {
    if p.Band != other.Band {
        return int(p.Band) - int(other.Band)
    }
    return p.SubPriority - other.SubPriority
}
```

### Composition Modes

Each effect declares how it combines with lower-priority effects for the same channel:

```go
type CompositionMode string

const (
    // OVERRIDE: Higher priority completely replaces lower priority value
    // Use for: Crossfades, blackout, precise cue execution
    // Default mode
    ComposeModeOverride CompositionMode = "OVERRIDE"

    // ADDITIVE: Effect adds its modulation to the current value
    // Use for: Chase effects, pulses, flashes layered on base
    ComposeModeAdditive CompositionMode = "ADDITIVE"

    // MULTIPLY: Effect scales the current value (0.0-1.0 multiplier)
    // Use for: Grand master, dimmer curves, intensity scaling
    ComposeModeMultiply CompositionMode = "MULTIPLY"
)
```

**Default**: `OVERRIDE` - This is the safest default because:
- Crossfades must hit exact target values
- System effects (blackout) must fully override
- Predictable behavior matches traditional lighting consoles

### Transition Behavior

When a cue change occurs, each active effect's behavior is configurable:

```go
type TransitionBehavior string

const (
    // FADE_OUT: Effect fades intensity to 0 over cue's fadeInTime (DEFAULT)
    TransitionFadeOut TransitionBehavior = "FADE_OUT"

    // PERSIST: Effect continues unchanged until explicitly stopped
    TransitionPersist TransitionBehavior = "PERSIST"

    // SNAP_OFF: Effect stops immediately when cue changes
    TransitionSnapOff TransitionBehavior = "SNAP_OFF"

    // CROSSFADE_PARAMS: Effect parameters smoothly transition to new values
    // Used when same effect continues but with different intensity/speed
    TransitionCrossfadeParams TransitionBehavior = "CROSSFADE_PARAMS"
)
```

**Default**: `FADE_OUT` - This is the safest default because:
- Provides smooth visual transitions
- Prevents "orphaned" effects from previous cues
- Matches expected theatrical behavior

### Effect Model

All effects (including crossfades) share a common structure:

```go
type Effect struct {
    ID          string
    Name        string
    Description string
    ProjectID   string

    // Effect type determines behavior
    EffectType  EffectType  // WAVEFORM, CROSSFADE, STATIC, MASTER

    // Priority
    Priority    EffectPriority

    // Composition
    CompositionMode CompositionMode  // Default: OVERRIDE

    // Transition behavior on cue change
    OnCueChange     TransitionBehavior  // Default: FADE_OUT
    FadeDuration    *float64            // Override fade time (nil = use cue fadeInTime)

    // Easing parameters (for CROSSFADE type)
    EasingType      EasingType    // Default: EASE_IN_OUT_SINE

    // Waveform parameters (for WAVEFORM type)
    Waveform        WaveformType  // SINE, SQUARE, SAWTOOTH, etc.
    Frequency       float64       // Hz
    Amplitude       float64       // 0-100%
    Offset          float64       // 0-100% baseline
    PhaseOffset     float64       // 0-360 degrees

    // Target channels
    TargetFixtures  []EffectFixture
    TargetChannels  []EffectChannel

    // Runtime state (not persisted)
    Intensity       float64  // Current intensity 0-100
    Phase           float64  // Current phase for waveforms
}

type EffectType string

const (
    EffectTypeWaveform  EffectType = "WAVEFORM"   // LFO-based modulation
    EffectTypeCrossfade EffectType = "CROSSFADE"  // Look-to-look transition
    EffectTypeStatic    EffectType = "STATIC"     // Set channels to fixed values
    EffectTypeMaster    EffectType = "MASTER"     // Grand master / dimmer
)
```

### Built-in Effect Types

#### 1. Crossfade Effect (Cue Transitions)

Crossfades are effects with:
- `EffectType`: CROSSFADE
- `Priority`: CUE band
- `CompositionMode`: OVERRIDE
- `EasingType`: Configurable (default: `EASE_IN_OUT_SINE`)
- `OnCueChange`: N/A (crossfades ARE the cue change)

The easing function controls the "feel" of the transition:
- `EASE_IN_OUT_SINE` (default): Smooth, natural acceleration and deceleration
- `LINEAR`: Constant rate, mechanical feel
- `EASE_IN_OUT_CUBIC`: More dramatic acceleration/deceleration than sine
- `EASE_OUT_EXPONENTIAL`: Quick start, gradual finish (good for snappy cues)
- `S_CURVE`: Very smooth with extended ease-in and ease-out

```go
// CreateCrossfadeEffect creates an effect for look-to-look transition
func CreateCrossfadeEffect(
    fromChannels map[ChannelKey]int,  // Current values (captured)
    toChannels map[ChannelKey]int,    // Target look values
    duration time.Duration,
    easingType EasingType,            // Defaults to EASE_IN_OUT_SINE if empty
) *Effect {
    if easingType == "" {
        easingType = EasingInOutSine
    }
    return &Effect{
        ID:              generateID("crossfade"),
        EffectType:      EffectTypeCrossfade,
        Priority:        EffectPriority{Band: PriorityBandCue, SubPriority: 50},
        CompositionMode: ComposeModeOverride,
        EasingType:      easingType,
        // Crossfade-specific data stored in effect
        crossfadeData: &CrossfadeData{
            FromChannels: fromChannels,
            ToChannels:   toChannels,
            Duration:     duration,
            StartTime:    time.Now(),
        },
    }
}
```

#### 2. Blackout Effect (System Override)

```go
var BlackoutEffect = &Effect{
    ID:              "system-blackout",
    Name:            "Blackout",
    EffectType:      EffectTypeStatic,
    Priority:        EffectPriority{Band: PriorityBandSystem, SubPriority: 100},
    CompositionMode: ComposeModeOverride,
    OnCueChange:     TransitionPersist,  // Blackout persists until released
    // Targets all channels with value 0
}
```

#### 3. Grand Master Effect

```go
var GrandMasterEffect = &Effect{
    ID:              "system-grand-master",
    Name:            "Grand Master",
    EffectType:      EffectTypeMaster,
    Priority:        EffectPriority{Band: PriorityBandSystem, SubPriority: 50},
    CompositionMode: ComposeModeMultiply,
    OnCueChange:     TransitionPersist,
    // masterValue: 0.0-1.0 multiplier for all intensity channels
}
```

#### 4. Waveform Effects (User Effects)

```go
// Example: Chase effect
chaseEffect := &Effect{
    ID:              "chase-1",
    Name:            "4-Fixture Chase",
    EffectType:      EffectTypeWaveform,
    Priority:        EffectPriority{Band: PriorityBandUser, SubPriority: 50},
    CompositionMode: ComposeModeAdditive,  // Adds pulse on top of base
    OnCueChange:     TransitionFadeOut,    // Fades out on cue change
    Waveform:        WaveformSine,
    Frequency:       1.0,  // 1 Hz
    Amplitude:       50,   // ±50%
    // Phase offsets per fixture create chase pattern
}
```

### Multiple Looks per Cue

Cues can contain multiple looks with different priorities:

```go
type CueLook struct {
    LookID      string
    Priority    int     // Sub-priority within CUE band (0-100)
    // Higher priority look values win for overlapping channels
}

type Cue struct {
    ID          string
    // ... other fields ...

    // Multiple looks, layered by priority
    Looks       []CueLook  // Ordered by priority (lowest first)

    // Effects attached to this cue
    Effects     []CueEffect
}
```

**Resolution for overlapping channels:**
When multiple looks in the same cue affect the same channel, higher sub-priority wins:

```
Look A (priority 30): Fixtures 1-4 at 50% intensity
Look B (priority 70): Fixtures 3-6 at 100% intensity

Result:
- Fixtures 1-2: 50% (only Look A)
- Fixtures 3-4: 100% (Look B wins, higher priority)
- Fixtures 5-6: 100% (only Look B)
```

### Unified Engine Architecture

```go
type Engine struct {
    mu sync.RWMutex

    dmxService *dmx.Service

    // All active effects, sorted by priority
    activeEffects []*ActiveEffect

    // Channel state tracking
    channelOwners map[ChannelKey]*ActiveEffect  // Which effect owns each channel

    // Control
    stopChan   chan struct{}
    doneChan   chan struct{}
    running    bool
    updateRate time.Duration

    // Timing
    lastUpdate time.Time

    // Callbacks
    onEffectComplete func(effectID string)
}

type ActiveEffect struct {
    Effect      *Effect
    StartTime   time.Time
    Intensity   float64  // Current intensity (may be fading)
    Phase       float64  // Current phase for waveforms

    // For crossfades
    FromValues  map[ChannelKey]int
    ToValues    map[ChannelKey]int

    // Fade state
    IntensityFade *FadeTransition
}
```

### Processing Pipeline

```go
func (e *Engine) processModulation() {
    e.mu.Lock()
    defer e.mu.Unlock()

    now := time.Now()
    elapsed := now.Sub(e.lastUpdate)
    e.lastUpdate = now

    // Initialize channel values map
    channelValues := make(map[ChannelKey]ChannelState)

    // Process effects in priority order (lowest to highest)
    // Higher priority effects can override or modify lower priority results
    for _, active := range e.activeEffects {
        e.processEffect(active, elapsed, channelValues)
    }

    // Write final values to DMX
    for key, state := range channelValues {
        e.dmxService.SetChannelValue(key.Universe, key.Channel, byte(state.Value))
    }

    e.dmxService.TriggerChangeDetection()
    e.cleanupCompletedEffects()
}

type ChannelState struct {
    Value           int
    OwnerEffect     string           // ID of effect that set this value
    CompositionMode CompositionMode  // How this value was composed
}

func (e *Engine) processEffect(active *ActiveEffect, elapsed time.Duration, channels map[ChannelKey]ChannelState) {
    effect := active.Effect

    // Update intensity if fading
    if active.IntensityFade != nil {
        active.Intensity = active.IntensityFade.CurrentValue(elapsed)
        if active.IntensityFade.IsComplete() {
            active.IntensityFade = nil
            if active.Intensity == 0 {
                return // Effect faded out, will be cleaned up
            }
        }
    }

    // Skip if intensity is zero
    if active.Intensity == 0 {
        return
    }

    // Calculate effect values based on type
    var effectValues map[ChannelKey]int
    switch effect.EffectType {
    case EffectTypeCrossfade:
        effectValues = e.calculateCrossfadeValues(active, elapsed)
    case EffectTypeWaveform:
        effectValues = e.calculateWaveformValues(active, elapsed)
    case EffectTypeStatic:
        effectValues = e.calculateStaticValues(active)
    case EffectTypeMaster:
        effectValues = e.calculateMasterValues(active, channels)
    }

    // Apply effect values based on composition mode
    for key, effectValue := range effectValues {
        existing, hasExisting := channels[key]

        var finalValue int
        switch effect.CompositionMode {
        case ComposeModeOverride:
            // Higher priority completely replaces
            finalValue = effectValue

        case ComposeModeAdditive:
            // Add to existing value
            if hasExisting {
                finalValue = clamp(existing.Value + effectValue, 0, 255)
            } else {
                finalValue = effectValue
            }

        case ComposeModeMultiply:
            // Scale existing value (effectValue is 0-255, treat as 0.0-1.0)
            if hasExisting {
                multiplier := float64(effectValue) / 255.0
                finalValue = int(float64(existing.Value) * multiplier)
            } else {
                finalValue = effectValue
            }
        }

        channels[key] = ChannelState{
            Value:           finalValue,
            OwnerEffect:     effect.ID,
            CompositionMode: effect.CompositionMode,
        }
    }
}
```

### Cue Transition Flow

When a cue transition occurs:

```go
func (e *Engine) ExecuteCueTransition(
    ctx context.Context,
    fromCue *Cue,
    toCue *Cue,
    fadeInTime float64,
    easingType EasingType,
) error {
    e.mu.Lock()
    defer e.mu.Unlock()

    // 1. Handle existing effects based on their OnCueChange behavior
    for _, active := range e.activeEffects {
        if active.Effect.Priority.Band < PriorityBandCue {
            // User-level effects - apply transition behavior
            switch active.Effect.OnCueChange {
            case TransitionFadeOut:
                fadeDuration := fadeInTime
                if active.Effect.FadeDuration != nil {
                    fadeDuration = *active.Effect.FadeDuration
                }
                active.IntensityFade = &FadeTransition{
                    StartValue: active.Intensity,
                    EndValue:   0,
                    Duration:   time.Duration(fadeDuration * float64(time.Second)),
                    StartTime:  time.Now(),
                }

            case TransitionPersist:
                // Do nothing - effect continues

            case TransitionSnapOff:
                active.Intensity = 0  // Will be cleaned up

            case TransitionCrossfadeParams:
                // Check if same effect is in new cue with different params
                // If so, crossfade parameters instead of fading out
                if newParams := findEffectInCue(toCue, active.Effect.ID); newParams != nil {
                    e.crossfadeEffectParams(active, newParams, fadeInTime)
                } else {
                    // Effect not in new cue, fade out
                    active.IntensityFade = &FadeTransition{
                        StartValue: active.Intensity,
                        EndValue:   0,
                        Duration:   time.Duration(fadeInTime * float64(time.Second)),
                        StartTime:  time.Now(),
                    }
                }
            }
        }
    }

    // 2. Capture current DMX state for crossfade start values
    fromValues := e.captureCurrentState()

    // 3. Build target values from new cue's looks (respecting look priorities)
    toValues := e.buildCueLookValues(ctx, toCue)

    // 4. Create crossfade effect
    crossfadeEffect := CreateCrossfadeEffect(fromValues, toValues,
        time.Duration(fadeInTime*float64(time.Second)), easingType)

    // 5. Remove any existing crossfade effects
    e.removeEffectsByType(EffectTypeCrossfade)

    // 6. Add new crossfade effect
    e.addEffect(crossfadeEffect)

    // 7. Start new cue's effects (fading in)
    for _, cueEffect := range toCue.Effects {
        effect := e.loadEffect(ctx, cueEffect.EffectID)
        e.activateEffect(effect, cueEffect.Intensity, fadeInTime)
    }

    return nil
}
```

### Example Scenarios

#### Scenario 1: Simple Cue Transition

```
Cue 1: Look A (all fixtures at 50%)
  ↓ GO (3s fade)
Cue 2: Look B (all fixtures at 100%)

Effects Timeline:
t=0s:  [CrossfadeEffect(A→B, CUE priority, OVERRIDE)] starts
t=1s:  Fixtures interpolated to ~67%
t=2s:  Fixtures interpolated to ~83%
t=3s:  CrossfadeEffect completes, removed. Base state = Look B
```

#### Scenario 2: Cue with User Effect

```
Cue 1: Look A + ChaseEffect (USER priority, ADDITIVE)
  ↓ GO (3s fade)
Cue 2: Look B (no effects)

Effects Timeline:
t=0s:  [CrossfadeEffect(A→B)] starts at CUE priority
       [ChaseEffect] starts fading out (OnCueChange=FADE_OUT)
t=1.5s: CrossfadeEffect at 50%, ChaseEffect at 50% intensity
t=3s:  CrossfadeEffect completes, ChaseEffect fully faded out
       Final state: Look B only
```

#### Scenario 3: Effect Persists Across Cues

```
Cue 1: Look A + AmbienceEffect (USER priority, ADDITIVE, OnCueChange=PERSIST)
  ↓ GO (3s fade)
Cue 2: Look B (no new effects)

Effects Timeline:
t=0s:  [CrossfadeEffect(A→B)] starts
       [AmbienceEffect] continues unchanged (PERSIST)
t=3s:  CrossfadeEffect completes
       Final state: Look B + AmbienceEffect still running
```

#### Scenario 4: Blackout Override

```
Current: Look A + ChaseEffect + AmbienceEffect
  ↓ BLACKOUT pressed

Effects Timeline:
t=0s:  [BlackoutEffect] added at SYSTEM priority, OVERRIDE
       All channels immediately go to 0 (BlackoutEffect wins)
       Other effects continue running but their output is overridden

  ↓ BLACKOUT released
       [BlackoutEffect] removed
       Previous effects' outputs now visible again
```

#### Scenario 5: Multiple Looks in Single Cue

```
Cue 1:
  - Look A (priority 30): Fixtures 1-4 blue wash
  - Look B (priority 70): Fixtures 3-4 red spotlight

Channel Resolution:
- Fixtures 1-2: Blue wash (only Look A)
- Fixtures 3-4: Red spotlight (Look B overrides Look A, higher priority)
```

#### Scenario 6: Conflicting User Effects

```
Active Effects:
- ChaseEffect (USER, sub-priority 30, ADDITIVE): Fixtures 1-4 intensity pulse
- ColorCycleEffect (USER, sub-priority 60, OVERRIDE): Fixtures 3-6 color cycle

Channel Resolution for Fixture 3 Intensity:
- ChaseEffect calculates +30 modulation
- ColorCycleEffect (higher priority, OVERRIDE) sets to 200
- Final value: 200 (ColorCycleEffect wins)

Channel Resolution for Fixture 3 Color:
- ChaseEffect doesn't target color
- ColorCycleEffect sets RGB values
- Final value: ColorCycleEffect's RGB values
```

### State Query API

```go
// GetChannelState returns detailed information about a channel's current state
func (e *Engine) GetChannelState(universe, channel int) ChannelStateInfo {
    e.mu.RLock()
    defer e.mu.RUnlock()

    key := ChannelKey{Universe: universe, Channel: channel}

    return ChannelStateInfo{
        FinalValue:      e.getCurrentValue(key),
        OwnerEffectID:   e.getChannelOwner(key),
        CompositionMode: e.getChannelCompositionMode(key),
        ContributingEffects: e.getEffectsAffectingChannel(key),
    }
}

// GetActiveEffects returns all currently active effects with their state
func (e *Engine) GetActiveEffects() []ActiveEffectInfo {
    e.mu.RLock()
    defer e.mu.RUnlock()

    var result []ActiveEffectInfo
    for _, active := range e.activeEffects {
        result = append(result, ActiveEffectInfo{
            EffectID:        active.Effect.ID,
            EffectName:      active.Effect.Name,
            EffectType:      active.Effect.EffectType,
            Priority:        active.Effect.Priority,
            CompositionMode: active.Effect.CompositionMode,
            Intensity:       active.Intensity,
            IsFading:        active.IntensityFade != nil,
            TargetChannels:  len(active.ToValues),
        })
    }
    return result
}

// GetModulationStatus returns overall engine status
func (e *Engine) GetModulationStatus() ModulationStatus {
    e.mu.RLock()
    defer e.mu.RUnlock()

    return ModulationStatus{
        ActiveEffectCount:     len(e.activeEffects),
        EffectsByBand: map[PriorityBand]int{
            PriorityBandBase:   e.countEffectsByBand(PriorityBandBase),
            PriorityBandUser:   e.countEffectsByBand(PriorityBandUser),
            PriorityBandCue:    e.countEffectsByBand(PriorityBandCue),
            PriorityBandSystem: e.countEffectsByBand(PriorityBandSystem),
        },
        HasActiveCrossfade:    e.hasEffectOfType(EffectTypeCrossfade),
        CrossfadeProgress:     e.getCrossfadeProgress(),
        BlackoutActive:        e.isBlackoutActive(),
    }
}
```

### Data Model Updates

```
effects (updated)
├── id (CUID, PK)
├── name
├── description
├── project_id (FK)
├── effect_type (WAVEFORM, CROSSFADE, STATIC, MASTER)
├── priority_band (BASE, USER, CUE, SYSTEM)
├── priority_sub (0-100)
├── composition_mode (OVERRIDE, ADDITIVE, MULTIPLY) - default: OVERRIDE
├── on_cue_change (FADE_OUT, PERSIST, SNAP_OFF, CROSSFADE_PARAMS) - default: FADE_OUT
├── fade_duration (nullable, override for cue fadeInTime)
├── easing_type (for CROSSFADE: LINEAR, EASE_IN_OUT_SINE, etc.) - default: EASE_IN_OUT_SINE
├── waveform (for WAVEFORM: SINE, COSINE, SQUARE, SAWTOOTH, TRIANGLE, RANDOM)
├── frequency (Hz, default 1.0)
├── amplitude (0-100%, default 100)
├── offset (0-100% baseline, default 50)
├── phase_offset (0-360 degrees, default 0)
├── created_at, updated_at

cue_looks (new)
├── id (CUID, PK)
├── cue_id (FK)
├── look_id (FK)
├── priority (0-100 sub-priority within cue)
├── created_at

cues (updated)
├── id (CUID, PK)
├── ... existing fields ...
├── look_id (DEPRECATED - use cue_looks for multiple looks)
```

### Implementation Notes

1. **Single Update Loop**: ONE goroutine at 60Hz processes all effects
2. **Priority Ordering**: Effects sorted by (Band, SubPriority) - processed low to high
3. **Composition Resolution**: Higher priority effects apply their composition mode
4. **Thread Safety**: All modifications under engine mutex
5. **Memory Efficiency**: Completed effects removed immediately
6. **Graceful Degradation**: Effect failures don't crash the pipeline

### Migration from Existing Fade Engine

The existing fade engine becomes a thin wrapper that creates crossfade effects:

```go
// Compatibility layer
func (e *Engine) FadeToLook(lookChannels []LookChannel, duration time.Duration, easingType EasingType) string {
    // Capture current values
    fromValues := e.captureCurrentState()

    // Build target values
    toValues := make(map[ChannelKey]int)
    for _, ch := range lookChannels {
        key := ChannelKey{Universe: ch.Universe, Channel: ch.Channel}
        toValues[key] = ch.Value
    }

    // Create and activate crossfade effect
    effect := CreateCrossfadeEffect(fromValues, toValues, duration, easingType)
    return e.addEffect(effect)
}
```

---

## Future Enhancements (Not in Scope)

- Audio-reactive effects (BPM sync, audio input)
- Custom waveform editor
- Effect macros/presets
- MIDI clock synchronization
- Effect groups with synchronized phase
