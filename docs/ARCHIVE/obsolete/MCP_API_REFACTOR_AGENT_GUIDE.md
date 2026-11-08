# Agent Quick Start Guide - MCP API Refactor

## Overview

This guide helps agents quickly start working on MCP API refactor tasks across multiple conversations.

## Before You Start

1. **Read the main plan:** `~/src/lacylights/MCP_API_REFACTOR_PLAN.md`
2. **Check current status:** `~/src/lacylights/MCP_API_REFACTOR_STATUS.md`
3. **Find an available task:** Look for tasks marked 🔴 Not Started with no dependencies

## Claiming a Task

1. Pick a task from the plan that:
   - Has status 🔴 Not Started
   - Has all dependencies complete (check "Dependencies" field)
   - Matches your assigned work stream

2. Update `MCP_API_REFACTOR_STATUS.md`:
   ```markdown
   | Agent-YourName | Task X.Y | 🟡 In Progress | feature/branch-name |
   ```

3. Create your feature branch:
   ```bash
   cd lacylights-node  # or lacylights-mcp
   git checkout main
   git pull
   git checkout -b feature/branch-name-from-plan
   ```

## Working on Your Task

### Task Structure

Each task in the plan includes:
- **Dependencies:** What must be done first
- **Files to modify:** Specific files you'll work with
- **Changes:** Detailed list of what to implement
- **GraphQL Schema Changes:** Exact schema additions (for backend tasks)
- **Acceptance Criteria:** Checkboxes for completion verification

### Development Workflow

1. **Backend Tasks (lacylights-node):**
   ```bash
   cd ~/src/lacylights/lacylights-node
   git checkout -b feature/your-branch-name

   # Make your changes per the task description
   # Add/modify GraphQL schema files
   # Add/modify resolvers
   # Add/modify tests

   npm run type-check
   npm run lint
   npm test
   npm run test:coverage
   ```

2. **MCP Tasks (lacylights-mcp):**
   ```bash
   cd ~/src/lacylights/lacylights-mcp
   git checkout -b feature/your-branch-name

   # Make your changes per the task description
   # Add/modify tool definitions
   # Add/modify tests

   npm run type-check
   npm run lint
   npm test
   ```

### Testing Requirements

- All tasks require unit tests
- Backend tasks: Test GraphQL queries/mutations
- MCP tasks: Test tool input/output
- Target: >80% code coverage for new code
- All existing tests must continue to pass

### Code Quality Requirements

- TypeScript strict mode must pass
- ESLint must pass with no warnings
- All Prettier formatting must be applied
- JSDoc comments on all public functions
- Clear commit messages referencing the plan

## Completing Your Task

### Pre-Merge Checklist

- [ ] All acceptance criteria checked off in plan
- [ ] Unit tests written and passing
- [ ] Code coverage meets requirements
- [ ] TypeScript type-check passes
- [ ] ESLint passes with no warnings
- [ ] All existing tests still pass
- [ ] GraphQL schema validated (backend only)
- [ ] Tool descriptions are comprehensive (MCP only)
- [ ] Commit messages reference the plan

### Commit & Push

```bash
# Add your changes
git add .

# Commit with descriptive message
git commit -m "feat: implement task X.Y - Brief Description

Implements Task X.Y from MCP_API_REFACTOR_PLAN.md

Changes:
- Specific change 1
- Specific change 2
- etc.

Closes: MCP_API_REFACTOR_PLAN.md Task X.Y

Testing:
- Added unit tests for all new functionality
- All existing tests pass
- Coverage: XX%"

# Push to remote
git push -u origin feature/your-branch-name
```

### Create Pull Request

