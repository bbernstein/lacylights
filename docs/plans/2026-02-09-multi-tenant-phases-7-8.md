# Multi-Tenant Group Ownership: Phases 7 & 8 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the remaining multi-tenant group ownership work: device-to-group assignment UI (frontend) and group management tools (MCP server).

**Architecture:** Phase 7 adds device-group management to the existing frontend group UI. Phase 8 adds group-aware MCP tools so an AI assistant can query and manage groups. Both consume the already-complete GraphQL API from lacylights-go.

**Tech Stack:** Next.js/React/Apollo Client (frontend), TypeScript/MCP SDK (MCP server), GraphQL

---

## Pre-Implementation: What's Already Done

Before starting, understand what exists to avoid duplicating work:

### Frontend (lacylights-fe) - COMPLETE
- `src/contexts/GroupContext.tsx` - Group selection, activeGroup, localStorage persistence
- `src/components/GroupSelector.tsx` - Dropdown to switch groups (with tests)
- `src/app/(main)/groups/page.tsx` - Group listing + create group
- `src/app/(main)/groups/[id]/page.tsx` - Group detail: edit metadata, manage members (role change, remove), invite by email, view/cancel pending invitations
- `src/components/InvitationBadge.tsx` - Header badge showing pending invitations with accept/decline
- `src/components/ProjectManagementModal.tsx` - Project creation with groupId, group selector
- `src/contexts/ProjectContext.tsx` - Filters projects by activeGroup client-side
- `src/graphql/auth.ts` - All group/invitation GraphQL operations defined
- `src/types/auth.ts` - All group/invitation TypeScript types defined

### MCP Server (lacylights-mcp) - PARTIAL
- `src/utils/device-fingerprint.ts` - Device fingerprint generation + caching
- `src/services/graphql-client-simple.ts` - Sends `X-Device-Fingerprint` header, has `checkDevice`/`registerDevice` methods
- `src/tools/project-tools.ts` - `groupId` in create/list project operations
- Startup flow checks device auth status and auto-registers

### Backend (lacylights-go) - COMPLETE
- All group CRUD, member management, invitation, and device-group mutations implemented
- `addDeviceToGroup`, `removeDeviceFromGroup` mutations ready
- `approveDevice` accepts optional `groupId` parameter
- Device type has `groups: [UserGroup!]!` field

---

## Phase 7: Frontend Device-Group Assignment

### What's Missing
The `DeviceManagementModal` (`src/components/DeviceManagementModal.tsx`) shows devices with name, fingerprint, status, and role but has **no group assignment UI**. The GraphQL mutations `ADD_DEVICE_TO_GROUP` and `REMOVE_DEVICE_FROM_GROUP` are not defined in the frontend. The group detail page (`/groups/[id]`) shows members and invitations but **not devices**.

---

### Task 7.1: Add Device-Group GraphQL Operations

**Files:**
- Modify: `lacylights-fe/src/graphql/auth.ts`

**Step 1: Write the failing test**

Create a test that imports the new operations to verify they exist.

```typescript
// In lacylights-fe/src/components/__tests__/DeviceManagementModal.test.tsx
// (or verify by importing in an existing test file)
import { ADD_DEVICE_TO_GROUP, REMOVE_DEVICE_FROM_GROUP } from '@/graphql/auth';
expect(ADD_DEVICE_TO_GROUP).toBeDefined();
expect(REMOVE_DEVICE_FROM_GROUP).toBeDefined();
```

**Step 2: Run test to verify it fails**

Run: `cd ~/src/lacylights/lacylights-fe && npx jest --testPathPattern="DeviceManagement" --no-coverage 2>&1 | tail -20`
Expected: FAIL - imports not found

**Step 3: Add GraphQL operations to auth.ts**

Add to `lacylights-fe/src/graphql/auth.ts` (after existing device mutations, near line ~600):

```typescript
export const ADD_DEVICE_TO_GROUP = gql`
  mutation AddDeviceToGroup($deviceId: ID!, $groupId: ID!) {
    addDeviceToGroup(deviceId: $deviceId, groupId: $groupId)
  }
