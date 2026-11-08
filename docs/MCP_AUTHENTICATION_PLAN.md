# MCP Authentication Plan

## Executive Summary

This document outlines the approach for adding authentication to `lacylights-mcp` and other LacyLights components. The recommended approach is **Device Authentication** using a hybrid fingerprinting strategy optimized for the theatre production environment.

## Production Environment

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Theatre Internal Network (Closed)                     │
│                                                                              │
│  ┌──────────────────────┐       ┌─────────────────────────────────────────┐ │
│  │  Operator Laptop     │       │  Raspberry Pi (lacylights.local)        │ │
│  │  (Dual-homed)        │       │                                         │ │
│  │                      │       │  ┌─────────────────────────────────┐    │ │
│  │  ┌────────────────┐  │ ETH   │  │ lacylights-go (port 4000)       │    │ │
│  │  │ lacylights-mcp │──┼───────┼─►│ Backend GraphQL API             │    │ │
│  │  └────────────────┘  │       │  └─────────────────────────────────┘    │ │
│  │         │            │       │  ┌─────────────────────────────────┐    │ │
│  │  ┌──────▼─────────┐  │       │  │ lacylights-fe (port 3000)       │    │ │
│  │  │ Claude/LLM     │  │ WiFi  │  │ Frontend Next.js                │    │ │
│  │  │ (Internet)     │◄─┼───────┼──┤                                 │    │ │
│  │  └────────────────┘  │       │  └─────────────────────────────────┘    │ │
│  └──────────────────────┘       └─────────────────────────────────────────┘ │
│                                                                              │
│  ┌──────────────────────┐       ┌──────────────────────┐                    │
│  │  Stage Manager iPad  │       │  Tech Director iPad  │                    │
│  │  (Internal WiFi)     │───────│  (Internal WiFi)     │                    │
│  └──────────────────────┘       └──────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Characteristics:**
- Raspberry Pi hosts backend and frontend on closed internal network
- Operator laptop is dual-homed: ethernet to internal network, WiFi to internet for LLM access
- iPads connect via internal WiFi (no internet access)
- Single operator uses MCP at a time
- Devices (not users) are the unit of trust
- Crew members do not change frequently

## Current State

### lacylights-go Authentication (Implemented)
- JWT-based authentication with access tokens (15-min TTL) and refresh tokens (7-day TTL)
- Session management with database persistence and in-memory caching
- Argon2id password hashing
- Account lockout after 5 failed attempts
- GraphQL mutations: `login`, `register`, `refreshToken`, `logout`
- Bearer token in `Authorization` header
- Configurable via `AUTH_ENABLED` environment variable
- Device authentication support (fingerprint-based)

### lacylights-fe Authentication (Implemented)
- Stores tokens in localStorage
- Apollo Client authLink adds `Authorization: Bearer <token>` header
- Automatic token refresh on expiry
- Session cookies for middleware protection

### lacylights-mcp Current State (No Auth)
- Simple HTTP client with only `Content-Type` header
- No token management
- Direct GraphQL queries without authentication

---

## Authentication Modes

The system supports two operating modes, controlled by the `AUTH_ENABLED` environment variable:

| Feature | AUTH_ENABLED=false | AUTH_ENABLED=true |
|---------|-------------------|-------------------|
| Network access | Any client allowed | Approved devices only |
| Device registration | Not needed | Required |
| Admin approval | Not needed | Required for new devices |
| Device revocation | N/A | Supported |
| MCP server setup | Just set endpoint | Register + approve device |
| iPad setup | Just open URL | Name device + admin approves |
| Best for | Isolated networks | Shared/guest networks |

### Mode 1: No Authentication (AUTH_ENABLED=false)

**Use Case:** Network is sufficiently secured/isolated, no authentication needed.

```bash
# /opt/lacylights/backend/.env
AUTH_ENABLED=false
```

**Behavior:**
- All clients on the network have full access
- No login required
- No device registration required
- `X-Device-Fingerprint` header ignored (can still be sent)
- Simplest setup for trusted/isolated networks

