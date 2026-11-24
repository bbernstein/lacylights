# WiFi Configuration Design

## Overview

This document describes the design and implementation of the WiFi configuration feature for the LacyLights Raspberry Pi product. The feature allows users to configure WiFi connectivity through the web interface, enabling dual-network operation:
- **Wired Network**: For internal DMX/Art-Net lighting control
- **WiFi Network**: For external internet access (AI models, updates, etc.)

## Architecture

### Network Topology

```
Raspberry Pi (lacylights.local)
├── eth0 (Wired) → Internal lighting network (Art-Net broadcast)
└── wlan0 (WiFi) → External network (Internet, AI APIs)
```

### Technology Stack

**Backend:**
- **NetworkManager** (via `nmcli` CLI): Modern network management on Raspberry Pi OS
- **GraphQL API**: Queries, mutations, and subscriptions for WiFi operations
- **Child Process Execution**: Node.js `child_process.exec()` to run nmcli commands
- **Settings Storage**: Persistent WiFi state in PostgreSQL via Prisma

**Frontend:**
- **React Components**: WiFi settings UI integrated into existing settings page
- **Apollo Client**: GraphQL queries and mutations
- **Real-time Updates**: Subscriptions for connection status changes

## Backend Implementation

### 1. WiFiService (`src/services/WiFiService.ts`)

Core service for WiFi operations using NetworkManager.

#### Key Methods:

```typescript
class WiFiService {
  // Scan for available WiFi networks
  async scanNetworks(): Promise<WiFiNetwork[]>

  // Get current WiFi connection status
  async getStatus(): Promise<WiFiStatus>

  // Connect to a WiFi network
  async connect(ssid: string, password?: string): Promise<boolean>

  // Disconnect from current WiFi network
  async disconnect(): Promise<boolean>

  // Enable/disable WiFi radio
  async setEnabled(enabled: boolean): Promise<boolean>

  // Check if WiFi is enabled
  async isEnabled(): Promise<boolean>

  // Forget a saved network
  async forgetNetwork(ssid: string): Promise<boolean>
}
```

#### NetworkManager Commands:

```bash
# Scan networks
nmcli device wifi list --rescan yes

# Get WiFi status
nmcli device status | grep wifi
nmcli connection show --active | grep wifi

# Connect to network (auto-detect security)
nmcli device wifi connect "SSID" password "PASSWORD"

# Disconnect
nmcli connection down "CONNECTION_NAME"

# Enable/disable WiFi
nmcli radio wifi on
nmcli radio wifi off

# Forget network
nmcli connection delete "CONNECTION_NAME"

# Get connection details
nmcli connection show "CONNECTION_NAME"
```

### 2. GraphQL Schema Extensions

#### Types:

```graphql
type WiFiNetwork {
  ssid: String!
  signalStrength: Int!          # 0-100 percentage
  frequency: String!             # "2.4 GHz" or "5 GHz"
  security: WiFiSecurityType!
  inUse: Boolean!               # Currently connected
  saved: Boolean!               # Saved in NetworkManager
}

enum WiFiSecurityType {
  OPEN
  WEP
  WPA_PSK          # WPA/WPA2 Personal
  WPA_EAP          # WPA/WPA2 Enterprise
  WPA3_PSK         # WPA3 Personal
  WPA3_EAP         # WPA3 Enterprise
  OWE              # Opportunistic Wireless Encryption
}

type WiFiStatus {
  enabled: Boolean!
  connected: Boolean!
  ssid: String
  signalStrength: Int
  ipAddress: String
  macAddress: String
  frequency: String
}

type WiFiConnection Result {
  success: Boolean!
  message: String
  connected: Boolean!
}
```

#### Queries:

```graphql
extend type Query {
  # Scan for available WiFi networks
  wifiNetworks(rescan: Boolean = true): [WiFiNetwork!]!

  # Get current WiFi status
  wifiStatus: WiFiStatus!

  # Get saved WiFi networks
  savedWifiNetworks: [WiFiNetwork!]!
}
```

#### Mutations:

```graphql
extend type Mutation {
  # Connect to WiFi network (password optional for open networks)
  connectWiFi(ssid: String!, password: String): WiFiConnectionResult!

  # Disconnect from current WiFi network
  disconnectWiFi: WiFiConnectionResult!

  # Enable/disable WiFi radio
  setWiFiEnabled(enabled: Boolean!): WiFiStatus!

  # Forget a saved WiFi network
  forgetWiFiNetwork(ssid: String!): Boolean!
}
```

#### Subscriptions:

```graphql
extend type Subscription {
  # Subscribe to WiFi status changes
  wifiStatusUpdated: WiFiStatus!
}
```

### 3. Settings Integration

Add WiFi-related settings to the `Setting` model:

