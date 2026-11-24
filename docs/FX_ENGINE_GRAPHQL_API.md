# FX Engine GraphQL API Contract

## Overview

This document defines the complete GraphQL API contract for the FX Engine. All types, queries, mutations, and subscriptions are specified here for implementation reference.

---

## Enums

### EffectType

```graphql
"""
The type of effect, determining its calculation behavior.
"""
enum EffectType {
  """
  LFO-based continuous modulation using waveforms.
  """
  WAVEFORM

  """
  Interpolation between channel states over time.
  """
  CROSSFADE

  """
  Fixed channel values without modulation.
  """
  STATIC

  """
  Multiplier effect for intensity scaling (grand master).
  """
  MASTER
}
```

### PriorityBand

```graphql
"""
Priority bands determine the order in which effects are processed.
Higher bands override lower bands for the same channels.
"""
enum PriorityBand {
  """
  Lowest priority: static look values, default state.
  """
  BASE

  """
  User-activated effects: chase, pulse, color cycle.
  """
  USER

  """
  Cue transitions: crossfades between looks.
  """
  CUE

  """
  Highest priority: blackout, grand master, emergency.
  """
  SYSTEM
}
```

### CompositionMode

```graphql
"""
Determines how an effect combines with lower-priority effects
on the same channel.
"""
enum CompositionMode {
  """
  Effect completely replaces lower priority value.
  Default mode for most effects.
  """
  OVERRIDE

  """
  Effect adds its value to the existing value.
  Useful for chase pulses layered on base look.
  """
  ADDITIVE

  """
  Effect scales the existing value (0.0-1.0 multiplier).
  Used for grand master and dimmer curves.
  """
  MULTIPLY
}
```

### TransitionBehavior

```graphql
"""
Determines what happens to an effect when a cue change occurs.
"""
enum TransitionBehavior {
  """
  Effect fades intensity to 0 over the cue's fadeInTime.
  Default behavior for most effects.
  """
  FADE_OUT

  """
  Effect continues unchanged until explicitly stopped.
  Useful for ambient effects and blackout.
  """
  PERSIST

  """
  Effect stops immediately when cue changes.
  Useful for strobe and precise timing.
  """
  SNAP_OFF

  """
  Effect parameters smoothly transition to new values.
  Used when same effect continues with different intensity/speed.
  """
  CROSSFADE_PARAMS
}
```

### WaveformType

```graphql
"""
Waveform shape for WAVEFORM effects.
"""
enum WaveformType {
  """
  Smooth sinusoidal oscillation. Default.
  """
  SINE

  """
  Cosine wave (sine shifted 90°).
  """
  COSINE

  """
  On/off pulse wave.
  """
  SQUARE

  """
  Ramp up, snap down.
  """
  SAWTOOTH

  """
  Linear up and down.
  """
  TRIANGLE

  """
  Random values per cycle.
  """
  RANDOM
}
```

### EasingType

```graphql
"""
Easing function for crossfades and intensity fades.
"""
enum EasingType {
  """
  Constant rate, no acceleration.
  """
  LINEAR

  """
  Smooth acceleration and deceleration.
  """
  EASE_IN_OUT_CUBIC

  """
  Subtle smooth transition. Default for crossfades.
  """
  EASE_IN_OUT_SINE

  """
  Quick start, gradual finish.
  """
  EASE_OUT_EXPONENTIAL

  """
  Custom bezier curve (requires control points).
  """
  BEZIER

  """
  Extended ease-in and ease-out.
  """
  S_CURVE
}
```

### ChannelType

```graphql
"""
DMX channel type for targeting effects to specific channel categories.
"""
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
```

### PhaseDistribution