`;

export const REMOVE_DEVICE_FROM_GROUP = gql`
  mutation RemoveDeviceFromGroup($deviceId: ID!, $groupId: ID!) {
    removeDeviceFromGroup(deviceId: $deviceId, groupId: $groupId)
  }
`;
```

**Step 4: Run test to verify it passes**

Run: `cd ~/src/lacylights/lacylights-fe && npx jest --testPathPattern="DeviceManagement" --no-coverage 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add lacylights-fe/src/graphql/auth.ts
git commit -m "feat(fe): add device-to-group GraphQL operations"
```

---

### Task 7.2: Add Group Assignment to DeviceManagementModal

**Files:**
- Modify: `lacylights-fe/src/components/DeviceManagementModal.tsx`
- Test: `lacylights-fe/src/components/__tests__/DeviceManagementModal.test.tsx`

**Step 1: Update the Device interface to include groups**

In `DeviceManagementModal.tsx`, update the local `Device` interface (line 11-26):

```typescript
interface Device {
  id: string;
  name: string;
  fingerprint: string;
  isAuthorized: boolean;
  defaultRole: DeviceRole;
  lastSeenAt?: string;
  lastIPAddress?: string;
  createdAt: string;
  updatedAt: string;
  defaultUser?: {
    id: string;
    email: string;
    name?: string;
  };
  groups?: {
    id: string;
    name: string;
    isPersonal: boolean;
  }[];
}
```

**Step 2: Update the GET_DEVICES query**

The `GET_DEVICES` query in `src/graphql/auth.ts` needs to include `groups` on the device. Check if it already does. If not, add:

```graphql
groups {
  id
  name
  isPersonal
}
```

to the device fields in `GET_DEVICES`.

**Step 3: Add group assignment UI to DeviceManagementModal**

Add imports at top of `DeviceManagementModal.tsx`:

```typescript
import { GET_DEVICES, UPDATE_DEVICE, CREATE_DEVICE_AUTH_CODE, REVOKE_DEVICE, ADD_DEVICE_TO_GROUP, REMOVE_DEVICE_FROM_GROUP } from '@/graphql/auth';
import { useGroup } from '@/contexts/GroupContext';
```

Add group management state and mutations:

```typescript
const { groups: allGroups } = useGroup();
const [addDeviceToGroup] = useMutation(ADD_DEVICE_TO_GROUP, {
  onError: (err) => setError(`Failed to add device to group: ${err.message}`),
  onCompleted: () => refetch(),
});
const [removeDeviceFromGroup] = useMutation(REMOVE_DEVICE_FROM_GROUP, {
  onError: (err) => setError(`Failed to remove device from group: ${err.message}`),
  onCompleted: () => refetch(),
});
```

In the device card (non-editing view), after the default user display, add a groups section:

```tsx
{device.groups && device.groups.length > 0 && (
  <div className="text-gray-500 dark:text-gray-500 text-xs mt-1 flex flex-wrap gap-1 items-center">
    Groups:
    {device.groups.map(g => (
      <span key={g.id} className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-300">
        {g.name}{g.isPersonal && ' (Personal)'}
        <button
          onClick={() => removeDeviceFromGroup({ variables: { deviceId: device.id, groupId: g.id } })}
          className="text-gray-400 hover:text-red-500 transition-colors"
          title={`Remove from ${g.name}`}
        >
          &times;
        </button>
      </span>
    ))}
  </div>
)}
```

In the editing view, add a group selector dropdown that lets admins assign the device to additional groups:

```tsx
<div>
  <label className="block text-sm text-gray-600 dark:text-gray-400 mb-1">Add to group</label>
  <select
    onChange={(e) => {
      if (e.target.value) {
        addDeviceToGroup({ variables: { deviceId: editingDevice.id, groupId: e.target.value } });
        e.target.value = '';
      }
    }}
    className="w-full px-2 py-1 bg-white dark:bg-gray-600 text-gray-900 dark:text-white border border-gray-300 dark:border-gray-500 rounded text-base focus:outline-none focus:ring-2 focus:ring-blue-500"
    defaultValue=""
  >
    <option value="" disabled>Select a group...</option>
    {allGroups
      .filter(g => !editingDevice || !device.groups?.some(dg => dg.id === g.id))
      .map(g => (
        <option key={g.id} value={g.id}>{g.name}{g.isPersonal ? ' (Personal)' : ''}</option>
      ))}
  </select>
</div>
```

