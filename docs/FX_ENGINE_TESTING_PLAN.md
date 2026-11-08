# FX Engine Testing Plan

## Overview

This document defines the comprehensive testing strategy for the FX Engine Unified Modulator. Tests are organized by component, with specific focus on:

1. **Unit Tests** - Component-level verification in `lacylights-go`
2. **Integration Tests** - Cross-component verification in `lacylights-test`
3. **Manual Testing** - UI/UX verification with real hardware

---

## Test Organization

### Unit Tests (lacylights-go)

Located in `internal/services/modulator/*_test.go`

### Integration Tests (lacylights-test)

Located in `fx_engine/` directory:
```
lacylights-test/
├── fx_engine/
│   ├── crossfade_test.go       # Cue transition crossfades
│   ├── waveform_test.go        # LFO effect behavior
│   ├── priority_test.go        # Priority band resolution
│   ├── composition_test.go     # Composition mode behavior
│   ├── transition_test.go      # Effect lifecycle on cue change
│   ├── system_effects_test.go  # Blackout and grand master
│   ├── compatibility_test.go   # FadeToLook backward compat
│   ├── performance_test.go     # Load and timing tests
│   └── graphql_test.go         # GraphQL API contract tests
```

---

## Unit Test Specifications

### 1. Priority System Tests (`priority_test.go`)

```go
func TestPriorityBandOrdering(t *testing.T) {
    // Verify band ordering: BASE < USER < CUE < SYSTEM
    tests := []struct {
        name   string
        lower  PriorityBand
        higher PriorityBand
    }{
        {"BASE < USER", PriorityBandBase, PriorityBandUser},
        {"USER < CUE", PriorityBandUser, PriorityBandCue},
        {"CUE < SYSTEM", PriorityBandCue, PriorityBandSystem},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            p1 := EffectPriority{Band: tt.lower, SubPriority: 50}
            p2 := EffectPriority{Band: tt.higher, SubPriority: 50}
            assert.True(t, p1.Less(p2))
            assert.False(t, p2.Less(p1))
        })
    }
}

func TestSubPriorityWithinBand(t *testing.T) {
    // Verify sub-priority ordering within same band
    p1 := EffectPriority{Band: PriorityBandUser, SubPriority: 30}
    p2 := EffectPriority{Band: PriorityBandUser, SubPriority: 70}

    assert.True(t, p1.Less(p2))
    assert.False(t, p2.Less(p1))
}

func TestSubPriorityDoesNotOverrideBand(t *testing.T) {
    // High sub-priority in lower band still loses to low sub-priority in higher band
    userHigh := EffectPriority{Band: PriorityBandUser, SubPriority: 100}
    cueLow := EffectPriority{Band: PriorityBandCue, SubPriority: 0}

    assert.True(t, userHigh.Less(cueLow))
}

func TestPriorityEquality(t *testing.T) {
    p1 := EffectPriority{Band: PriorityBandUser, SubPriority: 50}
    p2 := EffectPriority{Band: PriorityBandUser, SubPriority: 50}

    assert.Equal(t, 0, p1.Compare(p2))
    assert.False(t, p1.Less(p2))
    assert.False(t, p2.Less(p1))
}
```

### 2. Composition Mode Tests (`composition_test.go`)

```go
func TestCompositionOverride(t *testing.T) {
    tests := []struct {
        existing    int
        effect      int
        expected    int
    }{
        {100, 200, 200},  // Effect completely replaces
        {255, 0, 0},      // Override to black
        {0, 128, 128},    // Override from black
    }

    for _, tt := range tests {
        result := ApplyComposition(tt.existing, tt.effect, ComposeModeOverride, true)
        assert.Equal(t, tt.expected, result)
    }
}

func TestCompositionAdditive(t *testing.T) {
    tests := []struct {
        name     string
        existing int
        effect   int
        expected int
    }{
        {"add to existing", 100, 50, 150},
        {"clamp at max", 200, 100, 255},
        {"add from zero", 0, 50, 50},
        {"negative clamped", 100, -50, 50}, // If negative effects supported
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := ApplyComposition(tt.existing, tt.effect, ComposeModeAdditive, true)
            assert.Equal(t, tt.expected, result)
        })
    }
}

func TestCompositionMultiply(t *testing.T) {
    tests := []struct {
        name     string
        existing int
        effect   int  // Treated as 0-255 = 0.0-1.0 multiplier
        expected int
    }{
        {"full multiply", 200, 255, 200},      // 200 * 1.0 = 200
        {"half multiply", 200, 127, 99},       // 200 * 0.5 ≈ 100
        {"zero multiply", 200, 0, 0},          // 200 * 0.0 = 0
        {"quarter multiply", 255, 64, 64},     // 255 * 0.25 ≈ 64
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := ApplyComposition(tt.existing, tt.effect, ComposeModeMultiply, true)
            // Allow ±1 for rounding
            assert.InDelta(t, tt.expected, result, 1)
        })
    }
}

func TestCompositionNoExistingValue(t *testing.T) {
    // When no existing value, effect becomes the value
    result := ApplyComposition(0, 128, ComposeModeAdditive, false)
    assert.Equal(t, 128, result)

    result = ApplyComposition(0, 128, ComposeModeMultiply, false)
    assert.Equal(t, 128, result)  // No existing to multiply
}
```

### 3. Easing Function Tests (`easing_test.go`)

