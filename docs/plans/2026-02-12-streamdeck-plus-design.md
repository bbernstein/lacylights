# Stream Deck + Integration Design

**Date**: 2026-02-12
**Status**: Approved
**Repo**: lacylights-streamdeck (renamed from lacylights-streamdock)

## Overview

Add Elgato Stream Deck + support to the LacyLights hardware control surface plugin. The Stream Deck + provides 8 LCD keys, 4 rotary dials (with press), and a touch strip display (4 × 200×100 segments) — significantly more controls than the Stream Dock N3.

The existing `lacylights-streamdock` repo is renamed to `lacylights-streamdeck` and refactored into a shared core with thin adapter layers for each hardware platform.

## Hardware Comparison

| Feature | Stream Dock N3 | Elgato Stream Deck + |
|---------|---------------|---------------------|
| LCD keys | 6 | 8 |
| Plain keys | 3 | 0 |
| Knobs/dials | 3 (1 large + 2 small) | 4 (equal, with press + rotate) |
| Touch strip | No | Yes (800×100, 4 segments) |
| Key resolution | Varies | 72×72 / 144×144 |
| SDK | Stream Dock SDK | `@elgato/streamdeck` (npm) |
| Host app | Stream Dock | Elgato Stream Deck |

## Architecture

### Repo Structure

```
lacylights-streamdeck/
  src/
    core/
      bridge/          # WebSocket bridge client (port 4100)
      state/           # State manager (tracks frontend state)
      modes/           # Mode definitions (shared logic)
      commands/        # Command protocol types & handlers
      icons/           # Icon/image generation (SVG)
      types.ts         # Shared types
    adapters/
      streamdock/      # Stream Dock N3 SDK adapter
        sdk-client.ts
        manifest.json
      elgato/          # Elgato Stream Deck + SDK adapter
        plugin.ts      # Entry point using @elgato/streamdeck
        actions/       # Action classes (KeyAction, EncoderAction)
        layouts/       # Custom touch strip layouts (JSON)
        manifest.json
    index-streamdock.ts
    index-elgato.ts
```

### Communication

Both adapters share the same WebSocket bridge protocol to the frontend on port 4100. The frontend's `StreamDockContext` serves both devices without modification (beyond supporting new commands).

```
Hardware → Host App → Plugin Adapter → Shared Core → WebSocket Bridge → Frontend
Frontend → WebSocket Bridge → Shared Core → Plugin Adapter → Host App → Hardware
```

### Mode Interface

Each mode implements:
- `getKeyMapping(keyCount)` — returns key labels, actions, visual state
- `getDialMapping(dialCount)` — returns dial rotate/press handlers
- `getTouchStripLayout()` — returns layout + feedback data (Elgato only)

The Stream Dock adapter queries only the controls it has; the Elgato adapter queries all three.

## Operating Modes

| Mode | Auto-detected Route | Priority |
|------|-------------------|----------|
| Color Picker | Any page + modal open | 1 (highest) |
| Cue Player | `/cue-lists/[id]` or `/player/[id]` | 2 |
| Look Editor (Channels) | `/looks/[id]/edit` (channels mode) | 3 |
| Look Editor (Layout) | `/looks/[id]/edit` (layout mode) | 4 |
| Effect Editor | `/effects/[id]/edit` | 5 |
| Look Board | `/look-board/[id]` | 6 |
| Cue List Browser | `/cue-lists` | 7 |
| Navigation/Dashboard | `/`, `/fixtures`, `/looks`, `/settings`, etc. | 8 (lowest) |

Color Picker overrides all modes as a modal overlay. Key 8 provides manual mode override via navigation.

### Mode Detection

```typescript
function detectMode(state: StateUpdate): Mode {
  if (state.colorPicker?.isOpen) return 'color_picker';
  if (state.route.match(/\/player\//)) return 'cue_player';
  if (state.route.match(/\/cue-lists\/\w+/)) return 'cue_player';
  if (state.route.match(/\/looks\/\w+\/edit/)) {
    if (state.lookEditor?.editorMode === 'layout') return 'look_editor_layout';
    if (state.lookEditor?.selectedFixtureIndex >= 0) return 'channel_editor';
    return 'look_editor_channels'; // fixture browser (no fixture selected or initial load)
  }
  if (state.route.match(/\/effects\/\w+\/edit/)) return 'effect_editor';
  if (state.route.match(/\/look-board\/\w+/)) return 'look_board';
  if (state.route === '/cue-lists') return 'cue_list_browser';
  return 'navigation';
}
```

## Control Mappings — Stream Deck +

