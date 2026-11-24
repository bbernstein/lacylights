# FX Engine Backend Implementation Plan

## Overview

This document provides a phased implementation plan for the FX Engine backend, organized to enable **early testing of cue fading** before building additional features. The plan ensures that:

1. Crossfade functionality is implemented and testable first
2. Existing fade engine behavior is preserved through a compatibility layer
3. Each phase builds on verified functionality
4. Frontend can test fading before any frontend FX UI is built

---

## Implementation Status

| Phase | Description | Status | Completion Date |
|-------|-------------|--------|-----------------|
| Phase 0 | Foundation Setup | ✅ Complete | 2026-01-14 |
| Phase 1 | Easing Migration | ✅ Complete | 2026-01-14 |
| Phase 2 | Effect Types and Structures | ✅ Complete | 2026-01-14 |
| Phase 3 | Crossfade Effect Implementation | ✅ Complete | 2026-01-14 |
| Phase 4 | Engine Update Loop | ✅ Complete | 2026-01-14 |
| Phase 5 | Compatibility Layer | ✅ Complete | 2026-01-14 |
| Phase 6 | Playback Service Integration | ✅ Complete | 2026-01-14 |
| Phase 7 | Integration Testing Milestone | ✅ Complete | 2026-01-14 |
| Phase 8 | Waveform Implementation | ✅ Complete | 2026-01-14 |
| Phase 9 | System Effects | ✅ Complete | 2026-01-14 |
| Phase 10 | Cue Transition System | ✅ Complete | 2026-01-14 |
| Phase 11 | Database Models and Migration | ✅ Complete | 2026-01-14 |
| Phase 12 | Effect Repository | ✅ Complete | 2026-01-14 |
| Phase 13 | GraphQL Schema and Resolvers | ✅ Complete | 2026-01-14 |
| Phase 14 | Final Integration | ✅ Complete | 2026-01-14 |

### Checkpoint Status

- ✅ **Checkpoint 1**: Foundation (End of Phase 2) - All core types compile, unit tests pass
- ✅ **Checkpoint 2**: Crossfade Works (End of Phase 5) - FadeToLook compatibility API works
- ✅ **Checkpoint 3**: Fading Integration (End of Phase 7) - **Frontend can test cue transitions**
- ✅ **Checkpoint 4**: Effects Work (End of Phase 10) - Waveforms, system effects, cue transitions
- ✅ **Checkpoint 5**: Persistence (End of Phase 13) - Database models, repository, GraphQL API
- ✅ **Checkpoint 6**: Complete (End of Phase 14) - All tests pass, ready for frontend integration

### Implementation Notes (Phases 0-7)

**Files Created**:
- `internal/services/modulator/types.go` - Core types (ChannelKey, ChannelState, FadeTransition)
- `internal/services/modulator/priority.go` - Priority bands (BASE → USER → CUE → SYSTEM)
- `internal/services/modulator/composition.go` - Composition modes (OVERRIDE, ADDITIVE, MULTIPLY)
- `internal/services/modulator/transition.go` - Transition behaviors (FADE_OUT, PERSIST, SNAP_OFF, CROSSFADE_PARAMS)
- `internal/services/modulator/easing.go` - Easing functions migrated from fade engine
- `internal/services/modulator/effects.go` - Effect and ActiveEffect types
- `internal/services/modulator/crossfade.go` - Crossfade calculation logic
- `internal/services/modulator/waveforms.go` - Waveform generation (SINE, COSINE, SQUARE, etc.)
- `internal/services/modulator/engine.go` - Main engine with 60Hz update loop
- `internal/services/modulator/fade_api.go` - Backward-compatible FadeToLook/FadeToBlack API

**Files Modified**:
- `internal/services/fade/easing.go` - Re-exports from modulator for backward compatibility
- `internal/services/playback/service.go` - Switched from fade to modulator engine
- `internal/graphql/resolvers/resolver.go` - Updated engine type
- `internal/graphql/resolvers/schema.resolvers.go` - Updated to use modulator types
- `cmd/server/main.go` - Creates modulator engine on startup

**Test Results**: 144+ tests passing in modulator package, all existing tests pass.

**Branch**: `feature/fx-engine-backend` (lacylights-go)

### Implementation Notes (Phases 8-14)

**Files Created (Phase 8-10)**:
- `internal/services/modulator/system_effects.go` - Blackout and grand master controls
- `internal/services/modulator/system_effects_test.go` - System effects tests
- `internal/services/modulator/cue_transition.go` - Cue transition lifecycle management
- `internal/services/modulator/cue_transition_test.go` - Cue transition tests

**Files Created (Phase 11-13)**:
- `internal/database/repositories/effect_repository.go` - Effect CRUD repository
- `internal/database/repositories/effect_repository_test.go` - Repository tests
- `internal/graphql/resolvers/effect_resolvers.go` - Effect GraphQL resolvers

