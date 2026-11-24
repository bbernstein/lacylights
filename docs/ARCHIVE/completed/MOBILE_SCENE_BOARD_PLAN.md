# Mobile-Optimized Scene Board Implementation Plan
**Status:** ✅ COMPLETED
**Created:** 2025-11-22
**Completed:** 2025-11-22
**Priority:** High

## Executive Summary

Transform the Scene Board from percentage-based (0-1) to pixel-based coordinates with a fixed canvas size, enabling proper zoom/pan support optimized for mobile devices. This is a **breaking schema change** that requires coordinated updates across three repositories.

## Problem Statement

Current Scene Board implementation uses percentage-based positioning (0-1 normalized coordinates), which causes:
- Buttons can overlap at different zoom levels and screen sizes
- No proper zoom/pan support for mobile devices
- Difficult to maintain consistent button sizing across devices
- Poor mobile UX for lighting technicians in the field

## Solution Overview

1. **Backend:** Change coordinate system from Float (0-1) to Int (pixels) with fixed 2000x2000px canvas
2. **Frontend:** Implement transform-based zoom/pan with touch gesture support
3. **MCP:** Regenerate types (no tools exist yet, so minimal impact)

## Cross-Repository Changes Required

### Repositories Affected:
1. **lacylights-node** (backend) - Schema, GraphQL, resolvers, tests
2. **lacylights-fe** (frontend) - UI, zoom/pan, touch gestures, responsive design
3. **lacylights-mcp** (MCP server) - Type regeneration only

---

## PHASE 1: Backend Schema & API Changes (lacylights-node)

**Branch:** `feature/scene-board-pixel-coordinates-backend`

### 1.1 Update Prisma Database Schema
**File:** `lacylights-node/prisma/schema.prisma`

**Changes to SceneBoard model:**
```prisma
model SceneBoard {
  id              String   @id @default(cuid())
  name            String
  description     String?
  projectId       String   @map("project_id")
  defaultFadeTime Float    @default(3.0) @map("default_fade_time")
  gridSize        Int?     @default(50) @map("grid_size")

  // NEW FIELDS:
  canvasWidth     Int      @default(2000) @map("canvas_width")
  canvasHeight    Int      @default(2000) @map("canvas_height")

  createdAt       DateTime @default(now()) @map("created_at")
  updatedAt       DateTime @updatedAt @map("updated_at")

  project         Project            @relation(fields: [projectId], references: [id], onDelete: Cascade)
  buttons         SceneBoardButton[]

  @@map("scene_boards")
}
```

**Changes to SceneBoardButton model:**
```prisma
model SceneBoardButton {
  id           String   @id @default(cuid())
  sceneBoardId String   @map("scene_board_id")
  sceneId      String   @map("scene_id")

  // CHANGED: Float (0-1) → Int (pixels)
  layoutX      Int      @map("layout_x")
  layoutY      Int      @map("layout_y")
  width        Int?     @default(200) @map("width")     // Changed from 0.1
  height       Int?     @default(120) @map("height")    // Changed from 0.1

  color        String?
  label        String?
  createdAt    DateTime @default(now()) @map("created_at")
  updatedAt    DateTime @updatedAt @map("updated_at")

  sceneBoard   SceneBoard @relation(fields: [sceneBoardId], references: [id], onDelete: Cascade)
  scene        Scene      @relation(fields: [sceneId], references: [id], onDelete: Cascade)

  @@unique([sceneBoardId, sceneId])
  @@map("scene_board_buttons")
}
```

### 1.2 Create Database Migration
```bash
cd lacylights-node
npx prisma migrate dev --name scene_board_pixel_coordinates
```

**Migration will:**
- Add `canvas_width` and `canvas_height` to `scene_boards` table
- Change column types in `scene_board_buttons`:
  - `layout_x`: REAL → INTEGER
  - `layout_y`: REAL → INTEGER
  - `width`: REAL → INTEGER
  - `height`: REAL → INTEGER