```go
func TestEasingBoundaries(t *testing.T) {
    easings := []EasingType{
        EasingLinear, EasingInOutCubic, EasingInOutSine,
        EasingOutExponential, EasingSCurve,
    }

    for _, easing := range easings {
        t.Run(string(easing), func(t *testing.T) {
            // At progress 0, output should be 0
            assert.InDelta(t, 0.0, ApplyEasing(0, easing), 0.001)

            // At progress 1, output should be 1
            assert.InDelta(t, 1.0, ApplyEasing(1, easing), 0.001)
        })
    }
}

func TestEasingMonotonicity(t *testing.T) {
    // Easing functions should be monotonically increasing
    easings := []EasingType{
        EasingLinear, EasingInOutCubic, EasingInOutSine,
        EasingOutExponential, EasingSCurve,
    }

    for _, easing := range easings {
        t.Run(string(easing), func(t *testing.T) {
            prev := 0.0
            for p := 0.0; p <= 1.0; p += 0.1 {
                current := ApplyEasing(p, easing)
                assert.GreaterOrEqual(t, current, prev,
                    "easing should be monotonic at progress %.1f", p)
                prev = current
            }
        })
    }
}

func TestInterpolation(t *testing.T) {
    tests := []struct {
        start    float64
        end      float64
        progress float64
        expected float64
    }{
        {0, 100, 0.0, 0},
        {0, 100, 0.5, 50},
        {0, 100, 1.0, 100},
        {100, 0, 0.5, 50},  // Reverse
        {50, 200, 0.5, 125}, // Non-zero start
    }

    for _, tt := range tests {
        result := Interpolate(tt.start, tt.end, tt.progress, EasingLinear)
        assert.InDelta(t, tt.expected, result, 0.001)
    }
}
```

### 4. Waveform Generation Tests (`waveforms_test.go`)

```go
func TestSineWaveform(t *testing.T) {
    tests := []struct {
        phase    float64
        expected float64
    }{
        {0, 0.5},     // sin(0) = 0, normalized to 0.5
        {90, 1.0},    // sin(90°) = 1, normalized to 1.0
        {180, 0.5},   // sin(180°) = 0, normalized to 0.5
        {270, 0.0},   // sin(270°) = -1, normalized to 0.0
    }

    for _, tt := range tests {
        result := GenerateWaveform(tt.phase, WaveformSine)
        assert.InDelta(t, tt.expected, result, 0.01,
            "sine at phase %.0f°", tt.phase)
    }
}

func TestSquareWaveform(t *testing.T) {
    tests := []struct {
        phase    float64
        expected float64
    }{
        {0, 1.0},
        {89, 1.0},
        {90, 1.0},
        {179, 1.0},
        {180, 0.0},
        {270, 0.0},
        {359, 0.0},
    }

    for _, tt := range tests {
        result := GenerateWaveform(tt.phase, WaveformSquare)
        assert.Equal(t, tt.expected, result,
            "square at phase %.0f°", tt.phase)
    }
}

func TestSawtoothWaveform(t *testing.T) {
    tests := []struct {
        phase    float64
        expected float64
    }{
        {0, 0.0},
        {90, 0.25},
        {180, 0.5},
        {270, 0.75},
        {360, 0.0},  // Wraps
    }

    for _, tt := range tests {
        result := GenerateWaveform(tt.phase, WaveformSawtooth)
        assert.InDelta(t, tt.expected, result, 0.01,
            "sawtooth at phase %.0f°", tt.phase)
    }
}

func TestTriangleWaveform(t *testing.T) {
    tests := []struct {
        phase    float64
        expected float64
    }{
        {0, 0.0},
        {90, 0.5},
        {180, 1.0},
        {270, 0.5},
        {360, 0.0},
    }

    for _, tt := range tests {
        result := GenerateWaveform(tt.phase, WaveformTriangle)
        assert.InDelta(t, tt.expected, result, 0.01,
            "triangle at phase %.0f°", tt.phase)
    }
}

func TestPhaseNormalization(t *testing.T) {
    // Negative phases should wrap correctly
    assert.InDelta(t,
        GenerateWaveform(90, WaveformSine),
        GenerateWaveform(-270, WaveformSine),
        0.001)

    // Phases > 360 should wrap
    assert.InDelta(t,
        GenerateWaveform(90, WaveformSine),
        GenerateWaveform(450, WaveformSine),
        0.001)
}
```

### 5. Crossfade Calculation Tests (`crossfade_test.go`)

