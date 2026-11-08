# Stream Deck + Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Elgato Stream Deck + support to LacyLights by refactoring the existing streamdock plugin into a shared-core architecture and building the Elgato adapter with comprehensive mode coverage.

**Architecture:** Rename lacylights-streamdock → lacylights-streamdeck. Extract shared core (bridge, modes, state, commands, icons) from existing code. Build thin adapters for Stream Dock N3 and Elgato Stream Deck +. Extend frontend bridge protocol with new commands for the 5 new modes. The Elgato adapter uses `@elgato/streamdeck` npm SDK with TypeScript action classes.

**Tech Stack:** TypeScript, Node.js 20+, `@elgato/streamdeck` SDK, `ws` WebSocket library, Jest, esbuild

**Design Doc:** `docs/plans/2026-02-12-streamdeck-plus-design.md`

---

## Implementation Status

**Completed PRs:**
- ✅ [#7 - Elgato Stream Deck + Support (Phases 3-4)](https://github.com/bbernstein/lacylights-streamdeck/pull/7)
- ✅ [#157 - Stream Deck Phase 5: Frontend Integration](https://github.com/bbernstein/lacylights-fe/pull/157)

**Branch:** `feature/streamdeck-plus` (plugin), `main` (frontend - merged)

**Completed Phases:**
- ✅ **Phase 1**: Repository Rename & Shared Core Extraction (Tasks 1-7)
- ✅ **Phase 2**: Protocol & Type System Extension (Task 8)
- ✅ **Phase 3**: Core Mode Implementation (Tasks 9-14)
  - 5 new modes: Navigation, Look Board, Effect Editor, Cue List Browser, Look Editor Layout
  - 3 updated modes: Cue Player, Look Editor, Color Picker
  - 121 new passing tests
- ✅ **Phase 4**: Elgato Adapter Implementation (Tasks 15-20)
  - Key & Encoder actions with hardware abstraction
  - Bridge Manager for mode orchestration
  - Touch strip layouts (5 JSON files)
  - Build & packaging configuration
  - 28 new passing tests
- ✅ **Phase 5**: Frontend Integration (Tasks 21-25) - **MERGED 2026-02-13**
  - Extended StreamDockContext with 24 new command handlers
  - Added state publishers for all 5 new modes
  - Updated mode detection for 8-mode system
  - 37 new passing tests, comprehensive input validation
  - Security hardened with `Number.isFinite` checks, path injection prevention

- ✅ **Phase 6**: Integration Testing & Polish (Tasks 26-28)
  - 23 end-to-end integration tests covering full flow
  - CI updated to build both Stream Dock + Elgato targets
  - Documentation updated with shared core architecture

**Total Progress:** 28/28 tasks complete (100%)

**Notes:**
- All phases complete and production-ready
- 472 tests across 26 test suites
- Both build targets verified in CI

---

## Phase 1: Repository Rename & Shared Core Extraction

This phase refactors the existing code without changing behavior. All existing tests must continue passing.

### Task 1: Rename Repository & Update References

**Files:**
- Modify: `lacylights-streamdock/package.json`
- Modify: `lacylights-streamdock/manifest.json`
- Modify: `lacylights-streamdock/CLAUDE.md`

**Step 1: Rename the directory**

```bash
cd ~/src/lacylights
mv lacylights-streamdock lacylights-streamdeck
cd lacylights-streamdeck
```

**Step 2: Update package.json name field**

Change `"name"` from `"lacylights-streamdock"` to `"lacylights-streamdeck"`.

**Step 3: Update manifest.json description**

Change Description to reference Stream Deck. Keep Stream Dock N3 compatibility mentioned.

**Step 4: Update CLAUDE.md references**

Update any references to "streamdock" in the project instructions.

**Step 5: Create feature branch and commit**

```bash
git checkout -b feature/streamdeck-plus
git add -A
git commit -m "chore: rename repo from lacylights-streamdock to lacylights-streamdeck"
```

**Step 6: Run tests to verify nothing broke**

```bash
npm test
```

Expected: All 187 tests pass.

---

### Task 2: Extract Shared Types to `src/core/types.ts`

**Files:**
- Create: `src/core/types.ts`
- Modify: `src/types/messages.ts`

The existing `src/types/messages.ts` contains all protocol types. We'll create `src/core/types.ts` that re-exports everything and adds the new hardware abstraction types.

**Step 1: Write failing test for new hardware abstraction types**

Create: `src/__tests__/core-types.test.ts`

```typescript
import {
  HardwareCapabilities,
  KeyEvent,
  DialEvent,
  TouchEvent,
  HardwareEvent,
} from '../core/types';

describe('core types', () => {
  it('KeyEvent has correct shape', () => {
    const event: KeyEvent = { type: 'key', index: 0, action: 'press' };
    expect(event.type).toBe('key');
    expect(event.index).toBe(0);
    expect(event.action).toBe('press');
  });

  it('DialEvent has correct shape', () => {
    const event: DialEvent = { type: 'dial', index: 0, action: 'rotate', delta: 1, pressed: false };
    expect(event.type).toBe('dial');
    expect(event.delta).toBe(1);
  });

  it('TouchEvent has correct shape', () => {
    const event: TouchEvent = { type: 'touch', index: 0, x: 100, y: 50, hold: false };
    expect(event.type).toBe('touch');
  });

  it('HardwareCapabilities describes device', () => {
    const caps: HardwareCapabilities = { keyCount: 8, dialCount: 4, hasTouchStrip: true };
    expect(caps.keyCount).toBe(8);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern core-types
```

Expected: FAIL — module not found.

**Step 3: Create `src/core/types.ts`**

```typescript
// ─── Hardware Abstraction ───────────────────────────────────────────────────

/** Describes what controls a device has */
export interface HardwareCapabilities {
  keyCount: number;       // Stream Dock N3: 6 LCD + 3 plain = 9, Elgato SD+: 8
  dialCount: number;      // Stream Dock N3: 3, Elgato SD+: 4
  hasTouchStrip: boolean; // Stream Dock N3: false, Elgato SD+: true
}

/** Unified key press event (covers LCD buttons, plain buttons, SD+ keys) */
export interface KeyEvent {
  type: 'key';
  index: number;
  action: 'press' | 'release';
}

/** Unified dial/knob event */
export interface DialEvent {
  type: 'dial';
  index: number;
  action: 'rotate' | 'press' | 'release';
  delta?: number;     // For rotate: positive = clockwise
  pressed?: boolean;  // Whether dial is pressed during rotate
}

/** Touch strip tap event (Elgato SD+ only) */
export interface TouchEvent {
  type: 'touch';
  index: number;  // 0-3 segment
  x: number;
  y: number;
  hold: boolean;
}

export type HardwareEvent = KeyEvent | DialEvent | TouchEvent;

// ─── Mode Types ─────────────────────────────────────────────────────────────

export type StreamDeckMode =
  | 'cue_player'
  | 'look_editor_channels'
  | 'look_editor_layout'
  | 'color_picker'
  | 'effect_editor'
  | 'look_board'
  | 'cue_list_browser'
  | 'navigation';

// Re-export existing protocol types
export type {
  StateUpdateMessage,
  CueListState,
  LookEditorState,
  ColorPickerState,
  ChannelInfo,
  FixtureSummary,
  PluginMessage,
  FrontendMessage,
  PongMessage,
} from '../types/messages';

// Re-export legacy mode type for backward compatibility
export type { StreamDockMode } from '../types/messages';
```

**Step 4: Run test to verify it passes**

```bash
npm test -- --testPathPattern core-types
```

Expected: PASS

**Step 5: Run all tests**

```bash
npm test
```

Expected: All existing tests still pass.

**Step 6: Commit**

```bash
git add src/core/types.ts src/__tests__/core-types.test.ts
git commit -m "feat: add shared core types with hardware abstraction layer"
```

---

### Task 3: Extract Mode Base Interface to `src/core/modes/base-mode.ts`

**Files:**
- Create: `src/core/modes/base-mode.ts`
- Modify: `src/modes/base-mode.ts` (re-export from core)

**Step 1: Write failing test**

Create: `src/__tests__/core-base-mode.test.ts`

```typescript
import { BaseMode, ModeKeyMapping, ModeDialMapping, ModeTouchStripFeedback } from '../core/modes/base-mode';
import { HardwareEvent, HardwareCapabilities } from '../core/types';
import { PluginMessage, StateUpdateMessage } from '../types/messages';

class TestMode extends BaseMode {
  readonly name = 'Test Mode';
  readonly modeId = 'navigation' as const;

  handleEvent(event: HardwareEvent): PluginMessage[] { return []; }
  onStateUpdate(message: StateUpdateMessage): void {}
  activate(): void {}
  deactivate(): void {}

  getKeyMapping(keyCount: number): ModeKeyMapping[] {
    return [{ index: 0, label: 'TEST', backgroundColor: '#000', textColor: '#fff' }];
  }

  getDialMapping(dialCount: number): ModeDialMapping[] {
    return [{ index: 0, rotateLabel: 'Scroll', pressLabel: 'Select' }];
  }

  getTouchStripFeedback(): ModeTouchStripFeedback[] {
    return [{ index: 0, layout: '$B1', feedback: { title: 'Test' } }];
  }
}

describe('BaseMode (core)', () => {
  it('can be extended with key/dial/touch methods', () => {
    const mode = new TestMode();
    expect(mode.name).toBe('Test Mode');
    expect(mode.getKeyMapping(8)).toHaveLength(1);
    expect(mode.getDialMapping(4)).toHaveLength(1);
    expect(mode.getTouchStripFeedback()).toHaveLength(1);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern core-base-mode
```

**Step 3: Create `src/core/modes/base-mode.ts`**

```typescript
import { HardwareEvent, StreamDeckMode } from '../types';
import { PluginMessage, StateUpdateMessage } from '../../types/messages';

/** Describes a key's visual state for any hardware device */
export interface ModeKeyMapping {
  index: number;
  label: string;
  detail?: string;
  backgroundColor: string;
  textColor: string;
  active?: boolean;
  disabled?: boolean;
  progress?: number;
  badge?: string;
}

/** Describes a dial's function labels */
export interface ModeDialMapping {
  index: number;
  rotateLabel?: string;
  pressLabel?: string;
}

/** Describes a touch strip segment's feedback (Elgato SD+ only) */
export interface ModeTouchStripFeedback {
  index: number;
  layout: string;  // '$A1', '$B1', '$B2', or custom layout path
  feedback: Record<string, unknown>;  // Layout item key → value
}

/**
 * Abstract base class for all operating modes.
 * Modes handle hardware events and generate visual feedback for both
 * Stream Dock N3 and Elgato Stream Deck + devices.
 */
export abstract class BaseMode {
  abstract readonly name: string;
  abstract readonly modeId: StreamDeckMode;

  /** Handle a hardware event and return commands to send to the frontend */
  abstract handleEvent(event: HardwareEvent): PluginMessage[];

  /** Update internal state when frontend publishes new state */
  abstract onStateUpdate(message: StateUpdateMessage): void;

  /** Called when this mode becomes active */
  abstract activate(): void;

  /** Called when this mode is deactivated */
  abstract deactivate(): void;

  /** Get key visual mappings for the given number of keys */
  abstract getKeyMapping(keyCount: number): ModeKeyMapping[];

  /** Get dial function descriptions */
  abstract getDialMapping(dialCount: number): ModeDialMapping[];

  /** Get touch strip feedback (default: empty for devices without touch) */
  getTouchStripFeedback(): ModeTouchStripFeedback[] {
    return [];
  }
}
```

**Step 4: Run test to verify it passes**

```bash
npm test -- --testPathPattern core-base-mode
```

**Step 5: Make existing `src/modes/base-mode.ts` a thin wrapper**

Update `src/modes/base-mode.ts` to re-export from core for backward compatibility. The existing mode classes (`CuePlayerMode`, etc.) still import from `../modes/base-mode` — this re-export ensures they don't break.

```typescript
// Re-export core base mode for backward compatibility
export { BaseMode, type ModeKeyMapping, type ModeDialMapping, type ModeTouchStripFeedback } from '../core/modes/base-mode';

// Legacy hardware event types for Stream Dock N3
// These map to the new unified types
export interface LcdButtonEvent {
  type: 'lcd_button';
  index: number;
  action: 'press' | 'release';
}

export interface PlainButtonEvent {
  type: 'plain_button';
  index: number;
  action: 'press' | 'release';
}

export interface KnobEvent {
  type: 'knob';
  index: number;
  action: 'rotate' | 'press' | 'release';
  delta?: number;
}

export type HardwareEvent = LcdButtonEvent | PlainButtonEvent | KnobEvent;
```

**Step 6: Run all tests**

```bash
npm test
```

Expected: All tests pass (existing mode tests still work via re-exports).

**Step 7: Commit**

```bash
git add src/core/modes/ src/__tests__/core-base-mode.test.ts src/modes/base-mode.ts
git commit -m "feat: extract shared BaseMode with key/dial/touch mapping interfaces"
```

---

### Task 4: Move Shared Utilities to Core

**Files:**
- Create: `src/core/utils/knob-velocity.ts` (copy from `src/utils/knob-velocity.ts`)
- Create: `src/core/utils/color-conversion.ts` (copy from `src/utils/color-conversion.ts`)
- Modify: `src/utils/knob-velocity.ts` (re-export from core)
- Modify: `src/utils/color-conversion.ts` (re-export from core)

**Step 1: Move files to core**

Copy `src/utils/knob-velocity.ts` → `src/core/utils/knob-velocity.ts`
Copy `src/utils/color-conversion.ts` → `src/core/utils/color-conversion.ts`

**Step 2: Update original files to re-export**

`src/utils/knob-velocity.ts`:
```typescript
export {
  KnobVelocityTracker,
  type VelocityScalingConfig,
  CHANNEL_VALUE_CONFIG,
  COARSE_ADJUST_CONFIG,
  HUE_ADJUST_CONFIG,
  PERCENTAGE_ADJUST_CONFIG,
} from '../core/utils/knob-velocity';
```

`src/utils/color-conversion.ts`:
```typescript
export { hsbToRgb, rgbToHsb, rgbToHex } from '../core/utils/color-conversion';
```

**Step 3: Run all tests**

```bash
npm test
```

Expected: All 187 tests pass — re-exports are transparent.

**Step 4: Commit**

```bash
git add src/core/utils/ src/utils/
git commit -m "refactor: move utilities to shared core with re-exports for compatibility"
```

---

### Task 5: Move Icon Generation to Core

**Files:**
- Create: `src/core/icons/icon-generator.ts` (copy from `src/ui/icon-generator.ts`)
- Create: `src/core/icons/svg-renderer.ts` (copy from `src/ui/svg-renderer.ts`)
- Create: `src/core/icons/themes.ts` (copy from `src/ui/themes.ts`)
- Modify: `src/ui/icon-generator.ts` (re-export)
- Modify: `src/ui/svg-renderer.ts` (re-export)
- Modify: `src/ui/themes.ts` (re-export)

**Step 1: Copy icon files to core**

```bash
mkdir -p src/core/icons
cp src/ui/icon-generator.ts src/core/icons/
cp src/ui/svg-renderer.ts src/core/icons/
cp src/ui/themes.ts src/core/icons/
```

**Step 2: Update import paths in core copies**

In `src/core/icons/icon-generator.ts`, update imports to reference `../../types/messages` (or use the core types re-exports).

In `src/core/icons/themes.ts`, update the `StreamDockMode` import.

**Step 3: Update original files to re-export**

Each original file becomes a single re-export line.

**Step 4: Run all tests**

```bash
npm test
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add src/core/icons/ src/ui/
git commit -m "refactor: move icon generation to shared core"
```

---

### Task 6: Move Bridge and State to Core

**Files:**
- Create: `src/core/bridge/ws-server.ts` (copy)
- Create: `src/core/bridge/message-router.ts` (copy)
- Create: `src/core/state/state-manager.ts` (copy)
- Update originals to re-export

**Step 1: Copy files**

```bash
mkdir -p src/core/bridge src/core/state
cp src/bridge/ws-server.ts src/core/bridge/
cp src/bridge/message-router.ts src/core/bridge/
cp src/state/state-manager.ts src/core/state/
```

**Step 2: Update imports in core copies**

Fix relative import paths to point to correct locations.

**Step 3: Update originals to re-export**

**Step 4: Run all tests**

```bash
npm test
```

**Step 5: Commit**

```bash
git add src/core/bridge/ src/core/state/ src/bridge/ src/state/
git commit -m "refactor: move bridge and state manager to shared core"
```

---

## Phase 2: Extended Protocol & New Mode Types

### Task 7: Add New State Types to Protocol

**Files:**
- Modify: `src/types/messages.ts`
- Test: `src/__tests__/extended-protocol.test.ts`

**Step 1: Write failing test**

Create: `src/__tests__/extended-protocol.test.ts`

```typescript
import {
  EffectEditorState,
  LookBoardState,
  CueListBrowserState,
  GlobalState,
  ExtendedStateUpdateMessage,
} from '../types/messages';

describe('Extended protocol types', () => {
  it('EffectEditorState has required fields', () => {
    const state: EffectEditorState = {
      effectId: 'e1',
      effectName: 'Chase',
      effectType: 'WAVEFORM',
      isRunning: false,
      parameters: [{ name: 'speed', value: 50, min: 0, max: 100 }],
      selectedParamIndex: 0,
      canUndo: false,
      canRedo: false,
      isDirty: false,
    };
    expect(state.effectType).toBe('WAVEFORM');
  });

  it('LookBoardState has paging info', () => {
    const state: LookBoardState = {
      boardId: 'b1',
      boardName: 'Main',
      buttons: [{ id: 'btn1', lookId: 'l1', lookName: 'Wash', color: '#ff0000', position: 0 }],
      activeLookId: 'l1',
      totalButtons: 10,
      pageSize: 7,
      currentPage: 0,
      fadeTime: 2.0,
    };
    expect(state.pageSize).toBe(7);
  });

  it('GlobalState has undo/redo and master', () => {
    const state: GlobalState = {
      canUndo: true,
      canRedo: false,
      masterIntensity: 100,
      isBlackedOut: false,
    };
    expect(state.masterIntensity).toBe(100);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern extended-protocol
```

**Step 3: Add types to `src/types/messages.ts`**

```typescript
// ─── Effect Editor State ────────────────────────────────────────────────────

export interface EffectParameter {
  name: string;
  value: number;
  min: number;
  max: number;
}

export interface EffectEditorState {
  effectId: string;
  effectName: string;
  effectType: string;
  isRunning: boolean;
  parameters: EffectParameter[];
  selectedParamIndex: number;
  canUndo: boolean;
  canRedo: boolean;
  isDirty: boolean;
}

// ─── Look Board State ───────────────────────────────────────────────────────

export interface LookBoardButton {
  id: string;
  lookId: string;
  lookName: string;
  color: string;
  position: number;
}

export interface LookBoardState {
  boardId: string;
  boardName: string;
  buttons: LookBoardButton[];
  activeLookId: string | null;
  totalButtons: number;
  pageSize: number;
  currentPage: number;
  fadeTime: number;
}

// ─── Cue List Browser State ─────────────────────────────────────────────────

export interface CueListBrowserItem {
  id: string;
  name: string;
  cueCount: number;
}

export interface CueListBrowserState {
  cueLists: CueListBrowserItem[];
  highlightedIndex: number;
}

// ─── Global State ───────────────────────────────────────────────────────────

export interface GlobalState {
  canUndo: boolean;
  canRedo: boolean;
  masterIntensity: number;
  isBlackedOut: boolean;
}

// ─── Extended State Update ──────────────────────────────────────────────────

export interface ExtendedStateUpdateMessage {
  type: 'STATE_UPDATE';
  payload: {
    route: string;
    mode: string;
    cueList?: CueListState;
    lookEditor?: LookEditorState;
    colorPicker?: ColorPickerState;
    effectEditor?: EffectEditorState;
    lookBoard?: LookBoardState;
    cueListBrowser?: CueListBrowserState;
    global?: GlobalState;
  };
}
```

**Step 4: Run test**

```bash
npm test -- --testPathPattern extended-protocol
```

Expected: PASS

**Step 5: Run all tests**

```bash
npm test
```

**Step 6: Commit**

```bash
git add src/types/messages.ts src/__tests__/extended-protocol.test.ts
git commit -m "feat: add extended protocol types for effect editor, look board, browser, and global state"
```

---

### Task 8: Add New Command Types

**Files:**
- Modify: `src/types/messages.ts`
- Test: `src/__tests__/new-commands.test.ts`

**Step 1: Write failing test**

```typescript
import {
  EffectCommand,
  LookBoardCommand,
  NavigationCommand,
  GlobalCommand,
  LayoutCommand,
  CueListBrowserCommand,
} from '../types/messages';

describe('New command types', () => {
  it('EffectCommand types compile correctly', () => {
    const cmd: EffectCommand = { type: 'COMMAND', command: 'EFFECT_START', payload: { effectId: 'e1' } };
    expect(cmd.command).toBe('EFFECT_START');
  });

  it('LookBoardCommand types compile correctly', () => {
    const cmd: LookBoardCommand = { type: 'COMMAND', command: 'BOARD_ACTIVATE_LOOK', payload: { lookId: 'l1', slotIndex: 0 } };
    expect(cmd.command).toBe('BOARD_ACTIVATE_LOOK');
  });

  it('GlobalCommand types compile correctly', () => {
    const cmd: GlobalCommand = { type: 'COMMAND', command: 'GLOBAL_FTB' };
    expect(cmd.command).toBe('GLOBAL_FTB');
  });

  it('LayoutCommand types compile correctly', () => {
    const cmd: LayoutCommand = { type: 'COMMAND', command: 'LAYOUT_ZOOM', payload: { delta: 0.1 } };
    expect(cmd.command).toBe('LAYOUT_ZOOM');
  });
});
```

**Step 2: Add command types to `src/types/messages.ts`**

```typescript
// ─── Effect Commands ────────────────────────────────────────────────────────

export type EffectCommand =
  | { type: 'COMMAND'; command: 'EFFECT_START'; payload: { effectId: string } }
  | { type: 'COMMAND'; command: 'EFFECT_STOP'; payload: { effectId: string } }
  | { type: 'COMMAND'; command: 'EFFECT_SET_PARAM'; payload: { paramName: string; value: number } };

// ─── Look Board Commands ────────────────────────────────────────────────────

export type LookBoardCommand =
  | { type: 'COMMAND'; command: 'BOARD_ACTIVATE_LOOK'; payload: { lookId: string; slotIndex: number } }
  | { type: 'COMMAND'; command: 'BOARD_PAGE_NEXT' }
  | { type: 'COMMAND'; command: 'BOARD_PAGE_PREV' }
  | { type: 'COMMAND'; command: 'BOARD_SET_FADE_TIME'; payload: { seconds: number } };

// ─── Global Commands ────────────────────────────────────────────────────────

export type GlobalCommand =
  | { type: 'COMMAND'; command: 'GLOBAL_UNDO' }
  | { type: 'COMMAND'; command: 'GLOBAL_REDO' }
  | { type: 'COMMAND'; command: 'GLOBAL_FTB' }
  | { type: 'COMMAND'; command: 'GLOBAL_SET_MASTER'; payload: { intensity: number } };

// ─── Layout Commands ────────────────────────────────────────────────────────

export type LayoutCommand =
  | { type: 'COMMAND'; command: 'LAYOUT_ZOOM'; payload: { delta: number } }
  | { type: 'COMMAND'; command: 'LAYOUT_PAN'; payload: { deltaX: number; deltaY: number } }
  | { type: 'COMMAND'; command: 'LAYOUT_SELECT_ALL' }
  | { type: 'COMMAND'; command: 'LAYOUT_DESELECT_ALL' }
  | { type: 'COMMAND'; command: 'LAYOUT_TOGGLE_SNAP' }
  | { type: 'COMMAND'; command: 'LAYOUT_AUTO_LAYOUT' }
  | { type: 'COMMAND'; command: 'LAYOUT_FIT_TO_VIEW' };

// ─── Cue List Browser Commands ──────────────────────────────────────────────

export type CueListBrowserCommand =
  | { type: 'COMMAND'; command: 'CUE_LIST_OPEN'; payload: { cueListId: string } }
  | { type: 'COMMAND'; command: 'CUE_LIST_CREATE' };
```

**Step 3: Run tests**

```bash
npm test
```

**Step 4: Commit**

```bash
git add src/types/messages.ts src/__tests__/new-commands.test.ts
git commit -m "feat: add command types for effects, look board, navigation, layout, and global"
```

---

## Phase 3: New Shared Modes

Each mode implements the `BaseMode` interface with `getKeyMapping()`, `getDialMapping()`, and `getTouchStripFeedback()`.

### Task 9: Implement Navigation Mode

**Files:**
- Create: `src/core/modes/navigation-mode.ts`
- Create: `src/__tests__/navigation-mode.test.ts`

This is the simplest mode — 6 navigation keys + FTB + NAV, minimal dial usage. Build and test it first as the pattern for all other modes.

**Step 1: Write comprehensive test**

Test key presses generate `NAVIGATE` commands with correct routes. Test FTB generates `GLOBAL_FTB`. Test NAV key toggles back to auto-detected mode. Test `getKeyMapping()` returns 8 entries with correct labels. Test `getDialMapping()` returns dial configs. Test `getTouchStripFeedback()` returns 4 segments.

**Step 2: Implement `src/core/modes/navigation-mode.ts`**

Key mapping per design doc section 8. Handle `KeyEvent` for indices 0-7. Dial 0 rotate = undo/redo scroll, Dial 3 = master intensity.

**Step 3: Run tests, commit**

---

### Task 10: Implement Look Board Mode

**Files:**
- Create: `src/core/modes/look-board-mode.ts`
- Create: `src/__tests__/look-board-mode.test.ts`

**Key behaviors:**
- Keys 0-6 (indices 0-6) map to paged look board buttons. Pressing activates the look.
- Key 7 = NAV
- Dial 0 = page through pages, Dial 1 = fade time, Dial 2 = scroll boards, Dial 3 = master/FTB
- Touch strip: page indicator, fade time, board name, active look

**Step 1: Write tests covering:**
- Key press with valid look → `BOARD_ACTIVATE_LOOK`
- Key press on empty slot → no command
- Dial page rotation → update current page
- Fade time adjustment clamps to reasonable range
- `getKeyMapping()` returns dynamic look names from state
- Touch strip feedback includes page info

**Step 2: Implement mode**

**Step 3: Run tests, commit**

---

### Task 11: Implement Effect Editor Mode

**Files:**
- Create: `src/core/modes/effect-editor-mode.ts`
- Create: `src/__tests__/effect-editor-mode.test.ts`

**Key behaviors:**
- Keys: SAVE, UNDO, REDO, START/STOP, TYPE, PREVIEW, FTB, NAV
- Dials: param cycle, param value, frequency, amplitude
- Touch: effect name, param value bar, speed bar, amplitude bar

**Step 1: Write tests**

**Step 2: Implement mode**

**Step 3: Run tests, commit**

---

### Task 12: Implement Cue List Browser Mode

**Files:**
- Create: `src/core/modes/cue-list-browser-mode.ts`
- Create: `src/__tests__/cue-list-browser-mode.test.ts`

**Key behaviors:**
- Keys 0-5 = paged cue list names
- Key 6 = NEW (create cue list)
- Key 7 = NAV
- Dial 0 = scroll through cue lists

**Step 1: Write tests**

**Step 2: Implement mode**

**Step 3: Run tests, commit**

---

### Task 13: Implement Look Editor Layout Mode

**Files:**
- Create: `src/core/modes/look-editor-layout-mode.ts`
- Create: `src/__tests__/look-editor-layout-mode.test.ts`

This is a variant of the existing look editor mode but with layout-specific controls (select all, deselect, snap, zoom, pan).

**Key behaviors:**
- Keys: SAVE, UNDO, REDO, CHANNELS (switch mode), SEL ALL, DESEL, SNAP, NAV
- Dials: fixture cycle, zoom, pan X, pan Y
- Touch: selection info, zoom level, count, snap status

**Step 1: Write tests**

**Step 2: Implement mode**

**Step 3: Run tests, commit**

---

### Task 14: Update Existing Modes for New Interface

**Files:**
- Modify: `src/modes/cue-player-mode.ts`
- Modify: `src/modes/look-editor-mode.ts`
- Modify: `src/modes/color-picker-mode.ts`
- Modify existing test files

Update the 3 existing modes to implement the new `getKeyMapping()`, `getDialMapping()`, `getTouchStripFeedback()` methods from the core `BaseMode`. Also update them to support 8 keys (SD+) and 4 dials (SD+) in addition to existing N3 layouts.

For the color picker specifically:
- Keys 0-3: MRU colors (default Red, Green, Blue, White), updated as user selects colors
- Key 4: TAB toggle
- Key 5: Reserved
- Key 6: APPLY
- Key 7: CANCEL

Add `modeId` property to each mode.

**Step 1: Update CuePlayerMode — add `getKeyMapping(8)` for SD+ with LOOP button**

**Step 2: Update LookEditorMode — rename to channels mode, add `getKeyMapping(8)` with ACTIVE and LAYOUT toggle**

**Step 3: Update ColorPickerMode — MRU color tracking, TAB toggle key, 8-key layout**

**Step 4: Run all tests (existing + new)**

```bash
npm test
```

**Step 5: Commit**

```bash
git commit -m "feat: update existing modes with key/dial/touch mapping and SD+ support"
```

---

## Phase 4: Elgato Stream Deck + Adapter

### Task 15: Add Elgato SDK Dependency & Scaffold

**Files:**
- Modify: `package.json`
- Create: `src/adapters/elgato/manifest.json`
- Create: `src/adapters/elgato/plugin.ts`

**Step 1: Install Elgato SDK**

```bash
npm install @elgato/streamdeck
```

**Step 2: Create Elgato manifest.json**

```json
{
  "Name": "LacyLights",
  "Version": "0.1.0",
  "Description": "Theatrical lighting control for LacyLights",
  "Author": "LacyLights",
  "Category": "Lighting",
  "Icon": "imgs/plugin/icon",
  "URL": "https://github.com/bbernstein/lacylights-streamdeck",
  "SDKVersion": 2,
  "Software": { "MinimumVersion": "6.9" },
  "Nodejs": { "Version": "20", "Debug": "enabled" },
  "OS": [
    { "Platform": "mac", "MinimumVersion": "10.15" },
    { "Platform": "windows", "MinimumVersion": "10" }
  ],
  "Actions": [
    {
      "Name": "LacyLights Key",
      "UUID": "com.lacylights.streamdeck.key",
      "Icon": "imgs/actions/key/icon",
      "Controllers": ["Keypad"],
      "States": [{ "Image": "imgs/actions/key/key" }]
    },
    {
      "Name": "LacyLights Encoder",
      "UUID": "com.lacylights.streamdeck.encoder",
      "Icon": "imgs/actions/encoder/icon",
      "Controllers": ["Encoder"],
      "Encoder": {
        "layout": "$B1",
        "TriggerDescription": {
          "Rotate": "Adjust",
          "Push": "Select",
          "Touch": "Tap"
        }
      }
    }
  ]
}
```

**Step 3: Create plugin entry point scaffold**

`src/adapters/elgato/plugin.ts`:

```typescript
import streamDeck from '@elgato/streamdeck';
import { LacyLightsKeyAction } from './actions/key-action';
import { LacyLightsEncoderAction } from './actions/encoder-action';

// Register actions
streamDeck.actions.registerAction(new LacyLightsKeyAction());
streamDeck.actions.registerAction(new LacyLightsEncoderAction());

// Connect to Stream Deck
streamDeck.connect();
```

**Step 4: Commit**

```bash
git commit -m "feat: scaffold Elgato Stream Deck + adapter with manifest and entry point"
```

---

### Task 16: Implement Elgato Key Action

**Files:**
- Create: `src/adapters/elgato/actions/key-action.ts`
- Create: `src/__tests__/elgato-key-action.test.ts`

**Step 1: Write test**

Test that `onKeyDown` translates coordinates to key index and calls the active mode's `handleEvent()` with a `KeyEvent`. Test that `onWillAppear` registers the action context. Test `setImage` is called with SVG data on state updates.

**Step 2: Implement**

```typescript
import { action, KeyDownEvent, SingletonAction, WillAppearEvent } from '@elgato/streamdeck';

@action({ UUID: 'com.lacylights.streamdeck.key' })
export class LacyLightsKeyAction extends SingletonAction {
  // Track key contexts by coordinate
  private keyContexts = new Map<string, { row: number; col: number }>();

  override onWillAppear(ev: WillAppearEvent): void {
    const { row, column } = ev.payload.coordinates ?? { row: 0, column: 0 };
    this.keyContexts.set(ev.action.id, { row, col: column });
  }

  override onKeyDown(ev: KeyDownEvent): void {
    const { row, column } = ev.payload.coordinates ?? { row: 0, column: 0 };
    const keyIndex = row * 4 + column; // SD+ has 4 columns
    // Dispatch to bridge manager
  }
}
```

**Step 3: Run tests, commit**

---

### Task 17: Implement Elgato Encoder Action

**Files:**
- Create: `src/adapters/elgato/actions/encoder-action.ts`
- Create: `src/__tests__/elgato-encoder-action.test.ts`

**Step 1: Write test**

Test `onDialRotate` translates to `DialEvent` with correct ticks/pressed. Test `onDialDown`/`onDialUp` generate press/release events. Test `onTouchTap` generates `TouchEvent` with coordinates and hold flag. Test `setFeedback` and `setFeedbackLayout` are called on state updates.

**Step 2: Implement**

```typescript
import {
  action,
  DialDownEvent,
  DialRotateEvent,
  DialUpEvent,
  TouchTapEvent,
  SingletonAction,
} from '@elgato/streamdeck';

@action({ UUID: 'com.lacylights.streamdeck.encoder' })
export class LacyLightsEncoderAction extends SingletonAction {
  override onDialRotate(ev: DialRotateEvent): void {
    const dialIndex = ev.payload.coordinates?.column ?? 0;
    // Create DialEvent and dispatch
  }

  override onDialDown(ev: DialDownEvent): void {
    const dialIndex = ev.payload.coordinates?.column ?? 0;
    // Create DialEvent press and dispatch
  }

  override onDialUp(ev: DialUpEvent): void {
    const dialIndex = ev.payload.coordinates?.column ?? 0;
    // Create DialEvent release and dispatch
  }

  override onTouchTap(ev: TouchTapEvent): void {
    const segmentIndex = ev.payload.coordinates?.column ?? 0;
    const [x, y] = ev.payload.tapPos ?? [0, 0];
    // Create TouchEvent and dispatch
  }
}
```

**Step 3: Run tests, commit**

---

### Task 18: Implement Elgato Bridge Manager

**Files:**
- Create: `src/adapters/elgato/bridge-manager.ts`
- Create: `src/__tests__/elgato-bridge-manager.test.ts`

The bridge manager connects the Elgato actions to the shared core. It:
1. Creates and manages the WebSocket bridge to the frontend
2. Maintains the mode manager (detects mode, switches active mode)
3. Translates hardware events from actions → core mode → frontend commands
4. Updates key images and touch strip feedback when state changes

**Step 1: Write test**

Test state updates trigger mode detection. Test hardware events are routed to active mode. Test key images are updated via action `setImage()`. Test touch strip feedback is updated via `setFeedback()`.

**Step 2: Implement**

This is the central orchestrator for the Elgato adapter — equivalent to `StreamDockPlugin` in `src/index.ts` but using the Elgato SDK surface.

**Step 3: Run tests, commit**

---

### Task 19: Create Custom Touch Strip Layouts

**Files:**
- Create: `src/adapters/elgato/layouts/cue-player.json`
- Create: `src/adapters/elgato/layouts/look-editor.json`
- Create: `src/adapters/elgato/layouts/color-picker.json`
- Create: `src/adapters/elgato/layouts/look-board.json`
- Create: `src/adapters/elgato/layouts/default.json`

Each layout is a JSON file defining the touch strip segment items (text, bars, icons) for each mode.

**Step 1: Create cue player layout (segment template)**

```json
{
  "$schema": "https://schemas.elgato.com/streamdeck/plugins/layout.json",
  "id": "lacylights-cue-player",
  "items": [
    {
      "key": "title",
      "type": "text",
      "rect": [8, 6, 184, 20],
      "font": { "size": 14, "weight": 600 },
      "alignment": "left"
    },
    {
      "key": "value",
      "type": "text",
      "rect": [8, 28, 184, 24],
      "font": { "size": 20, "weight": 700 },
      "alignment": "center"
    },
    {
      "key": "bar",
      "type": "bar",
      "rect": [8, 60, 184, 16],
      "subtype": 4,
      "range": { "min": 0, "max": 100 },
      "bar_fill_c": "0:#00cc66,1:#00cc66"
    }
  ]
}
```

**Step 2: Create similar layouts for each mode**

Adjust labels, bar colors, and item arrangement per the design doc touch strip sections.

**Step 3: Create color picker layout with gradient bar for hue**

Use `$B2` (gradient bar) for the hue segment showing a rainbow gradient.

**Step 4: Commit**

```bash
git commit -m "feat: add custom touch strip layouts for all modes"
```

---

### Task 20: Add Elgato Build Configuration

**Files:**
- Modify: `package.json` (add build:elgato script)
- Create: `scripts/build-elgato.sh`
- Create: `scripts/package-elgato.sh`

**Step 1: Add esbuild entry point for Elgato**

```bash
# In package.json scripts:
"build:elgato": "esbuild src/adapters/elgato/plugin.ts --bundle --platform=node --target=node20 --outfile=dist-elgato/plugin.js --sourcemap"
"build:streamdock": "esbuild src/index.ts --bundle --platform=node --target=node20 --outfile=dist/index.js --sourcemap"
"build:all": "npm run build:streamdock && npm run build:elgato"
```

**Step 2: Create packaging script for Elgato .sdPlugin bundle**

```bash
#!/bin/bash
# scripts/package-elgato.sh
PLUGIN_DIR="com.lacylights.streamdeck.sdPlugin"
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR/bin" "$PLUGIN_DIR/imgs" "$PLUGIN_DIR/layouts"
cp dist-elgato/plugin.js "$PLUGIN_DIR/bin/"
cp src/adapters/elgato/manifest.json "$PLUGIN_DIR/"
cp -r src/adapters/elgato/layouts/*.json "$PLUGIN_DIR/layouts/"
# Copy images...
echo "Packaged to $PLUGIN_DIR"
```

**Step 3: Run build to verify**

```bash
npm run build:all
```

**Step 4: Commit**

```bash
git commit -m "feat: add Elgato build and packaging configuration"
```

---

## Phase 5: Frontend Integration

### Task 21: Extend StreamDockContext with New Handlers

**Files:**
- Modify: `lacylights-fe/src/contexts/StreamDockContext.tsx`
- Modify: `lacylights-fe/src/contexts/__tests__/StreamDockContext.test.tsx`

**Step 1: Add new handler interfaces**

```typescript
export interface EffectEditorHandlers {
  handleSave: () => void;
  handleUndo: () => void;
  handleRedo: () => void;
  handleStartStop: () => void;
  handleCycleType: () => void;
  handleTogglePreview: () => void;
  handleSetParam: (paramName: string, value: number) => void;
}

export interface LookBoardHandlers {
  handleActivateLook: (lookId: string, slotIndex: number) => void;
  handlePageNext: () => void;
  handlePagePrev: () => void;
  handleSetFadeTime: (seconds: number) => void;
}

export interface GlobalHandlers {
  handleUndo: () => void;
  handleRedo: () => void;
  handleFadeToBlack: () => void;
  handleSetMaster: (intensity: number) => void;
}

export interface LayoutHandlers {
  handleZoom: (delta: number) => void;
  handlePan: (deltaX: number, deltaY: number) => void;
  handleSelectAll: () => void;
  handleDeselectAll: () => void;
  handleToggleSnap: () => void;
  handleAutoLayout: () => void;
  handleFitToView: () => void;
}
```

**Step 2: Add registration methods to context**

Add `registerEffectEditorHandlers`, `registerLookBoardHandlers`, `registerGlobalHandlers`, `registerLayoutHandlers` to the context interface and provider.

**Step 3: Add new publish methods**

Add `publishEffectEditorState`, `publishLookBoardState`, `publishCueListBrowserState`, `publishGlobalState`.

**Step 4: Extend command dispatcher**

Add switch cases for all new commands (EFFECT_*, BOARD_*, GLOBAL_*, LAYOUT_*, CUE_LIST_*).

**Step 5: Update mode detection**

Extend `detectMode()` to return the expanded mode set matching the design doc's mode detection logic.

**Step 6: Write tests for all new dispatches**

**Step 7: Run frontend tests**

```bash
cd ~/src/lacylights/lacylights-fe && npm test -- --testPathPattern StreamDock
```

**Step 8: Commit**

```bash
git commit -m "feat: extend StreamDockContext with handlers for effects, look board, layout, and global"
```

---

### Task 22: Add State Publishing to Look Board Component

**Files:**
- Modify: `lacylights-fe/src/components/LookBoardCanvas.tsx` (or equivalent)

Add `useStreamDock()` hook call. Publish `LookBoardState` on mount and whenever buttons, active look, or page changes. Register `LookBoardHandlers`.

**Step 1: Add useStreamDock integration**

**Step 2: Write test**

**Step 3: Commit**

---

### Task 23: Add State Publishing to Effect Editor Component

**Files:**
- Modify: `lacylights-fe/src/components/EffectEditor.tsx` (or equivalent)

Same pattern: publish `EffectEditorState`, register `EffectEditorHandlers`.

**Step 1-3: Implement, test, commit**

---

### Task 24: Add Global State Publishing

**Files:**
- Modify: `lacylights-fe/src/contexts/StreamDockContext.tsx`

The global state (undo/redo availability, master intensity, blackout status) should be published from the `UndoRedoProvider` or a new hook that aggregates this info.

**Step 1: Add global state aggregation**

**Step 2: Register global handlers for undo/redo/FTB/master**

**Step 3: Write tests, commit**

---

### Task 25: Add Navigation Command Handling

**Files:**
- Modify: `lacylights-fe/src/contexts/StreamDockContext.tsx`

The `NAV_GO_TO` command should use Next.js router to navigate. The `NAV_BACK` command should use `router.back()`.

**Step 1: Update NAVIGATE handling to use Next.js router instead of window.location**

```typescript
import { useRouter } from 'next/navigation';

// In dispatchCommand:
case 'NAV_GO_TO':
  if (payload?.route && typeof payload.route === 'string') {
    router.push(payload.route);
  }
  return;
case 'NAV_BACK':
  router.back();
  return;
```

**Step 2: Write tests, commit**

---

## Phase 6: Integration Testing & Polish

### Task 26: End-to-End Integration Test

**Files:**
- Create: `src/__tests__/integration/elgato-full-flow.test.ts`

Test the complete flow:
1. Bridge connects
2. Frontend sends STATE_UPDATE for cue player page
3. Mode auto-detects to cue_player
4. Key press on index 0 → GO command sent to frontend
5. State update with fadeProgress → touch strip feedback updated
6. Navigate to look editor → mode switches to look_editor_channels

Mock the Elgato SDK and WebSocket, but test the full chain from hardware event → command → state update → visual feedback.

**Step 1: Write integration test**

**Step 2: Run all tests**

```bash
npm test
```

**Step 3: Commit**

---

### Task 27: Update CI Configuration

**Files:**
- Modify: `.github/workflows/ci.yml` (if exists)

Add build:all step to CI. Ensure both streamdock and elgato builds succeed. Coverage thresholds remain at 80%.

**Step 1: Update CI to build both targets**

**Step 2: Commit**

---

### Task 28: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (if exists)

Update to reflect the shared architecture, both supported devices, new build scripts, and installation instructions for the Elgato Stream Deck +.

**Step 1: Update docs**

**Step 2: Commit**

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1 | 1-6 | Rename repo, extract shared core (no behavior changes) |
| 2 | 7-8 | Extended protocol types and commands |
| 3 | 9-14 | New modes (navigation, look board, effects, browser, layout) + update existing |
| 4 | 15-20 | Elgato SDK adapter (actions, bridge manager, layouts, build) |
| 5 | 21-25 | Frontend integration (new handlers, state publishing, navigation) |
| 6 | 26-28 | Integration tests, CI, documentation |

Total: 28 tasks across 6 phases. Each phase builds on the previous and can be verified independently.