Physical layout:
```
Keys:    [1] [2] [3] [4]         Touch:  [----1----][----2----][----3----][----4----]
         [5] [6] [7] [8]         Dials:    (1)        (2)        (3)        (4)
```

Key 8 is always the **NAV key** (except in Color Picker where it becomes CANCEL).

---

### Mode 1: Cue Player

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | **GO** | Play next cue | Green when ready, pulsing during fade, gray when stopped |
| 2 | PREV | Previous cue | Dimmed if at first cue |
| 3 | STOP | Stop playback | Red during playback, dimmed when stopped |
| 4 | HURRY | Speed up current fade | Lit only during active fade |
| 5 | FTB | Fade to black | Red tint when blacked out |
| 6 | EDIT | Open look editor for current cue's look | Dimmed if no cue selected |
| 7 | LOOP | Toggle cue list loop | Lit when loop enabled |
| 8 | **NAV** | Navigation mode | Always available |

#### Dials

| Dial | Rotate | Press | Rotate+Press |
|------|--------|-------|--------------|
| 1 | Scroll cue list (highlight next/prev) | Jump to highlighted cue | Fast scroll (×5 per tick) |
| 2 | Master intensity (0-100%) | Reset to 100% | — |
| 3 | Adjust fade-in time (±0.1s) | Reset to cue default | Coarse (±1s) |
| 4 | Adjust fade-out time (±0.1s) | Reset to cue default | Coarse (±1s) |

#### Touch Strip

| Segment | Content | Tap |
|---------|---------|-----|
| 1 | Current cue: name + number, fade progress bar | GO |
| 2 | Next cue: name + number | Jump to next |
| 3 | "Fade In" + time value + bar | Reset to default |
| 4 | "Fade Out" + time value + bar | Reset to default |

---

### Mode 2: Look Editor — Fixture Browser (`look_editor_channels`)

Fixture-only browser mode. When a fixture is selected (via dial 0 press), the frontend switches to Channel Editor mode (Mode 2B).

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | **SAVE** | Save look | Orange `*` badge when unsaved |
| 2 | UNDO | Undo | Dimmed if unavailable |
| 3 | REDO | Redo | Dimmed if unavailable |
| 4 | PREVIEW | Toggle live preview | Lit when active |
| 5 | COLOR | Open color picker | Shows fixture color swatch |
| 6 | LAYOUT | Switch to Layout mode | — |
| 7 | — | Reserved | — |
| 8 | **NAV** | Navigation | — |

#### Dials

| Dial | Rotate | Press | Rotate+Press |
|------|--------|-------|--------------|
| 1 | Navigate fixtures | Select highlighted fixture → switch to Channel Editor | — |
| 2-4 | — | — | — |

#### Touch Strip

| Segment | Content | Layout |
|---------|---------|--------|
| 1 | Look name | `$B1` |
| 2 | Highlighted fixture name + index | `$B1` |
| 3 | Fixture count (e.g., "3/12") | `$B1` |
| 4 | Preview status | `$B1` |

---

### Mode 2B: Channel Editor (`channel_editor`)

Active when a fixture is selected for channel editing. Provides fine-grained control over individual channel values.

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | **SAVE** | Save look | Orange `*` badge when unsaved |
| 2 | UNDO | Undo | Dimmed if unavailable |
| 3 | REDO | Redo | Dimmed if unavailable |
| 4 | PREVIEW | Toggle live preview | Lit when active |
| 5 | COLOR | Open color picker | Shows fixture color swatch |
| 6 | DESEL | Deselect fixture → back to Fixture Browser | — |
| 7 | ACTIVE | Toggle channel active/inactive | Green when active, gray when inactive |
| 8 | **NAV** | Navigation | — |

#### Dials

| Dial | Rotate | Press | Rotate+Press |
|------|--------|-------|--------------|
| 1 | Cycle through fixtures | Select highlighted fixture | — |
| 2 | Cycle through channels | Toggle channel active | — |
| 3 | Coarse channel value ±5 (velocity-scaled) | Toggle 0 ↔ 255 | — |
| 4 | Fine channel value ±1 (velocity-scaled) | Set to 50% (128) | — |

#### Touch Strip

| Segment | Content | Layout |
|---------|---------|--------|
| 1 | Fixture name + index (e.g., "PAR 64 [3/12]") | `$B1` |
| 2 | Channel name + type (e.g., "Red - RGB") | `$B1` |
| 3 | Channel value + bar (coarse) | `$B1` |
| 4 | Channel value + bar (fine mirror) | `$B1` |

---

