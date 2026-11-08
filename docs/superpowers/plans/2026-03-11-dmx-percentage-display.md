# DMX Percentage Display Mode — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user preference to display DMX channel values as percentages (0.0%-100.0%) instead of raw DMX (0-255) in the frontend, with channel-type awareness so discrete channels always show raw DMX.

**Architecture:** A new `utils/dmxPercentage.ts` module handles all conversions (single source of truth). A `hooks/useDisplayMode.ts` localStorage-backed hook provides the preference. ChannelSlider is the only component that performs conversions at the display/input boundary — all parent components continue to pass and receive raw DMX values.

**Tech Stack:** React, TypeScript, localStorage, Jest + React Testing Library

**Spec:** `docs/superpowers/specs/2026-03-11-dmx-percentage-display-design.md`

---

## Design Decision: Hook vs Prop Drilling

The spec describes ChannelListEditor and MultiSelectControls passing `displayMode` as a prop to ChannelSlider. Instead, **ChannelSlider calls `useDisplayMode()` directly**, which is simpler and avoids prop drilling through intermediate components. Parent components (ChannelListEditor, MultiSelectControls, LookEditorLayout) need zero changes — they continue to pass and receive raw DMX values. The hook is lightweight (reads localStorage once on mount), so calling it from each ChannelSlider instance is fine.

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/utils/dmxPercentage.ts` | Create | All DMX/percent conversion functions and channel type classification |
| `src/utils/__tests__/dmxPercentage.test.ts` | Create | Tests for conversion module |
| `src/hooks/useDisplayMode.ts` | Create | localStorage-backed display mode preference hook |
| `src/hooks/__tests__/useDisplayMode.test.ts` | Create | Tests for display mode hook |
| `src/components/ChannelSlider.tsx` | Modify | Add percentage display/input mode at the rendering boundary |
| `src/components/__tests__/ChannelSlider.test.tsx` | Modify | Add tests for percentage mode rendering and input |
| `src/hooks/useValueScrub.ts` | Modify | Accept step size override for percentage mode |
| `src/app/(main)/settings/page.tsx` | Modify | Add display mode toggle |
| `src/components/__tests__/MultiSelectControls.test.tsx` | Modify | Add useDisplayMode mock (ChannelSlider dependency) |
| `src/components/__tests__/LookEditorLayout.test.tsx` | Modify | Add useDisplayMode mock (ChannelSlider dependency) |
| `src/components/__tests__/ChannelListEditor.test.tsx` | Modify | Add useDisplayMode mock (ChannelSlider dependency) |

---

## Chunk 1: Conversion Module

### Task 1: Create `dmxPercentage.ts` conversion utility

**Files:**
- Create: `src/utils/dmxPercentage.ts`
- Test: `src/utils/__tests__/dmxPercentage.test.ts`

- [ ] **Step 1: Write failing tests for core conversions**

Create `src/utils/__tests__/dmxPercentage.test.ts`:

```typescript
import {
  dmxToPercent,
  percentToDmx,
  formatPercent,
  formatDmx,
  isPercentageChannel,
  percentStep,
  dmxStep,
} from '../dmxPercentage';
import { ChannelType } from '@/types';