**Files Modified (Phase 11-14)**:
- `internal/database/models/models.go` - Added Effect, EffectFixture, EffectChannel, CueEffect models
- `internal/database/models/models_test.go` - Added model table name tests
- `internal/graphql/schema/schema.graphql` - Added Effect types, queries, mutations
- `internal/graphql/resolvers/resolver.go` - Added EffectRepo to Resolver
- `internal/graphql/resolvers/schema.resolvers.go` - Implemented effect resolvers
- `internal/services/testutil/testutil.go` - Added effect models to test setup
- `cmd/server/main.go` - Added effect tables to AutoMigrate

**Test Results**: All tests pass, linter clean, all packages build successfully.

---

## Implementation Phases

### Phase 0: Foundation Setup (Day 1)
**Goal**: Create package structure and core types with no runtime behavior.

**Files to Create**:
```
lacylights-go/internal/services/modulator/
├── types.go        # Core types
├── priority.go     # Priority system
├── composition.go  # Composition modes
├── transition.go   # Transition behaviors
└── engine.go       # Engine struct (empty)
```

**Tasks**:

1. **Create `types.go`**:
   ```go
   package modulator

   // ChannelKey uniquely identifies a DMX channel
   type ChannelKey struct {
       Universe int
       Channel  int
   }

   // ChannelState tracks the current value and source
   type ChannelState struct {
       Value           int
       OwnerEffectID   string
       CompositionMode CompositionMode
   }

   // FadeTransition represents an ongoing intensity fade
   type FadeTransition struct {
       StartValue  float64
       EndValue    float64
       Duration    time.Duration
       StartTime   time.Time
       EasingType  EasingType
   }

   func (f *FadeTransition) CurrentValue() float64 { ... }
   func (f *FadeTransition) IsComplete() bool { ... }
   ```

2. **Create `priority.go`**:
   ```go
   type PriorityBand int

   const (
       PriorityBandBase   PriorityBand = 0
       PriorityBandUser   PriorityBand = 1
       PriorityBandCue    PriorityBand = 2
       PriorityBandSystem PriorityBand = 3
   )

   type EffectPriority struct {
       Band        PriorityBand
       SubPriority int // 0-100
   }

   func (p EffectPriority) Compare(other EffectPriority) int { ... }
   func (p EffectPriority) Less(other EffectPriority) bool { ... }
   ```

3. **Create `composition.go`**:
   ```go
   type CompositionMode string

   const (
       ComposeModeOverride  CompositionMode = "OVERRIDE"
       ComposeModeAdditive  CompositionMode = "ADDITIVE"
       ComposeModeMultiply  CompositionMode = "MULTIPLY"
   )

   func ApplyComposition(existing, effect int, mode CompositionMode) int { ... }
   ```

4. **Create `transition.go`**:
   ```go
   type TransitionBehavior string

   const (
       TransitionFadeOut        TransitionBehavior = "FADE_OUT"
       TransitionPersist        TransitionBehavior = "PERSIST"
       TransitionSnapOff        TransitionBehavior = "SNAP_OFF"
       TransitionCrossfadeParams TransitionBehavior = "CROSSFADE_PARAMS"
   )
   ```

5. **Create `engine.go`** (struct only):
   ```go
   type Engine struct {
       mu         sync.RWMutex
       dmxService *dmx.Service

       activeEffects []*ActiveEffect

       stopChan   chan struct{}
       doneChan   chan struct{}
       running    bool
       updateRate time.Duration
       lastUpdate time.Time

       onEffectComplete func(effectID string)
       onStateChange    func()
   }

   func New(dmxService *dmx.Service) *Engine { ... }
   ```

**Tests**:
- Unit tests for `EffectPriority.Compare()`
- Unit tests for `ApplyComposition()`
- Unit tests for `FadeTransition.CurrentValue()` and `IsComplete()`

**Verification**: `go test ./internal/services/modulator/...`

---

### Phase 1: Easing Migration (Day 1-2)
**Goal**: Migrate easing functions from fade engine to modulator.

**Files**:
```
lacylights-go/internal/services/modulator/easing.go
```

**Tasks**:

1. **Create `easing.go`**:
   - Copy/refactor easing types and functions from `fade/easing.go`
   - Add any missing easing types from PRD (S_CURVE, etc.)
   ```go
   type EasingType string

   const (
       EasingLinear           EasingType = "LINEAR"
       EasingInOutCubic       EasingType = "EASE_IN_OUT_CUBIC"
       EasingInOutSine        EasingType = "EASE_IN_OUT_SINE"
       EasingOutExponential   EasingType = "EASE_OUT_EXPONENTIAL"
       EasingBezier           EasingType = "BEZIER"
       EasingSCurve           EasingType = "S_CURVE"
   )

   func ApplyEasing(progress float64, easingType EasingType) float64 { ... }
   func Interpolate(start, end, progress float64, easingType EasingType) float64 { ... }
   ```

2. **Update fade engine** to import from modulator (temporary):
   ```go
   // In fade/easing.go
   import "lacylights-go/internal/services/modulator"

   // Re-export for backward compatibility
   type EasingType = modulator.EasingType
   const EasingLinear = modulator.EasingLinear
   // etc.
   ```

**Tests**:
- Unit tests for each easing function
- Verify existing fade engine tests still pass