```graphql
"""
Pattern for distributing phase offsets across fixtures.
"""
enum PhaseDistribution {
  """
  Equal spacing: 0°, 90°, 180°, 270° for 4 fixtures.
  """
  LINEAR

  """
  Reverse: 270°, 180°, 90°, 0°.
  """
  REVERSE_LINEAR

  """
  Random phase assignments.
  """
  RANDOM

  """
  Paired: 0°, 0°, 180°, 180°.
  """
  PAIRS

  """
  Alternating: 0°, 180°, 0°, 180°.
  """
  ALTERNATING
}
```

---

## Types

### Effect

```graphql
"""
A lighting effect definition.
Effects can be waveform-based (LFO), crossfades, or static values.
"""
type Effect {
  """
  Unique identifier.
  """
  id: ID!

  """
  Human-readable name.
  """
  name: String!

  """
  Optional description.
  """
  description: String

  """
  Parent project.
  """
  project: Project!

  """
  Type determining calculation behavior.
  """
  effectType: EffectType!

  """
  Priority band for conflict resolution.
  """
  priorityBand: PriorityBand!

  """
  Sub-priority within band (0-100). Higher wins.
  """
  prioritySub: Int!

  """
  How effect combines with lower priority effects.
  """
  compositionMode: CompositionMode!

  """
  Behavior when cue changes.
  """
  onCueChange: TransitionBehavior!

  """
  Override fade duration (seconds). Null uses cue fadeInTime.
  """
  fadeDuration: Float

  """
  Easing function for CROSSFADE type effects.
  """
  easingType: EasingType

  """
  Waveform shape for WAVEFORM type effects.
  """
  waveform: WaveformType

  """
  Oscillation frequency in Hz. Default: 1.0
  """
  frequency: Float

  """
  Modulation range (0-100%). Default: 100
  """
  amplitude: Float

  """
  Center point (0-100%). Default: 50
  """
  offset: Float

  """
  Starting phase (0-360°). Default: 0
  """
  phaseOffset: Float

  """
  Fixtures targeted by this effect.
  """
  fixtures: [EffectFixture!]!

  """
  Creation timestamp.
  """
  createdAt: String!

  """
  Last update timestamp.
  """
  updatedAt: String!
}
```

### EffectFixture

```graphql
"""
A fixture instance within an effect, with per-fixture overrides.
"""
type EffectFixture {
  """
  Unique identifier.
  """
  id: ID!

  """
  The fixture instance.
  """
  fixture: FixtureInstance!

  """
  Phase offset override for this fixture (degrees).
  Null uses effect's phaseOffset.
  """
  phaseOffset: Float

  """
  Amplitude scale for this fixture (0-200%).
  Null uses 100%.
  """
  amplitudeScale: Float

  """
  Order for auto-phase distribution.
  """
  effectOrder: Int

  """
  Channels targeted within this fixture.
  """
  channels: [EffectChannel!]!
}
```

### EffectChannel

```graphql
"""
A channel targeted within an effect fixture.
Target by offset OR type (not both).
"""
type EffectChannel {
  """
  Unique identifier.
  """
  id: ID!

  """
  Specific DMX channel offset (0-based).
  Null if targeting by type.
  """
  channelOffset: Int

  """
  Channel type to target.
  Null if targeting by offset.
  """
  channelType: ChannelType

  """
  Amplitude scale for this channel (0-200%).
  Null uses effect's amplitude.
  """
  amplitudeScale: Float

  """
  Frequency scale for this channel.
  Null uses effect's frequency.
  """
  frequencyScale: Float
}
```

### ActiveEffectInfo

```graphql
"""
Information about a currently running effect.
"""
type ActiveEffectInfo {
  """
  Effect definition ID.
  """
  effectId: ID!

  """
  Effect name.
  """
  effectName: String!

  """
  Effect type.
  """
  effectType: EffectType!

  """
  Priority band.
  """
  priorityBand: PriorityBand!

  """
  Sub-priority within band.
  """
  prioritySub: Int!

  """
  Composition mode.
  """
  compositionMode: CompositionMode!

  """
  Current intensity (0-100%).
  """
  intensity: Float!

  """
  Whether intensity is currently fading.
  """
  isFading: Boolean!

  """
  Fade progress if fading (0-100%).
  """
  fadeProgress: Float

  """
  Number of channels being modulated.
  """
  targetChannelCount: Int!

  """
  Effect start time.
  """
  startedAt: String!
}
```