### 1.3 Write Data Migration Script
**File:** `lacylights-node/scripts/migrate-scene-board-coordinates.ts`

```typescript
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function migrateCoordinates() {
  const boards = await prisma.sceneBoard.findMany({
    include: { buttons: true }
  });

  for (const board of boards) {
    const canvasWidth = board.canvasWidth || 2000;
    const canvasHeight = board.canvasHeight || 2000;

    for (const button of board.buttons) {
      // Convert 0-1 normalized to pixels
      const layoutX = Math.round(button.layoutX * canvasWidth);
      const layoutY = Math.round(button.layoutY * canvasHeight);
      const width = button.width ? Math.round(button.width * canvasWidth) : 200;
      const height = button.height ? Math.round(button.height * canvasHeight) : 120;

      await prisma.sceneBoardButton.update({
        where: { id: button.id },
        data: { layoutX, layoutY, width, height }
      });
    }
  }
}

migrateCoordinates()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

### 1.4 Update GraphQL Schema
**File:** `lacylights-node/src/graphql/schema.ts`

**Update type definitions (around lines 113-137):**
```typescript
type SceneBoard {
  id: ID!
  name: String!
  description: String
  project: Project!
  defaultFadeTime: Float!
  gridSize: Int
  canvasWidth: Int!        # NEW
  canvasHeight: Int!       # NEW
  buttons: [SceneBoardButton!]!
  createdAt: String!
  updatedAt: String!
}

type SceneBoardButton {
  id: ID!
  sceneBoard: SceneBoard!
  scene: Scene!
  layoutX: Int!            # CHANGED: Float → Int
  layoutY: Int!            # CHANGED: Float → Int
  width: Int               # CHANGED: Float → Int
  height: Int              # CHANGED: Float → Int
  color: String
  label: String
  createdAt: String!
  updatedAt: String!
}
```

**Update input types:**
```typescript
input CreateSceneBoardInput {
  name: String!
  description: String
  projectId: ID!
  defaultFadeTime: Float = 3.0
  gridSize: Int = 50
  canvasWidth: Int = 2000   # NEW
  canvasHeight: Int = 2000  # NEW
}

input UpdateSceneBoardInput {
  name: String
  description: String
  defaultFadeTime: Float
  gridSize: Int
  canvasWidth: Int          # NEW
  canvasHeight: Int         # NEW
}

input CreateSceneBoardButtonInput {
  sceneBoardId: ID!
  sceneId: ID!
  layoutX: Int!             # CHANGED: Float → Int
  layoutY: Int!             # CHANGED: Float → Int
  width: Int = 200          # CHANGED: Float → Int, default 0.1 → 200
  height: Int = 120         # CHANGED: Float → Int, default 0.1 → 120
  color: String
  label: String
}

input UpdateSceneBoardButtonInput {
  layoutX: Int              # CHANGED: Float → Int
  layoutY: Int              # CHANGED: Float → Int
  width: Int                # CHANGED: Float → Int
  height: Int               # CHANGED: Float → Int
  color: String
  label: String
}