### Mode 3: Look Editor — Layout

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | **SAVE** | Save look | Orange `*` badge when unsaved |
| 2 | UNDO | Undo | Dimmed if unavailable |
| 3 | REDO | Redo | Dimmed if unavailable |
| 4 | CHANNELS | Switch to Channels mode | — |
| 5 | SEL ALL | Select all fixtures | — |
| 6 | DESEL | Deselect all | Dimmed if none selected |
| 7 | SNAP | Toggle snap-to-grid | Lit when snap enabled |
| 8 | **NAV** | Navigation | — |

#### Dials

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Cycle through fixtures (highlight) | Toggle select on highlighted |
| 2 | Zoom in/out | Reset zoom to fit |
| 3 | Pan canvas X | Auto-layout fixtures |
| 4 | Pan canvas Y | Fit all to view |

#### Touch Strip

| Segment | Content |
|---------|---------|
| 1 | Selected fixture name (or "N selected") |
| 2 | Zoom level + bar |
| 3 | Selection count (e.g., "4 of 12") |
| 4 | Grid: "Snap ON" / "Snap OFF" |

---

### Mode 4: Color Picker (Modal Overlay)

Highest priority — overrides any other mode when color picker modal is open. Key 8 becomes CANCEL (closing the modal returns to the underlying mode).

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | MRU 1 | Apply most recent color | Color swatch |
| 2 | MRU 2 | Apply 2nd most recent | Color swatch |
| 3 | MRU 3 | Apply 3rd most recent | Color swatch |
| 4 | MRU 4 | Apply 4th most recent | Color swatch |
| 5 | TAB | Toggle Color Wheel ↔ Roscolux | Shows current tab name |
| 6 | — | (Reserved) | — |
| 7 | **APPLY** | Apply color & close | Green checkmark |
| 8 | **CANCEL** | Close without applying | Red X |

MRU colors default to Red, Green, Blue, White and update as the user selects colors.

#### Dials — Color Wheel Tab

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Hue ±5° (velocity-scaled, wraps 0-360) | Apply & close |
| 2 | Saturation ±2% (0-100%) | Reset to 100% |
| 3 | Brightness ±2% (0-100%) | Reset to 100% |
| 4 | — | — |

#### Dials — Roscolux Tab

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Navigate swatches | Select highlighted swatch |
| 2 | Scroll swatch categories | — |
| 3 | — | — |
| 4 | — | — |

#### Touch Strip (custom layout)

| Segment | Content |
|---------|---------|
| 1 | "H" + hue value + rainbow gradient bar |
| 2 | "S" + saturation value + bar |
| 3 | "B" + brightness value + bar |
| 4 | Color preview (filled with current color) |

---

### Mode 5: Look Board

#### Keys (Paged — 7 looks per page)

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1-7 | Look name (dynamic) | Activate that look | Color swatch, bright border when active, dimmed if empty |
| 8 | **NAV** | Navigation | — |

#### Dials

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Page through pages (7 per page) | — |
| 2 | Adjust crossfade time (±0.1s) | Reset to default |
| 3 | Scroll through boards | Open selected board |
| 4 | Master intensity (0-100%) | Fade to black |

#### Touch Strip

| Segment | Content |
|---------|---------|
| 1 | Page indicator: "Page 1/3" |
| 2 | "Fade" + crossfade time + bar |
| 3 | Board name |
| 4 | Active look name + color swatch |

---

### Mode 6: Effect Editor

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | **SAVE** | Save effect | Orange badge when unsaved |
| 2 | UNDO | Undo | Dimmed if unavailable |
| 3 | REDO | Redo | Dimmed if unavailable |
| 4 | ▶/⏹ | Start/stop effect | Green running, red stopped |
| 5 | TYPE | Cycle effect type | Shows current type icon |
| 6 | PREVIEW | Toggle preview | Lit when active |
| 7 | FTB | Fade to black | — |
| 8 | **NAV** | Navigation | — |

#### Dials

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Cycle parameters | Select for editing |
| 2 | Adjust selected parameter | Reset to default |
| 3 | Adjust frequency/speed | Reset |
| 4 | Adjust amplitude/intensity | Reset |

#### Touch Strip

| Segment | Content |
|---------|---------|
| 1 | Effect name + type badge |
| 2 | Selected param name + value + bar |
| 3 | "Speed" + frequency + bar |
| 4 | "Amp" + amplitude + bar |

---

### Mode 7: Cue List Browser

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1-6 | Cue list names (paged) | Open selected cue list | Shows cue count badge |
| 7 | **NEW** | Create new cue list | + icon |
| 8 | **NAV** | Navigation | — |

#### Dials

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Scroll through cue lists | Open highlighted list |
| 2-4 | — | — |

#### Touch Strip

| Segment | Content |
|---------|---------|
| 1 | Highlighted cue list name |
| 2 | Cue count + last modified |
| 3-4 | — |

---