### ChannelStateInfo

```graphql
"""
Detailed information about a single DMX channel's current state.
"""
type ChannelStateInfo {
  """
  DMX universe number.
  """
  universe: Int!

  """
  DMX channel number (1-512).
  """
  channel: Int!

  """
  Final computed value (0-255).
  """
  finalValue: Int!

  """
  ID of effect that set the final value.
  """
  ownerEffectId: ID

  """
  Name of effect that set the final value.
  """
  ownerEffectName: String

  """
  Composition mode used for final value.
  """
  compositionMode: CompositionMode

  """
  All effects contributing to this channel.
  """
  contributingEffects: [ContributingEffect!]!
}
```

### ContributingEffect

```graphql
"""
An effect contributing to a channel's value.
"""
type ContributingEffect {
  """
  Effect ID.
  """
  effectId: ID!

  """
  Effect name.
  """
  effectName: String!

  """
  Raw value before composition.
  """
  rawValue: Int!

  """
  Composition mode of this effect.
  """
  compositionMode: CompositionMode!
}
```

### ModulationStatus

```graphql
"""
Overall status of the modulation engine.
"""
type ModulationStatus {
  """
  Total number of active effects.
  """
  activeEffectCount: Int!

  """
  Count of effects by priority band.
  """
  effectsByBand: EffectsByBand!

  """
  Whether a crossfade is currently in progress.
  """
  hasActiveCrossfade: Boolean!

  """
  Crossfade progress if active (0-100%).
  """
  crossfadeProgress: Float

  """
  Whether system blackout is active.
  """
  blackoutActive: Boolean!

  """
  Current grand master level (0.0-1.0).
  """
  grandMasterValue: Float!

  """
  Engine update rate in Hz.
  """
  updateRateHz: Int!
}
```

### EffectsByBand

```graphql
"""
Count of effects in each priority band.
"""
type EffectsByBand {
  base: Int!
  user: Int!
  cue: Int!
  system: Int!
}
```

### CueLook

```graphql
"""
A look attached to a cue with priority ordering.
"""
type CueLook {
  """
  Unique identifier.
  """
  id: ID!

  """
  The look.
  """
  look: Look!

  """
  Priority within the cue (0-100). Higher wins on overlap.
  """
  priority: Int!
}
```

### CueEffect

```graphql
"""
An effect attached to a cue with runtime overrides.
"""
type CueEffect {
  """
  Unique identifier.
  """
  id: ID!

  """
  The effect definition.
  """
  effect: Effect!

  """
  Intensity override (0-100%).
  """
  intensity: Float!

  """
  Speed multiplier.
  """
  speed: Float!

  """
  Override transition behavior. Null uses effect's default.
  """
  onCueChangeOverride: TransitionBehavior
}
```

---

## Extended Cue Type

```graphql
"""
Extended Cue type with multiple looks and effects support.
"""
type Cue {
  id: ID!
  name: String!
  cueNumber: Float!
  cueList: CueList!

  """
  Primary look (deprecated - use looks field).
  """
  look: Look @deprecated(reason: "Use looks field for multiple looks")

  """
  Multiple looks with priority ordering.
  """
  looks: [CueLook!]!

  """
  Effects attached to this cue.
  """
  effects: [CueEffect!]!

  fadeInTime: Float!
  fadeOutTime: Float!
  followTime: Float
  easingType: EasingType
  notes: String
  skip: Boolean!
  createdAt: String!
  updatedAt: String!
}
```

---

## Queries