input SceneBoardButtonPositionInput {
  buttonId: ID!
  layoutX: Int!             # CHANGED: Float → Int
  layoutY: Int!             # CHANGED: Float → Int
}
```

### 1.5 Update GraphQL Resolvers
**File:** `lacylights-node/src/graphql/resolvers/sceneBoard.ts`

**Key changes:**
1. Add validation for pixel coordinates (must be within canvas bounds)
2. Update default values for width/height (200x120 instead of 0.1)
3. Ensure all coordinate operations use integers

**Example validation function:**
```typescript
function validateButtonPosition(
  layoutX: number,
  layoutY: number,
  width: number,
  height: number,
  canvasWidth: number,
  canvasHeight: number
): void {
  if (layoutX < 0 || layoutX > canvasWidth) {
    throw new Error(`layoutX must be between 0 and ${canvasWidth}`);
  }
  if (layoutY < 0 || layoutY > canvasHeight) {
    throw new Error(`layoutY must be between 0 and ${canvasHeight}`);
  }
  // Additional validation as needed
}
```

### 1.6 Update Backend Unit Tests
**File:** `lacylights-node/src/graphql/resolvers/__tests__/sceneBoard.test.ts`

**Changes needed:**
- Update all test data to use pixel coordinates (e.g., `layoutX: 1000` instead of `layoutX: 0.5`)
- Update expected values in assertions
- Add tests for canvas bounds validation
- Test default canvas size (2000x2000)
- Verify batch position updates work with Int values

**Example update:**
```typescript
// OLD:
const button = await addSceneToBoard({
  layoutX: 0.5,
  layoutY: 0.5,
  width: 0.1,
  height: 0.1
});

// NEW:
const button = await addSceneToBoard({
  layoutX: 1000,
  layoutY: 1000,
  width: 200,
  height: 120
});
```

### 1.7 Update Integration Tests
**File:** `lacylights-node/src/__tests__/integration/scenarios/live-busking.integration.test.ts`

**Update scene board button creation:**
```typescript
// OLD:
await addSceneToBoard({
  layoutX: 0.1,
  layoutY: 0.1
});

// NEW:
await addSceneToBoard({
  layoutX: 200,
  layoutY: 200
});
```

### 1.8 Backend Testing Checklist
- [ ] Run `npm test` - all tests pass
- [ ] Run `npm run lint` - no warnings
- [ ] Run `npm run type-check` - no type errors
- [ ] Manual test: Create scene board via GraphQL
- [ ] Manual test: Add buttons with pixel coordinates
- [ ] Manual test: Activate scene from board

### 1.9 Backend Commit & PR
```bash
cd lacylights-node
git add .
git commit -m "feat: convert Scene Board to pixel-based coordinates

- Update Prisma schema: Float → Int for coordinates
- Add canvasWidth/canvasHeight to SceneBoard model
- Update GraphQL schema and resolvers
- Add coordinate bounds validation
- Update all tests for pixel coordinates
- Change default button size from 0.1 to 200x120px

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin feature/scene-board-pixel-coordinates-backend
```

Then create PR using `gh` CLI or GitHub web interface.

---

## PHASE 2: Frontend Implementation (lacylights-fe)

**Branch:** `feature/mobile-scene-board-zoom`
**Prerequisite:** Backend PR must be merged first

### 2.1 Update TypeScript Types
**File:** `lacylights-fe/src/types/index.ts`

```typescript
export interface SceneBoard {
  id: string;
  name: string;
  description?: string;
  project: Project;
  defaultFadeTime: number;
  gridSize?: number;
  canvasWidth: number;     // NEW
  canvasHeight: number;    // NEW
  buttons: SceneBoardButton[];
  createdAt: string;
  updatedAt: string;
}

export interface SceneBoardButton {
  id: string;
  sceneBoard: SceneBoard;
  scene: Scene;
  layoutX: number;         // NOW pixels (Int)
  layoutY: number;         // NOW pixels (Int)
  width?: number;          // NOW pixels (Int)
  height?: number;         // NOW pixels (Int)
  color?: string;
  label?: string;
  createdAt: string;
  updatedAt: string;
}
```

### 2.2 Update GraphQL Queries
**File:** `lacylights-fe/src/graphql/sceneBoards.ts`

**Add canvas size to queries:**
```typescript
export const GET_SCENE_BOARD = gql`
  query GetSceneBoard($id: ID!) {
    sceneBoard(id: $id) {
      id
      name
      description
      defaultFadeTime
      gridSize
      canvasWidth      # NEW
      canvasHeight     # NEW
      buttons {
        id
        layoutX        # Now Int
        layoutY        # Now Int
        width          # Now Int
        height         # Now Int
        color
        label
        scene {
          id
          name
          description
        }
      }
    }
  }
`;
```

### 2.3 Create Canvas Utility Functions
**File:** `lacylights-fe/src/lib/canvasUtils.ts`

```typescript
/**
 * Canvas coordinate and collision utilities for Scene Board
 */

