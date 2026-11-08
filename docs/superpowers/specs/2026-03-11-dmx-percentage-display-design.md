# DMX Percentage Display Mode — Design Spec

**Date**: 2026-03-11
**Status**: Approved
**Scope**: lacylights-fe (frontend only)

## Problem

DMX values (0-255) are meaningful to lighting technicians but opaque to casual users. Many lighting consoles offer a percentage view (0-100%) as an alternative. LacyLights should support both display modes, controlled by a user preference.

## Design

### Display Modes

- **DMX mode** (default): Values shown as 0-255, current behavior preserved exactly.
- **Percent mode**: Values shown as 0.0%-100.0% with one decimal place, providing enough resolution to distinguish all 256 DMX values.

### Channel Type Awareness

Not all channels represent a continuum. Channels like GOBO, COLOR_WHEEL, EFFECT, and MACRO use discrete values where each number selects a specific option. Percentage display only applies to continuum channels.

**Continuum channels** (percentage applies):
INTENSITY, RED, GREEN, BLUE, WHITE, AMBER, UV, CYAN, MAGENTA, YELLOW, LIME, INDIGO, COLD_WHITE, WARM_WHITE, PAN, TILT, ZOOM, FOCUS, IRIS, STROBE

**Discrete channels** (always show raw DMX):
GOBO, COLOR_WHEEL, EFFECT, MACRO, OTHER

### Conversion Module — `utils/dmxPercentage.ts`

Single source of truth for all conversions. If the algorithm changes, only this file changes.

```typescript
// Core conversions
dmxToPercent(dmxValue: number): number        // 128 → 50.2
percentToDmx(percent: number): number         // 50.0 → 128 (rounded, clamped 0-255)
formatPercent(dmxValue: number): string        // 128 → "50.2%"
formatDmx(dmxValue: number): string            // 128 → "128"

// Channel type classification
isPercentageChannel(type: ChannelType): boolean

// Step sizes for keyboard/gesture input
percentStep(fine: boolean): number             // 1.0 (normal), 0.1 (shift)
dmxStep(fine: boolean): number                 // 1 (normal), 10 (shift)
```

### Settings Hook — `hooks/useDisplayMode.ts`

Follows the same pattern as `useScrollDirectionPreference`.

- **Storage**: localStorage, key `'lacylights-display-mode'`
- **Values**: `'dmx'` (default) | `'percent'`
- **Returns**: `{ displayMode, setDisplayMode, isDmxMode, isPercentMode }`

### Affected Components

| Component | Change |
|-----------|--------|
| **ChannelSlider** | Accepts `channelType` and `displayMode`. Continuum channels in percent mode: slider range 0.0-100.0, number input accepts/shows percentages, converts to DMX at boundary. Discrete channels always show raw DMX regardless of setting. |
| **ChannelListEditor** | Passes `channelType` and `displayMode` through to each ChannelSlider. |
| **MultiSelectControls** | Average value display respects mode per channel type. Merged sliders use percent range for continuum channels. |
| **useValueScrub** | Accepts display mode + channel type. In percent mode for continuum channels: normal step = 1.0%, shift step = 0.1%. DMX mode unchanged. |
| **Settings page** | New toggle: "Show values as percentages" with descriptive label. |

### NOT Affected

- **ColorPickerModal** — stays RGB 0-255 / hex (industry standard for color pickers).
- **Backend / GraphQL** — always works in raw DMX values. No schema changes.
- **LookEditorLayout** — internal state remains DMX number arrays (`Map<string, number[]>`).
- **channelConversion.ts** — sparse/dense conversion unchanged (operates on raw DMX).
- **colorConversion.ts / colorHelpers.ts** — unchanged.

### Data Flow

```
Display path:  DMX value (from state) → dmxToPercent() → render "50.2%"
Input path:    User types "50.0" → percentToDmx() → 128 → store as DMX
Slider path:   Slider at position 50.2 → percentToDmx(50.2) → 128 → onChange(128)
```

Conversion happens at the ChannelSlider boundary. All parent components and state management continue to work exclusively with DMX values.

### Keyboard/Gesture Behavior

| Input | DMX Mode | Percent Mode (continuum) | Percent Mode (discrete) |
|-------|----------|--------------------------|-------------------------|
| Arrow key | +/- 1 DMX | +/- 1.0% (~2.55 DMX) | +/- 1 DMX |
| Shift+Arrow | +/- 10 DMX | +/- 0.1% (~0.255 DMX) | +/- 10 DMX |
| Wheel scroll | 1 DMX per 2px | proportionally scaled | 1 DMX per 2px |
| Touch scrub | 1 DMX per 4px | proportionally scaled | 1 DMX per 4px |

### Edge Cases

- **Rounding**: `percentToDmx` rounds to nearest integer, clamped 0-255. Two different percentage inputs may map to the same DMX value — this is expected.
- **Custom min/max channels**: Some channel definitions have custom minValue/maxValue. Percentage should scale relative to the channel's actual range (e.g., if min=10, max=200, then 0% = 10, 100% = 200).
- **Zero preservation**: A value of 0 DMX always displays as 0.0%. A value of 255 always displays as 100.0%.

## Future Considerations (Out of Scope)

- **Option-based selectors**: Discrete channels (GOBO, COLOR_WHEEL, etc.) could show named options from fixture definitions instead of raw numbers. This would be a separate feature.