```go
func TestCrossfadeProgress(t *testing.T) {
    engine := NewTestEngine()

    fromValues := map[ChannelKey]int{
        {Universe: 1, Channel: 1}: 0,
        {Universe: 1, Channel: 2}: 255,
    }
    toValues := map[ChannelKey]int{
        {Universe: 1, Channel: 1}: 255,
        {Universe: 1, Channel: 2}: 0,
    }

    effect := CreateCrossfadeEffect(fromValues, toValues, time.Second, EasingLinear)
    active := &ActiveEffect{
        Effect:     effect,
        StartTime:  time.Now(),
        FromValues: fromValues,
        ToValues:   toValues,
        Duration:   time.Second,
        Intensity:  100,
    }

    // At start (t=0)
    values := engine.calculateCrossfadeValues(active)
    assert.Equal(t, 0, values[ChannelKey{1, 1}])
    assert.Equal(t, 255, values[ChannelKey{1, 2}])

    // Simulate time passage
    active.StartTime = time.Now().Add(-500 * time.Millisecond)
    values = engine.calculateCrossfadeValues(active)
    assert.InDelta(t, 127, values[ChannelKey{1, 1}], 2)
    assert.InDelta(t, 127, values[ChannelKey{1, 2}], 2)

    // At end (t=1s)
    active.StartTime = time.Now().Add(-time.Second)
    values = engine.calculateCrossfadeValues(active)
    assert.Equal(t, 255, values[ChannelKey{1, 1}])
    assert.Equal(t, 0, values[ChannelKey{1, 2}])
}

func TestCrossfadeNewChannels(t *testing.T) {
    // Channels in target but not in from should fade from 0
    fromValues := map[ChannelKey]int{}
    toValues := map[ChannelKey]int{
        {Universe: 1, Channel: 1}: 200,
    }

    engine := NewTestEngine()
    effect := CreateCrossfadeEffect(fromValues, toValues, time.Second, EasingLinear)
    active := &ActiveEffect{
        Effect:     effect,
        StartTime:  time.Now().Add(-500 * time.Millisecond),
        FromValues: fromValues,
        ToValues:   toValues,
        Duration:   time.Second,
        Intensity:  100,
    }

    values := engine.calculateCrossfadeValues(active)
    assert.InDelta(t, 100, values[ChannelKey{1, 1}], 2)  // Half of 200
}

func TestCrossfadeRemovedChannels(t *testing.T) {
    // Channels in from but not in to should fade to 0
    fromValues := map[ChannelKey]int{
        {Universe: 1, Channel: 1}: 200,
    }
    toValues := map[ChannelKey]int{}

    engine := NewTestEngine()
    effect := CreateCrossfadeEffect(fromValues, toValues, time.Second, EasingLinear)
    active := &ActiveEffect{
        Effect:     effect,
        StartTime:  time.Now().Add(-500 * time.Millisecond),
        FromValues: fromValues,
        ToValues:   toValues,
        Duration:   time.Second,
        Intensity:  100,
    }

    values := engine.calculateCrossfadeValues(active)
    assert.InDelta(t, 100, values[ChannelKey{1, 1}], 2)  // Half of 200 to 0

    // At completion, channel should be 0
    active.StartTime = time.Now().Add(-time.Second)
    values = engine.calculateCrossfadeValues(active)
    assert.Equal(t, 0, values[ChannelKey{1, 1}])
}

func TestCrossfadeWithEasing(t *testing.T) {
    // Verify different easing types produce different curves
    fromValues := map[ChannelKey]int{
        {Universe: 1, Channel: 1}: 0,
    }
    toValues := map[ChannelKey]int{
        {Universe: 1, Channel: 1}: 255,
    }

    engine := NewTestEngine()

    // At 50% progress, different easings should give different values
    easings := []EasingType{EasingLinear, EasingInOutSine, EasingInOutCubic}
    var values []int

    for _, easing := range easings {
        effect := CreateCrossfadeEffect(fromValues, toValues, time.Second, easing)
        active := &ActiveEffect{
            Effect:     effect,
            StartTime:  time.Now().Add(-500 * time.Millisecond),
            FromValues: fromValues,
            ToValues:   toValues,
            Duration:   time.Second,
            Intensity:  100,
        }
        vals := engine.calculateCrossfadeValues(active)
        values = append(values, vals[ChannelKey{1, 1}])
    }

    // Linear should be exactly 127-128
    assert.InDelta(t, 127, values[0], 2)

    // Non-linear should be different (not testing exact values,
    // just that they're different from linear)
    // In-out easings at 50% should actually be close to linear at midpoint
}
```

### 6. FadeTransition Tests (`fade_transition_test.go`)

```go
func TestFadeTransitionCurrentValue(t *testing.T) {
    fade := &FadeTransition{
        StartValue: 100,
        EndValue:   0,
        Duration:   time.Second,
        StartTime:  time.Now(),
        EasingType: EasingLinear,
    }

    // At start
    assert.InDelta(t, 100, fade.CurrentValue(), 1)

    // Simulate half-way
    fade.StartTime = time.Now().Add(-500 * time.Millisecond)
    assert.InDelta(t, 50, fade.CurrentValue(), 2)

    // At end
    fade.StartTime = time.Now().Add(-time.Second)
    assert.InDelta(t, 0, fade.CurrentValue(), 1)
}

func TestFadeTransitionIsComplete(t *testing.T) {
    fade := &FadeTransition{
        StartValue: 100,
        EndValue:   0,
        Duration:   time.Second,
        StartTime:  time.Now(),
        EasingType: EasingLinear,
    }

    assert.False(t, fade.IsComplete())

    fade.StartTime = time.Now().Add(-500 * time.Millisecond)
    assert.False(t, fade.IsComplete())

    fade.StartTime = time.Now().Add(-time.Second)
    assert.True(t, fade.IsComplete())

    // Beyond duration
    fade.StartTime = time.Now().Add(-2 * time.Second)
    assert.True(t, fade.IsComplete())
}
```

---

## Integration Test Specifications

### 1. Crossfade Integration Tests

