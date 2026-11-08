# FX Engine Documentation Index

## Overview

The FX Engine introduces a **Unified Modulator Architecture** that replaces the existing fade engine with a single, priority-based modulation pipeline. This documentation suite provides everything needed to implement, test, and extend the FX Engine.

---

## Document Map

| Document | Purpose | Audience |
|----------|---------|----------|
| [FX_ENGINE_PLAN.md](FX_ENGINE_PLAN.md) | Original feature plan with full architecture | All |
| [FX_ENGINE_PRD.md](FX_ENGINE_PRD.md) | Product Requirements Document for backend | Developers |
| [FX_ENGINE_BACKEND_IMPLEMENTATION.md](FX_ENGINE_BACKEND_IMPLEMENTATION.md) | Phased implementation plan | Backend developers |
| [FX_ENGINE_TESTING_PLAN.md](FX_ENGINE_TESTING_PLAN.md) | Unit and integration test specifications | QA/Testing |
| [FX_ENGINE_GRAPHQL_API.md](FX_ENGINE_GRAPHQL_API.md) | Complete GraphQL API contract | Frontend/Backend |

---

## Quick Start

### For Backend Development

1. Read [FX_ENGINE_PRD.md](FX_ENGINE_PRD.md) to understand the architecture
2. Follow [FX_ENGINE_BACKEND_IMPLEMENTATION.md](FX_ENGINE_BACKEND_IMPLEMENTATION.md) phase by phase
3. Write tests according to [FX_ENGINE_TESTING_PLAN.md](FX_ENGINE_TESTING_PLAN.md)

### For Frontend Integration

1. Review [FX_ENGINE_GRAPHQL_API.md](FX_ENGINE_GRAPHQL_API.md) for API contract
2. Wait for **Checkpoint 3** (fading integration) before testing cue transitions
3. See original [FX_ENGINE_PLAN.md](FX_ENGINE_PLAN.md) for UI component plans

### For Testing

1. Start with unit tests in [FX_ENGINE_TESTING_PLAN.md](FX_ENGINE_TESTING_PLAN.md)
2. Add integration tests to `lacylights-test/fx_engine/`
3. Follow manual testing checklist before release

---

## Key Concepts

### Everything is an Effect

The unified modulator treats **all DMX modulation as effects**:

- **Crossfade** = Effect that interpolates from state A to state B
- **Chase** = Waveform effect with phase offsets across fixtures
- **Blackout** = System effect that overrides all channels to 0
- **Look** = Static effect providing base channel values

### Priority Bands

```
SYSTEM (3)  - Blackout, Grand Master (always wins)
CUE (2)     - Crossfades during cue transitions
USER (1)    - User-activated effects (chase, pulse)
BASE (0)    - Static look values
```

### Composition Modes

- **OVERRIDE** - Higher priority replaces lower (default)
- **ADDITIVE** - Add modulation on top of base
- **MULTIPLY** - Scale existing value (grand master)

### Transition Behaviors

When a cue changes, each effect responds based on its behavior:
- **FADE_OUT** - Smooth fade to 0 (default)
- **PERSIST** - Continue unchanged
- **SNAP_OFF** - Immediate stop
- **CROSSFADE_PARAMS** - Smoothly transition parameters

---

## Implementation Checkpoints

| Checkpoint | Phase | Description | Frontend Can Test |
|------------|-------|-------------|-------------------|
| 1 | 0-2 | Foundation types compile | No |
| 2 | 3-5 | Crossfade works standalone | No |
| **3** | **6-7** | **Fading integration complete** | **Yes - cue transitions** |
| 4 | 8-10 | Effects work | Yes - waveform effects |
| 5 | 11-13 | Persistence complete | Yes - effect CRUD |
| 6 | 14 | Migration complete | Yes - full system |

**Checkpoint 3 is critical** - frontend can test cue transitions before any FX UI is built.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     GraphQL API Layer                           │
│         (effects, activeEffects, modulationStatus)              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    Unified Modulator Engine                     │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   60Hz Update Loop                          ││
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐            ││
│  │  │ SYSTEM │  │  CUE   │  │  USER  │  │  BASE  │            ││
│  │  │ Band   │  │ Band   │  │ Band   │  │ Band   │            ││
│  │  └────────┘  └────────┘  └────────┘  └────────┘            ││
│  │       │           │           │           │                 ││
│  │       └───────────┴───────────┴───────────┘                 ││
│  │                        │                                     ││
│  │                Priority-Ordered Processing                   ││
│  │                        │                                     ││
│  │                Composition Mode Resolution                   ││
│  │                        │                                     ││
│  │               Final DMX Channel Values                       ││
│  └────────────────────────┼────────────────────────────────────┘│
└───────────────────────────┼─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                      DMX Service                                │
│                   (Art-Net Output)                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure (Backend)

```
lacylights-go/
├── internal/
│   ├── services/
│   │   ├── modulator/           # NEW: Unified Modulator
│   │   │   ├── engine.go        # Core engine, 60Hz loop
│   │   │   ├── types.go         # ChannelKey, ChannelState, etc.
│   │   │   ├── priority.go      # PriorityBand, EffectPriority
│   │   │   ├── composition.go   # Composition mode resolution
│   │   │   ├── transition.go    # Transition behavior handling
│   │   │   ├── effects.go       # Effect struct, EffectType
│   │   │   ├── easing.go        # Easing functions
│   │   │   ├── waveforms.go     # Waveform generation
│   │   │   ├── crossfade.go     # CROSSFADE effect impl
│   │   │   ├── system_effects.go# Blackout, Grand Master
│   │   │   ├── cue_transition.go# Full cue change logic
│   │   │   ├── fade_api.go      # Compatibility layer
│   │   │   └── *_test.go        # Unit tests
│   │   ├── playback/            # MODIFY: Use modulator
│   │   └── fade/                # DEPRECATE: Replaced by modulator
│   ├── database/
│   │   ├── models/              # MODIFY: Add Effect models
│   │   ├── repositories/        # NEW: effect_repository.go
│   │   └── migrations/          # NEW: add_effects migration
│   └── graphql/
│       ├── schema/              # MODIFY: Add effect types
│       └── resolvers/           # NEW: effect_resolvers.go
```

---

## Test Structure

```
lacylights-go/
└── internal/services/modulator/*_test.go   # Unit tests

lacylights-test/
└── fx_engine/                              # Integration tests
    ├── crossfade_test.go
    ├── waveform_test.go
    ├── priority_test.go
    ├── composition_test.go
    ├── transition_test.go
    ├── system_effects_test.go
    ├── compatibility_test.go
    ├── performance_test.go
    └── graphql_test.go
```

---

## Success Criteria

| Metric | Target |
|--------|--------|
| Unit test coverage | ≥ 90% |
| Integration tests | 100% pass |
| Crossfade timing | ≤ 2ms variance |
| Update loop | 60Hz ± 1Hz |
| Memory stability | No leaks |
| Performance | 100 effects @ 60Hz |
| Backward compatibility | FadeToLook unchanged |

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-01-14 | 1.0 | Claude | Initial documentation suite |

---

## Related Documents

- [CHANNEL_FADE_BEHAVIOR_PLAN.md](CHANNEL_FADE_BEHAVIOR_PLAN.md) - Per-channel fade behavior
- [MOBILE_SCENE_BOARD_PLAN.md](MOBILE_SCENE_BOARD_PLAN.md) - Look board optimization