export interface Point {
  x: number;
  y: number;
}

export interface Rect {
  layoutX: number;
  layoutY: number;
  width: number;
  height: number;
}

export interface Transform {
  scale: number;
  offsetX: number;
  offsetY: number;
}

/**
 * Convert percentage (0-1) to pixels (for migration)
 */
export function percentToPixel(percent: number, canvasSize: number): number {
  return Math.round(percent * canvasSize);
}

/**
 * Convert pixels to percentage (for backward compat)
 */
export function pixelToPercent(pixel: number, canvasSize: number): number {
  return pixel / canvasSize;
}

/**
 * Convert screen coordinates to canvas coordinates
 * accounting for zoom and pan
 */
export function screenToCanvas(
  screenX: number,
  screenY: number,
  transform: Transform,
  canvasElement: HTMLElement
): Point {
  const rect = canvasElement.getBoundingClientRect();
  const canvasX = (screenX - rect.left) / transform.scale - transform.offsetX;
  const canvasY = (screenY - rect.top) / transform.scale - transform.offsetY;
  return { x: canvasX, y: canvasY };
}

/**
 * Check if two rectangles collide
 */
export function checkCollision(
  rect1: Rect,
  rect2: Rect,
  padding: number = 0
): boolean {
  return !(
    rect1.layoutX + rect1.width + padding < rect2.layoutX ||
    rect1.layoutX > rect2.layoutX + rect2.width + padding ||
    rect1.layoutY + rect1.height + padding < rect2.layoutY ||
    rect1.layoutY > rect2.layoutY + rect2.height + padding
  );
}

/**
 * Find an available position on the canvas for a new button
 */
export function findAvailablePosition(
  existingButtons: Rect[],
  canvasWidth: number,
  canvasHeight: number,
  buttonWidth: number,
  buttonHeight: number,
  gridStep: number = 250,
  padding: number = 20
): Point | null {
  for (let y = padding; y < canvasHeight - buttonHeight; y += gridStep) {
    for (let x = padding; x < canvasWidth - buttonWidth; x += gridStep) {
      const candidate = { layoutX: x, layoutY: y, width: buttonWidth, height: buttonHeight };
      const hasCollision = existingButtons.some(existing =>
        checkCollision(candidate, existing, padding)
      );
      if (!hasCollision) {
        return { x, y };
      }
    }
  }
  return null; // No available position found
}

/**
 * Clamp a value between min and max
 */
export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

/**
 * Snap a value to the nearest grid position
 */
export function snapToGrid(value: number, gridSize: number): number {
  return Math.round(value / gridSize) * gridSize;
}
```

### 2.4 Implement Fixed Canvas with Zoom/Pan
**File:** `lacylights-fe/src/app/(main)/scene-board/[id]/SceneBoardClient.tsx`

**Add viewport state:**
```typescript
const [viewport, setViewport] = useState({
  scale: 1.0,
  offsetX: 0,
  offsetY: 0
});

// Zoom constraints
const MIN_ZOOM = 0.5;
const MAX_ZOOM = 3.0;
```

**Update canvas rendering:**
```tsx
<div
  ref={canvasRef}
  className="flex-1 bg-gray-900 relative overflow-hidden"
  onTouchStart={handleTouchStart}
  onTouchMove={handleTouchMove}
  onTouchEnd={handleTouchEnd}