**When to Use:**
- Theatre network is physically isolated
- No untrusted devices can connect
- Single-user or trusted crew environment
- Development and testing

### Mode 2: Device Authentication (AUTH_ENABLED=true)

**Use Case:** Network may have untrusted devices, or audit trail is desired.

```bash
# /opt/lacylights/backend/.env
AUTH_ENABLED=true
DEVICE_AUTH_ENABLED=true
```

**Behavior:**
- Devices must register and be approved
- Approved devices have automatic access
- Unknown devices are rejected
- Admin can revoke devices at any time

**When to Use:**
- Shared network with guest/untrusted devices
- Multiple venues with different security needs
- Audit trail required for changes
- Enterprise deployments

---

## Device Authentication Details (Mode 2)

**Core Principle:** Specific computers and iOS devices are trusted automatically, regardless of who is using them.

### Why Device Authentication

| Requirement | How Device Auth Addresses It |
|-------------|------------------------------|
| Device-centric trust | Machines are approved, not individual users |
| Single operator at a time | No concurrent session conflicts |
| Stable crew | Devices registered once, rarely changed |
| Mixed device types | Hybrid fingerprinting for laptops vs iPads |
| Closed network | Simpler than OAuth, appropriate for trusted environment |

### Device Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Device Registration Flow                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. FIRST CONNECTION                                                         │
│     ┌──────────┐     GET /graphql      ┌──────────┐                         │
│     │  Device  │ ──────────────────►   │ Backend  │                         │
│     │          │  X-Device-Fingerprint │          │                         │
│     │          │ ◄────────────────────  │          │                         │
│     └──────────┘  "Device not approved" └──────────┘                         │
│                                                                              │
│  2. REGISTRATION                                                             │
│     ┌──────────┐     Register Device    ┌──────────┐                         │
│     │  Device  │ ──────────────────►   │ Backend  │                         │
│     │          │  fingerprint + name    │          │                         │
│     │          │ ◄────────────────────  │          │                         │
│     └──────────┘  "Pending approval"    └──────────┘                         │
│                                                                              │
│  3. ADMIN APPROVAL                                                           │
│     ┌──────────┐     Approve Device     ┌──────────┐                         │
│     │  Admin   │ ──────────────────►   │ Backend  │                         │
│     │ (via FE) │  deviceId + permissions│          │                         │
│     └──────────┘                        └──────────┘                         │
│                                                                              │
│  4. SUBSEQUENT CONNECTIONS                                                   │
│     ┌──────────┐     Any Request        ┌──────────┐                         │
│     │  Device  │ ──────────────────►   │ Backend  │                         │
│     │          │  X-Device-Fingerprint │          │                         │
│     │          │ ◄────────────────────  │          │                         │
│     └──────────┘  Success (authorized)  └──────────┘                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Device Fingerprinting Strategy

### Challenge: Apple Device Privacy

Apple has implemented aggressive privacy protections that block traditional fingerprinting:

| Technique | Status on iOS | Notes |
|-----------|---------------|-------|
| MAC Address | ❌ Randomized | iOS 14+ uses private MAC per network |
| Device UDID | ❌ Deprecated | No longer accessible |
| IDFA | ❌ Requires opt-in | User must approve, can reset |
| Canvas/WebGL | ⚠️ Limited | Safari ITP reduces uniqueness |
| IP Address | ❌ Changes | DHCP assignment varies |

### Solution: Hybrid Fingerprinting Approach

#### For MCP Server (Laptops/Desktops)

Use `node-machine-id` package for stable OS-level machine identification:

```typescript
import { machineIdSync } from 'node-machine-id';
import * as os from 'os';
import * as crypto from 'crypto';

function generateMcpFingerprint(): string {
  try {
    // Primary: OS machine ID (very stable)
    // macOS: IOPlatformUUID from IOKit
    // Linux: /etc/machine-id
    // Windows: MachineGuid from registry
    return machineIdSync();
  } catch {
    // Fallback: hash of hostname + username
    const data = `${os.hostname()}-${os.userInfo().username}-lacylights`;
    return crypto.createHash('sha256').update(data).digest('hex').slice(0, 32);
  }
}
```

