# Mobile Scene Board Implementation - Task Checklist

**Project:** LacyLights Mobile Scene Board Optimization
**Status:** Ready to start
**See:** MOBILE_SCENE_BOARD_PLAN.md for detailed plan

---

## PHASE 1: Backend Changes (lacylights-node)

**Branch:** `feature/scene-board-pixel-coordinates-backend`

- [ ] 1.1 Create feature branch in lacylights-node
- [ ] 1.2 Update Prisma schema
  - [ ] Add canvasWidth/canvasHeight to SceneBoard model
  - [ ] Change layoutX/layoutY from Float to Int in SceneBoardButton
  - [ ] Change width/height from Float to Int in SceneBoardButton
  - [ ] Update default values (0.1 → 200 for width, 120 for height)
- [ ] 1.3 Create database migration
  - [ ] Run `npx prisma migrate dev --name scene_board_pixel_coordinates`
  - [ ] Verify migration SQL is correct
- [ ] 1.4 Write data migration script
  - [ ] Create `scripts/migrate-scene-board-coordinates.ts`
  - [ ] Test migration on development database
- [ ] 1.5 Update GraphQL schema (`src/graphql/schema.ts`)
  - [ ] Update SceneBoard type (add canvasWidth/canvasHeight)
  - [ ] Update SceneBoardButton type (Float → Int for coordinates)
  - [ ] Update CreateSceneBoardInput
  - [ ] Update UpdateSceneBoardInput
  - [ ] Update CreateSceneBoardButtonInput
  - [ ] Update UpdateSceneBoardButtonInput
  - [ ] Update SceneBoardButtonPositionInput
- [ ] 1.6 Update GraphQL resolvers (`src/graphql/resolvers/sceneBoard.ts`)
  - [ ] Add coordinate bounds validation
  - [ ] Update default values (200x120 instead of 0.1)
  - [ ] Ensure all operations use integers
- [ ] 1.7 Update backend unit tests (`src/graphql/resolvers/__tests__/sceneBoard.test.ts`)
  - [ ] Update test data to use pixel coordinates
  - [ ] Update assertions for new values
  - [ ] Add tests for bounds validation
  - [ ] Add tests for canvas size defaults
- [ ] 1.8 Update integration tests (`src/__tests__/integration/scenarios/live-busking.integration.test.ts`)
  - [ ] Update scene board button creation coordinates
  - [ ] Verify activation still works
- [ ] 1.9 Run backend linter
  - [ ] `npm run lint` - fix all warnings
- [ ] 1.10 Run backend tests
  - [ ] `npm test` - all tests pass
  - [ ] `npm run type-check` - no type errors
- [ ] 1.11 Commit backend changes
- [ ] 1.12 Push backend branch
- [ ] 1.13 Create backend PR
- [ ] 1.14 **WAIT FOR BACKEND PR TO BE MERGED** ⚠️

---

## PHASE 2: Frontend Changes (lacylights-fe)

**Branch:** `feature/mobile-scene-board-zoom`
**Prerequisite:** Backend PR merged ✅

- [ ] 2.1 Create feature branch in lacylights-fe
- [ ] 2.2 Update TypeScript types (`src/types/index.ts`)
  - [ ] Add canvasWidth/canvasHeight to SceneBoard interface
  - [ ] Update coordinate types to reflect pixels (Int)
- [ ] 2.3 Update GraphQL queries (`src/graphql/sceneBoards.ts`)
  - [ ] Add canvasWidth/canvasHeight to GET_SCENE_BOARD query
  - [ ] Update mutation input types
- [ ] 2.4 Create canvas utility functions
  - [ ] Create `src/lib/canvasUtils.ts`
  - [ ] Implement percentToPixel (migration helper)
  - [ ] Implement pixelToPercent (backward compat)
  - [ ] Implement screenToCanvas (coordinate conversion)
  - [ ] Implement checkCollision
  - [ ] Implement findAvailablePosition
  - [ ] Implement clamp, snapToGrid
- [ ] 2.5 Update SceneBoardClient component
  - [ ] Add viewport state (scale, offsetX, offsetY)
  - [ ] Implement fixed canvas with transform
  - [ ] Update button rendering to use pixel coordinates
  - [ ] Remove percentage-based positioning
- [ ] 2.6 Update drag handlers
  - [ ] Use screenToCanvas for coordinate conversion
  - [ ] Update drag start/move/end for pixel coordinates
  - [ ] Use pixel-based grid snapping
  - [ ] Add bounds checking
- [ ] 2.7 Implement pinch-to-zoom
  - [ ] Add touch state management
  - [ ] Implement onTouchStart handler
  - [ ] Implement onTouchMove handler (pinch detection)
  - [ ] Implement onTouchEnd handler
  - [ ] Add zoom constraints (0.5x - 3.0x)
- [ ] 2.8 Implement touch-pan
  - [ ] Detect single-finger drag
  - [ ] Update viewport offset
  - [ ] Add pan bounds
  - [ ] Distinguish tap vs drag
- [ ] 2.9 Add zoom UI controls
  - [ ] Create zoom control component
  - [ ] Zoom in button
  - [ ] Zoom out button
  - [ ] Reset zoom button
  - [ ] Display current zoom level
