# WiFi Availability Check Implementation

## Overview

The WiFi configuration system now includes a **platform detection feature** that automatically hides the WiFi section on systems where WiFi configuration is not supported (e.g., macOS development machines) and only shows it on systems with WiFi capability (e.g., Raspberry Pi).

## Problem Solved

**Before:** WiFi configuration UI would appear on all systems, even macOS development machines where NetworkManager (nmcli) is not available, leading to confusing error messages and broken functionality.

**After:** WiFi configuration UI only appears on systems that actually support WiFi configuration, providing a clean and appropriate user experience across all platforms.

---

## How It Works

### Backend Detection

#### 1. **WiFiService.isWiFiSupported()** (`src/services/WiFiService.ts`)

New public method that checks if WiFi configuration is supported:

```typescript
async isWiFiSupported(): Promise<boolean>
```

**Checks:**
1. ✅ NetworkManager (nmcli) is installed
2. ✅ System has a WiFi device (wlan0, etc.)

**Returns:**
- `true` - On Raspberry Pi or other Linux systems with WiFi
- `false` - On macOS, Windows, or systems without WiFi hardware

**Logging:**
```
[INFO] WiFi configuration is supported on this system
[INFO] WiFi configuration not supported: NetworkManager (nmcli) not found
[INFO] WiFi configuration not supported: No WiFi device found
```

#### 2. **Updated WiFiStatus Interface**

Added `available` field to WiFiStatus:

```typescript
export interface WiFiStatus {
  available: boolean;  // NEW: Is WiFi configuration supported?
  enabled: boolean;
  connected: boolean;
  ssid?: string;
  signalStrength?: number;
  ipAddress?: string;
  macAddress?: string;
  frequency?: string;
}
```

#### 3. **WiFiService.getStatus() Updates**

Now checks availability first:

```typescript
async getStatus(): Promise<WiFiStatus> {
  const available = await this.isWiFiSupported();

  if (!available) {
    return {
      available: false,
      enabled: false,
      connected: false,
    };
  }

  // ... rest of status check logic
}
```

**Behavior:**
- On macOS: Returns `{ available: false, enabled: false, connected: false }`
- On Raspberry Pi: Returns full WiFi status with `available: true`

### GraphQL Schema

Updated `WiFiStatus` type:

```graphql
type WiFiStatus {
  available: Boolean!  # NEW: Indicates if WiFi is supported
  enabled: Boolean!
  connected: Boolean!
  ssid: String
  signalStrength: Int
  ipAddress: String
  macAddress: String
  frequency: String
}
```

All queries, mutations, and subscriptions that return `WiFiStatus` now include the `available` field.

### Frontend Detection

#### 1. **Updated GraphQL Queries**

All WiFi GraphQL operations now fetch the `available` field:

```graphql
query WiFiStatus {
  wifiStatus {
    available  # NEW
    enabled
    connected
    # ... other fields
  }
}
```

#### 2. **WiFiSettings Component** (`src/app/(main)/settings/WiFiSettings.tsx`)

Added conditional rendering based on availability:

```typescript
// Don't render WiFi section if WiFi is not available on this system
if (!status?.available) {
  return null;
}
```

**Behavior:**
- On macOS: Component returns `null`, no WiFi UI appears
- On Raspberry Pi: Component renders full WiFi configuration interface

#### 3. **Settings Page** (`src/app/(main)/settings/page.tsx`)

Clean integration:

```tsx
{/* WiFi Configuration Section - Only show on systems with WiFi support */}
<WiFiSettings />

{/* Art-Net Configuration Section */}
<div>
  <h2>Art-Net Configuration</h2>
  {/* ... Art-Net settings always visible ... */}
</div>
```

The WiFiSettings component handles its own visibility, so the settings page remains simple and clean.

---

## Platform-Specific Behavior

### macOS Development Machine

**Detection:**
```bash
$ which nmcli
# (no output - nmcli not found)
```

**Backend Response:**
```json
{
  "wifiStatus": {
    "available": false,
    "enabled": false,
    "connected": false
  }
}
```

**Frontend Rendering:**
```
Settings
┌─────────────────────────────┐
│ Art-Net Configuration       │  ← Only Art-Net section visible
│ ...                         │
└─────────────────────────────┘
```

### Raspberry Pi (or Linux with WiFi)

**Detection:**
```bash
$ which nmcli
/usr/bin/nmcli

$ nmcli device status
DEVICE  TYPE      STATE
wlan0   wifi      disconnected  ← WiFi device found!
eth0    ethernet  connected
```

**Backend Response:**
```json
{
  "wifiStatus": {
    "available": true,
    "enabled": true,
    "connected": false
  }
}
```

**Frontend Rendering:**
```
Settings
┌─────────────────────────────┐
│ WiFi Configuration          │  ← WiFi section visible
│ - WiFi Radio Toggle         │
│ - Current Status            │
│ - Available Networks        │
│ ...                         │
└─────────────────────────────┘
┌─────────────────────────────┐
│ Art-Net Configuration       │
│ ...                         │
└─────────────────────────────┘
```