```graphql
type Query {
  # ============================================
  # Effect Definition Queries
  # ============================================

  """
  List all effects in a project.
  """
  effects(
    projectId: ID!
    """
    Filter by effect type.
    """
    effectType: EffectType
    """
    Filter by priority band.
    """
    priorityBand: PriorityBand
  ): [Effect!]!

  """
  Get a single effect by ID.
  """
  effect(id: ID!): Effect

  # ============================================
  # Runtime State Queries
  # ============================================

  """
  Get all currently active effects.
  """
  activeEffects: [ActiveEffectInfo!]!

  """
  Get detailed state for a specific DMX channel.
  """
  channelState(universe: Int!, channel: Int!): ChannelStateInfo!

  """
  Get overall modulation engine status.
  """
  modulationStatus: ModulationStatus!
}
```

---

## Mutations

### Effect CRUD

```graphql
type Mutation {
  # ============================================
  # Effect CRUD
  # ============================================

  """
  Create a new effect.
  """
  createEffect(input: CreateEffectInput!): Effect!

  """
  Update an existing effect.
  """
  updateEffect(id: ID!, input: UpdateEffectInput!): Effect!

  """
  Delete an effect. Fails if effect is currently active.
  """
  deleteEffect(id: ID!): Boolean!

  """
  Duplicate an effect with a new name.
  """
  duplicateEffect(id: ID!, name: String!): Effect!

  # ============================================
  # Effect Fixture Management
  # ============================================

  """
  Add a single fixture to an effect.
  """
  addFixtureToEffect(
    effectId: ID!
    fixtureId: ID!
    input: EffectFixtureInput
  ): EffectFixture!

  """
  Add multiple fixtures to an effect with a channel type filter.
  """
  addFixturesToEffect(
    effectId: ID!
    fixtureIds: [ID!]!
    """
    Only target channels of this type.
    """
    channelType: ChannelType
  ): [EffectFixture!]!

  """
  Remove a fixture from an effect.
  """
  removeFixtureFromEffect(effectId: ID!, fixtureId: ID!): Boolean!

  """
  Update fixture-specific settings in an effect.
  """
  updateEffectFixture(id: ID!, input: UpdateEffectFixtureInput!): EffectFixture!

  """
  Distribute phase offsets across all fixtures in an effect.
  """
  distributePhase(effectId: ID!, distribution: PhaseDistribution!): [EffectFixture!]!

  # ============================================
  # Effect Channel Management
  # ============================================

  """
  Add a channel to an effect fixture.
  """
  addChannelToEffectFixture(
    effectFixtureId: ID!
    input: EffectChannelInput!
  ): EffectChannel!

  """
  Remove a channel from an effect fixture.
  """
  removeChannelFromEffectFixture(id: ID!): Boolean!

  # ============================================
  # Playback Control
  # ============================================

  """
  Activate an effect at specified intensity.
  """
  activateEffect(
    effectId: ID!
    """
    Initial intensity (0-100%). Default: 100
    """
    intensity: Float
    """
    Fade-in time in seconds. Default: 0 (instant)
    """
    fadeTime: Float
  ): ActiveEffectInfo!

  """
  Stop a running effect.
  """
  stopEffect(
    effectId: ID!
    """
    Fade-out time in seconds. Default: 0 (instant)
    """
    fadeTime: Float
  ): Boolean!

  """
  Update parameters of a running effect.
  """
  updateEffectParameters(
    effectId: ID!
    params: EffectParametersInput!
  ): ActiveEffectInfo!

  # ============================================
  # System Controls
  # ============================================

  """
  Activate system blackout (overrides all effects).
  """
  activateBlackout(
    """
    Fade time in seconds. Default: 0 (instant)
    """
    fadeTime: Float
  ): ModulationStatus!

  """
  Release system blackout.
  """
  releaseBlackout(
    """
    Fade time in seconds. Default: 0 (instant)
    """
    fadeTime: Float
  ): ModulationStatus!

  """
  Set grand master level.
  """
  setGrandMaster(
    """
    Grand master value (0.0-1.0).
    """
    value: Float!
  ): ModulationStatus!

  # ============================================
  # Cue Look Management
  # ============================================

  """
  Add a look to a cue with priority.
  """
  addLookToCue(
    cueId: ID!
    lookId: ID!
    """
    Priority within cue (0-100). Default: 50
    """
    priority: Int
  ): CueLook!

  """
  Remove a look from a cue.
  """
  removeLookFromCue(cueId: ID!, lookId: ID!): Boolean!

  """
  Update look priority in a cue.
  """
  updateCueLookPriority(cueId: ID!, lookId: ID!, priority: Int!): CueLook!

  # ============================================
  # Cue Effect Management
  # ============================================

  """
  Add an effect to a cue.
  """
  addEffectToCue(
    cueId: ID!
    effectId: ID!
    input: CueEffectInput
  ): CueEffect!

  """
  Remove an effect from a cue.
  """
  removeEffectFromCue(cueId: ID!, effectId: ID!): Boolean!

  """
  Update effect parameters in a cue.
  """
  updateCueEffect(cueId: ID!, effectId: ID!, input: UpdateCueEffectInput!): CueEffect!

  # ============================================
  # Bulk Operations
  # ============================================

  """
  Create multiple effects in one operation.
  """
  bulkCreateEffects(effects: [CreateEffectInput!]!): [Effect!]!

  """
  Delete multiple effects. Returns count of deleted.
  """
  bulkDeleteEffects(ids: [ID!]!, confirmDelete: Boolean!): BulkDeleteResult!
}
```