**Verification**: `go test ./internal/services/fade/... ./internal/services/modulator/...`

---

### Phase 2: Effect Types and Structures (Day 2-3)
**Goal**: Define all effect types and the ActiveEffect structure.

**Files**:
```
lacylights-go/internal/services/modulator/effects.go
```

**Tasks**:

1. **Create `effects.go`**:
   ```go
   type EffectType string

   const (
       EffectTypeWaveform  EffectType = "WAVEFORM"
       EffectTypeCrossfade EffectType = "CROSSFADE"
       EffectTypeStatic    EffectType = "STATIC"
       EffectTypeMaster    EffectType = "MASTER"
   )

   type Effect struct {
       ID          string
       Name        string
       Description string
       ProjectID   string

       EffectType      EffectType
       Priority        EffectPriority
       CompositionMode CompositionMode
       OnCueChange     TransitionBehavior
       FadeDuration    *float64

       // For CROSSFADE
       EasingType EasingType

       // For WAVEFORM
       Waveform    WaveformType
       Frequency   float64
       Amplitude   float64
       Offset      float64
       PhaseOffset float64

       // Channel targets (loaded from DB)
       TargetChannels []EffectChannel
   }

   type ActiveEffect struct {
       Effect      *Effect
       StartTime   time.Time
       Intensity   float64
       Phase       float64

       // For crossfades
       FromValues map[ChannelKey]int
       ToValues   map[ChannelKey]int
       Duration   time.Duration

       // Intensity fading
       IntensityFade *FadeTransition

       // Calculated channel values (cached)
       channelValues map[ChannelKey]int
   }
   ```

2. **Add helper methods**:
   ```go
   func (e *Effect) Clone() *Effect { ... }
   func (a *ActiveEffect) IsComplete() bool { ... }
   func (a *ActiveEffect) GetProgress() float64 { ... }
   ```

**Tests**:
- Effect cloning preserves all fields
- ActiveEffect progress calculation
- ActiveEffect completion detection

---

### Phase 3: Crossfade Effect Implementation (Day 3-4)
**Goal**: Implement crossfade effect calculation - the core of cue transitions.

**Files**:
```
lacylights-go/internal/services/modulator/crossfade.go
```

**Tasks**:

1. **Create `crossfade.go`**:
   ```go
   // CreateCrossfadeEffect creates a crossfade from current state to target
   func CreateCrossfadeEffect(
       fromValues map[ChannelKey]int,
       toValues map[ChannelKey]int,
       duration time.Duration,
       easingType EasingType,
   ) *Effect { ... }

   // CalculateCrossfadeValues returns current interpolated values
   func (e *Engine) calculateCrossfadeValues(active *ActiveEffect) map[ChannelKey]int {
       elapsed := time.Since(active.StartTime)
       progress := elapsed.Seconds() / active.Duration.Seconds()
       progress = clamp(progress, 0, 1)

       easedProgress := ApplyEasing(progress, active.Effect.EasingType)

       values := make(map[ChannelKey]int)

       // Interpolate each channel
       for key, toValue := range active.ToValues {
           fromValue := 0
           if v, ok := active.FromValues[key]; ok {
               fromValue = v
           }
           values[key] = int(Interpolate(float64(fromValue), float64(toValue),
                                         easedProgress, EasingLinear))
       }

       // Handle channels in from but not in to (fade to 0)
       for key, fromValue := range active.FromValues {
           if _, inTo := active.ToValues[key]; !inTo {
               values[key] = int(Interpolate(float64(fromValue), 0,
                                             easedProgress, EasingLinear))
           }
       }

       return values
   }
   ```

2. **Add crossfade completion detection**:
   ```go
   func (a *ActiveEffect) isCrossfadeComplete() bool {
       if a.Effect.EffectType != EffectTypeCrossfade {
           return false
       }
       return time.Since(a.StartTime) >= a.Duration
   }
   ```

**Tests**:
- Crossfade progress at 0%, 50%, 100%
- Crossfade with different easing types
- Crossfade with channels only in from (fade out)
- Crossfade with channels only in to (fade in)
- Crossfade with overlapping channels

---

### Phase 4: Engine Update Loop (Day 4-5)
**Goal**: Implement the 60Hz update loop that processes all effects.

**Files**:
```
lacylights-go/internal/services/modulator/engine.go (update)
```

**Tasks**:

1. **Implement lifecycle methods**:
   ```go
   func (e *Engine) Start() error {
       e.mu.Lock()
       defer e.mu.Unlock()

       if e.running {
           return errors.New("engine already running")
       }

       e.stopChan = make(chan struct{})
       e.doneChan = make(chan struct{})
       e.running = true
       e.lastUpdate = time.Now()

       go e.updateLoop()
       return nil
   }

   func (e *Engine) Stop() error {
       e.mu.Lock()
       if !e.running {
           e.mu.Unlock()
           return nil
       }
       e.running = false
       close(e.stopChan)
       e.mu.Unlock()

       <-e.doneChan
       return nil
   }
   ```