**Stability:** Persists across reboots, app reinstalls, and OS updates.

#### For iPads/Browsers (Frontend)

Use **PWA + localStorage UUID** with explicit device registration:

```typescript
// Device ID management for browsers
const DEVICE_ID_KEY = 'lacylights_device_id';
const DEVICE_NAME_KEY = 'lacylights_device_name';

function getOrCreateDeviceId(): string {
  let deviceId = localStorage.getItem(DEVICE_ID_KEY);
  if (!deviceId) {
    deviceId = crypto.randomUUID();
    localStorage.setItem(DEVICE_ID_KEY, deviceId);
  }
  return deviceId;
}

function getDeviceName(): string | null {
  return localStorage.getItem(DEVICE_NAME_KEY);
}

function setDeviceName(name: string): void {
  localStorage.setItem(DEVICE_NAME_KEY, name);
}
```

**Registration Flow for iPads:**

```
1. User opens lacylights.local on iPad
2. App detects no device name stored
3. Prompt: "Name this device" → "Stage Manager iPad"
4. Device ID + name sent to backend for registration
5. Admin approves device in Device Management panel
6. iPad now has persistent access
```

**PWA Installation (Recommended):**

```typescript
// Request persistent storage for PWA
async function requestPersistentStorage(): Promise<boolean> {
  if (navigator.storage && navigator.storage.persist) {
    const granted = await navigator.storage.persist();
    console.log(`Persistent storage: ${granted ? 'granted' : 'denied'}`);
    return granted;
  }
  return false;
}
```

Installing as PWA ("Add to Home Screen") provides:
- More durable localStorage (less likely to be evicted)
- Full-screen app experience
- Offline capability for basic viewing

**Recovery from Storage Cleared:**

If a user clears Safari data:
1. Device appears as new (different UUID)
2. User re-enters device name: "Stage Manager iPad"
3. Admin sees new pending device with familiar name
4. Admin approves (or links to previous registration)

---

## Implementation Plan

### Phase 1: Backend Updates (lacylights-go)

#### 1.1 Device Authentication Enhancements

```graphql
# New/updated GraphQL operations

type Device {
  id: ID!
  fingerprint: String!
  name: String!
  status: DeviceStatus!  # PENDING, APPROVED, REVOKED
  permissions: DevicePermissions!
  lastSeen: DateTime
  createdAt: DateTime!
  approvedAt: DateTime
  approvedBy: User
}

enum DeviceStatus {
  PENDING
  APPROVED
  REVOKED
}

enum DevicePermissions {
  READ_ONLY
  OPERATOR    # Can control lights
  ADMIN       # Full access including device management
}

type Query {
  # Check device status (unauthenticated)
  checkDevice(fingerprint: String!): DeviceCheckResult!

  # List devices (admin only)
  getDevices(status: DeviceStatus): [Device!]!
  getPendingDevices: [Device!]!
}

type Mutation {
  # Register new device (unauthenticated)
  registerDevice(fingerprint: String!, name: String!): DeviceRegistrationResult!

  # Admin operations
  approveDevice(deviceId: ID!, permissions: DevicePermissions!): Device!
  revokeDevice(deviceId: ID!): Device!
  updateDevicePermissions(deviceId: ID!, permissions: DevicePermissions!): Device!
}

type DeviceCheckResult {
  status: DeviceStatus!
  device: Device
  message: String
}

type DeviceRegistrationResult {
  success: Boolean!
  device: Device
  message: String!
}
```

#### 1.2 Middleware Updates