---

## Subscriptions

```graphql
type Subscription {
  """
  Subscribe to active effects list changes.
  Emits when effects are activated, stopped, or parameters change.
  """
  activeEffectsUpdated: [ActiveEffectInfo!]!

  """
  Subscribe to modulation engine status changes.
  Emits on crossfade progress, blackout toggle, etc.
  """
  modulationStatusUpdated: ModulationStatus!

  """
  Subscribe to specific channel state changes.
  Useful for debugging effect behavior.
  """
  channelStateUpdated(universe: Int!, channel: Int!): ChannelStateInfo!
}
```

---

## Input Types

```graphql
input CreateEffectInput {
  name: String!
  description: String
  projectId: ID!

  effectType: EffectType = WAVEFORM
  priorityBand: PriorityBand = USER
  prioritySub: Int = 50
  compositionMode: CompositionMode = OVERRIDE
  onCueChange: TransitionBehavior = FADE_OUT
  fadeDuration: Float

  easingType: EasingType
  waveform: WaveformType = SINE
  frequency: Float = 1.0
  amplitude: Float = 100.0
  offset: Float = 50.0
  phaseOffset: Float = 0.0
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
  """
  Target by DMX offset (0-based).
  """
  channelOffset: Int
  """
  Target by channel type.
  """
  channelType: ChannelType
  amplitudeScale: Float
  frequencyScale: Float
}

input EffectParametersInput {
  """
  New intensity (0-100%).
  """
  intensity: Float
  """
  Speed multiplier.
  """
  speed: Float
  """
  New frequency in Hz.
  """
  frequency: Float
  """
  New amplitude (0-100%).
  """
  amplitude: Float
  """
  New offset (0-100%).
  """
  offset: Float
}

input CueEffectInput {
  """
  Initial intensity (0-100%). Default: 100
  """
  intensity: Float = 100.0
  """
  Speed multiplier. Default: 1.0
  """
  speed: Float = 1.0
  """
  Override transition behavior.
  """
  onCueChangeOverride: TransitionBehavior
}

input UpdateCueEffectInput {
  intensity: Float
  speed: Float
  onCueChangeOverride: TransitionBehavior
}

type BulkDeleteResult {
  deletedCount: Int!
  failedIds: [ID!]!
}
```

---

## Example Queries and Mutations

### Create Waveform Effect