```bash
gh pr create --title "feat: Task X.Y - Brief Description" --body "$(cat <<'EOF'
## Summary

Implements Task X.Y from MCP_API_REFACTOR_PLAN.md

[Brief description of what this task accomplishes]

## Changes

- Specific change 1
- Specific change 2
- etc.

## Testing

- [x] Unit tests added and passing
- [x] Integration tests pass
- [x] Type checking passes
- [x] Linting passes
- [x] Code coverage: XX%

## Acceptance Criteria

[Copy checkboxes from task in plan and mark complete]

- [x] Criterion 1
- [x] Criterion 2
- etc.

## Documentation

- [x] Code is documented with JSDoc
- [x] Tool descriptions updated (MCP only)
- [x] GraphQL schema documented (backend only)

## Related

- Plan: MCP_API_REFACTOR_PLAN.md Task X.Y
- Depends on: [List any task dependencies]
- Enables: [List any tasks this unblocks]

🤖 Generated as part of MCP API Refactor
EOF
)"
```

### Update Status

After PR is created, update `MCP_API_REFACTOR_STATUS.md`:

```markdown
- [x] **X.Y** Task Name (PX) - 🟢 Complete - PR #123
```

## Task-Specific Guidance

### Backend Tasks (lacylights-node)

**Repository:** `~/src/lacylights/lacylights-node`

**Key Files:**
- GraphQL schemas: `src/graphql/schema/*.graphql`
- Resolvers: `src/graphql/resolvers/*.ts`
- Context: `src/context.ts`
- Tests: `src/__tests__/graphql/*.test.ts`

**Testing Backend:**
```bash
# Run specific test file
npm test -- src/__tests__/graphql/project.test.ts

# Run with coverage
npm run test:coverage

# Check types
npm run type-check

# Run all checks
npm run check
```

**GraphQL Schema Best Practices:**
- Always include descriptions on types and fields
- Use consistent naming: PascalCase for types, camelCase for fields
- Add input types for filters and complex arguments
- Use enums for fixed sets of values
- Include pagination info in list responses

### MCP Tasks (lacylights-mcp)

**Repository:** `~/src/lacylights/lacylights-mcp`

**Key Files:**
- Tools: `src/tools/*.ts`
- Types: `src/types/*.ts`
- Utils: `src/utils/*.ts`
- Tests: `src/__tests__/tools/*.test.ts`

**Testing MCP:**
```bash
# Run specific test file
npm test -- src/__tests__/tools/project.test.ts

# Run with coverage
npm run test:coverage

# Check types
npm run type-check
```

**Tool Definition Best Practices:**
- Include comprehensive descriptions that guide LLM usage
- Explain what the tool returns and what it doesn't
- Provide example use cases
- Document when to use this tool vs alternatives
- Include pagination guidance
- Specify performance characteristics
- Add usage examples in description

**Tool Description Template:**
```typescript
{
  name: "tool_name",
  description: `[One-line summary]

  Returns:
  - [What data is included]
  - [What data is included]

  Does NOT include:
  - [What data is excluded]
  - [What data is excluded]

  Parameters:
  - param1: [Description with defaults]
  - param2: [Description with constraints]

  Pagination:
  - [How pagination works]
  - [Max/default values]

  Performance:
  - [Expected response size]
  - [Best practices]

  Use cases:
  - "[Example use case 1]"
  - "[Example use case 2]"

  Example workflow:
  1. [Step 1]
  2. [Step 2]
  3. [Step 3]`,
  inputSchema: { /* ... */ }
}
```

## Common Patterns

### Pagination Implementation

**Backend (GraphQL):**
```typescript
// In resolver
const { page = 1, perPage = 50 } = args;
const skip = (page - 1) * perPage;
const take = Math.min(perPage, 100); // Max 100

const [items, total] = await Promise.all([
  prisma.model.findMany({ skip, take, where, orderBy }),
  prisma.model.count({ where })
]);

const totalPages = Math.ceil(total / take);

return {
  items,
  pagination: {
    total,
    page,
    perPage: take,
    totalPages,
    hasMore: page < totalPages
  }
};
```