```go
// Middleware checks authentication based on server configuration
func AuthMiddleware(authService *auth.Service, config *config.Config) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // If auth is disabled, allow all requests
            if !config.AuthEnabled {
                next.ServeHTTP(w, r)
                return
            }

            // Check for device fingerprint first
            fingerprint := r.Header.Get("X-Device-Fingerprint")
            if fingerprint != "" && config.DeviceAuthEnabled {
                device, err := authService.GetDeviceByFingerprint(fingerprint)
                if err == nil && device.Status == "APPROVED" {
                    // Device is approved - add to context and allow
                    ctx := context.WithValue(r.Context(), "device", device)
                    next.ServeHTTP(w, r.WithContext(ctx))
                    return
                }
            }

            // Fall back to Bearer token authentication
            token := extractBearerToken(r)
            if token != "" {
                session, err := authService.ValidateSession(token)
                if err == nil {
                    ctx := context.WithValue(r.Context(), "session", session)
                    next.ServeHTTP(w, r.WithContext(ctx))
                    return
                }
            }

            // No valid authentication - reject
            http.Error(w, "Unauthorized", http.StatusUnauthorized)
        })
    }
}
```

**Key Points:**
- When `AUTH_ENABLED=false`, middleware passes all requests through
- When enabled, checks device fingerprint first, then Bearer token
- Supports both authentication methods simultaneously

#### 1.3 Database Schema

```sql
-- Extend existing devices table or create new
CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    fingerprint TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING',  -- PENDING, APPROVED, REVOKED
    permissions TEXT NOT NULL DEFAULT 'READ_ONLY',
    last_seen DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    approved_at DATETIME,
    approved_by TEXT REFERENCES users(id)
);

CREATE INDEX idx_devices_fingerprint ON devices(fingerprint);
CREATE INDEX idx_devices_status ON devices(status);
```

### Phase 2: MCP Server Updates (lacylights-mcp)

#### 2.1 Add Device Fingerprint Generation

```typescript
// src/utils/device-fingerprint.ts
import { machineIdSync } from 'node-machine-id';
import * as os from 'os';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const FINGERPRINT_FILE = path.join(os.homedir(), '.lacylights', 'device-id');

export function getDeviceFingerprint(): string {
  // Try cached fingerprint first
  if (fs.existsSync(FINGERPRINT_FILE)) {
    return fs.readFileSync(FINGERPRINT_FILE, 'utf-8').trim();
  }

  // Generate new fingerprint
  let fingerprint: string;
  try {
    fingerprint = machineIdSync();
  } catch {
    const data = `${os.hostname()}-${os.userInfo().username}-lacylights-mcp`;
    fingerprint = crypto.createHash('sha256').update(data).digest('hex').slice(0, 32);
  }

  // Cache it
  const dir = path.dirname(FINGERPRINT_FILE);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(FINGERPRINT_FILE, fingerprint);

  return fingerprint;
}

export function getDeviceName(): string {
  return `${os.hostname()} (MCP)`;
}
```

#### 2.2 Update GraphQL Client

```typescript
// src/services/graphql-client-simple.ts

export class LacyLightsGraphQLClient {
  private endpoint: string;
  private deviceFingerprint: string;

  constructor(endpoint: string, deviceFingerprint: string) {
    this.endpoint = endpoint;
    this.deviceFingerprint = deviceFingerprint;
  }

  private async query(query: string, variables?: any): Promise<any> {
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Device-Fingerprint': this.deviceFingerprint,
      },
      body: JSON.stringify({ query, variables }),
    });

    const result = await response.json();

    if (result.errors) {
      const error = result.errors[0];
      if (error.extensions?.code === 'DEVICE_NOT_APPROVED') {
        throw new DeviceNotApprovedError(error.message, this.deviceFingerprint);
      }
      throw new Error(error.message);
    }

    return result.data;
  }
}

export class DeviceNotApprovedError extends Error {
  constructor(message: string, public fingerprint: string) {
    super(message);
    this.name = 'DeviceNotApprovedError';
  }
}
```

#### 2.3 Startup Device Check