---

## Files Modified

### Backend (`lacylights-node`)

1. **src/services/WiFiService.ts**
   - Added `isWiFiSupported()` method
   - Updated `WiFiStatus` interface with `available` field
   - Updated `getStatus()` to check availability first

2. **src/graphql/schema.ts**
   - Added `available: Boolean!` to `WiFiStatus` type

3. **No changes to resolvers needed** - WiFiService handles everything

### Frontend (`lacylights-fe`)

1. **src/types/index.ts**
   - Added `available: boolean` to `WiFiStatus` interface

2. **src/graphql/wifi.ts**
   - Added `available` field to all WiFi queries, mutations, and subscription

3. **src/app/(main)/settings/WiFiSettings.tsx**
   - Added availability check that returns `null` when WiFi not available
   - Wrapped content in div with h2 title for cleaner layout

4. **src/app/(main)/settings/page.tsx**
   - Simplified - WiFiSettings component handles its own visibility

---

## Testing

### ✅ Verified on macOS
```bash
# Backend type check
cd lacylights-node
npm run type-check  # ✓ PASSES

# Frontend type check
cd lacylights-fe
npm run type-check  # ✓ PASSES

# Availability check
which nmcli  # Not found (expected)
```

**Expected behavior on macOS:**
- Backend returns `{ available: false, enabled: false, connected: false }`
- Frontend hides WiFi section
- Only Art-Net configuration visible in Settings

### 🔄 To Test on Raspberry Pi

When you deploy to the Pi, the WiFi section should automatically appear because:

1. nmcli is available: `/usr/bin/nmcli`
2. WiFi device exists: `wlan0`
3. Backend returns `available: true`
4. Frontend shows WiFi configuration UI

**Test commands on Pi:**
```bash
# Verify nmcli is available
which nmcli
# Expected: /usr/bin/nmcli

# Verify WiFi device exists
nmcli device status | grep wifi
# Expected: wlan0  wifi  ...

# Test GraphQL query
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ wifiStatus { available enabled connected } }"}'
# Expected: {"data":{"wifiStatus":{"available":true,"enabled":true,"connected":false}}}
```

---

## Error Handling

### Graceful Degradation

The system gracefully handles all scenarios:

| Scenario | Backend Behavior | Frontend Behavior |
|----------|------------------|-------------------|
| **nmcli not installed** | Returns `available: false` | Hides WiFi section |
| **No WiFi device** | Returns `available: false` | Hides WiFi section |
| **WiFi device present** | Returns `available: true` | Shows WiFi section |
| **nmcli errors** | Logs warning, returns `available: false` | Hides WiFi section |

### No User Errors

Users never see:
- ❌ "nmcli not found" errors
- ❌ Empty WiFi network lists on non-WiFi systems
- ❌ Broken UI elements
- ❌ Confusing error messages

Instead:
- ✅ WiFi section simply doesn't appear when not supported
- ✅ Clean, platform-appropriate UI
- ✅ Informative logs for debugging

---

## Benefits

### 1. **Cross-Platform Development**
Developers can run the full LacyLights stack on macOS for development without seeing broken WiFi UI.

### 2. **Clean User Experience**
Users only see features that are actually available on their system.

### 3. **Future-Proof**
Easy to extend for other platform-specific features:
- Bluetooth configuration
- Cellular/LTE connectivity
- Platform-specific hardware controls

### 4. **No Configuration Required**
Automatic detection - no environment variables or config files needed.

### 5. **Fail-Safe**
If detection fails, system defaults to hiding WiFi rather than showing broken UI.

---

## Deployment Notes

### No Additional Setup Required

The WiFi availability check works automatically on all systems:

- **Raspberry Pi**: nmcli + WiFi device → WiFi UI appears
- **macOS**: No nmcli → WiFi UI hidden
- **Windows**: No nmcli → WiFi UI hidden
- **Linux Desktop (no WiFi)**: No WiFi device → WiFi UI hidden
- **Linux Desktop (with WiFi)**: nmcli + WiFi device → WiFi UI appears

### Environment Variables (Optional)

You can still use environment variables if needed:

```bash
# Override WiFi device name (default: wlan0)
WIFI_DEVICE=wlan1

# Disable WiFi features entirely (overrides detection)
WIFI_ENABLED=false
```

But in most cases, automatic detection is sufficient.

---

## Summary

The WiFi configuration system is now **platform-aware** and provides the optimal user experience on every system:

- 🎯 **Smart Detection**: Automatically detects WiFi capability
- 🚀 **Zero Configuration**: Works out of the box on all platforms
- 💎 **Clean UI**: Only shows features that are available
- 🛡️ **Fail-Safe**: Gracefully handles all error scenarios
- 📱 **Raspberry Pi Ready**: Full WiFi UI on supported hardware
- 💻 **Developer Friendly**: Clean experience on macOS development machines

The system is ready to deploy and will behave appropriately on both development machines and production Raspberry Pi devices!