```go
// crossfade_test.go

func TestBasicCueTransition(t *testing.T) {
    client := NewTestClient(t)
    ctx := context.Background()

    // Create project and fixtures
    project := client.CreateProject("Test Project")
    fixtures := client.CreateFixtures(project.ID, 4)  // 4 LED PARs

    // Create two looks
    lookA := client.CreateLook(project.ID, "Look A", map[string]int{
        fixtures[0].ID: 128,  // 50%
        fixtures[1].ID: 128,
        fixtures[2].ID: 128,
        fixtures[3].ID: 128,
    })

    lookB := client.CreateLook(project.ID, "Look B", map[string]int{
        fixtures[0].ID: 255,  // 100%
        fixtures[1].ID: 255,
        fixtures[2].ID: 255,
        fixtures[3].ID: 255,
    })

    // Create cue list
    cueList := client.CreateCueList(project.ID, "Test Cues")
    client.AddCue(cueList.ID, 1.0, lookA.ID, 2.0)  // 2s fade
    client.AddCue(cueList.ID, 2.0, lookB.ID, 2.0)

    // Start cue list at cue 1
    client.StartCueList(cueList.ID)

    // Verify initial state
    time.Sleep(100 * time.Millisecond)
    dmxValues := client.GetDMXValues(1)
    for _, fixture := range fixtures {
        assert.Equal(t, 128, dmxValues[fixture.StartChannel])
    }

    // Advance to cue 2
    client.NextCue(cueList.ID)

    // Check mid-fade (1 second in)
    time.Sleep(1 * time.Second)
    dmxValues = client.GetDMXValues(1)
    for _, fixture := range fixtures {
        // Should be approximately half-way between 128 and 255
        assert.InDelta(t, 191, dmxValues[fixture.StartChannel], 10)
    }

    // Check after fade complete
    time.Sleep(1100 * time.Millisecond)
    dmxValues = client.GetDMXValues(1)
    for _, fixture := range fixtures {
        assert.Equal(t, 255, dmxValues[fixture.StartChannel])
    }
}

func TestFadeInterruption(t *testing.T) {
    client := NewTestClient(t)

    // Setup similar to above...

    // Start fade to Look B
    client.NextCue(cueList.ID)

    // Interrupt mid-fade
    time.Sleep(500 * time.Millisecond)
    captured := client.GetDMXValues(1)[fixtures[0].StartChannel]

    // Go back to Look A
    client.PreviousCue(cueList.ID)

    // Verify fade starts from interrupted value, not from Look B's target
    time.Sleep(100 * time.Millisecond)
    current := client.GetDMXValues(1)[fixtures[0].StartChannel]

    // Should be fading from captured value toward Look A
    assert.True(t, current < captured || current == 128)
}

func TestEasingTypes(t *testing.T) {
    client := NewTestClient(t)

    easings := []string{"LINEAR", "EASE_IN_OUT_SINE", "EASE_IN_OUT_CUBIC"}

    for _, easing := range easings {
        t.Run(easing, func(t *testing.T) {
            // Create cue with specific easing
            cue := client.CreateCueWithEasing(cueList.ID, 1.0, look.ID, 1.0, easing)

            // Execute and sample values at intervals
            client.StartCue(cue.ID)

            samples := make([]int, 0)
            for i := 0; i < 10; i++ {
                time.Sleep(100 * time.Millisecond)
                samples = append(samples, client.GetDMXValues(1)[1])
            }

            // Verify samples are monotonically increasing
            for i := 1; i < len(samples); i++ {
                assert.GreaterOrEqual(t, samples[i], samples[i-1])
            }
        })
    }
}
```

### 2. Priority System Integration Tests

```go
// priority_test.go

func TestPriorityBandOverride(t *testing.T) {
    client := NewTestClient(t)

    // Create USER effect on channel 1
    userEffect := client.CreateEffect(project.ID, "User Chase", EffectTypeWaveform)
    client.AddEffectFixture(userEffect.ID, fixture.ID)
    client.ActivateEffect(userEffect.ID)

    // Verify effect is running
    time.Sleep(100 * time.Millisecond)
    status := client.GetModulationStatus()
    assert.Equal(t, 1, status.EffectsByBand.User)

    // Start cue transition (CUE band)
    client.NextCue(cueList.ID)

    // CUE crossfade should override USER effect output
    time.Sleep(50 * time.Millisecond)
    status = client.GetModulationStatus()
    assert.True(t, status.HasActiveCrossfade)

    // Verify channel state shows CUE as owner
    channelState := client.GetChannelState(1, 1)
    assert.Equal(t, PriorityBandCue, channelState.OwnerPriorityBand)
}

func TestBlackoutOverridesAll(t *testing.T) {
    client := NewTestClient(t)

    // Activate look
    client.ActivateLook(look.ID)
    time.Sleep(100 * time.Millisecond)
    assert.NotEqual(t, 0, client.GetDMXValues(1)[1])

    // Activate USER effect
    client.ActivateEffect(effect.ID)

    // Activate blackout
    client.ActivateBlackout(0)  // Instant

    // All channels should be 0
    time.Sleep(50 * time.Millisecond)
    dmxValues := client.GetDMXValues(1)
    for ch := 1; ch <= 10; ch++ {
        assert.Equal(t, 0, dmxValues[ch], "channel %d should be 0", ch)
    }

    // Verify effects still registered but output overridden
    status := client.GetModulationStatus()
    assert.True(t, status.BlackoutActive)
    assert.Greater(t, status.EffectsByBand.User, 0)

    // Release blackout
    client.ReleaseBlackout(0)
    time.Sleep(50 * time.Millisecond)

    // Values should return
    dmxValues = client.GetDMXValues(1)
    assert.NotEqual(t, 0, dmxValues[1])
}

func TestGrandMasterScaling(t *testing.T) {
    client := NewTestClient(t)

    // Activate look at full brightness
    client.ActivateLook(look.ID)
    time.Sleep(100 * time.Millisecond)
    fullValue := client.GetDMXValues(1)[1]

    // Set grand master to 50%
    client.SetGrandMaster(0.5)
    time.Sleep(50 * time.Millisecond)

    scaledValue := client.GetDMXValues(1)[1]
    assert.InDelta(t, fullValue*0.5, scaledValue, 2)

    // Set to 0%
    client.SetGrandMaster(0)
    time.Sleep(50 * time.Millisecond)
    assert.Equal(t, 0, client.GetDMXValues(1)[1])

    // Restore to 100%
    client.SetGrandMaster(1.0)
    time.Sleep(50 * time.Millisecond)
    assert.Equal(t, fullValue, client.GetDMXValues(1)[1])
}
```