```graphql
mutation CreateChaseEffect {
  createEffect(input: {
    projectId: "proj_abc123"
    name: "4-Fixture Chase"
    description: "Sine wave chase across all pars"
    effectType: WAVEFORM
    priorityBand: USER
    compositionMode: ADDITIVE
    onCueChange: FADE_OUT
    waveform: SINE
    frequency: 1.0
    amplitude: 50
    offset: 50
  }) {
    id
    name
    effectType
    waveform
    frequency
    amplitude
  }
}
```

### Add Fixtures with Phase Distribution

```graphql
mutation AddFixturesWithPhase {
  addFixturesToEffect(
    effectId: "effect_xyz789"
    fixtureIds: ["fix_1", "fix_2", "fix_3", "fix_4"]
    channelType: INTENSITY
  ) {
    id
    fixture {
      name
    }
    effectOrder
  }
}

mutation DistributePhases {
  distributePhase(
    effectId: "effect_xyz789"
    distribution: LINEAR
  ) {
    id
    phaseOffset
  }
}
```

### Activate Effect with Fade

```graphql
mutation ActivateChase {
  activateEffect(
    effectId: "effect_xyz789"
    intensity: 80
    fadeTime: 2.0
  ) {
    effectId
    effectName
    intensity
    isFading
    fadeProgress
  }
}
```

### Query Modulation Status

```graphql
query GetStatus {
  modulationStatus {
    activeEffectCount
    effectsByBand {
      base
      user
      cue
      system
    }
    hasActiveCrossfade
    crossfadeProgress
    blackoutActive
    grandMasterValue
    updateRateHz
  }
}
```

### Query Channel State

```graphql
query DebugChannel {
  channelState(universe: 1, channel: 5) {
    finalValue
    ownerEffectName
    compositionMode
    contributingEffects {
      effectName
      rawValue
      compositionMode
    }
  }
}
```

### Add Effect to Cue

```graphql
mutation AddEffectToCue {
  addEffectToCue(
    cueId: "cue_123"
    effectId: "effect_xyz789"
    input: {
      intensity: 75
      speed: 1.5
      onCueChangeOverride: PERSIST
    }
  ) {
    id
    effect {
      name
    }
    intensity
    speed
    onCueChangeOverride
  }
}
```

### Subscribe to Active Effects

```graphql
subscription WatchEffects {
  activeEffectsUpdated {
    effectId
    effectName
    effectType
    intensity
    isFading
    fadeProgress
  }
}
```

---

## Error Codes

| Code | Message | Description |
|------|---------|-------------|
| `EFFECT_NOT_FOUND` | Effect not found | The specified effect ID does not exist |
| `EFFECT_ACTIVE` | Effect is currently active | Cannot delete an effect that is running |
| `FIXTURE_NOT_FOUND` | Fixture not found | The specified fixture ID does not exist |
| `INVALID_PRIORITY` | Invalid priority value | Priority must be 0-100 |
| `INVALID_PARAMETER` | Invalid parameter value | Parameter out of valid range |
| `CHANNEL_CONFLICT` | Channel already targeted | Channel is already in effect fixture |
| `PROJECT_MISMATCH` | Project mismatch | Effect and fixture belong to different projects |

---

## Migration Notes

### Cue.look → Cue.looks

The single `look` field on Cue is deprecated. New implementations should use the `looks` field which supports multiple looks with priority ordering.

**Migration path**:
1. Continue reading from `look` for backward compatibility
2. Write to both `look` (first look) and `looks` (all looks)
3. Eventually remove `look` field

### Existing Cue Mutations

The existing `createCue` and `updateCue` mutations should be extended to support the new fields:

```graphql
input CreateCueInput {
  # ... existing fields ...

  """
  Multiple looks with priorities. If provided, lookId is ignored.
  """
  looks: [CueLookInput!]

  """
  Effects to attach to the cue.
  """
  effects: [CueEffectInput!]
}

input CueLookInput {
  lookId: ID!
  priority: Int = 50
}
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01 | Initial API design |