```typescript
// src/index.ts

async function initializeServer() {
  const fingerprint = getDeviceFingerprint();
  const deviceName = getDeviceName();

  console.log(`Device fingerprint: ${fingerprint}`);
  console.log(`Device name: ${deviceName}`);

  const client = new LacyLightsGraphQLClient(graphqlEndpoint, fingerprint);

  try {
    // Check auth settings first
    const authSettings = await client.getAuthSettings();

    if (!authSettings.authEnabled) {
      console.log('Authentication disabled on server - all access allowed');
      // Continue without device registration
      return client;
    }

    // Auth is enabled - check device status
    const result = await client.checkDevice(fingerprint);

    if (result.status === 'APPROVED') {
      console.log(`Device approved: ${result.device.name}`);
    } else if (result.status === 'PENDING') {
      console.log('Device is pending approval.');
      console.log('Please approve this device in the LacyLights admin panel.');
      console.log(`Device name: ${deviceName}`);
      console.log(`Fingerprint: ${fingerprint}`);
      // Could exit or continue in limited mode
    } else if (result.status === 'UNKNOWN') {
      // Register the device
      console.log('Registering device...');
      await client.registerDevice(fingerprint, deviceName);
      console.log('Device registered. Please approve in admin panel.');
    }
  } catch (error) {
    if (error instanceof DeviceNotApprovedError) {
      console.error('Device not approved. Please approve in admin panel.');
      console.error(`Fingerprint: ${error.fingerprint}`);
    }
    throw error;
  }

  // Continue with server initialization...
}
```

#### 2.4 Package Dependencies

```json
{
  "dependencies": {
    "node-machine-id": "^1.1.12"
  }
}
```

### Phase 3: Frontend Updates (lacylights-fe)

#### 3.1 Device Registration Component

```typescript
// src/components/auth/DeviceRegistration.tsx

export function DeviceRegistration() {
  const [deviceName, setDeviceName] = useState('');
  const deviceId = getOrCreateDeviceId();
  const existingName = getDeviceName();

  if (existingName) {
    // Already registered, check status
    return <DeviceStatusCheck deviceId={deviceId} name={existingName} />;
  }

  const handleRegister = async () => {
    await registerDevice(deviceId, deviceName);
    setDeviceName(deviceName);
    localStorage.setItem(DEVICE_NAME_KEY, deviceName);
  };

  return (
    <div className="device-registration">
      <h2>Register This Device</h2>
      <p>Give this device a name so it can be identified:</p>
      <input
        type="text"
        placeholder="e.g., Stage Manager iPad"
        value={deviceName}
        onChange={(e) => setDeviceName(e.target.value)}
      />
      <button onClick={handleRegister}>Register Device</button>
    </div>
  );
}
```

#### 3.2 Device Management Admin Panel

```typescript
// src/components/admin/DeviceManagement.tsx

export function DeviceManagement() {
  const { data: devices } = useQuery(GET_DEVICES);
  const [approveDevice] = useMutation(APPROVE_DEVICE);
  const [revokeDevice] = useMutation(REVOKE_DEVICE);

  const pendingDevices = devices?.filter(d => d.status === 'PENDING') || [];
  const approvedDevices = devices?.filter(d => d.status === 'APPROVED') || [];

  return (
    <div className="device-management">
      <h2>Device Management</h2>

      {pendingDevices.length > 0 && (
        <section>
          <h3>Pending Approval</h3>
          {pendingDevices.map(device => (
            <DeviceCard
              key={device.id}
              device={device}
              onApprove={(perms) => approveDevice({ variables: { deviceId: device.id, permissions: perms }})}
            />
          ))}
        </section>
      )}

      <section>
        <h3>Approved Devices</h3>
        {approvedDevices.map(device => (
          <DeviceCard
            key={device.id}
            device={device}
            onRevoke={() => revokeDevice({ variables: { deviceId: device.id }})}
          />
        ))}
      </section>
    </div>
  );
}
```

#### 3.3 Apollo Client Device Header

```typescript
// src/lib/apollo-client.ts

const deviceLink = setContext((_, { headers }) => {
  const deviceId = localStorage.getItem('lacylights_device_id');
  return {
    headers: {
      ...headers,
      ...(deviceId && { 'X-Device-Fingerprint': deviceId }),
    }
  };
});

// Link chain
const link = from([configLink, authLink, deviceLink, httpLink]);
```

### Phase 4: Platform Updates

#### 4.1 lacylights-rpi