### 3. Composition Mode Integration Tests

```go
// composition_test.go

func TestAdditiveEffectOnLook(t *testing.T) {
    client := NewTestClient(t)

    // Activate look with fixture at 50%
    look := client.CreateLook(project.ID, "Base", map[string]int{
        fixture.ID: 128,  // 50%
    })
    client.ActivateLook(look.ID)

    // Create additive pulse effect
    effect := client.CreateEffect(project.ID, "Pulse", EffectTypeWaveform)
    effect.CompositionMode = ComposeModeAdditive
    effect.Amplitude = 25  // ±25%
    client.UpdateEffect(effect)
    client.AddEffectFixture(effect.ID, fixture.ID)

    // Activate effect
    client.ActivateEffect(effect.ID)

    // Sample values over one cycle
    time.Sleep(100 * time.Millisecond)
    min, max := 255, 0
    for i := 0; i < 20; i++ {
        time.Sleep(50 * time.Millisecond)
        value := client.GetDMXValues(1)[fixture.StartChannel]
        if value < min {
            min = value
        }
        if value > max {
            max = value
        }
    }

    // Should oscillate around 128 ± 25%
    // Min should be around 128 - 64 = 64
    // Max should be around 128 + 64 = 192
    assert.InDelta(t, 64, min, 20)
    assert.InDelta(t, 192, max, 20)
}

func TestOverrideComposition(t *testing.T) {
    client := NewTestClient(t)

    // Create two USER effects on same channel
    effect1 := client.CreateEffect(project.ID, "Effect 1", EffectTypeStatic)
    effect1.PrioritySub = 30
    effect1.CompositionMode = ComposeModeOverride
    client.CreateStaticChannelValue(effect1.ID, fixture.ID, 100)

    effect2 := client.CreateEffect(project.ID, "Effect 2", EffectTypeStatic)
    effect2.PrioritySub = 70  // Higher sub-priority
    effect2.CompositionMode = ComposeModeOverride
    client.CreateStaticChannelValue(effect2.ID, fixture.ID, 200)

    // Activate both
    client.ActivateEffect(effect1.ID)
    client.ActivateEffect(effect2.ID)

    time.Sleep(100 * time.Millisecond)

    // Effect 2 should win (higher sub-priority)
    assert.Equal(t, 200, client.GetDMXValues(1)[fixture.StartChannel])
}
```

### 4. Transition Behavior Integration Tests

```go
// transition_test.go

func TestEffectFadeOutOnCueChange(t *testing.T) {
    client := NewTestClient(t)

    // Create effect with FADE_OUT behavior (default)
    effect := client.CreateEffect(project.ID, "Chase", EffectTypeWaveform)
    effect.OnCueChange = TransitionFadeOut
    client.UpdateEffect(effect)
    client.AddEffectFixture(effect.ID, fixture.ID)

    // Activate effect
    client.ActivateEffect(effect.ID, 100)  // 100% intensity
    time.Sleep(100 * time.Millisecond)

    // Get current effect intensity
    activeEffects := client.GetActiveEffects()
    assert.Equal(t, float64(100), activeEffects[0].Intensity)

    // Trigger cue change with 2s fade
    client.NextCue(cueList.ID)  // Cue has 2s fadeInTime

    // After 1 second, effect intensity should be ~50%
    time.Sleep(1 * time.Second)
    activeEffects = client.GetActiveEffects()
    foundEffect := false
    for _, ae := range activeEffects {
        if ae.EffectID == effect.ID {
            foundEffect = true
            assert.InDelta(t, 50, ae.Intensity, 10)
            assert.True(t, ae.IsFading)
        }
    }
    assert.True(t, foundEffect)

    // After fade completes, effect should be removed
    time.Sleep(1100 * time.Millisecond)
    activeEffects = client.GetActiveEffects()
    for _, ae := range activeEffects {
        assert.NotEqual(t, effect.ID, ae.EffectID)
    }
}

func TestEffectPersistAcrossCues(t *testing.T) {
    client := NewTestClient(t)

    // Create effect with PERSIST behavior
    effect := client.CreateEffect(project.ID, "Ambient", EffectTypeWaveform)
    effect.OnCueChange = TransitionPersist
    client.UpdateEffect(effect)

    // Activate
    client.ActivateEffect(effect.ID, 100)

    // Change cue
    client.NextCue(cueList.ID)

    // Effect should still be active at same intensity
    time.Sleep(500 * time.Millisecond)
    activeEffects := client.GetActiveEffects()
    found := false
    for _, ae := range activeEffects {
        if ae.EffectID == effect.ID {
            found = true
            assert.Equal(t, float64(100), ae.Intensity)
            assert.False(t, ae.IsFading)
        }
    }
    assert.True(t, found)
}

func TestEffectSnapOffOnCueChange(t *testing.T) {
    client := NewTestClient(t)

    // Create effect with SNAP_OFF behavior
    effect := client.CreateEffect(project.ID, "Strobe", EffectTypeWaveform)
    effect.OnCueChange = TransitionSnapOff
    client.UpdateEffect(effect)

    client.ActivateEffect(effect.ID, 100)
    time.Sleep(100 * time.Millisecond)

    // Verify active
    assert.Equal(t, 1, len(client.GetActiveEffects()))

    // Change cue
    client.NextCue(cueList.ID)

    // Effect should be immediately gone (no fade)
    time.Sleep(50 * time.Millisecond)
    activeEffects := client.GetActiveEffects()
    for _, ae := range activeEffects {
        assert.NotEqual(t, effect.ID, ae.EffectID)
    }
}

func TestEffectCrossfadeParams(t *testing.T) {
    client := NewTestClient(t)

    // Create effect
    effect := client.CreateEffect(project.ID, "Chase", EffectTypeWaveform)
    effect.OnCueChange = TransitionCrossfadeParams
    effect.Frequency = 1.0  // 1 Hz
    client.UpdateEffect(effect)

    // Create two cues using same effect with different parameters
    cue1 := client.CreateCueWithEffect(cueList.ID, 1.0, look.ID, 2.0, effect.ID, 100, 1.0)  // 100%, 1x speed
    cue2 := client.CreateCueWithEffect(cueList.ID, 2.0, look.ID, 2.0, effect.ID, 50, 2.0)   // 50%, 2x speed

    // Start at cue 1
    client.StartCueList(cueList.ID)
    time.Sleep(100 * time.Millisecond)

    // Verify initial parameters
    activeEffects := client.GetActiveEffects()
    assert.Equal(t, float64(100), activeEffects[0].Intensity)

    // Advance to cue 2
    client.NextCue(cueList.ID)

    // Parameters should be crossfading (not effect being replaced)
    time.Sleep(1 * time.Second)  // Half-way through 2s fade
    activeEffects = client.GetActiveEffects()
    assert.InDelta(t, 75, activeEffects[0].Intensity, 10)  // ~75% (between 100 and 50)
}
```