>
  {/* Transformed canvas container */}
  <div
    style={{
      transform: `scale(${viewport.scale}) translate(${viewport.offsetX}px, ${viewport.offsetY}px)`,
      transformOrigin: '0 0',
      width: `${sceneBoard.canvasWidth}px`,
      height: `${sceneBoard.canvasHeight}px`,
      position: 'relative'
    }}
  >
    {/* Render buttons with pixel coordinates */}
    {sceneBoard.buttons.map((button) => (
      <div
        key={button.id}
        style={{
          position: 'absolute',
          left: `${button.layoutX}px`,
          top: `${button.layoutY}px`,
          width: `${button.width || 200}px`,
          height: `${button.height || 120}px`
        }}
        // ... rest of button props
      >
        {/* Button content */}
      </div>
    ))}
  </div>
</div>
```

### 2.5 Update Drag Handlers
**Update coordinate conversion:**
```typescript
const handleDragMove = useCallback((e: MouseEvent) => {
  if (!draggingButton || !canvasRef.current) return;

  const canvasPos = screenToCanvas(
    e.clientX,
    e.clientY,
    viewport,
    canvasRef.current
  );

  const newX = clamp(
    canvasPos.x - dragOffset.x,
    0,
    (sceneBoard.canvasWidth || 2000) - (draggingButton.width || 200)
  );
  const newY = clamp(
    canvasPos.y - dragOffset.y,
    0,
    (sceneBoard.canvasHeight || 2000) - (draggingButton.height || 120)
  );

  // Snap to grid (in pixels)
  const gridSize = sceneBoard.gridSize || 50;
  const snappedX = snapToGrid(newX, gridSize);
  const snappedY = snapToGrid(newY, gridSize);

  // Update position
  setDraggingButton({
    ...draggingButton,
    layoutX: snappedX,
    layoutY: snappedY
  });
}, [draggingButton, dragOffset, viewport, sceneBoard]);
```

### 2.6 Implement Pinch-to-Zoom
```typescript
const [touchState, setTouchState] = useState<{
  initialDistance: number | null;
  initialScale: number;
  initialTouches: { x: number; y: number }[];
}>({
  initialDistance: null,
  initialScale: 1.0,
  initialTouches: []
});

const handleTouchStart = useCallback((e: React.TouchEvent) => {
  if (e.touches.length === 2) {
    // Pinch zoom starting
    const touch1 = e.touches[0];
    const touch2 = e.touches[1];
    const distance = Math.hypot(
      touch2.clientX - touch1.clientX,
      touch2.clientY - touch1.clientY
    );
    setTouchState({
      initialDistance: distance,
      initialScale: viewport.scale,
      initialTouches: [
        { x: touch1.clientX, y: touch1.clientY },
        { x: touch2.clientX, y: touch2.clientY }
      ]
    });
  }
}, [viewport.scale]);

const handleTouchMove = useCallback((e: React.TouchEvent) => {
  if (e.touches.length === 2 && touchState.initialDistance) {
    // Pinch zoom
    const touch1 = e.touches[0];
    const touch2 = e.touches[1];
    const currentDistance = Math.hypot(
      touch2.clientX - touch1.clientX,
      touch2.clientY - touch1.clientY
    );
    const scaleChange = currentDistance / touchState.initialDistance;
    const newScale = clamp(
      touchState.initialScale * scaleChange,
      MIN_ZOOM,
      MAX_ZOOM
    );
    setViewport(prev => ({ ...prev, scale: newScale }));
  }
}, [touchState]);