- [ ] 2.10 Update auto-placement algorithm
  - [ ] Change from percentage to pixel-based placement
  - [ ] Use collision detection
  - [ ] Set 250px grid step
  - [ ] Add 20px padding between buttons
- [ ] 2.11 Implement collision detection during drag
  - [ ] Check for overlaps in handleDragMove
  - [ ] Add visual feedback (red border on collision)
- [ ] 2.12 Update button sizing
  - [ ] Remove percentage-based width/height
  - [ ] Use pixel dimensions from data
  - [ ] Set default 200x120px
  - [ ] Ensure minimum 44x44px touch targets
- [ ] 2.13 Make header responsive
  - [ ] Add hamburger menu button (mobile)
  - [ ] Implement slide-in menu
  - [ ] Move controls to menu on mobile
  - [ ] Keep inline on desktop (md: breakpoint)
- [ ] 2.14 Optimize modals for mobile
  - [ ] Full-screen on mobile (< md)
  - [ ] Slide-up animation
  - [ ] Fixed header with close button
  - [ ] Touch-friendly button sizes
- [ ] 2.15 Add Play Mode mobile enhancements
  - [ ] Increase touch target sizes
  - [ ] Larger font sizes at small zoom
  - [ ] Active state feedback
  - [ ] Consider haptic feedback
- [ ] 2.16 Write unit tests
  - [ ] Create `src/lib/__tests__/canvasUtils.test.ts`
  - [ ] Test percentToPixel/pixelToPercent
  - [ ] Test screenToCanvas
  - [ ] Test checkCollision
  - [ ] Test findAvailablePosition
  - [ ] Test clamp, snapToGrid
  - [ ] Achieve 75%+ coverage
- [ ] 2.17 Run frontend linter
  - [ ] `npm run lint` - fix all warnings
- [ ] 2.18 Run frontend tests
  - [ ] `npm test` - all tests pass
  - [ ] `npm run type-check` - no type errors
- [ ] 2.19 Manual testing
  - [ ] Test on desktop browser (Chrome)
  - [ ] Test on desktop browser (Firefox)
  - [ ] Test on desktop browser (Safari)
  - [ ] Test on iOS Safari (mobile)
  - [ ] Test on Android Chrome (mobile)
  - [ ] Verify pinch-to-zoom works smoothly
  - [ ] Verify touch-pan works
  - [ ] Verify no button overlaps
  - [ ] Test Layout Mode drag-and-drop
  - [ ] Test Play Mode scene activation
- [ ] 2.20 Commit frontend changes
- [ ] 2.21 Push frontend branch
- [ ] 2.22 Create frontend PR

---

## PHASE 3: MCP Server Type Update (lacylights-mcp)

**Branch:** `feature/scene-board-types-update`
**Prerequisite:** Backend PR merged ✅

- [ ] 3.1 Create feature branch in lacylights-mcp
- [ ] 3.2 Regenerate GraphQL types
  - [ ] Run `npm run generate`
  - [ ] Verify `src/generated/graphql.ts` updated
- [ ] 3.3 Verify types are correct
  - [ ] Check SceneBoardButton.layoutX is number (Int)
  - [ ] Check SceneBoardButton.layoutY is number (Int)
  - [ ] Check SceneBoardButton.width is number (Int)
  - [ ] Check SceneBoardButton.height is number (Int)
  - [ ] Check SceneBoard.canvasWidth exists
  - [ ] Check SceneBoard.canvasHeight exists
- [ ] 3.4 Commit MCP changes
- [ ] 3.5 Push MCP branch
- [ ] 3.6 Create MCP PR

---

## Completion Checklist

### All PRs Created
- [ ] Backend PR created and merged
- [ ] Frontend PR created and merged
- [ ] MCP PR created and merged

### Verification
- [ ] All tests pass in all repos
- [ ] No lint warnings in any repo
- [ ] Manual testing complete on mobile and desktop
- [ ] Scene Board works with pixel coordinates
- [ ] Zoom/pan works smoothly
- [ ] No button overlaps
- [ ] Mobile UX is improved

### Documentation
- [ ] Update MOBILE_SCENE_BOARD_PLAN.md with "COMPLETED" status
- [ ] Update this TODO.md with completion date
- [ ] Add any lessons learned or notes

---

## Notes

- Follow strict implementation order: Backend → Frontend → MCP
- Never commit to main branch
- All code must pass tests and linting before commit
- Test on actual mobile devices, not just browser dev tools
- Coordinate changes affect database schema - handle with care

## Current Status

**Last Updated:** 2025-11-22
**Current Phase:** ✅ COMPLETED
**All Phases Complete:** Backend (PR #67), Frontend (PR #64), MCP (PR #77)

**Deployed:**
- Backend v1.6.0 deployed to production (lacylights.local)
- Frontend v0.7.0 deployed to production (lacylights.local)
- MCP v1.4.0+ pending release after PR #77 merge

**Status Summary:**
- ✅ Phase 1 (Backend): MERGED - PR #67 in lacylights-node
- ✅ Phase 2 (Frontend): MERGED - PR #64 in lacylights-fe
- ✅ Phase 3 (MCP): READY TO MERGE - PR #77 in lacylights-mcp (all CI checks passing)

**Next Action:** Merge MCP PR #77 and create release