### 5. Waveform Effect Integration Tests

```go
// waveform_test.go

func TestChaseEffect(t *testing.T) {
    client := NewTestClient(t)

    // Create chase effect across 4 fixtures
    effect := client.CreateEffect(project.ID, "Chase", EffectTypeWaveform)
    effect.Waveform = WaveformSine
    effect.Frequency = 1.0
    effect.Amplitude = 100
    effect.Offset = 50
    client.UpdateEffect(effect)

    // Add fixtures with distributed phase
    for i, fixture := range fixtures {
        client.AddEffectFixture(effect.ID, fixture.ID)
        client.UpdateEffectFixture(effect.ID, fixture.ID, map[string]interface{}{
            "phaseOffset": float64(i) * 90,  // 0, 90, 180, 270
        })
    }

    // Activate
    client.ActivateEffect(effect.ID)

    // Sample at a specific moment
    time.Sleep(100 * time.Millisecond)
    dmx := client.GetDMXValues(1)

    // At t=0.1s with 1Hz, we're at phase ~36°
    // Each fixture should have different value based on its phase offset
    values := make([]int, 4)
    for i, fixture := range fixtures {
        values[i] = dmx[fixture.StartChannel]
    }

    // Values should all be different (chase pattern)
    assert.NotEqual(t, values[0], values[1])
    assert.NotEqual(t, values[1], values[2])
    assert.NotEqual(t, values[2], values[3])
}

func TestWaveformAmplitudeAndOffset(t *testing.T) {
    client := NewTestClient(t)

    // Create effect with 50% amplitude, 75% offset
    effect := client.CreateEffect(project.ID, "Pulse", EffectTypeWaveform)
    effect.Waveform = WaveformSine
    effect.Frequency = 2.0  // Fast for quick sampling
    effect.Amplitude = 50   // ±50% of 255 = ±127
    effect.Offset = 75      // Center at 75% of 255 = 191
    client.UpdateEffect(effect)
    client.AddEffectFixture(effect.ID, fixture.ID)

    client.ActivateEffect(effect.ID)

    // Sample over one cycle
    min, max := 255, 0
    for i := 0; i < 20; i++ {
        time.Sleep(25 * time.Millisecond)  // 500ms / 20 samples
        value := client.GetDMXValues(1)[fixture.StartChannel]
        if value < min {
            min = value
        }
        if value > max {
            max = value
        }
    }

    // Min should be around 191 - 127 = 64
    // Max should be around 191 + 127 = 255 (clamped)
    assert.InDelta(t, 64, min, 20)
    assert.InDelta(t, 255, max, 20)
}
```

### 6. Compatibility Layer Integration Tests

```go
// compatibility_test.go

func TestFadeToLookCompatibility(t *testing.T) {
    client := NewTestClient(t)

    // Use old fade API
    channels := []LookChannel{
        {Universe: 1, Channel: 1, TargetValue: 200, FadeBehavior: "FADE"},
        {Universe: 1, Channel: 2, TargetValue: 100, FadeBehavior: "FADE"},
    }

    fadeID := client.FadeToLook(channels, 1*time.Second, "EASE_IN_OUT_SINE")
    assert.NotEmpty(t, fadeID)

    // Verify crossfade effect was created
    status := client.GetModulationStatus()
    assert.True(t, status.HasActiveCrossfade)

    // Verify fade completes
    time.Sleep(1100 * time.Millisecond)
    dmx := client.GetDMXValues(1)
    assert.Equal(t, 200, dmx[1])
    assert.Equal(t, 100, dmx[2])
}

func TestFadeToBlackCompatibility(t *testing.T) {
    client := NewTestClient(t)

    // Set some values first
    client.SetDMXValue(1, 1, 255)
    client.SetDMXValue(1, 2, 255)

    fadeID := client.FadeToBlack(1 * time.Second)
    assert.NotEmpty(t, fadeID)

    // After fade, all should be 0
    time.Sleep(1100 * time.Millisecond)
    dmx := client.GetDMXValues(1)
    assert.Equal(t, 0, dmx[1])
    assert.Equal(t, 0, dmx[2])
}

func TestCancelFadeCompatibility(t *testing.T) {
    client := NewTestClient(t)

    channels := []LookChannel{
        {Universe: 1, Channel: 1, TargetValue: 255, FadeBehavior: "FADE"},
    }
    client.SetDMXValue(1, 1, 0)

    fadeID := client.FadeToLook(channels, 2*time.Second, "LINEAR")

    // Cancel mid-fade
    time.Sleep(500 * time.Millisecond)
    client.CancelFade(fadeID)

    capturedValue := client.GetDMXValues(1)[1]

    // Value should freeze (not continue to 255)
    time.Sleep(200 * time.Millisecond)
    assert.Equal(t, capturedValue, client.GetDMXValues(1)[1])
}
```