```bash
# /opt/lacylights/backend/.env

# Option A: No authentication (default for simple setups)
AUTH_ENABLED=false

# Option B: Device authentication (for shared networks)
# AUTH_ENABLED=true
# DEVICE_AUTH_ENABLED=true
# JWT_SECRET=<generated-during-install>
# DEFAULT_ADMIN_EMAIL=admin@lacylights.local
# DEFAULT_ADMIN_PASSWORD=<set-during-setup>
```

Installation script updates:
- Prompt user: "Enable device authentication? (y/N)"
- If yes: Generate secure JWT_SECRET, prompt for admin credentials
- If no: Set `AUTH_ENABLED=false` (simplest setup)
- Can be changed later by editing `.env` and restarting

#### 4.2 lacylights-mac

StartupCoordinator updates:
- Default to `AUTH_ENABLED=false` for local-only use
- Add preference toggle: "Require device authentication"
- If enabled: Generate/store JWT_SECRET in Keychain
- First-run wizard includes optional auth setup

---

## Other Repositories Requiring Updates

### lacylights-test (Integration Tests)

**Required Updates:**
- Add `X-Device-Fingerprint` header support to GraphQL client
- Create test device that's auto-approved in test mode
- Or: Add `AUTH_SKIP_FOR_TESTS=true` environment variable

```go
// pkg/graphql/client.go
type Client struct {
    endpoint    string
    fingerprint string  // Add this
}

func (c *Client) do(query string, variables map[string]any, response any) error {
    req, _ := http.NewRequest("POST", c.endpoint, body)
    req.Header.Set("Content-Type", "application/json")
    if c.fingerprint != "" {
        req.Header.Set("X-Device-Fingerprint", c.fingerprint)
    }
    // ...
}
```

### lacylights-terraform

No updates needed - infrastructure only, no backend communication.

---

## Implementation Priority

| Priority | Repository | Task | Effort |
|----------|------------|------|--------|
| 1 | lacylights-go | Device auth enhancements (schema, middleware) | 2-3 days |
| 2 | lacylights-fe | Device registration + admin panel | 2 days |
| 3 | lacylights-mcp | Add fingerprint generation + header | 1 day |
| 4 | lacylights-test | Add device fingerprint to test client | 0.5 days |
| 5 | lacylights-rpi | Enable device auth in setup | 1 day |
| 6 | lacylights-mac | Enable device auth in startup | 1 day |

---

## Security Considerations

1. **Network Security**: Theatre network should be isolated from public networks
2. **Device Revocation**: Admin can immediately revoke any device
3. **Permission Levels**: Devices can have READ_ONLY, OPERATOR, or ADMIN permissions
4. **Fingerprint Privacy**: Fingerprints are hashed/random, not PII
5. **Storage Durability**: PWA installation recommended for iPads

---

## Edge Cases and Recovery

| Scenario | Recovery |
|----------|----------|
| iPad Safari data cleared | Re-register with same name, admin approves |
| Laptop reimaged | New machine ID, re-register as new device |
| Device lost/stolen | Admin revokes device immediately |
| Network changes | Fingerprint is network-independent |
| Multiple users same device | Device is trusted, not user - works as designed |

---

## Future Enhancements

1. **QR Code Pairing**: Scan QR from approved device to fast-approve new device
2. **Time-Limited Access**: Guest devices with expiring approval
3. **Audit Log**: Track which device made which changes (if needed later)
4. **OAuth 2.1**: Add for enterprise deployments requiring SSO

---

## References

- [MCP Security Best Practices](https://modelcontextprotocol.io/specification/draft/basic/security_best_practices)
- [MCP Authorization Guide (Auth0)](https://auth0.com/blog/an-introduction-to-mcp-and-authorization/)
- [MCP Spec Updates June 2025](https://auth0.com/blog/mcp-specs-update-all-about-auth/)
- [Apple Privacy - Device Identifiers](https://developer.apple.com/documentation/uikit/uidevice/1620059-identifierforvendor)
- [node-machine-id](https://www.npmjs.com/package/node-machine-id)