**Step 4: Write tests for group assignment display and actions**

Create/update `lacylights-fe/src/components/__tests__/DeviceManagementModal.test.tsx`:

Test cases:
1. Device groups are displayed when present
2. Remove-from-group button calls mutation with correct variables
3. Add-to-group dropdown filters out already-assigned groups
4. Empty groups array shows no groups section

**Step 5: Run tests**

Run: `cd ~/src/lacylights/lacylights-fe && npx jest --testPathPattern="DeviceManagement" --no-coverage`
Expected: PASS

**Step 6: Run lint and type-check**

Run: `cd ~/src/lacylights/lacylights-fe && npm run check`
Expected: No errors

**Step 7: Commit**

```bash
git add lacylights-fe/src/components/DeviceManagementModal.tsx lacylights-fe/src/components/__tests__/DeviceManagementModal.test.tsx lacylights-fe/src/graphql/auth.ts
git commit -m "feat(fe): add device-to-group assignment in DeviceManagementModal"
```

---

### Task 7.3: Add Device List to Group Detail Page

**Files:**
- Modify: `lacylights-fe/src/app/(main)/groups/[id]/page.tsx`
- Modify: `lacylights-fe/src/graphql/auth.ts` (if `GET_USER_GROUP` doesn't include devices)

**Step 1: Verify GET_USER_GROUP includes devices**

Check if the `GET_USER_GROUP` query in `src/graphql/auth.ts` already fetches `devices`. If not, add:

```graphql
devices {
  id
  name
  fingerprint
  isAuthorized
  lastSeenAt
}
```

**Step 2: Add devices section to group detail page**

In `lacylights-fe/src/app/(main)/groups/[id]/page.tsx`, after the invitations section, add a Devices section:

```tsx
{/* Devices Section */}
{isGroupAdmin && (
  <div className="mt-8">
    <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
      Devices
    </h2>
    {group.devices && group.devices.length > 0 ? (
      <div className="space-y-2">
        {group.devices.map((device: { id: string; name: string; fingerprint: string; isAuthorized: boolean; lastSeenAt?: string }) => (
          <div key={device.id} className="flex items-center justify-between p-3 rounded bg-gray-50 dark:bg-gray-700/50 border border-gray-200 dark:border-gray-600">
            <div>
              <span className="text-gray-900 dark:text-white font-medium">{device.name}</span>
              <span className={`ml-2 px-2 py-0.5 rounded text-xs ${device.isAuthorized ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400' : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400'}`}>
                {device.isAuthorized ? 'Authorized' : 'Pending'}
              </span>
              {device.lastSeenAt && (
                <div className="text-gray-500 text-xs mt-1">
                  Last seen: {new Date(device.lastSeenAt).toLocaleString()}
                </div>
              )}
            </div>
            <button
              onClick={async () => {
                if (confirm(`Remove "${device.name}" from this group?`)) {
                  await removeDeviceFromGroup({ variables: { deviceId: device.id, groupId } });
                }
              }}
              className="text-gray-400 hover:text-red-500 p-2 min-h-[44px] min-w-[44px] flex items-center justify-center touch-manipulation"
              title="Remove from group"
            >
              <XCircleIcon className="h-5 w-5" />
            </button>
          </div>
        ))}
      </div>
    ) : (
      <p className="text-gray-500 dark:text-gray-400 text-sm">
        No devices assigned to this group. Assign devices in Settings &gt; Manage Devices.
      </p>
    )}
  </div>
)}
```

Add the `removeDeviceFromGroup` mutation import and hook setup (similar to Task 7.2).

**Step 3: Determine `isGroupAdmin`**

Check if the group detail page already computes whether the current user is a group admin. The page has access to `group.members` - check if the current user's role is GROUP_ADMIN. Use:

```typescript
const { user } = useAuth();
const isGroupAdmin = isAdmin || group?.members?.some(
  (m: GroupMember) => m.user.id === user?.id && m.role === 'GROUP_ADMIN'
);
```

**Step 4: Run lint and type-check**

Run: `cd ~/src/lacylights/lacylights-fe && npm run check`

**Step 5: Commit**

```bash
git add lacylights-fe/src/app/(main)/groups/[id]/page.tsx lacylights-fe/src/graphql/auth.ts
git commit -m "feat(fe): show devices on group detail page with remove capability"
```

---

### Task 7.4: Run Full Frontend Test Suite

**Step 1: Run all tests**

Run: `cd ~/src/lacylights/lacylights-fe && npm test -- --no-coverage 2>&1 | tail -30`
Expected: All tests pass

**Step 2: Run lint + type-check**

Run: `cd ~/src/lacylights/lacylights-fe && npm run check`
Expected: No errors

**Step 3: Commit any fixes if needed**

---

## Phase 8: MCP Server Group Management Tools

### What's Missing
The MCP server can create projects with a groupId and returns groupId in project listings, but an AI assistant cannot:
- List the user's/device's groups
- View group details (members, devices, projects)
- Manage group membership (invite users, remove members)
- See which group context it's operating in

---

### Task 8.1: Add Group Methods to GraphQL Client

**Files:**
- Modify: `lacylights-mcp/src/services/graphql-client-simple.ts`
- Test: `lacylights-mcp/tests/services/graphql-client-simple.test.ts` (if exists, or create)

**Step 1: Add group query methods to the GraphQL client**

Add these methods to the `LacyLightsGraphQLClient` class in `graphql-client-simple.ts`:

```typescript
/**
 * Get groups accessible to the current device/user
 */
async getMyGroups(): Promise<any[]> {
  const result = await this.query(`
    query GetMyGroups {
      myGroups {
        id
        name
        description
        memberCount
        isPersonal
        members {
          id
          user { id email name }
          role
        }
        devices {
          id
          name
          isAuthorized
        }
      }
    }
  `);
  return result.myGroups || [];
}

/**
 * Get a single group by ID with full details
 */
async getGroupDetails(groupId: string): Promise<any> {
  const result = await this.query(`
    query GetGroupDetails($id: ID!) {
      userGroup(id: $id) {
        id
        name
        description
        memberCount
        isPersonal
        members {
          id
          user { id email name role }
          role
          joinedAt
        }
        projects {
          id
          name
          description
        }
        devices {
          id
          name
          fingerprint
          isAuthorized
          lastSeenAt
        }
        createdAt
        updatedAt
      }
    }
  `, { id: groupId });
  return result.userGroup;
}

/**
 * Get pending invitations for the current user
 */
async getMyInvitations(): Promise<any[]> {
  const result = await this.query(`
    query GetMyInvitations {
      myInvitations {
        id
        group { id name }
        email
        invitedBy { id email name }
        role
        status
        expiresAt
      }
    }
  `);
  return result.myInvitations || [];
}

/**
 * Invite a user to a group by email
 */
async inviteToGroup(groupId: string, email: string, role?: string): Promise<any> {
  const result = await this.query(`
    mutation InviteToGroup($groupId: ID!, $email: String!, $role: GroupMemberRole) {
      inviteToGroup(groupId: $groupId, email: $email, role: $role) {
        id
        email
        role
        status
        expiresAt
      }
    }
  `, { groupId, email, role: role || 'MEMBER' });
  return result.inviteToGroup;
}
```

**Step 2: Run existing tests**

Run: `cd ~/src/lacylights/lacylights-mcp && npm test 2>&1 | tail -20`
Expected: Existing tests pass (new methods are additive)

**Step 3: Commit**

```bash
git add lacylights-mcp/src/services/graphql-client-simple.ts
git commit -m "feat(mcp): add group query/mutation methods to GraphQL client"
```

---

### Task 8.2: Create Group Tools Module

**Files:**
- Create: `lacylights-mcp/src/tools/group-tools.ts`

**Step 1: Create the group tools module**

Create `lacylights-mcp/src/tools/group-tools.ts`:

```typescript
import { z } from 'zod';
import type { LacyLightsGraphQLClient } from '../services/graphql-client-simple.js';

const GetGroupDetailsSchema = z.object({
  groupId: z.string().describe('The group ID to get details for'),
});

const InviteToGroupSchema = z.object({
  groupId: z.string().describe('The group ID to invite the user to'),
  email: z.string().email().describe('Email address of the user to invite'),
  role: z.enum(['MEMBER', 'GROUP_ADMIN']).optional().describe('Role for the invited user (default: MEMBER)'),
});

export class GroupTools {
  constructor(private graphqlClient: LacyLightsGraphQLClient) {}

  /**
   * List groups accessible to this MCP device/user
   */
  async listGroups() {
    const groups = await this.graphqlClient.getMyGroups();
    return {
      count: groups.length,
      groups: groups.map((g: any) => ({
        id: g.id,
        name: g.name,
        description: g.description,
        memberCount: g.memberCount,
        isPersonal: g.isPersonal,
        deviceCount: g.devices?.length ?? 0,
      })),
    };
  }

  /**
   * Get full details of a group including members, projects, and devices
   */
  async getGroupDetails(args: z.infer<typeof GetGroupDetailsSchema>) {
    const { groupId } = GetGroupDetailsSchema.parse(args);
    const group = await this.graphqlClient.getGroupDetails(groupId);
    if (!group) {
      throw new Error(`Group not found: ${groupId}`);
    }
    return {
      id: group.id,
      name: group.name,
      description: group.description,
      isPersonal: group.isPersonal,
      memberCount: group.memberCount,
      members: group.members?.map((m: any) => ({
        userId: m.user.id,
        email: m.user.email,
        name: m.user.name,
        role: m.role,
        joinedAt: m.joinedAt,
      })) ?? [],
      projects: group.projects?.map((p: any) => ({
        id: p.id,
        name: p.name,
        description: p.description,
      })) ?? [],
      devices: group.devices?.map((d: any) => ({
        id: d.id,
        name: d.name,
        isAuthorized: d.isAuthorized,
        lastSeenAt: d.lastSeenAt,
      })) ?? [],
      createdAt: group.createdAt,
      updatedAt: group.updatedAt,
    };
  }

  /**
   * Invite a user to a group by email
   */
  async inviteToGroup(args: z.infer<typeof InviteToGroupSchema>) {
    const { groupId, email, role } = InviteToGroupSchema.parse(args);
    const invitation = await this.graphqlClient.inviteToGroup(groupId, email, role);
    return {
      success: true,
      invitation: {
        id: invitation.id,
        email: invitation.email,
        role: invitation.role,
        status: invitation.status,
        expiresAt: invitation.expiresAt,
      },
    };
  }
}

export { GetGroupDetailsSchema, InviteToGroupSchema };
```

**Step 2: Commit**

```bash
git add lacylights-mcp/src/tools/group-tools.ts
git commit -m "feat(mcp): create group tools module with list, details, invite"
```

---

### Task 8.3: Register Group Tools in MCP Server

**Files:**
- Modify: `lacylights-mcp/src/index.ts`

**Step 1: Import and initialize GroupTools**

Near the top of `index.ts`, add the import (alongside other tool imports):

```typescript
import { GroupTools } from './tools/group-tools.js';
```

In the constructor (where other tools are initialized, around line ~4500), add:

```typescript
private groupTools: GroupTools;
// In constructor:
this.groupTools = new GroupTools(this.graphqlClient);
```

**Step 2: Register tool definitions**

In the `ListToolsRequestSchema` handler, add these tool definitions (alongside existing tools):

```typescript
{
  name: "list_groups",
  description: "List groups accessible to this device/user. Shows group names, member counts, and device counts. Groups determine which projects you can access.",
  inputSchema: {
    type: "object",
    properties: {},
    required: [],
  },
},
{
  name: "get_group_details",
  description: "Get full details of a group including its members, projects, and assigned devices. Requires the group ID.",
  inputSchema: {
    type: "object",
    properties: {
      groupId: {
        type: "string",
        description: "The group ID to get details for",
      },
    },
    required: ["groupId"],
  },
},
{
  name: "invite_to_group",
  description: "Invite a user to join a group by their email address. Requires GROUP_ADMIN role in the target group. The invited user will receive a pending invitation they can accept or decline.",
  inputSchema: {
    type: "object",
    properties: {
      groupId: {
        type: "string",
        description: "The group ID to invite the user to",
      },
      email: {
        type: "string",
        description: "Email address of the user to invite",
      },
      role: {
        type: "string",
        enum: ["MEMBER", "GROUP_ADMIN"],
        description: "Role for the invited user (default: MEMBER)",
      },
    },
    required: ["groupId", "email"],
  },
},
```

**Step 3: Register tool handlers**

In the `CallToolRequestSchema` handler (the switch statement), add:

```typescript
case "list_groups":
  return {
    content: [{
      type: "text",
      text: JSON.stringify(await this.groupTools.listGroups(), null, 2),
    }],
  };

case "get_group_details":
  return {
    content: [{
      type: "text",
      text: JSON.stringify(await this.groupTools.getGroupDetails(args), null, 2),
    }],
  };

case "invite_to_group":
  return {
    content: [{
      type: "text",
      text: JSON.stringify(await this.groupTools.inviteToGroup(args), null, 2),
    }],
  };
```

**Step 4: Build and verify**

Run: `cd ~/src/lacylights/lacylights-mcp && npm run build 2>&1 | tail -20`
Expected: Build succeeds

**Step 5: Run tests**

Run: `cd ~/src/lacylights/lacylights-mcp && npm test 2>&1 | tail -20`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lacylights-mcp/src/index.ts
git commit -m "feat(mcp): register group tools (list_groups, get_group_details, invite_to_group)"
```

---

### Task 8.4: Add Group Tools Tests

**Files:**
- Create: `lacylights-mcp/tests/tools/group-tools.test.ts`

**Step 1: Write unit tests**

Create `lacylights-mcp/tests/tools/group-tools.test.ts` following the existing test patterns in the repo:

Test cases:
1. `listGroups` - returns formatted group list from client
2. `listGroups` - returns empty array when no groups
3. `getGroupDetails` - returns full group with members, projects, devices
4. `getGroupDetails` - throws when group not found
5. `inviteToGroup` - sends invitation with default MEMBER role
6. `inviteToGroup` - sends invitation with GROUP_ADMIN role
7. `inviteToGroup` - validates email format (Zod validation)

Mock the `LacyLightsGraphQLClient` methods.

**Step 2: Run tests**

Run: `cd ~/src/lacylights/lacylights-mcp && npm test 2>&1 | tail -20`
Expected: All tests pass

**Step 3: Run lint**

Run: `cd ~/src/lacylights/lacylights-mcp && npm run lint 2>&1 | tail -20`
Expected: No errors

**Step 4: Commit**

```bash
git add lacylights-mcp/tests/tools/group-tools.test.ts
git commit -m "test(mcp): add unit tests for group tools"
```

---

### Task 8.5: Run Full MCP Test Suite

**Step 1: Build**

Run: `cd ~/src/lacylights/lacylights-mcp && npm run build`
Expected: Clean build

**Step 2: Run all tests**

Run: `cd ~/src/lacylights/lacylights-mcp && npm test`
Expected: All pass

**Step 3: Run lint**

Run: `cd ~/src/lacylights/lacylights-mcp && npm run lint`
Expected: Clean

**Step 4: Commit any fixes**

---

## Summary

| Task | Repo | Description | Estimated Steps |
|------|------|-------------|-----------------|
| 7.1 | lacylights-fe | Add device-group GraphQL operations | 5 |
| 7.2 | lacylights-fe | Add group assignment to DeviceManagementModal | 7 |
| 7.3 | lacylights-fe | Add device list to group detail page | 5 |
| 7.4 | lacylights-fe | Run full frontend test suite | 3 |
| 8.1 | lacylights-mcp | Add group methods to GraphQL client | 3 |
| 8.2 | lacylights-mcp | Create group tools module | 2 |
| 8.3 | lacylights-mcp | Register group tools in MCP server | 6 |
| 8.4 | lacylights-mcp | Add group tools tests | 4 |
| 8.5 | lacylights-mcp | Run full MCP test suite | 4 |

**Total: 9 tasks, ~39 steps**

### Branch Strategy
- Frontend (Phase 7): Create branch `feature/group-device-assignment` from `main` in lacylights-fe
- MCP Server (Phase 8): Create branch `feature/mcp-group-tools` from `main` in lacylights-mcp
- These can be developed in parallel since they're independent repos