const handleTouchEnd = useCallback(() => {
  setTouchState({
    initialDistance: null,
    initialScale: viewport.scale,
    initialTouches: []
  });
}, [viewport.scale]);
```

### 2.7 Add Zoom UI Controls
**Create component:**
```tsx
const ZoomControls = () => (
  <div className="fixed bottom-4 right-4 flex flex-col gap-2 bg-gray-800 rounded-lg p-2">
    <button
      onClick={() => setViewport(prev => ({ ...prev, scale: clamp(prev.scale + 0.1, MIN_ZOOM, MAX_ZOOM) }))}
      className="px-3 py-2 bg-blue-600 rounded hover:bg-blue-500"
      aria-label="Zoom in"
    >
      +
    </button>
    <div className="text-center text-sm text-white">
      {Math.round(viewport.scale * 100)}%
    </div>
    <button
      onClick={() => setViewport(prev => ({ ...prev, scale: clamp(prev.scale - 0.1, MIN_ZOOM, MAX_ZOOM) }))}
      className="px-3 py-2 bg-blue-600 rounded hover:bg-blue-500"
      aria-label="Zoom out"
    >
      −
    </button>
    <button
      onClick={() => setViewport({ scale: 1.0, offsetX: 0, offsetY: 0 })}
      className="px-3 py-2 bg-gray-600 rounded hover:bg-gray-500 text-xs"
      aria-label="Reset zoom"
    >
      Reset
    </button>
  </div>
);
```

### 2.8 Responsive Mobile UI

**Hamburger menu for mobile:**
```tsx
const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

// Mobile menu button (visible < md)
<button
  className="md:hidden p-2 bg-gray-700 rounded"
  onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
>
  ☰
</button>

// Slide-in menu
{mobileMenuOpen && (
  <div className="fixed inset-0 bg-black bg-opacity-50 z-50 md:hidden">
    <div className="absolute right-0 top-0 bottom-0 w-64 bg-gray-800 p-4">
      {/* Menu items */}
    </div>
  </div>
)}
```

### 2.9 Frontend Testing Checklist
- [ ] Unit tests for canvasUtils.ts
- [ ] Test coordinate conversion
- [ ] Test collision detection
- [ ] Test zoom/pan calculations
- [ ] Run `npm test` - all tests pass
- [ ] Run `npm run lint` - no warnings
- [ ] Test on desktop browser
- [ ] Test on iOS Safari
- [ ] Test on Android Chrome
- [ ] Verify pinch-to-zoom works
- [ ] Verify buttons never overlap

### 2.10 Frontend Commit & PR
```bash
cd lacylights-fe
git add .
git commit -m "feat: mobile-optimized Scene Board with zoom/pan

- Convert to pixel-based coordinate system
- Implement transform-based zoom/pan
- Add pinch-to-zoom and touch-pan gestures
- Add collision detection for button placement
- Responsive UI with hamburger menu on mobile
- Full-screen modals on mobile devices
- Touch-optimized button sizes (min 44x44px)

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin feature/mobile-scene-board-zoom
```

---

## PHASE 3: MCP Server Type Update (lacylights-mcp)

**Branch:** `feature/scene-board-types-update`
**Prerequisite:** Backend PR must be merged first

### 3.1 Regenerate GraphQL Types
```bash
cd lacylights-mcp
npm run generate
```

This will regenerate `src/generated/graphql.ts` with:
- `SceneBoardButton.layoutX: number` (was Float, now Int)
- `SceneBoardButton.layoutY: number` (was Float, now Int)
- `SceneBoardButton.width: number` (was Float, now Int)
- `SceneBoardButton.height: number` (was Float, now Int)
- `SceneBoard.canvasWidth: number`
- `SceneBoard.canvasHeight: number`

### 3.2 Verify Types
**Check:** `src/generated/graphql.ts`

Ensure the types match the new schema.

### 3.3 MCP Commit & PR
```bash
cd lacylights-mcp
git add .
git commit -m "chore: update Scene Board types for pixel coordinates