### 7. Performance Integration Tests

```go
// performance_test.go

func TestUpdateLoopTiming(t *testing.T) {
    client := NewTestClient(t)

    // Start engine
    assert.True(t, client.IsEngineRunning())

    // Measure update rate over 1 second
    startTime := time.Now()
    updateCount := 0

    // Subscribe to update events
    updates := client.SubscribeToUpdates()

    timeout := time.After(1 * time.Second)
    for {
        select {
        case <-updates:
            updateCount++
        case <-timeout:
            goto done
        }
    }

done:
    duration := time.Since(startTime)

    // Should be approximately 60 updates per second
    expectedUpdates := int(duration.Seconds() * 60)
    assert.InDelta(t, expectedUpdates, updateCount, 5)
}

func TestManyEffectsPerformance(t *testing.T) {
    client := NewTestClient(t)

    // Create 100 effects
    effects := make([]string, 100)
    for i := 0; i < 100; i++ {
        effect := client.CreateEffect(project.ID, fmt.Sprintf("Effect %d", i), EffectTypeWaveform)
        effect.Frequency = 0.5 + float64(i)*0.01  // Varying frequencies
        client.UpdateEffect(effect)
        client.AddEffectFixture(effect.ID, fixtures[i%len(fixtures)].ID)
        effects[i] = effect.ID
    }

    // Activate all effects
    startActivate := time.Now()
    for _, effectID := range effects {
        client.ActivateEffect(effectID, 100)
    }
    activateTime := time.Since(startActivate)

    // Activation should be fast (< 100ms total)
    assert.Less(t, activateTime, 100*time.Millisecond)

    // Verify all active
    status := client.GetModulationStatus()
    assert.Equal(t, 100, status.ActiveEffectCount)

    // Measure processing time for one cycle
    time.Sleep(100 * time.Millisecond)  // Let it stabilize

    // Sample DMX values rapidly
    startSample := time.Now()
    for i := 0; i < 100; i++ {
        _ = client.GetDMXValues(1)
        time.Sleep(10 * time.Millisecond)
    }
    sampleTime := time.Since(startSample)

    // Should complete in reasonable time
    assert.Less(t, sampleTime, 2*time.Second)

    // Clean up
    for _, effectID := range effects {
        client.StopEffect(effectID)
    }
}

func TestMemoryStability(t *testing.T) {
    client := NewTestClient(t)

    var m runtime.MemStats

    // Initial memory
    runtime.ReadMemStats(&m)
    initialAlloc := m.Alloc

    // Create and destroy effects repeatedly
    for i := 0; i < 100; i++ {
        effect := client.CreateEffect(project.ID, "Temp", EffectTypeWaveform)
        client.AddEffectFixture(effect.ID, fixture.ID)
        client.ActivateEffect(effect.ID)
        time.Sleep(10 * time.Millisecond)
        client.StopEffect(effect.ID)
        client.DeleteEffect(effect.ID)
    }

    // Force GC
    runtime.GC()
    runtime.ReadMemStats(&m)
    finalAlloc := m.Alloc

    // Memory should not grow significantly (< 10MB increase)
    memGrowth := finalAlloc - initialAlloc
    assert.Less(t, memGrowth, uint64(10*1024*1024))
}
```

### 8. GraphQL API Contract Tests