2. **Implement update loop**:
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
   ```

3. **Implement effect processing**:
   ```go
   func (e *Engine) processModulation() {
       e.mu.Lock()
       defer e.mu.Unlock()

       now := time.Now()
       elapsed := now.Sub(e.lastUpdate)
       e.lastUpdate = now

       channelValues := make(map[ChannelKey]ChannelState)

       // Sort effects by priority (should already be sorted)
       // Process low to high priority
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

4. **Implement effect sorting**:
   ```go
   func (e *Engine) sortEffects() {
       sort.Slice(e.activeEffects, func(i, j int) bool {
           return e.activeEffects[i].Effect.Priority.Less(
               e.activeEffects[j].Effect.Priority)
       })
   }
   ```

**Tests**:
- Engine starts and stops cleanly
- Update loop runs at correct rate
- Effects processed in priority order
- Completed effects cleaned up

---

### Phase 5: Compatibility Layer (Day 5-6)
**Goal**: Implement FadeToLook and FadeToBlack for backward compatibility.

**Files**:
```
lacylights-go/internal/services/modulator/fade_api.go
```

**Tasks**:

1. **Create `fade_api.go`**:
   ```go
   // LookChannel matches the existing fade engine's LookChannel struct
   type LookChannel struct {
       Universe     int
       Channel      int
       TargetValue  int
       FadeBehavior string // FADE, SNAP, SNAP_END
   }

   // FadeToLook creates a crossfade effect to the specified look
   func (e *Engine) FadeToLook(channels []LookChannel, duration time.Duration, easingType EasingType) string {
       e.mu.Lock()
       defer e.mu.Unlock()

       // Capture current state as from values
       fromValues := e.captureCurrentState(channels)

       // Build target values
       toValues := make(map[ChannelKey]int)
       for _, ch := range channels {
           key := ChannelKey{Universe: ch.Universe, Channel: ch.Channel}
           toValues[key] = ch.TargetValue
       }

       // Remove any existing crossfades
       e.removeEffectsByType(EffectTypeCrossfade)

       // Create crossfade effect
       effect := CreateCrossfadeEffect(fromValues, toValues, duration, easingType)

       active := &ActiveEffect{
           Effect:     effect,
           StartTime:  time.Now(),
           Intensity:  100,
           FromValues: fromValues,
           ToValues:   toValues,
           Duration:   duration,
       }

       e.activeEffects = append(e.activeEffects, active)
       e.sortEffects()

       e.dmxService.ForceImmediateTransmission()

       return effect.ID
   }

   // FadeToBlack creates a crossfade to all zeros
   func (e *Engine) FadeToBlack(duration time.Duration) string {
       e.mu.Lock()
       defer e.mu.Unlock()

       // Capture current state
       fromValues := e.captureAllChannelState()

       // Target is all zeros
       toValues := make(map[ChannelKey]int)
       for key := range fromValues {
           toValues[key] = 0
       }

       // Remove any existing crossfades
       e.removeEffectsByType(EffectTypeCrossfade)

       effect := CreateCrossfadeEffect(fromValues, toValues, duration, EasingInOutSine)

       active := &ActiveEffect{
           Effect:     effect,
           StartTime:  time.Now(),
           Intensity:  100,
           FromValues: fromValues,
           ToValues:   toValues,
           Duration:   duration,
       }

       e.activeEffects = append(e.activeEffects, active)
       e.sortEffects()

       return effect.ID
   }

   // CancelFade removes a specific crossfade by ID
   func (e *Engine) CancelFade(fadeID string) {
       e.mu.Lock()
       defer e.mu.Unlock()

       e.removeEffectByID(fadeID)
   }

   func (e *Engine) captureCurrentState(channels []LookChannel) map[ChannelKey]int {
       values := make(map[ChannelKey]int)
       for _, ch := range channels {
           key := ChannelKey{Universe: ch.Universe, Channel: ch.Channel}
           values[key] = int(e.dmxService.GetChannelValue(ch.Universe, ch.Channel))
       }
       return values
   }
   ```

**Tests**:
- FadeToLook creates crossfade effect
- FadeToLook removes previous crossfade
- FadeToBlack fades all channels to 0
- CancelFade removes crossfade

---

### Phase 6: Playback Service Integration (Day 6-7)
**Goal**: Replace fade engine in playback service with modulator.

**Files**:
```
lacylights-go/internal/services/playback/service.go (modify)
```

**Tasks**:

1. **Add modulator to Service struct**:
   ```go
   type Service struct {
       // ... existing fields ...
       modulator  *modulator.Engine
       // fadeEngine *fade.Engine  // Keep temporarily for comparison
   }
   ```

2. **Update constructor**:
   ```go
   func New(db *gorm.DB, dmxService *dmx.Service, mod *modulator.Engine) *Service {
       return &Service{
           // ...
           modulator: mod,
       }
   }
   ```

3. **Update ExecuteCueDmx**:
   ```go
   func (s *Service) ExecuteCueDmx(ctx context.Context, cue *CueForPlayback, fadeInTime float64) error {
       // Build look channels (existing logic)
       channels := s.buildLookChannels(ctx, cue)

       // Convert to modulator LookChannel format
       modChannels := make([]modulator.LookChannel, len(channels))
       for i, ch := range channels {
           modChannels[i] = modulator.LookChannel{
               Universe:     ch.Universe,
               Channel:      ch.Channel,
               TargetValue:  ch.TargetValue,
               FadeBehavior: ch.FadeBehavior,
           }
       }

       // Use modulator instead of fade engine
       duration := time.Duration(fadeInTime * float64(time.Second))
       easing := modulator.EasingInOutSine
       if cue.EasingType != nil {
           easing = modulator.EasingType(*cue.EasingType)
       }

       s.modulator.FadeToLook(modChannels, duration, easing)

       s.dmxService.SetActiveLook(&cue.LookID)
       return nil
   }
   ```

4. **Update FadeToBlack call**:
   ```go
   func (s *Service) fadeToBlack(duration float64) {
       s.modulator.FadeToBlack(time.Duration(duration * float64(time.Second)))
   }
   ```

**Tests**:
- All existing playback tests pass
- ExecuteCueDmx creates crossfade in modulator
- Cue transitions work identically to before

---

### Phase 7: Integration Testing Milestone (Day 7-8)
**Goal**: Verify crossfade behavior matches existing fade engine.

**Testing Approach**:
1. Run existing cue transition tests
2. Add comparison tests that run both engines
3. Verify DMX output is identical

**Test Cases**:
- Simple look-to-look transition
- Look-to-black transition
- Black-to-look transition
- Multiple rapid cue transitions
- Cue transition during active fade
- Different easing types

**Verification**:
- Frontend can trigger cue transitions
- DMX output matches expected values
- Fade progress updates work correctly

**This is the "Fading Works" checkpoint - frontend testing can begin here.**

---

### Phase 8: Waveform Implementation (Day 8-10)
**Goal**: Implement waveform generation for LFO effects.

**Files**:
```
lacylights-go/internal/services/modulator/waveforms.go
```

**Tasks**:

1. **Create `waveforms.go`**:
   ```go
   type WaveformType string

   const (
       WaveformSine     WaveformType = "SINE"
       WaveformCosine   WaveformType = "COSINE"
       WaveformSquare   WaveformType = "SQUARE"
       WaveformSawtooth WaveformType = "SAWTOOTH"
       WaveformTriangle WaveformType = "TRIANGLE"
       WaveformRandom   WaveformType = "RANDOM"
   )

   // GenerateWaveform returns value 0-1 for given phase (0-360)
   func GenerateWaveform(phase float64, waveform WaveformType) float64 {
       // Normalize phase to 0-360
       phase = math.Mod(phase, 360)
       if phase < 0 {
           phase += 360
       }

       radians := phase * math.Pi / 180

       switch waveform {
       case WaveformSine:
           return (math.Sin(radians) + 1) / 2
       case WaveformCosine:
           return (math.Cos(radians) + 1) / 2
       case WaveformSquare:
           if phase < 180 {
               return 1
           }
           return 0
       case WaveformSawtooth:
           return phase / 360
       case WaveformTriangle:
           if phase < 180 {
               return phase / 180
           }
           return 2 - (phase / 180)
       case WaveformRandom:
           // Use phase as seed for deterministic random
           return deterministicRandom(phase)
       default:
           return 0.5
       }
   }

   // CalculateWaveformValues returns modulated channel values
   func (e *Engine) calculateWaveformValues(active *ActiveEffect, elapsed time.Duration) map[ChannelKey]int {
       effect := active.Effect

       // Update phase based on frequency and elapsed time
       degreesPerSecond := effect.Frequency * 360
       active.Phase += degreesPerSecond * elapsed.Seconds()
       active.Phase = math.Mod(active.Phase, 360)

       values := make(map[ChannelKey]int)

       for _, target := range effect.TargetChannels {
           // Calculate phase for this channel (including fixture offset)
           channelPhase := active.Phase + effect.PhaseOffset
           if target.PhaseOffset != nil {
               channelPhase += *target.PhaseOffset
           }

           // Generate waveform value (0-1)
           waveValue := GenerateWaveform(channelPhase, effect.Waveform)

           // Apply amplitude and offset
           // amplitude = modulation range (e.g., 50 means ±50% of 255)
           // offset = center point (e.g., 50% means center at 127)
           amplitude := effect.Amplitude / 100.0 * 255.0
           offset := effect.Offset / 100.0 * 255.0

           // Scale by intensity
           intensity := active.Intensity / 100.0

           // Calculate final value
           // waveValue is 0-1, convert to -1 to +1, then scale
           modulation := (waveValue - 0.5) * 2 * amplitude * intensity
           finalValue := int(offset + modulation)
           finalValue = clamp(finalValue, 0, 255)

           key := ChannelKey{Universe: target.Universe, Channel: target.Channel}
           values[key] = finalValue
       }

       return values
   }
   ```

**Tests**:
- Each waveform type produces correct shape
- Phase advances correctly over time
- Amplitude and offset applied correctly
- Per-fixture phase offset works

---

### Phase 9: System Effects (Day 10-11)
**Goal**: Implement blackout and grand master as SYSTEM priority effects.

**Files**:
```
lacylights-go/internal/services/modulator/system_effects.go
```

**Tasks**:

1. **Create `system_effects.go`**:
   ```go
   // BlackoutEffect is a system-level override that sets all channels to 0
   func CreateBlackoutEffect() *Effect {
       return &Effect{
           ID:              "system-blackout",
           Name:            "Blackout",
           EffectType:      EffectTypeStatic,
           Priority:        EffectPriority{Band: PriorityBandSystem, SubPriority: 100},
           CompositionMode: ComposeModeOverride,
           OnCueChange:     TransitionPersist,
       }
   }

   // GrandMasterEffect scales all intensity channels
   func CreateGrandMasterEffect(value float64) *Effect {
       return &Effect{
           ID:              "system-grand-master",
           Name:            "Grand Master",
           EffectType:      EffectTypeMaster,
           Priority:        EffectPriority{Band: PriorityBandSystem, SubPriority: 50},
           CompositionMode: ComposeModeMultiply,
           OnCueChange:     TransitionPersist,
           masterValue:     value, // 0.0-1.0
       }
   }

   // ActivateBlackout enables system blackout
   func (e *Engine) ActivateBlackout(fadeTime float64) {
       e.mu.Lock()
       defer e.mu.Unlock()

       // Check if blackout already active
       if e.isBlackoutActive() {
           return
       }

       effect := CreateBlackoutEffect()
       active := &ActiveEffect{
           Effect:    effect,
           StartTime: time.Now(),
           Intensity: 0,
       }

       // Fade in blackout
       if fadeTime > 0 {
           active.IntensityFade = &FadeTransition{
               StartValue: 0,
               EndValue:   100,
               Duration:   time.Duration(fadeTime * float64(time.Second)),
               StartTime:  time.Now(),
               EasingType: EasingInOutSine,
           }
       } else {
           active.Intensity = 100
       }

       e.activeEffects = append(e.activeEffects, active)
       e.sortEffects()
   }

   // ReleaseBlackout disables system blackout
   func (e *Engine) ReleaseBlackout(fadeTime float64) {
       e.mu.Lock()
       defer e.mu.Unlock()

       for _, active := range e.activeEffects {
           if active.Effect.ID == "system-blackout" {
               if fadeTime > 0 {
                   active.IntensityFade = &FadeTransition{
                       StartValue: active.Intensity,
                       EndValue:   0,
                       Duration:   time.Duration(fadeTime * float64(time.Second)),
                       StartTime:  time.Now(),
                       EasingType: EasingInOutSine,
                   }
               } else {
                   active.Intensity = 0
               }
               return
           }
       }
   }

   // SetGrandMaster sets the grand master level
   func (e *Engine) SetGrandMaster(value float64) {
       e.mu.Lock()
       defer e.mu.Unlock()

       // Find existing grand master
       for _, active := range e.activeEffects {
           if active.Effect.ID == "system-grand-master" {
               active.Effect.masterValue = value
               return
           }
       }

       // Create new grand master if not exists
       effect := CreateGrandMasterEffect(value)
       active := &ActiveEffect{
           Effect:    effect,
           StartTime: time.Now(),
           Intensity: 100,
       }

       e.activeEffects = append(e.activeEffects, active)
       e.sortEffects()
   }
   ```

2. **Implement static and master value calculation**:
   ```go
   func (e *Engine) calculateStaticValues(active *ActiveEffect) map[ChannelKey]int {
       // For blackout: return 0 for all universe channels
       if active.Effect.ID == "system-blackout" {
           values := make(map[ChannelKey]int)
           // Target all channels that have been set
           for key := range e.getActiveChannels() {
               values[key] = 0
           }
           return values
       }
       // ... handle other static effects
   }

   func (e *Engine) calculateMasterValues(active *ActiveEffect, existing map[ChannelKey]ChannelState) map[ChannelKey]int {
       values := make(map[ChannelKey]int)
       multiplier := active.Effect.masterValue

       for key, state := range existing {
           // Only apply to intensity-type channels
           if e.isIntensityChannel(key) {
               values[key] = int(float64(state.Value) * multiplier)
           }
       }
       return values
   }
   ```

**Tests**:
- Blackout overrides all other effects
- Grand master scales intensity channels
- Blackout fade in/out works
- Grand master persists across cues

---

### Phase 10: Cue Transition System (Day 11-13)
**Goal**: Implement full cue transition with effect lifecycle management.

**Files**:
```
lacylights-go/internal/services/modulator/cue_transition.go
```

**Tasks**:

1. **Create `cue_transition.go`**:
   ```go
   // ExecuteCueTransition handles full cue change including effect lifecycle
   func (e *Engine) ExecuteCueTransition(
       ctx context.Context,
       fromCue *models.Cue,
       toCue *models.Cue,
       fadeTime float64,
       easingType EasingType,
   ) error {
       e.mu.Lock()
       defer e.mu.Unlock()

       // Step 1: Handle existing USER effects based on transition behavior
       e.applyTransitionBehaviors(fadeTime, easingType, toCue)

       // Step 2: Capture current state for crossfade
       fromValues := e.captureCurrentDMXState()

       // Step 3: Build target values from new cue's looks
       toValues := e.buildCueTargetValues(ctx, toCue)

       // Step 4: Create and add crossfade effect
       e.removeEffectsByType(EffectTypeCrossfade)

       if len(toValues) > 0 || len(fromValues) > 0 {
           crossfade := CreateCrossfadeEffect(fromValues, toValues,
               time.Duration(fadeTime*float64(time.Second)), easingType)

           active := &ActiveEffect{
               Effect:     crossfade,
               StartTime:  time.Now(),
               Intensity:  100,
               FromValues: fromValues,
               ToValues:   toValues,
               Duration:   time.Duration(fadeTime * float64(time.Second)),
           }

           e.activeEffects = append(e.activeEffects, active)
       }

       // Step 5: Activate new cue's effects
       if toCue != nil {
           for _, cueEffect := range toCue.Effects {
               e.activateCueEffect(ctx, cueEffect, fadeTime, easingType)
           }
       }

       e.sortEffects()
       e.dmxService.ForceImmediateTransmission()

       return nil
   }

   func (e *Engine) applyTransitionBehaviors(fadeTime float64, easing EasingType, toCue *models.Cue) {
       for _, active := range e.activeEffects {
           if active.Effect.Priority.Band >= PriorityBandCue {
               continue // CUE and SYSTEM handled separately
           }

           behavior := active.Effect.OnCueChange

           switch behavior {
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
               // Do nothing

           case TransitionSnapOff:
               active.Intensity = 0

           case TransitionCrossfadeParams:
               if newParams := findEffectInCue(toCue, active.Effect.ID); newParams != nil {
                   e.crossfadeParams(active, newParams, fadeTime, easing)
               } else {
                   // Not in new cue, fade out
                   active.IntensityFade = &FadeTransition{
                       StartValue: active.Intensity,
                       EndValue:   0,
                       Duration:   time.Duration(fadeTime * float64(time.Second)),
                       StartTime:  time.Now(),
                       EasingType: easing,
                   }
               }
           }
       }
   }

   func (e *Engine) buildCueTargetValues(ctx context.Context, cue *models.Cue) map[ChannelKey]int {
       if cue == nil {
           return make(map[ChannelKey]int)
       }

       values := make(map[ChannelKey]int)

       // Sort looks by priority (lowest first so higher can override)
       looks := cue.Looks
       sort.Slice(looks, func(i, j int) bool {
           return looks[i].Priority < looks[j].Priority
       })

       for _, cueLook := range looks {
           look := loadLook(ctx, cueLook.LookID)
           for _, fv := range look.FixtureValues {
               for _, ch := range fv.Channels {
                   key := ChannelKey{
                       Universe: fv.Fixture.Universe,
                       Channel:  fv.Fixture.StartChannel + ch.Offset,
                   }
                   values[key] = ch.Value
               }
           }
       }

       return values
   }
   ```

**Tests**:
- All transition behaviors work correctly
- Multiple looks merge by priority
- Crossfade captures current state accurately
- New cue effects activate with fade in

---

### Phase 11: Database Models and Migration (Day 13-14)
**Goal**: Add database models for effects and run migration.

**Files**:
```
lacylights-go/internal/database/models/models.go (update)
lacylights-go/internal/database/migrations/XXX_add_effects.sql (new)
```

**Tasks**:

1. **Add models**:
   ```go
   type Effect struct {
       ID          string `gorm:"primaryKey"`
       Name        string
       Description string
       ProjectID   string

       EffectType      string `gorm:"default:'WAVEFORM'"`
       PriorityBand    string `gorm:"default:'USER'"`
       PrioritySub     int    `gorm:"default:50"`
       CompositionMode string `gorm:"default:'OVERRIDE'"`
       OnCueChange     string `gorm:"default:'FADE_OUT'"`
       FadeDuration    *float64

       EasingType  *string
       Waveform    *string
       Frequency   float64 `gorm:"default:1.0"`
       Amplitude   float64 `gorm:"default:100.0"`
       Offset      float64 `gorm:"default:50.0"`
       PhaseOffset float64 `gorm:"default:0.0"`

       Fixtures []EffectFixture

       CreatedAt time.Time
       UpdatedAt time.Time
   }

   type EffectFixture struct {
       ID        string `gorm:"primaryKey"`
       EffectID  string
       FixtureID string

       PhaseOffset    *float64
       AmplitudeScale *float64
       EffectOrder    *int

       Channels []EffectChannel
   }

   type EffectChannel struct {
       ID              string `gorm:"primaryKey"`
       EffectFixtureID string

       ChannelOffset *int
       ChannelType   *string

       AmplitudeScale *float64
       FrequencyScale *float64
   }

   type CueLook struct {
       ID       string `gorm:"primaryKey"`
       CueID    string
       LookID   string
       Priority int `gorm:"default:50"`

       CreatedAt time.Time
   }

   type CueEffect struct {
       ID        string `gorm:"primaryKey"`
       CueID     string
       EffectID  string

       Intensity   float64 `gorm:"default:100.0"`
       Speed       float64 `gorm:"default:1.0"`
       OnCueChange *string

       CreatedAt time.Time
   }
   ```

2. **Create migration file**

**Tests**:
- Models save and load correctly
- Relationships resolve
- Migration runs without errors

---

### Phase 12: Effect Repository (Day 14-15)
**Goal**: Create repository for effect CRUD operations.

**Files**:
```
lacylights-go/internal/database/repositories/effect_repository.go
```

**Tasks**:

1. **Create repository**:
   ```go
   type EffectRepository struct {
       db *gorm.DB
   }

   func NewEffectRepository(db *gorm.DB) *EffectRepository {
       return &EffectRepository{db: db}
   }

   func (r *EffectRepository) Create(effect *models.Effect) error { ... }
   func (r *EffectRepository) Update(effect *models.Effect) error { ... }
   func (r *EffectRepository) Delete(id string) error { ... }
   func (r *EffectRepository) FindByID(id string) (*models.Effect, error) { ... }
   func (r *EffectRepository) FindByProjectID(projectID string) ([]*models.Effect, error) { ... }
   func (r *EffectRepository) FindWithFixtures(id string) (*models.Effect, error) { ... }
   func (r *EffectRepository) AddFixture(effectID, fixtureID string, opts ...EffectFixtureOption) error { ... }
   func (r *EffectRepository) RemoveFixture(effectID, fixtureID string) error { ... }
   ```

**Tests**:
- All CRUD operations work
- Relationships loaded correctly
- Cascading deletes work

---

### Phase 13: GraphQL Schema and Resolvers (Day 15-17)
**Goal**: Add GraphQL API for effects.

**Files**:
```
lacylights-go/internal/graphql/schema/schema.graphql (update)
lacylights-go/internal/graphql/resolvers/effect_resolvers.go (new)
```

**Tasks**:

1. **Add schema definitions** (from PRD)
2. **Implement resolvers**:
   - Effect CRUD mutations
   - Effect fixture management
   - Playback control (activate, stop)
   - System controls (blackout, grand master)
   - Status queries and subscriptions

**Tests**:
- All queries return correct data
- Mutations create/update/delete correctly
- Subscriptions emit on state changes

---

### Phase 14: Final Integration (Day 17-18)
**Goal**: Remove fade engine dependency, final testing.

**Tasks**:

1. **Update all services** to use modulator only
2. **Remove fade engine package** (or deprecate)
3. **Update resolver initialization**
4. **Run full test suite**
5. **Performance testing**

---

## Testing Checkpoints

### Checkpoint 1: Foundation (End of Phase 2)
- All core types compile
- Unit tests pass for priority, composition, easing

### Checkpoint 2: Crossfade Works (End of Phase 5)
- Crossfade effect calculates correct values
- FadeToLook compatibility API works
- Can be called standalone for testing

### Checkpoint 3: Fading Integration (End of Phase 7)
- **Frontend can test cue transitions**
- Playback service uses modulator
- DMX output matches expected values
- All existing cue tests pass

### Checkpoint 4: Effects Work (End of Phase 10)
- Waveform effects modulate channels
- System effects (blackout, grand master) work
- Cue transitions handle effect lifecycle

### Checkpoint 5: Persistence (End of Phase 13)
- Effects save to database
- GraphQL API works
- Frontend can manage effects

### Checkpoint 6: Complete (End of Phase 14)
- All tests pass
- Performance verified
- Fade engine removed

---

## Risk Mitigation

### Performance Regression
- Benchmark crossfade against existing fade engine at Checkpoint 3
- Profile update loop under load

### Timing Precision
- Use monotonic clock (`time.Since()`)
- Test under concurrent load
- Verify 60Hz consistency

### State Corruption
- All state changes under mutex
- Clone effects before modification
- Comprehensive cleanup tests

### Migration Breakage
- Keep fade engine until Checkpoint 3 verified
- Run parallel for comparison testing
- Gradual rollout with feature flag

---

## Dependencies

### Phase Dependencies
```
Phase 0 (Foundation) ─┬─> Phase 1 (Easing)
                      │
                      └─> Phase 2 (Effects) ─> Phase 3 (Crossfade) ─> Phase 4 (Loop)
                                                                           │
                                                                           v
                      Phase 5 (Compat) ─> Phase 6 (Integration) ─> Phase 7 (TEST!)
                                                                           │
                                                                           v
                      Phase 8 (Waveforms) ─> Phase 9 (System) ─> Phase 10 (Transition)
                                                                           │
                                                                           v
                      Phase 11 (DB) ─> Phase 12 (Repo) ─> Phase 13 (GraphQL) ─> Phase 14 (Final)
```

### External Dependencies
- None - all Go standard library

---

## Success Metrics

1. **All existing fade tests pass** - No regression
2. **Crossfade timing within 1ms** - Precision maintained
3. **60Hz sustained with 100 effects** - Performance target
4. **Zero memory leaks** - Resource cleanup verified
5. **Frontend cue testing works at Checkpoint 3** - Early validation