```typescript
// Setting keys
const WIFI_SETTING_KEYS = {
  WIFI_ENABLED: 'wifi_enabled',          // 'true' or 'false'
  WIFI_LAST_SSID: 'wifi_last_ssid',      // Last connected SSID
} as const;
```

### 4. Error Handling

```typescript
class WiFiError extends Error {
  constructor(
    message: string,
    public code: WiFiErrorCode,
    public details?: string
  ) {
    super(message);
  }
}

enum WiFiErrorCode {
  SCAN_FAILED = 'SCAN_FAILED',
  CONNECTION_FAILED = 'CONNECTION_FAILED',
  INVALID_PASSWORD = 'INVALID_PASSWORD',
  NETWORK_NOT_FOUND = 'NETWORK_NOT_FOUND',
  ALREADY_CONNECTED = 'ALREADY_CONNECTED',
  WIFI_DISABLED = 'WIFI_DISABLED',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
}
```

## Frontend Implementation

### 1. WiFi Settings Section

Extend `/app/(main)/settings/page.tsx` to include WiFi configuration.

#### UI Components:

**A. WiFi Enable/Disable Toggle**
```tsx
<div className="flex items-center justify-between">
  <div>
    <h3>WiFi Radio</h3>
    <p>Enable or disable the WiFi adapter</p>
  </div>
  <Toggle
    enabled={wifiEnabled}
    onChange={handleToggleWiFi}
  />
</div>
```

**B. Current Status Card**
```tsx
<div className="status-card">
  {wifiStatus.connected ? (
    <>
      <Icon name="wifi" className="text-green-500" />
      <span>Connected to {wifiStatus.ssid}</span>
      <span>{wifiStatus.signalStrength}%</span>
      <span>{wifiStatus.ipAddress}</span>
    </>
  ) : (
    <>
      <Icon name="wifi-off" className="text-gray-400" />
      <span>Not connected</span>
    </>
  )}
</div>
```

**C. Network List**
```tsx
<div className="network-list">
  <button onClick={handleScan}>
    {scanning ? 'Scanning...' : 'Scan Networks'}
  </button>

  {networks.map(network => (
    <NetworkItem
      key={network.ssid}
      network={network}
      onConnect={() => handleConnect(network.ssid)}
      onForget={() => handleForget(network.ssid)}
    />
  ))}
</div>
```

**D. Network Item Component**
```tsx
<div className="network-item">
  <SignalStrengthIndicator strength={network.signalStrength} />
  <span className="ssid">{network.ssid}</span>
  <SecurityBadge type={network.security} />
  {network.inUse && <Badge>Connected</Badge>}
  {network.saved && <Icon name="bookmark" />}
  <button onClick={onConnect}>
    {network.inUse ? 'Disconnect' : 'Connect'}
  </button>
</div>
```

**E. Connection Form Dialog**
```tsx
<Dialog open={showConnectionForm}>
  <form onSubmit={handleSubmit}>
    <input
      type="text"
      value={selectedSSID}
      onChange={(e) => setSelectedSSID(e.target.value)}
      placeholder="Network name (SSID)"
    />

    {needsPassword && (
      <div className="password-field">
        <input
          type={showPassword ? 'text' : 'password'}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Password"
        />
        <button
          type="button"
          onClick={() => setShowPassword(!showPassword)}
        >
          {showPassword ? 'Hide' : 'Show'}
        </button>
      </div>
    )}

    <div className="actions">
      <button type="submit" disabled={connecting}>
        {connecting ? 'Connecting...' : 'Connect'}
      </button>
      <button type="button" onClick={handleCancel}>
        Cancel
      </button>
    </div>
  </form>
</Dialog>
```

### 2. Signal Strength Component

```tsx
function SignalStrengthIndicator({ strength }: { strength: number }) {
  const bars = Math.ceil(strength / 25); // 0-4 bars

  return (
    <div className="signal-bars">
      {[1, 2, 3, 4].map(bar => (
        <div
          key={bar}
          className={cn(
            'bar',
            bar <= bars ? 'active' : 'inactive'
          )}
        />
      ))}
    </div>
  );
}
```

### 3. Security Badge Component

```tsx
function SecurityBadge({ type }: { type: WiFiSecurityType }) {
  const badges = {
    OPEN: { icon: 'lock-open', color: 'text-yellow-600', label: 'Open' },
    WPA_PSK: { icon: 'lock', color: 'text-green-600', label: 'WPA2' },
    WPA3_PSK: { icon: 'shield', color: 'text-blue-600', label: 'WPA3' },
    // ... other types
  };

  const badge = badges[type] || { icon: 'lock', color: 'text-gray-600', label: type };

  return (
    <span className={cn('security-badge', badge.color)}>
      <Icon name={badge.icon} />
      {badge.label}
    </span>
  );
}
```

### 4. GraphQL Integration