### Mode 8: Navigation / Dashboard

Active on pages without specific controls, or when NAV key is pressed.

#### Keys

| Key | Label | Action | Visual Feedback |
|-----|-------|--------|-----------------|
| 1 | FIXTURES | Go to `/fixtures` | Highlighted if current page |
| 2 | LOOKS | Go to `/looks` | Highlighted if current page |
| 3 | EFFECTS | Go to `/effects` | Highlighted if current page |
| 4 | BOARDS | Go to `/look-board` | Highlighted if current page |
| 5 | CUES | Go to `/cue-lists` | Highlighted if current page |
| 6 | SETTINGS | Go to `/settings` | Highlighted if current page |
| 7 | **FTB** | Fade to black | Red when blacked out |
| 8 | **NAV** | Highlighted (current mode) | Bright/active state |

#### Dials

| Dial | Rotate | Press |
|------|--------|-------|
| 1 | Undo/redo history scroll | Jump to operation |
| 2-3 | — | — |
| 4 | Master intensity | Fade to black |

#### Touch Strip

| Segment | Content |
|---------|---------|
| 1 | Current page name |
| 2 | Project name |
| 3 | Connection status |
| 4 | Master intensity + bar |

---

## NAV Key Behavior

Key 8 is the **mode override toggle**:

- **Single press**: Enter Navigation mode (keys show screen selector). If already in Navigation, return to auto-detected mode.
- **In Navigation mode**: Keys 1-6 navigate the browser to that screen. The mode auto-switches when the frontend reports the new route.
- **Visual**: NAV key shows the current mode icon. In Navigation mode, shows a bright "back" indicator.

## Frontend Bridge Protocol Extensions

### New State Fields

```typescript
interface StateUpdate {
  // Existing
  mode: string;
  route: string;
  cuePlayer?: CuePlayerState;
  lookEditor?: LookEditorState;
  colorPicker?: ColorPickerState;

  // New
  effectEditor?: EffectEditorState;
  lookBoard?: LookBoardState;
  cueListBrowser?: CueListBrowserState;
  navigation?: NavigationState;
  global?: GlobalState;
}
```

### New Commands

| Category | Command | Payload |
|----------|---------|---------|
| Effect | `EFFECT_START` | `{ effectId }` |
| Effect | `EFFECT_STOP` | `{ effectId }` |
| Effect | `EFFECT_SET_PARAM` | `{ paramName, value }` |
| Look Board | `BOARD_ACTIVATE_LOOK` | `{ lookId, pageIndex, slotIndex }` |
| Look Board | `BOARD_PAGE_NEXT` | — |
| Look Board | `BOARD_PAGE_PREV` | — |
| Look Board | `BOARD_SET_FADE_TIME` | `{ seconds }` |
| Navigation | `NAV_GO_TO` | `{ route }` |
| Navigation | `NAV_BACK` | — |
| Global | `GLOBAL_UNDO` | — |
| Global | `GLOBAL_REDO` | — |
| Global | `GLOBAL_FTB` | — |
| Global | `GLOBAL_SET_MASTER` | `{ intensity }` |
| Color Picker | `COLOR_SET_TAB` | `{ tab: 'wheel' \| 'roscolux' }` |
| Cue List Browser | `CUE_LIST_OPEN` | `{ cueListId }` |
| Cue List Browser | `CUE_LIST_CREATE` | — |
| Layout | `LAYOUT_ZOOM` | `{ delta }` |
| Layout | `LAYOUT_PAN` | `{ deltaX, deltaY }` |
| Layout | `LAYOUT_SELECT_ALL` | — |
| Layout | `LAYOUT_DESELECT_ALL` | — |
| Layout | `LAYOUT_TOGGLE_SNAP` | — |
| Layout | `LAYOUT_AUTO_LAYOUT` | — |
| Layout | `LAYOUT_FIT_TO_VIEW` | — |

## Stream Dock N3 Compatibility

The N3 continues working with its existing 3 modes (cue player, look editor, color picker). The shared core provides mode interfaces that gracefully degrade — modes requiring more controls than the N3 has (look board, effects, navigation) are not activated on that device.

## Elgato SDK Specifics

- **SDK**: `@elgato/streamdeck` npm package
- **Runtime**: Node.js 20+
- **Actions**: Two action classes — `KeyAction` (keypad controller) and `EncoderAction` (encoder controller)
- **Touch strip layouts**: Mix of built-in (`$A1`, `$B1`, `$B2`) and custom JSON layouts
- **Key images**: SVG rendered to 144×144 (high DPI)
- **Touch strip updates**: Via `setFeedback()` and `setFeedbackLayout()`
- **Update rate**: Max 10 image/feedback updates per second