- Regenerate GraphQL types from updated schema
- layoutX/Y/width/height are now Int (pixels)
- Add canvasWidth/canvasHeight to SceneBoard type

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin feature/scene-board-types-update
```

---

## Implementation Order (Strict Dependencies)

### ✅ Step 1: Backend (FIRST)
1. Create backend branch
2. Update Prisma schema
3. Create migration
4. Write data migration script
5. Update GraphQL schema
6. Update resolvers
7. Update tests
8. Lint, test, commit
9. Create PR
10. **WAIT FOR MERGE**

### ✅ Step 2: Frontend (AFTER backend merged)
11. Create frontend branch
12. Update types
13. Update GraphQL queries
14. Create canvas utilities
15. Implement zoom/pan
16. Add touch gestures
17. Optimize mobile UI
18. Write tests
19. Lint, test, commit
20. Create PR

### ✅ Step 3: MCP (AFTER backend merged)
21. Create MCP branch
22. Regenerate types
23. Verify
24. Commit
25. Create PR

---

## Key Technical Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| Canvas Size | 2000x2000px | Good resolution, reasonable for layout |
| Zoom Range | 0.5x - 3.0x | Flexibility without extreme distortion |
| Default Button | 200x120px | Balances visibility and space |
| Min Button | 120x80px | Above 44x44px touch target minimum |
| Grid Spacing | 250px | Clean layout, ~8 buttons per row |
| Mobile Breakpoint | 768px (md:) | Standard tablet/mobile split |
| Touch Target | 44x44px min | iOS Human Interface Guidelines |

---

## Risk Mitigation

1. **Breaking Change:** Schema change breaks existing clients
   - ✅ Migration script handles data conversion
   - ✅ Coordinated deployment across all repos

2. **Data Loss:** Coordinate conversion could lose precision
   - ✅ Using Math.round() for stable conversion
   - ✅ 2000px canvas provides good granularity

3. **Mobile Performance:** Complex transforms could be slow
   - ✅ CSS transforms are GPU-accelerated
   - ✅ Debounce/throttle touch gestures

4. **Touch Conflicts:** Drag vs pan could conflict
   - ✅ Clear gesture detection with thresholds
   - ✅ Mode-based interaction (Play vs Layout)

---

## Success Criteria

### Functional Requirements
- [ ] Buttons use pixel coordinates instead of percentages
- [ ] Pinch-to-zoom works smoothly on mobile
- [ ] Touch-pan navigates the canvas
- [ ] Buttons never overlap
- [ ] Layout Mode drag-and-drop works with zoom
- [ ] Scene activation works in Play Mode

### Non-Functional Requirements
- [ ] All tests pass (backend and frontend)
- [ ] No lint warnings
- [ ] 75%+ code coverage on new code
- [ ] Responsive design works on mobile and desktop
- [ ] No performance regressions

### User Experience
- [ ] Lighting technicians can easily use Scene Board on mobile
- [ ] Touch targets are large enough (44x44px minimum)
- [ ] Text is readable at all zoom levels
- [ ] Interface is intuitive and responsive

---

## Files to Modify Summary

### Backend (lacylights-node)
- ✅ `prisma/schema.prisma`
- ✅ `src/graphql/schema.ts`
- ✅ `src/graphql/resolvers/sceneBoard.ts`
- ✅ `src/graphql/resolvers/__tests__/sceneBoard.test.ts`
- ✅ `src/__tests__/integration/scenarios/live-busking.integration.test.ts`
- ✅ NEW: `scripts/migrate-scene-board-coordinates.ts`

### Frontend (lacylights-fe)
- ✅ `src/types/index.ts`
- ✅ `src/graphql/sceneBoards.ts`
- ✅ `src/app/(main)/scene-board/[id]/SceneBoardClient.tsx`
- ✅ NEW: `src/lib/canvasUtils.ts`
- ✅ NEW: `src/lib/__tests__/canvasUtils.test.ts`

### MCP (lacylights-mcp)
- ✅ `src/generated/graphql.ts` (auto-generated)

---

## Next Steps

1. Start new Claude Code session in `~/src/lacylights/`
2. Begin with Phase 1 (Backend)
3. Follow the implementation order strictly
4. Check off items in TODO.md as completed
5. Create PRs in sequence: Backend → Frontend → MCP

## Notes

- This is a coordinated multi-repo change
- Backend MUST be completed and merged first
- Frontend and MCP depend on backend changes
- All changes follow CLAUDE.md coding standards
- Never commit to main branch directly
- All code must pass linting and tests before commit