**MCP (Tool):**
```typescript
// Use helper functions from Task 2.1
import { normalizePaginationParams, formatPaginationInfo } from '../utils/pagination';

const { page, perPage } = normalizePaginationParams(args.page, args.perPage);

const result = await graphqlClient.query({
  query: LIST_ITEMS_QUERY,
  variables: { page, perPage }
});

return {
  items: result.items,
  pagination: result.pagination
};
```

### Error Handling

**Backend:**
```typescript
try {
  // Operation
  return result;
} catch (error) {
  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    // Handle known errors
    throw new GraphQLError('Resource not found', {
      extensions: { code: 'NOT_FOUND' }
    });
  }
  throw error;
}
```

**MCP:**
```typescript
try {
  const result = await client.query(/* ... */);
  return { success: true, data: result };
} catch (error) {
  return {
    success: false,
    error: error instanceof Error ? error.message : 'Unknown error'
  };
}
```

## Getting Help

### Documentation References

- **Main Plan:** `MCP_API_REFACTOR_PLAN.md`
- **Status:** `MCP_API_REFACTOR_STATUS.md`
- **GraphQL Best Practices:** https://graphql.org/learn/best-practices/
- **MCP Protocol:** https://modelcontextprotocol.io/
- **Prisma Docs:** https://www.prisma.io/docs/

### Repository-Specific Docs

- **lacylights-node:** `CLAUDE.md` - Development guide
- **lacylights-mcp:** `README.md` - Tool documentation
- **lacylights:** Root `CLAUDE.md` - Overall project guide

### Questions to Ask

If you're unsure about anything:
1. Check the task's "Changes" section - it's detailed
2. Look at existing similar code for patterns
3. Check the acceptance criteria - they define success
4. Review related tasks for context

## Success Metrics

Your task is complete when:
- ✅ All acceptance criteria are checked
- ✅ All tests pass (unit + existing)
- ✅ Code coverage meets target (>80%)
- ✅ No linting/type errors
- ✅ PR is created with comprehensive description
- ✅ Status document is updated

## Tips for Efficiency

1. **Read the full task first** - Don't start coding until you understand the complete requirement
2. **Follow the file list** - The task specifies exactly which files to modify
3. **Copy schema examples** - The plan includes exact schema changes to implement
4. **Test as you go** - Write tests alongside implementation
5. **Check dependencies** - Make sure prerequisite tasks are actually complete
6. **Update status early** - Claim your task as soon as you start
7. **Commit frequently** - Small commits are easier to review and debug
8. **Reference the plan** - Every commit should mention the task number

## Multi-Conversation Continuity

Since agents may work across multiple conversations:

1. **Always check status first** - Another agent may have started your intended task
2. **Update status immediately** - Prevent duplicate work
3. **Document thoroughly** - Future agents need to understand your work
4. **Complete one task** - Don't leave tasks half-done
5. **Clean up on exit** - Update status, push code, create PR before ending session

## Example Session Flow

```bash
# 1. Check what's available
cd ~/src/lacylights
cat MCP_API_REFACTOR_STATUS.md

# 2. Pick Task 1.2 (example)
cd lacylights-node
git checkout main && git pull
git checkout -b feature/graphql-fixture-pagination

# 3. Update status file (mark as in progress)

# 4. Read task details
# Open MCP_API_REFACTOR_PLAN.md, find Task 1.2

# 5. Implement changes
# - Modify src/graphql/schema/fixture.graphql
# - Modify src/graphql/resolvers/fixture.ts
# - Add tests in src/__tests__/graphql/fixture.test.ts

# 6. Test
npm run type-check
npm run lint
npm test
npm run test:coverage

# 7. Commit & push
git add .
git commit -m "feat: implement task 1.2 - fixture pagination"
git push -u origin feature/graphql-fixture-pagination

# 8. Create PR
gh pr create --title "..." --body "..."

# 9. Update status (mark as complete)
```

## Good Luck!

The plan is comprehensive and detailed. Trust the task descriptions, follow the acceptance criteria, and you'll produce high-quality work that integrates seamlessly with the rest of the project.