```go
// graphql_test.go

func TestEffectCRUD(t *testing.T) {
    client := NewGraphQLClient(t)

    // Create
    createResp := client.Mutation(`
        mutation {
            createEffect(input: {
                projectId: "%s"
                name: "Test Effect"
                effectType: WAVEFORM
                waveform: SINE
                frequency: 1.0
                amplitude: 100
            }) {
                id
                name
                effectType
                waveform
                frequency
                amplitude
            }
        }
    `, project.ID)

    assert.NotEmpty(t, createResp.Data.CreateEffect.ID)
    assert.Equal(t, "Test Effect", createResp.Data.CreateEffect.Name)
    assert.Equal(t, "WAVEFORM", createResp.Data.CreateEffect.EffectType)
    assert.Equal(t, 1.0, createResp.Data.CreateEffect.Frequency)

    effectID := createResp.Data.CreateEffect.ID

    // Read
    readResp := client.Query(`
        query {
            effect(id: "%s") {
                id
                name
                priorityBand
                compositionMode
            }
        }
    `, effectID)

    assert.Equal(t, effectID, readResp.Data.Effect.ID)
    assert.Equal(t, "USER", readResp.Data.Effect.PriorityBand)  // Default
    assert.Equal(t, "OVERRIDE", readResp.Data.Effect.CompositionMode)  // Default

    // Update
    updateResp := client.Mutation(`
        mutation {
            updateEffect(id: "%s", input: {
                frequency: 2.0
                compositionMode: ADDITIVE
            }) {
                id
                frequency
                compositionMode
            }
        }
    `, effectID)

    assert.Equal(t, 2.0, updateResp.Data.UpdateEffect.Frequency)
    assert.Equal(t, "ADDITIVE", updateResp.Data.UpdateEffect.CompositionMode)

    // Delete
    deleteResp := client.Mutation(`
        mutation {
            deleteEffect(id: "%s")
        }
    `, effectID)

    assert.True(t, deleteResp.Data.DeleteEffect)

    // Verify deleted
    verifyResp := client.Query(`
        query {
            effect(id: "%s") {
                id
            }
        }
    `, effectID)

    assert.Nil(t, verifyResp.Data.Effect)
}

func TestModulationStatusQuery(t *testing.T) {
    client := NewGraphQLClient(t)

    resp := client.Query(`
        query {
            modulationStatus {
                activeEffectCount
                effectsByBand {
                    base
                    user
                    cue
                    system
                }
                hasActiveCrossfade
                blackoutActive
                grandMasterValue
                updateRateHz
            }
        }
    `)

    assert.GreaterOrEqual(t, resp.Data.ModulationStatus.ActiveEffectCount, 0)
    assert.Equal(t, 60, resp.Data.ModulationStatus.UpdateRateHz)
    assert.Equal(t, float64(1.0), resp.Data.ModulationStatus.GrandMasterValue)
}

func TestActiveEffectsQuery(t *testing.T) {
    client := NewGraphQLClient(t)

    // Activate an effect first
    effect := createTestEffect(t, client)
    client.Mutation(`
        mutation {
            activateEffect(effectId: "%s", intensity: 80) {
                effectId
            }
        }
    `, effect.ID)

    time.Sleep(100 * time.Millisecond)

    resp := client.Query(`
        query {
            activeEffects {
                effectId
                effectName
                effectType
                priorityBand
                intensity
                isFading
            }
        }
    `)

    found := false
    for _, ae := range resp.Data.ActiveEffects {
        if ae.EffectID == effect.ID {
            found = true
            assert.Equal(t, float64(80), ae.Intensity)
            assert.False(t, ae.IsFading)
        }
    }
    assert.True(t, found)
}

func TestSystemControlMutations(t *testing.T) {
    client := NewGraphQLClient(t)

    // Blackout
    blackoutResp := client.Mutation(`
        mutation {
            activateBlackout(fadeTime: 0) {
                blackoutActive
            }
        }
    `)
    assert.True(t, blackoutResp.Data.ActivateBlackout.BlackoutActive)

    releaseResp := client.Mutation(`
        mutation {
            releaseBlackout(fadeTime: 0) {
                blackoutActive
            }
        }
    `)
    assert.False(t, releaseResp.Data.ReleaseBlackout.BlackoutActive)

    // Grand Master
    gmResp := client.Mutation(`
        mutation {
            setGrandMaster(value: 0.75) {
                grandMasterValue
            }
        }
    `)
    assert.Equal(t, 0.75, gmResp.Data.SetGrandMaster.GrandMasterValue)
}
```

---

## Manual Testing Checklist

### Basic Functionality

- [ ] Create project with fixtures
- [ ] Create look with multiple fixtures
- [ ] Create cue list with multiple cues
- [ ] Start cue list - verify look activates
- [ ] Advance cue - verify smooth crossfade
- [ ] Verify fade progress updates in UI
- [ ] Test different easing types visually

### Effect Creation

- [ ] Create sine wave effect
- [ ] Add fixtures to effect
- [ ] Set phase offsets for chase pattern
- [ ] Activate effect - verify oscillation
- [ ] Adjust frequency - verify speed change
- [ ] Adjust amplitude - verify modulation range
- [ ] Test different waveform types

### Priority and Composition

- [ ] Activate look + effect simultaneously
- [ ] Verify additive effect modulates look
- [ ] Trigger cue transition during effect
- [ ] Verify effect fades out during cue change
- [ ] Test PERSIST behavior - effect continues
- [ ] Test blackout - overrides everything
- [ ] Test grand master - scales intensity

### Edge Cases

- [ ] Rapid cue transitions (GO-GO-GO)
- [ ] Cue transition during active fade
- [ ] Effect activation during cue fade
- [ ] Multiple effects on same fixture
- [ ] Effect with 0 amplitude
- [ ] Effect with 0 frequency
- [ ] Very long fades (30+ seconds)
- [ ] Very short fades (< 100ms)

### Real Hardware

- [ ] Verify Art-Net output
- [ ] Check for flicker or jumps
- [ ] Verify timing precision with scope
- [ ] Test with multiple universes
- [ ] Test channel addressing

---

## Test Environment Setup

### Unit Tests

```bash
cd lacylights-go
go test ./internal/services/modulator/...
```

### Integration Tests

```bash
cd lacylights-test
# Start test server
cd ../lacylights-go && make test-server &

# Run integration tests
go test ./fx_engine/...
```

### Coverage Report

```bash
cd lacylights-go
go test -coverprofile=coverage.out ./internal/services/modulator/...
go tool cover -html=coverage.out
```

---

## Continuous Integration

Add to CI pipeline:

```yaml
jobs:
  test-fx-engine:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Unit Tests
        run: |
          cd lacylights-go
          go test -v -race ./internal/services/modulator/...

      - name: Integration Tests
        run: |
          cd lacylights-go
          make test-server &
          sleep 5
          cd ../lacylights-test
          go test -v ./fx_engine/...

      - name: Coverage
        run: |
          cd lacylights-go
          go test -coverprofile=coverage.out ./internal/services/modulator/...
          go tool cover -func=coverage.out | grep total
```

---

## Success Criteria

| Category | Target |
|----------|--------|
| Unit Test Coverage | ≥ 90% |
| Integration Tests Passing | 100% |
| Crossfade Timing Accuracy | ≤ 2ms variance |
| Update Loop Stability | 60Hz ± 1Hz |
| Memory Stability | No leaks over 1000 cycles |
| Performance | 100 effects @ 60Hz |