describe('dmxPercentage', () => {
  describe('dmxToPercent', () => {
    it('converts 0 to 0', () => {
      expect(dmxToPercent(0)).toBe(0);
    });

    it('converts 255 to 100', () => {
      expect(dmxToPercent(255)).toBe(100);
    });

    it('converts 128 to approximately 50.2', () => {
      expect(dmxToPercent(128)).toBeCloseTo(50.2, 1);
    });

    it('converts 1 to approximately 0.4', () => {
      expect(dmxToPercent(1)).toBeCloseTo(0.4, 1);
    });

    it('handles custom min/max range', () => {
      // min=10, max=200: value 10 = 0%, value 200 = 100%
      expect(dmxToPercent(10, 10, 200)).toBe(0);
      expect(dmxToPercent(200, 10, 200)).toBe(100);
      expect(dmxToPercent(105, 10, 200)).toBe(50);
    });
  });

  describe('percentToDmx', () => {
    it('converts 0% to 0', () => {
      expect(percentToDmx(0)).toBe(0);
    });

    it('converts 100% to 255', () => {
      expect(percentToDmx(100)).toBe(255);
    });

    it('converts 50% to 128', () => {
      expect(percentToDmx(50)).toBe(128);
    });

    it('clamps above 100% to max', () => {
      expect(percentToDmx(110)).toBe(255);
    });

    it('clamps below 0% to min', () => {
      expect(percentToDmx(-5)).toBe(0);
    });

    it('rounds to nearest integer', () => {
      // 50.2% of 255 = 128.01 -> 128
      expect(percentToDmx(50.2)).toBe(128);
    });

    it('handles custom min/max range', () => {
      expect(percentToDmx(0, 10, 200)).toBe(10);
      expect(percentToDmx(100, 10, 200)).toBe(200);
      expect(percentToDmx(50, 10, 200)).toBe(105);
    });
  });

  describe('formatPercent', () => {
    it('formats 0 as "0.0%"', () => {
      expect(formatPercent(0)).toBe('0.0%');
    });

    it('formats 255 as "100.0%"', () => {
      expect(formatPercent(255)).toBe('100.0%');
    });

    it('formats 128 with one decimal', () => {
      expect(formatPercent(128)).toBe('50.2%');
    });
  });

  describe('formatDmx', () => {
    it('formats as integer string', () => {
      expect(formatDmx(128)).toBe('128');
    });
  });

  describe('isPercentageChannel', () => {
    it('returns true for intensity channels', () => {
      expect(isPercentageChannel(ChannelType.INTENSITY)).toBe(true);
    });

    it('returns true for color channels', () => {
      expect(isPercentageChannel(ChannelType.RED)).toBe(true);
      expect(isPercentageChannel(ChannelType.GREEN)).toBe(true);
      expect(isPercentageChannel(ChannelType.BLUE)).toBe(true);
      expect(isPercentageChannel(ChannelType.WHITE)).toBe(true);
      expect(isPercentageChannel(ChannelType.AMBER)).toBe(true);
    });

    it('returns true for position channels', () => {
      expect(isPercentageChannel(ChannelType.PAN)).toBe(true);
      expect(isPercentageChannel(ChannelType.TILT)).toBe(true);
    });

    it('returns true for optical channels', () => {
      expect(isPercentageChannel(ChannelType.ZOOM)).toBe(true);
      expect(isPercentageChannel(ChannelType.FOCUS)).toBe(true);
      expect(isPercentageChannel(ChannelType.IRIS)).toBe(true);
    });

    it('returns true for strobe', () => {
      expect(isPercentageChannel(ChannelType.STROBE)).toBe(true);
    });

    it('returns false for discrete channels', () => {
      expect(isPercentageChannel(ChannelType.GOBO)).toBe(false);
      expect(isPercentageChannel(ChannelType.COLOR_WHEEL)).toBe(false);
      expect(isPercentageChannel(ChannelType.EFFECT)).toBe(false);
      expect(isPercentageChannel(ChannelType.MACRO)).toBe(false);
      expect(isPercentageChannel(ChannelType.OTHER)).toBe(false);
    });
  });

  describe('formatPercent with custom range', () => {
    it('formats with custom min/max', () => {
      // min=10, max=200: value 105 = 50.0%
      expect(formatPercent(105, 10, 200)).toBe('50.0%');
    });
  });

  describe('percentStep', () => {
    it('returns 1.0 for normal step', () => {
      expect(percentStep(false)).toBe(1.0);
    });

    it('returns 0.1 for fine/shift step', () => {
      expect(percentStep(true)).toBe(0.1);
    });
  });

  describe('dmxStep', () => {
    it('returns 1 for normal step', () => {
      expect(dmxStep(false)).toBe(1);
    });

    it('returns 10 for shift step (coarser in DMX mode)', () => {
      expect(dmxStep(true)).toBe(10);
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lacylights-fe && npx jest src/utils/__tests__/dmxPercentage.test.ts --no-coverage`
Expected: FAIL — module not found

- [ ] **Step 3: Implement the conversion module**

Create `src/utils/dmxPercentage.ts`:

```typescript
import { ChannelType } from '@/types';

/**
 * Discrete channel types where each DMX value has a specific meaning
 * (e.g., gobo selection, color wheel position). These always display as raw DMX.
 */
const DISCRETE_CHANNEL_TYPES = new Set<ChannelType>([
  ChannelType.GOBO,
  ChannelType.COLOR_WHEEL,
  ChannelType.EFFECT,
  ChannelType.MACRO,
  ChannelType.OTHER,
]);

/**
 * Check if a channel type represents a continuous range suitable for percentage display.
 * Discrete channels (gobo, color wheel, effect, macro, other) always show raw DMX.
 */
export function isPercentageChannel(channelType: ChannelType): boolean {
  return !DISCRETE_CHANNEL_TYPES.has(channelType);
}

/**
 * Convert a DMX value to a percentage (0.0-100.0).
 * Supports custom min/max ranges for channels with non-standard bounds.
 */
export function dmxToPercent(dmxValue: number, min = 0, max = 255): number {
  const range = max - min;
  if (range === 0) return 0;
  return ((dmxValue - min) / range) * 100;
}

/**
 * Convert a percentage (0.0-100.0) to a DMX value, rounded and clamped.
 * Supports custom min/max ranges for channels with non-standard bounds.
 */
export function percentToDmx(percent: number, min = 0, max = 255): number {
  const range = max - min;
  const raw = min + (percent / 100) * range;
  return Math.round(Math.max(min, Math.min(max, raw)));
}

/**
 * Format a DMX value as a percentage string with one decimal place.
 */
export function formatPercent(dmxValue: number, min = 0, max = 255): string {
  return `${dmxToPercent(dmxValue, min, max).toFixed(1)}%`;
}

/**
 * Format a DMX value as a plain integer string.
 */
export function formatDmx(dmxValue: number): string {
  return String(Math.round(dmxValue));
}

/**
 * Get the step size for percentage mode input.
 * @param shiftHeld - true when shift key is held (finer control in percent mode)
 * @returns Step size in percentage units
 */
export function percentStep(shiftHeld: boolean): number {
  return shiftHeld ? 0.1 : 1.0;
}

/**
 * Get the step size for DMX mode input.
 * Note: In DMX mode, Shift = larger steps (coarser). In percent mode, Shift = smaller steps (finer).
 * The parameter is named `shiftHeld` to avoid confusion.
 * @param shiftHeld - true when shift key is held
 * @returns Step size in DMX units
 */
export function dmxStep(shiftHeld: boolean): number {
  return shiftHeld ? 10 : 1;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lacylights-fe && npx jest src/utils/__tests__/dmxPercentage.test.ts --no-coverage`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd lacylights-fe
git add src/utils/dmxPercentage.ts src/utils/__tests__/dmxPercentage.test.ts
git commit -m "feat: add DMX percentage conversion utility module

Single source of truth for DMX-to-percent and percent-to-DMX conversions,
channel type classification, and step size helpers."
```

---

### Task 2: Create `useDisplayMode` hook

**Files:**
- Create: `src/hooks/useDisplayMode.ts`
- Test: `src/hooks/__tests__/useDisplayMode.test.ts`

- [ ] **Step 1: Write failing tests for the hook**

Create `src/hooks/__tests__/useDisplayMode.test.ts`:

```typescript
import { renderHook, act } from '@testing-library/react';
import { useDisplayMode } from '../useDisplayMode';

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: jest.fn((key: string) => store[key] || null),
    setItem: jest.fn((key: string, value: string) => { store[key] = value; }),
    clear: () => { store = {}; },
  };
})();

Object.defineProperty(window, 'localStorage', { value: localStorageMock });

describe('useDisplayMode', () => {
  beforeEach(() => {
    localStorageMock.clear();
    jest.clearAllMocks();
  });

  it('defaults to dmx mode', () => {
    const { result } = renderHook(() => useDisplayMode());
    expect(result.current.displayMode).toBe('dmx');
    expect(result.current.isDmxMode).toBe(true);
    expect(result.current.isPercentMode).toBe(false);
  });

  it('reads stored preference on mount', () => {
    localStorageMock.getItem.mockReturnValueOnce('percent');
    const { result } = renderHook(() => useDisplayMode());
    expect(result.current.displayMode).toBe('percent');
    expect(result.current.isPercentMode).toBe(true);
  });

  it('persists preference to localStorage on change', () => {
    const { result } = renderHook(() => useDisplayMode());
    act(() => {
      result.current.setDisplayMode('percent');
    });
    expect(localStorageMock.setItem).toHaveBeenCalledWith(
      'lacylights-display-mode',
      'percent'
    );
    expect(result.current.isPercentMode).toBe(true);
  });

  it('ignores invalid stored values', () => {
    localStorageMock.getItem.mockReturnValueOnce('invalid');
    const { result } = renderHook(() => useDisplayMode());
    expect(result.current.displayMode).toBe('dmx');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lacylights-fe && npx jest src/hooks/__tests__/useDisplayMode.test.ts --no-coverage`
Expected: FAIL — module not found

- [ ] **Step 3: Implement the hook**

Create `src/hooks/useDisplayMode.ts`:

```typescript
import { useState, useEffect, useCallback } from 'react';

const STORAGE_KEY = 'lacylights-display-mode';

export type DisplayMode = 'dmx' | 'percent';

/**
 * Hook for managing the DMX value display mode preference stored in localStorage.
 *
 * - 'dmx' (default): Show raw DMX values (0-255)
 * - 'percent': Show values as percentages (0.0%-100.0%)
 */
export function useDisplayMode() {
  const [displayMode, setDisplayModeState] = useState<DisplayMode>('dmx');

  // Load preference from localStorage on mount
  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored === 'dmx' || stored === 'percent') {
        setDisplayModeState(stored);
      }
    } catch {
      // localStorage may not be available (SSR, privacy mode, etc.)
    }
  }, []);

  const setDisplayMode = useCallback((mode: DisplayMode) => {
    setDisplayModeState(mode);
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {
      // localStorage may not be available
    }
  }, []);

  return {
    displayMode,
    setDisplayMode,
    isDmxMode: displayMode === 'dmx',
    isPercentMode: displayMode === 'percent',
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lacylights-fe && npx jest src/hooks/__tests__/useDisplayMode.test.ts --no-coverage`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd lacylights-fe
git add src/hooks/useDisplayMode.ts src/hooks/__tests__/useDisplayMode.test.ts
git commit -m "feat: add useDisplayMode hook for DMX/percent preference

localStorage-backed hook following the same pattern as useScrollDirectionPreference."
```

---

## Chunk 2: ChannelSlider Percentage Mode

### Task 3: Add percentage display mode to ChannelSlider

**Files:**
- Modify: `src/components/ChannelSlider.tsx`
- Modify: `src/components/__tests__/ChannelSlider.test.tsx`

- [ ] **Step 1: Write failing tests for percentage mode**

Add to `src/components/__tests__/ChannelSlider.test.tsx`:

```typescript
// Add mock for useDisplayMode at top with other mocks:
jest.mock('@/hooks/useDisplayMode', () => ({
  useDisplayMode: jest.fn(() => ({
    displayMode: 'dmx',
    isDmxMode: true,
    isPercentMode: false,
    setDisplayMode: jest.fn(),
  })),
}));

import { useDisplayMode } from '@/hooks/useDisplayMode';
const mockUseDisplayMode = useDisplayMode as jest.MockedFunction<typeof useDisplayMode>;

// Add a GOBO channel for discrete testing:
const mockGoboChannel: SliderChannel = {
  name: 'Gobo',
  type: ChannelType.GOBO,
  minValue: 0,
  maxValue: 255,
};

// Add new describe block:
describe('percentage mode', () => {
  beforeEach(() => {
    mockUseDisplayMode.mockReturnValue({
      displayMode: 'percent',
      isDmxMode: false,
      isPercentMode: true,
      setDisplayMode: jest.fn(),
    });
  });

  afterEach(() => {
    mockUseDisplayMode.mockReturnValue({
      displayMode: 'dmx',
      isDmxMode: true,
      isPercentMode: false,
      setDisplayMode: jest.fn(),
    });
  });

  it('displays percentage for continuum channels', () => {
    render(
      <ChannelSlider
        channel={mockIntensityChannel}
        value={128}
        onChange={jest.fn()}
      />
    );
    // Number input should show percentage value
    expect(screen.getByRole('spinbutton')).toHaveValue(50.2);
  });

  it('displays raw DMX for discrete channels', () => {
    render(
      <ChannelSlider
        channel={mockGoboChannel}
        value={128}
        onChange={jest.fn()}
      />
    );
    // Discrete channels always show DMX
    expect(screen.getByRole('spinbutton')).toHaveValue(128);
  });

  it('converts percentage input back to DMX for onChange', () => {
    const handleChange = jest.fn();
    render(
      <ChannelSlider
        channel={mockIntensityChannel}
        value={128}
        onChange={handleChange}
      />
    );
    const numberInput = screen.getByRole('spinbutton');
    fireEvent.change(numberInput, { target: { value: '75.0' } });
    // 75% of 255 = 191.25 -> 191
    expect(handleChange).toHaveBeenCalledWith(191);
  });

  it('slider range is 0-100 with step 0.1 in percentage mode for continuum channels', () => {
    render(
      <ChannelSlider
        channel={mockIntensityChannel}
        value={128}
        onChange={jest.fn()}
      />
    );
    const slider = screen.getByRole('slider');
    expect(slider).toHaveAttribute('min', '0');
    expect(slider).toHaveAttribute('max', '100');
    expect(slider).toHaveAttribute('step', '0.1');
  });

  it('slider range remains 0-255 for discrete channels in percentage mode', () => {
    render(
      <ChannelSlider
        channel={mockGoboChannel}
        value={128}
        onChange={jest.fn()}
      />
    );
    const slider = screen.getByRole('slider');
    expect(slider).toHaveAttribute('min', '0');
    expect(slider).toHaveAttribute('max', '255');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lacylights-fe && npx jest src/components/__tests__/ChannelSlider.test.tsx --no-coverage`
Expected: FAIL — new tests fail (useDisplayMode not imported in component yet)

- [ ] **Step 3: Implement percentage mode in ChannelSlider**

Modify `src/components/ChannelSlider.tsx`:

**Add imports** at top of file:

```typescript
import { useDisplayMode } from '@/hooks/useDisplayMode';
import { dmxToPercent, percentToDmx, isPercentageChannel, percentStep, dmxStep } from '@/utils/dmxPercentage';
```

**Add display mode logic** inside the component function, after the `useScrollDirectionPreference` call:

```typescript
// Get display mode preference
const { isPercentMode } = useDisplayMode();

// Determine if this channel should show percentages
const min = channel.minValue || DEFAULT_MIN_VALUE;
const max = channel.maxValue || DEFAULT_MAX_VALUE;
const usePercent = isPercentMode && isPercentageChannel(channel.type);

// Compute display-space values
const displayValue = usePercent ? dmxToPercent(localValue, min, max) : localValue;
const displayMin = usePercent ? 0 : min;
const displayMax = usePercent ? 100 : max;
const displayStep = usePercent ? 0.1 : 1;
```

**Replace `handleSliderChange`:**

```typescript
const handleSliderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
  const rawValue = parseFloat(e.target.value);
  const dmxValue = usePercent ? percentToDmx(rawValue, min, max) : Math.round(rawValue);
  setLocalValue(dmxValue);
  onChange(dmxValue);
};
```

**Replace `handleSliderMouseUp`:**

```typescript
const handleSliderMouseUp = (e: React.MouseEvent<HTMLInputElement>) => {
  const rawValue = parseFloat((e.target as HTMLInputElement).value);
  const dmxValue = usePercent ? percentToDmx(rawValue, min, max) : Math.round(rawValue);
  if (onChangeComplete) {
    onChangeComplete(dmxValue);
  }
};
```

**Replace `handleSliderTouchEnd`:**

```typescript
const handleSliderTouchEnd = (e: React.TouchEvent<HTMLInputElement>) => {
  const rawValue = parseFloat((e.target as HTMLInputElement).value);
  const dmxValue = usePercent ? percentToDmx(rawValue, min, max) : Math.round(rawValue);
  if (onChangeComplete) {
    onChangeComplete(dmxValue);
  }
};
```

**Replace `handleInputChange`:**

```typescript
const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
  const rawValue = parseFloat(e.target.value);
  if (isNaN(rawValue)) return;
  const dmxValue = usePercent ? percentToDmx(rawValue, min, max) : Math.max(min, Math.min(max, Math.round(rawValue)));
  setLocalValue(dmxValue);
  onChange(dmxValue);
  if (onChangeComplete) {
    onChangeComplete(dmxValue);
  }
};
```

**Replace `handleKeyDown`:**

```typescript
const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
  if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
  e.preventDefault();

  const direction = e.key === 'ArrowUp' ? 1 : -1;

  let newDmxValue: number;
  if (usePercent) {
    const step = percentStep(e.shiftKey);
    const currentPercent = dmxToPercent(localValue, min, max);
    const newPercent = Math.max(0, Math.min(100, currentPercent + direction * step));
    newDmxValue = percentToDmx(newPercent, min, max);
  } else {
    const step = dmxStep(e.shiftKey);
    newDmxValue = Math.max(min, Math.min(max, localValue + direction * step));
  }

  if (newDmxValue !== localValue) {
    setLocalValue(newDmxValue);
    onChange(newDmxValue);
    if (onChangeComplete) {
      onChangeComplete(newDmxValue);
    }
  }
};
```

**Update the range slider element** — change `min`, `max`, `value`, and add `step`:

```tsx
<input
  type="range"
  min={displayMin}
  max={displayMax}
  step={displayStep}
  value={displayValue}
  onChange={handleSliderChange}
  onMouseUp={handleSliderMouseUp}
  onTouchEnd={handleSliderTouchEnd}
  disabled={isInactive}
  className={/* unchanged */}
/>
```

**Update the number input element** — use `displayValue`, wider width for percentages:

```tsx
<input
  type="number"
  min={displayMin}
  max={displayMax}
  step={displayStep}
  value={usePercent ? parseFloat(displayValue.toFixed(1)) : displayValue}
  onChange={handleInputChange}
  onKeyDown={handleKeyDown}
  disabled={isInactive}
  className={`${usePercent ? 'w-16' : 'w-12'} text-xs text-center font-mono text-gray-900 dark:text-gray-100 bg-gray-100 dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded px-1 py-0 focus:outline-none focus:ring-1 focus:ring-blue-500 select-none ${isInactive ? 'cursor-not-allowed' : 'cursor-ns-resize'}`}
  title={usePercent
    ? 'Scroll to adjust, arrow keys for ±1%, Shift+arrow for ±0.1%. Touch and drag vertically to scrub.'
    : 'Scroll to adjust, arrow keys for ±1, Shift+arrow for ±10. Touch and drag vertically to scrub.'}
  {...touchScrubProps}
/>
```

All `onChange` and `onChangeComplete` callbacks continue to emit raw DMX values — conversion happens at the display boundary only.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lacylights-fe && npx jest src/components/__tests__/ChannelSlider.test.tsx --no-coverage`
Expected: All tests PASS (both old and new)

- [ ] **Step 5: Commit**

```bash
cd lacylights-fe
git add src/components/ChannelSlider.tsx src/components/__tests__/ChannelSlider.test.tsx
git commit -m "feat: add percentage display mode to ChannelSlider

Continuum channels show 0.0%-100.0% in percent mode. Discrete channels
(GOBO, COLOR_WHEEL, etc.) always show raw DMX. All callbacks still emit
DMX values — conversion happens at the display boundary only."
```

---

### Task 4: Update useValueScrub for percentage mode step sizes

**Files:**
- Modify: `src/hooks/useValueScrub.ts`

- [ ] **Step 1: Add `step` option to UseValueScrubOptions**

Add an optional `step` property to `UseValueScrubOptions`:

```typescript
/**
 * Base step size for value changes (default: 1).
 * When using percentage mode, the caller passes the percentage step size
 * and handles conversion externally.
 */
step?: number;
```

- [ ] **Step 2: Use step in handleWheel and handleTouchMove**

In the options destructuring (line ~101), add `step = 1`:

```typescript
const {
  value,
  min,
  max,
  onChange,
  onChangeComplete,
  disabled = false,
  wheelSensitivity = DEFAULT_WHEEL_SENSITIVITY,
  touchSensitivity = DEFAULT_TOUCH_SENSITIVITY,
  shiftMultiplier = DEFAULT_SHIFT_MULTIPLIER,
  invertWheelDirection = false,
  step = 1,
} = options;
```

In `handleWheel` (around line ~143), replace the accumulation logic. The full updated `handleWheel` body:

```typescript
const handleWheel = useCallback(
  (e: React.WheelEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();

    const sensitivity = e.shiftKey
      ? wheelSensitivity / shiftMultiplier
      : wheelSensitivity;

    const directionMultiplier = invertWheelDirection ? -1 : 1;
    const delta = (e.deltaY * directionMultiplier) / sensitivity;

    accumulatedDelta.current += delta;

    // Use step size for accumulation threshold
    if (Math.abs(accumulatedDelta.current) >= step) {
      const steps = Math.trunc(accumulatedDelta.current / step);
      accumulatedDelta.current -= steps * step;

      const newValue = clamp(lastValue.current + steps * step);
      if (newValue !== lastValue.current) {
        lastValue.current = newValue;
        onChange(newValue);
        onChangeComplete?.(newValue);
      }
    }
  },
  [disabled, wheelSensitivity, shiftMultiplier, invertWheelDirection, step, clamp, onChange, onChangeComplete]
);
```

In `handleTouchMove` (around line ~203), quantize the value change to step size:

```typescript
const handleTouchMove = useCallback(
  (e: React.TouchEvent) => {
    if (disabled || touchStartY.current === null) return;
    if (e.touches.length !== 1) return;

    const currentY = e.touches[0].clientY;
    const deltaY = touchStartY.current - currentY;

    if (!isScrubbing.current && Math.abs(deltaY) > TOUCH_SCRUB_THRESHOLD) {
      isScrubbing.current = true;
      if (navigator.vibrate) {
        navigator.vibrate(10);
      }
    }

    if (isScrubbing.current) {
      e.preventDefault();
      const valueChange = deltaY / touchSensitivity;
      // Quantize to step size
      const steppedChange = Math.round(valueChange / step) * step;
      const newValue = clamp(touchStartValue.current + steppedChange);

      if (newValue !== lastValue.current) {
        lastValue.current = newValue;
        onChange(newValue);
      }
    }
  },
  [disabled, touchSensitivity, step, clamp, onChange]
);
```

- [ ] **Step 4: Run existing useValueScrub-dependent tests**

Run: `cd lacylights-fe && npx jest --no-coverage -- ChannelSlider useValueScrub`
Expected: All existing tests still PASS (step defaults to 1, preserving old behavior)

- [ ] **Step 5: Update ChannelSlider to pass step to useValueScrub**

In `ChannelSlider.tsx`, update the `useValueScrub` call:

```typescript
const { wheelProps, touchScrubProps, containerRef } = useValueScrub({
  value: displayValue,       // percentage value when in percent mode
  min: displayMin,           // 0 in percent mode
  max: displayMax,           // 100 in percent mode
  step: usePercent ? 0.1 : 1, // fine granularity for percentage
  onChange: (newDisplayValue) => {
    const dmxValue = usePercent ? percentToDmx(newDisplayValue, min, max) : newDisplayValue;
    setLocalValue(dmxValue);
    onChange(dmxValue);
  },
  onChangeComplete: onChangeComplete ? (newDisplayValue) => {
    const dmxValue = usePercent ? percentToDmx(newDisplayValue, min, max) : newDisplayValue;
    onChangeComplete(dmxValue);
  } : undefined,
  disabled: isInactive,
  invertWheelDirection,
});
```

- [ ] **Step 6: Run all related tests**

Run: `cd lacylights-fe && npx jest --no-coverage -- ChannelSlider`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
cd lacylights-fe
git add src/hooks/useValueScrub.ts src/components/ChannelSlider.tsx
git commit -m "feat: add step size support to useValueScrub for percentage mode

Callers can now specify a base step size. ChannelSlider passes percentage-
appropriate step sizes when in percent mode. Default step=1 preserves
existing behavior."
```

---

## Chunk 3: Settings UI & Integration

### Task 5: Add display mode toggle to Settings page

**Files:**
- Modify: `src/app/(main)/settings/page.tsx`

- [ ] **Step 1: Add the display mode toggle section**

Import `useDisplayMode` and add a "Display Preferences" section to the settings page, placed before the "Fade Engine Configuration" section:

```tsx
import { useDisplayMode } from '@/hooks/useDisplayMode';

// Inside SettingsPage component:
const { displayMode, setDisplayMode } = useDisplayMode();

// In the return JSX, add before "Fade Engine Configuration":
{/* Display Preferences Section */}
<div>
  <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">Display Preferences</h2>
  <div className="bg-white dark:bg-gray-800 shadow rounded-lg p-6">
    <div className="flex items-center justify-between">
      <div>
        <h3 className="text-sm font-medium text-gray-900 dark:text-white">
          Show values as percentages
        </h3>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Display channel values as 0.0%-100.0% instead of DMX 0-255.
          Discrete channels (gobo, color wheel, etc.) always show raw DMX values.
        </p>
      </div>
      <button
        role="switch"
        aria-checked={displayMode === 'percent'}
        onClick={() => setDisplayMode(displayMode === 'percent' ? 'dmx' : 'percent')}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
          displayMode === 'percent'
            ? 'bg-blue-600'
            : 'bg-gray-200 dark:bg-gray-600'
        }`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
            displayMode === 'percent' ? 'translate-x-6' : 'translate-x-1'
          }`}
        />
      </button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Run the settings page test (if exists) and type-check**

Run: `cd lacylights-fe && npx tsc --noEmit && npx jest --no-coverage -- settings`
Expected: PASS (or no existing settings tests — type-check should pass)

- [ ] **Step 3: Commit**

```bash
cd lacylights-fe
git add src/app/\(main\)/settings/page.tsx
git commit -m "feat: add display mode toggle to settings page

New 'Display Preferences' section with a toggle to switch between
DMX values (0-255) and percentage display (0.0%-100.0%)."
```

---

### Task 6: Run full test suite and lint

**Files:** None (validation only)

- [ ] **Step 1: Run full test suite**

Run: `cd lacylights-fe && npm test -- --no-coverage`
Expected: All tests PASS

- [ ] **Step 2: Run linter and type-check**

Run: `cd lacylights-fe && npm run check`
Expected: No errors

- [ ] **Step 3: Fix any failures**

If any tests fail due to the useDisplayMode import in ChannelSlider, add the mock to any test files that render ChannelSlider directly or indirectly:

```typescript
jest.mock('@/hooks/useDisplayMode', () => ({
  useDisplayMode: () => ({
    displayMode: 'dmx',
    isDmxMode: true,
    isPercentMode: false,
    setDisplayMode: jest.fn(),
  }),
}));
```

Files that will likely need this mock (they render ChannelSlider):
- `src/components/__tests__/ChannelListEditor.test.tsx`
- `src/components/__tests__/MultiSelectControls.test.tsx`
- `src/components/__tests__/LookEditorLayout.test.tsx`
- Any other test that renders components containing ChannelSlider

- [ ] **Step 4: Commit any mock fixes**

```bash
cd lacylights-fe
git add -A
git commit -m "fix: add useDisplayMode mock to tests that render ChannelSlider"
```

---

### Task 7: Manual smoke test

- [ ] **Step 1: Start dev server and verify**

Run: `cd lacylights-fe && npm run dev`

Manual verification checklist:
1. Open Settings page — verify "Display Preferences" toggle appears
2. Toggle to percentage mode — verify toggle switches
3. Open a look editor with fixtures — verify:
   - Intensity/color sliders show 0.0%-100.0%
   - GOBO/COLOR_WHEEL channels show 0-255
   - Slider drag updates percentage display smoothly
   - Number input accepts percentage values
   - Arrow keys step by 1.0%, Shift+Arrow by 0.1%
   - Wheel scroll works proportionally
4. Toggle back to DMX mode — verify all values return to 0-255 display
5. Refresh page — verify preference persists
6. Color picker still shows RGB 0-255 (unaffected)

- [ ] **Step 2: Final commit if any tweaks needed**

```bash
cd lacylights-fe
git add -A
git commit -m "fix: polish percentage display mode after smoke testing"
```