```tsx
// queries
const WIFI_NETWORKS = gql`
  query WiFiNetworks($rescan: Boolean) {
    wifiNetworks(rescan: $rescan) {
      ssid
      signalStrength
      frequency
      security
      inUse
      saved
    }
  }
`;

const WIFI_STATUS = gql`
  query WiFiStatus {
    wifiStatus {
      enabled
      connected
      ssid
      signalStrength
      ipAddress
      macAddress
      frequency
    }
  }
`;

// mutations
const CONNECT_WIFI = gql`
  mutation ConnectWiFi($ssid: String!, $password: String) {
    connectWiFi(ssid: $ssid, password: $password) {
      success
      message
      connected
    }
  }
`;

const SET_WIFI_ENABLED = gql`
  mutation SetWiFiEnabled($enabled: Boolean!) {
    setWiFiEnabled(enabled: $enabled) {
      enabled
      connected
    }
  }
`;

// subscriptions
const WIFI_STATUS_UPDATED = gql`
  subscription WiFiStatusUpdated {
    wifiStatusUpdated {
      enabled
      connected
      ssid
      signalStrength
      ipAddress
    }
  }
`;
```

## Security Considerations

1. **Password Storage**: NetworkManager securely stores WiFi passwords in `/etc/NetworkManager/system-connections/` with proper permissions (root:root 600)
2. **GraphQL Security**: WiFi passwords are not returned in queries, only accepted in mutations
3. **Input Validation**: SSID and password validation on both frontend and backend
4. **Permission Requirements**: The Node.js process must have permission to run `nmcli` commands (typically requires sudoers configuration or running as root/network group)

## Permissions Setup

The backend service needs permission to manage WiFi. On Raspberry Pi, add to `/etc/sudoers.d/lacylights`:

```bash
# Allow lacylights user to manage WiFi without password
lacylights ALL=(ALL) NOPASSWD: /usr/bin/nmcli device wifi *
lacylights ALL=(ALL) NOPASSWD: /usr/bin/nmcli connection *
lacylights ALL=(ALL) NOPASSWD: /usr/bin/nmcli radio wifi *
```

Or add the `lacylights` user to the `netdev` group:
```bash
sudo usermod -a -G netdev lacylights
```

## Testing Strategy

### Unit Tests

**Backend:**
- Mock `child_process.exec()` to test nmcli command parsing
- Test error handling for various nmcli failures
- Test security type detection from scan results
- Test signal strength percentage calculation

**Frontend:**
- Test network list rendering
- Test signal strength indicator display
- Test form validation
- Test connection state management

### Integration Tests

- Test full WiFi scan → connect → disconnect flow
- Test reconnection to saved networks
- Test handling of invalid passwords
- Test network interface state changes

### Manual Testing Checklist

- [ ] Scan networks and verify list appears
- [ ] Connect to open network
- [ ] Connect to WPA2 network with password
- [ ] Connect to WPA3 network with password
- [ ] Verify signal strength indicators are accurate
- [ ] Test manual SSID entry
- [ ] Test "show/hide password" toggle
- [ ] Verify connection persists after reboot
- [ ] Test disconnecting from network
- [ ] Test forgetting saved network
- [ ] Test enabling/disabling WiFi radio
- [ ] Verify subscription updates work in real-time

## Deployment Notes

### Prerequisites

1. **NetworkManager**: Should be pre-installed on modern Raspberry Pi OS
   ```bash
   sudo apt-get install network-manager
   ```

2. **Permissions**: Configure sudoers or netdev group as described above

3. **wpa_supplicant**: Ensure it's not conflicting with NetworkManager
   ```bash
   sudo systemctl disable wpa_supplicant
   sudo systemctl enable NetworkManager
   ```

### Environment Variables

```bash
# Disable WiFi features if running on non-WiFi hardware
WIFI_ENABLED=true

# WiFi device name (default: wlan0)
WIFI_DEVICE=wlan0
```

## Future Enhancements

1. **Enterprise WiFi**: Support for WPA2/WPA3 Enterprise with certificates
2. **Hotspot Mode**: Create a WiFi access point for initial setup
3. **Network Profiles**: Save and switch between multiple network configurations
4. **Connection Priority**: Automatically connect to preferred networks
5. **VPN Support**: Configure VPN connections over WiFi
6. **Bandwidth Monitoring**: Show current upload/download speeds
7. **Hidden Networks**: Support connecting to hidden SSIDs
8. **Static IP**: Configure static IP addresses for WiFi connections

## References

- [Raspberry Pi Forum: NetworkManager Configuration](https://forums.raspberrypi.com/viewtopic.php?t=179387)
- [NetworkManager Documentation](https://networkmanager.dev/)
- [nmcli Examples](https://developer.gnome.org/NetworkManager/stable/nmcli-examples.html)
- [Raspberry Pi WiFi Configuration](https://www.raspberrypi.com/documentation/computers/configuration.html#wireless-connectivity)
