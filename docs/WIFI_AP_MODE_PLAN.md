# LacyLights WiFi Configuration & AP Mode Implementation Plan

> **To continue implementation:** Say "continue with docs/WIFI_AP_MODE_PLAN.md" in a new conversation. The assistant will check the progress below and resume from the next incomplete task.

---

## Implementation Progress

### Phase 1: Backend Core (lacylights-go)
- [ ] 1.1 Create `internal/services/wifi/` package structure
- [ ] 1.2 Implement `wifi.go` - main service with mode management
- [ ] 1.3 Implement `ap.go` - AP mode start/stop using nmcli
- [ ] 1.4 Implement SSID generation from MAC address
- [ ] 1.5 Add GraphQL schema extensions (WiFiMode enum, APConfig type, etc.)
- [ ] 1.6 Implement WiFi resolvers (replace stubs)
- [ ] 1.7 Wire WiFiService to Resolver struct
- [ ] 1.8 Update main.go to initialize WiFi service
- [ ] 1.9 Write unit tests for WiFi service
- [ ] 1.10 Run linter and tests, ensure passing

### Phase 2: Frontend UI (lacylights-fe)
- [ ] 2.1 Add new types to `src/types/index.ts` (WiFiMode, APConfig, APClient)
- [ ] 2.2 Add GraphQL queries/mutations to `src/graphql/wifi.ts`
- [ ] 2.3 Create `WiFiModeIndicator.tsx` component
- [ ] 2.4 Create `APModeInstructions.tsx` component
- [ ] 2.5 Create `APClientList.tsx` component
- [ ] 2.6 Update `WiFiSettings.tsx` for mode awareness
- [ ] 2.7 Add WiFi mode indicator to header/status bar
- [ ] 2.8 Write component tests
- [ ] 2.9 Run linter and tests, ensure passing

### Phase 3: RPi Integration (lacylights-rpi)
- [ ] 3.1 Create `scripts/wifi-mode-check.sh` boot script
- [ ] 3.2 Create `config/systemd/lacylights-wifi.service`
- [ ] 3.3 Create `scripts/gpio-button-monitor.sh`
- [ ] 3.4 Create `config/systemd/lacylights-gpio.service`
- [ ] 3.5 Create `config/nginx/sites-available/lacylights-captive`
- [ ] 3.6 Create `config/networkmanager/dnsmasq-shared.d/captive-portal.conf`
- [ ] 3.7 Update `setup/02-network-setup.sh` with AP mode setup
- [ ] 3.8 Test on real Raspberry Pi

### Phase 4: Integration & Testing
- [ ] 4.1 End-to-end test: First boot AP mode
- [ ] 4.2 End-to-end test: Configure WiFi from AP mode
- [ ] 4.3 End-to-end test: Fallback to AP on WiFi loss
- [ ] 4.4 End-to-end test: GPIO button recovery
- [ ] 4.5 End-to-end test: 30-minute timeout
- [ ] 4.6 Update documentation
- [ ] 4.7 Create PRs for all repos

---

## Overview

Enable LacyLights Raspberry Pi devices to be configured as standalone turnkey products with:
1. **AP Mode (Hotspot)**: Device creates "lacylights-XXXX" open hotspot when no WiFi is configured
2. **Client Mode**: Device connects to user's WiFi for internet access (updates, AI)
3. **Auto-Fallback**: Automatic switch to AP mode when configured WiFi is unavailable
4. **GPIO Recovery**: Physical button to force AP mode for recovery scenarios
5. **30-Minute Timeout**: AP auto-disables after inactivity, retries client mode

## User Scenarios

| Scenario | Flow |
|----------|------|
| First Boot (no network) | Pi boots → No known WiFi → Starts AP "lacylights-A1B2" → User connects → Configures WiFi → Pi connects to WiFi |
| Ethernet Setup | Pi on ethernet → User accesses lacylights.local → Configures WiFi from settings page |
| WiFi Lost | Connection drops → Retry 3x → Start AP mode → User reconfigures |
| Recovery Button | User holds GPIO button 5s → Force AP mode regardless of state |

## Network Mode State Machine

```
                        +----------------+
                        |   BOOT/INIT    |
                        +-------+--------+
                                |
                     Check for known networks
                                |
               +----------------+----------------+
               |                                 |
               v                                 v
    +----------+----------+           +----------+----------+
    |   CLIENT_CONNECTING |           |    NO_KNOWN_NETS    |
    |  (Trying to connect)|           |                     |
    +----------+----------+           +----------+----------+
               |                                 |
    +----------+----------+                      |
    | Success? |  Fail?   |                      |
    +-----+----+----+-----+                      |
          |         |                            |
          v         +-------------+--------------+
    +-----+------+                |
    | CLIENT_    |                v
    | CONNECTED  |        +-------+-------+
    +-----+------+        |    AP_MODE    |
          |               | (Hotspot on)  |
          |               +-------+-------+
     Connection                   |
       lost?               User configures
          |                   WiFi via UI
          |                       |
          +-----------+-----------+
                      |
                      v
            +--------+---------+
            | CLIENT_CONNECTING |
            +------------------+
```

---

## Phase 1: Backend WiFi Service Implementation

### 1.1 New WiFi Service (`lacylights-go/internal/services/wifi/`)

**Files to create:**
- `wifi.go` - Main service with mode management
- `ap.go` - Access Point mode operations
- `client.go` - Client mode operations
- `gpio.go` - GPIO button monitoring
- `wifi_test.go` - Unit tests

**Key Functions:**
```go
// Mode Management
func (s *Service) GetMode() WiFiMode
func (s *Service) StartAPMode() error
func (s *Service) StopAPMode() error
func (s *Service) TransitionToClient(ssid, password string) error

// AP Mode
func (s *Service) GenerateAPSSID() string  // "lacylights-" + last 4 of MAC
func (s *Service) GetAPClients() []APClient
func (s *Service) StartAPTimer() // 30-min timeout

// Monitoring
func (s *Service) MonitorLoop(ctx context.Context)  // Background mode monitor
func (s *Service) CheckAndTransition()              // Auto-fallback logic
```

**NetworkManager Commands:**
```bash
# Create AP connection (open, no password)
nmcli connection add type wifi ifname wlan0 con-name "LacyLights-AP" \
  autoconnect no ssid "lacylights-XXXX" mode ap \
  ipv4.method shared ipv4.addresses "192.168.4.1/24" \
  wifi.band bg wifi.channel 6

# Start AP
nmcli connection up "LacyLights-AP"

# Stop AP
nmcli connection down "LacyLights-AP"
```

### 1.2 GraphQL Schema Updates

**File:** `lacylights-go/internal/graphql/schema/schema.graphql`

```graphql
# New enum for WiFi mode
enum WiFiMode {
  CLIENT
  AP
  DISABLED
  CONNECTING
  STARTING_AP
}

# AP configuration type
type APConfig {
  ssid: String!
  ipAddress: String!
  channel: Int!
  clientCount: Int!
  timeoutMinutes: Int!
  minutesRemaining: Int
}

# Client connected to AP
type APClient {
  macAddress: String!
  ipAddress: String
  hostname: String
  connectedAt: String!
}

# Extend WiFiStatus
extend type WiFiStatus {
  mode: WiFiMode!
  apConfig: APConfig
  connectedClients: [APClient!]
}

# New queries
extend type Query {
  wifiMode: WiFiMode!
  apConfig: APConfig
  apClients: [APClient!]!
}

# New mutations
extend type Mutation {
  startAPMode: WiFiModeResult!
  stopAPMode(connectToSSID: String): WiFiModeResult!
  resetAPTimeout: Boolean!
}

# New subscription
extend type Subscription {
  wifiModeChanged: WiFiMode!
}
```

### 1.3 Resolver Implementation

**File:** `lacylights-go/internal/graphql/resolvers/schema.resolvers.go`

Implement WiFi resolvers that currently return stubs. Wire the new WiFi service to the Resolver struct in `resolver.go`.

---

## Phase 2: Frontend UI Updates

### 2.1 New Components

**`WiFiModeIndicator.tsx`** - Shows current mode prominently:
- Green WiFi icon: Connected to client network
- Amber hotspot icon: AP mode active with client count
- Spinning icon: Transitioning

**`APModeInstructions.tsx`** - Setup instructions when in AP mode:
```
1. Connect your device to WiFi: lacylights-XXXX
2. Open browser (you'll be redirected automatically)
3. Select your home WiFi network below
```

**`APClientList.tsx`** - List of devices connected to hotspot

**`APTimeoutWarning.tsx`** - Shows countdown when timeout approaching

### 2.2 Update WiFiSettings.tsx

**File:** `lacylights-fe/src/app/(main)/settings/WiFiSettings.tsx`

Add:
- Mode indicator at top of component
- AP instructions when mode === 'AP'
- Client list when in AP mode
- "Switch to Hotspot Mode" button when in client mode
- Timeout countdown display

### 2.3 GraphQL Queries

**File:** `lacylights-fe/src/graphql/wifi.ts`

Add queries for:
- `WIFI_MODE` - Get current mode
- `AP_CONFIG` - Get AP configuration
- `AP_CLIENTS` - Get connected clients
- `START_AP_MODE` - Mutation
- `STOP_AP_MODE` - Mutation
- `WIFI_MODE_CHANGED` - Subscription

### 2.4 Header Status Icon

**File:** `lacylights-fe/src/components/SystemStatusBar.tsx` (or Header)

Add WiFi mode indicator showing current state at a glance.

---

## Phase 3: RPi System Configuration

### 3.1 Boot Mode Check Script

**File:** `lacylights-rpi/scripts/wifi-mode-check.sh`

Runs at boot to determine initial WiFi mode:
1. Check for Ethernet → Stay in default mode
2. Scan for known networks → Try to connect
3. No connection after 30s → Start AP mode

### 3.2 Systemd Service

**File:** `lacylights-rpi/config/systemd/lacylights-wifi.service`

```ini
[Unit]
Description=LacyLights WiFi Mode Management
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/lacylights/scripts/wifi-mode-check.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### 3.3 GPIO Button Service

**File:** `lacylights-rpi/scripts/gpio-button-monitor.sh`

Monitor GPIO pin for button press:
- Hold 5 seconds → Force AP mode
- Uses `gpiod` or `wiringpi` for GPIO access
- Communicates with backend via HTTP or file signal

**File:** `lacylights-rpi/config/systemd/lacylights-gpio.service`

### 3.4 Captive Portal (nginx)

**File:** `lacylights-rpi/config/nginx/sites-available/lacylights-captive`

Redirect captive portal detection URLs to setup page:
```nginx
location ~ ^/(generate_204|hotspot-detect.html|success.txt) {
    return 302 http://192.168.4.1/settings;
}
```

Activated via symlink when AP mode starts.

### 3.5 DNS Redirect (dnsmasq)

**File:** `lacylights-rpi/config/networkmanager/dnsmasq-shared.d/captive-portal.conf`

```
# Redirect all DNS to Pi when in AP mode
address=/#/192.168.4.1
```

### 3.6 Setup Script Updates

**File:** `lacylights-rpi/setup/02-network-setup.sh`

Add:
- Install `gpiod` package for GPIO monitoring
- Create AP connection profile (disabled by default)
- Install captive portal nginx config
- Enable GPIO button service

---

## Phase 4: Implementation Order

### Week 1: Backend Core
1. Create `internal/services/wifi/` package structure
2. Implement AP mode start/stop using nmcli
3. Implement SSID generation from MAC address
4. Add GraphQL schema extensions
5. Implement resolvers
6. Unit tests for WiFi service

### Week 2: Frontend UI
1. Create WiFiModeIndicator component
2. Create APModeInstructions component
3. Update WiFiSettings.tsx for mode awareness
4. Add GraphQL queries/mutations
5. Add subscriptions for real-time updates
6. Component tests

### Week 3: RPi Integration
1. Create wifi-mode-check.sh boot script
2. Create GPIO button monitor script
3. Create systemd services
4. Configure captive portal (nginx + dnsmasq)
5. Update setup scripts
6. Integration testing on real Pi

### Week 4: Polish & Testing
1. End-to-end testing all scenarios
2. Timeout logic testing
3. Recovery scenarios
4. Documentation updates
5. Edge case handling

---

## Critical Files to Modify

| Repository | File | Changes |
|------------|------|---------|
| lacylights-go | `internal/graphql/schema/schema.graphql` | Add WiFiMode enum, APConfig type, new queries/mutations |
| lacylights-go | `internal/graphql/resolvers/schema.resolvers.go` | Implement WiFi resolvers (replace stubs) |
| lacylights-go | `internal/graphql/resolvers/resolver.go` | Add WiFiService to Resolver struct |
| lacylights-go | `cmd/server/main.go` | Initialize and wire WiFi service |
| lacylights-fe | `src/app/(main)/settings/WiFiSettings.tsx` | Add mode handling, AP instructions |
| lacylights-fe | `src/graphql/wifi.ts` | Add new queries/mutations/subscriptions |
| lacylights-fe | `src/types/index.ts` | Add WiFiMode, APConfig, APClient types |
| lacylights-rpi | `config/sudoers.d/lacylights` | Already has needed permissions |
| lacylights-rpi | `setup/02-network-setup.sh` | Add GPIO package, AP profile setup |

## New Files to Create

| Repository | File | Purpose |
|------------|------|---------|
| lacylights-go | `internal/services/wifi/wifi.go` | Main WiFi service |
| lacylights-go | `internal/services/wifi/ap.go` | AP mode operations |
| lacylights-go | `internal/services/wifi/wifi_test.go` | Unit tests |
| lacylights-fe | `src/components/WiFiModeIndicator.tsx` | Mode indicator UI |
| lacylights-fe | `src/components/APModeInstructions.tsx` | Setup instructions |
| lacylights-fe | `src/components/APClientList.tsx` | Connected clients display |
| lacylights-rpi | `scripts/wifi-mode-check.sh` | Boot mode detection |
| lacylights-rpi | `scripts/gpio-button-monitor.sh` | GPIO button handler |
| lacylights-rpi | `config/systemd/lacylights-wifi.service` | WiFi mode service |
| lacylights-rpi | `config/systemd/lacylights-gpio.service` | GPIO button service |
| lacylights-rpi | `config/nginx/sites-available/lacylights-captive` | Captive portal config |

---

## Configuration Summary

| Setting | Value |
|---------|-------|
| AP SSID Format | `lacylights-XXXX` (last 4 of MAC) |
| AP Password | None (open network) |
| AP IP Address | 192.168.4.1 |
| AP DHCP Range | 192.168.4.10 - 192.168.4.100 |
| AP Timeout | 30 minutes of inactivity |
| GPIO Button | Hold 5 seconds to force AP mode |
| Fallback Behavior | Auto-switch to AP after 3 failed reconnects |
| WiFi Channel | 6 (2.4GHz for compatibility) |

---

## Existing Infrastructure

The following already exists and will be leveraged:

### Frontend (lacylights-fe)
- `src/app/(main)/settings/WiFiSettings.tsx` - Complete client mode UI
- `src/components/WiFiNetworkItem.tsx` - Network list item component
- `src/components/WiFiConnectionDialog.tsx` - Password entry dialog
- `src/graphql/wifi.ts` - GraphQL queries/mutations for client mode

### Backend (lacylights-go)
- GraphQL schema has WiFiNetwork, WiFiStatus types
- Resolver stubs exist for wifiNetworks, wifiStatus, connectWiFi, etc.
- NetworkManager integration in network service

### RPi (lacylights-rpi)
- `config/sudoers.d/lacylights` - Already has nmcli permissions including `nmcli connection add`
- `setup/02-network-setup.sh` - Network setup patterns
- `config/networkmanager/dispatcher.d/99-route-priority` - Route management

---

## Testing Checklist

- [ ] Device creates hotspot when no known networks
- [ ] SSID format is "lacylights-XXXX"
- [ ] Can connect to hotspot from phone/laptop
- [ ] Captive portal redirects to settings page
- [ ] lacylights.local resolves in AP mode
- [ ] Network list shows available networks
- [ ] Can connect to new network from AP mode
- [ ] Smooth transition from AP to Client mode
- [ ] AP stops after successful client connection
- [ ] Graceful fallback to AP on connection loss
- [ ] 30-minute timeout works correctly
- [ ] GPIO button forces AP mode
- [ ] User can manually switch between modes
- [ ] Wrong password shows error, stays in AP mode

---

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| Open network exposure | 30-min timeout auto-disables |
| Malicious clients | Firewall rules limit to port 80/443 |
| Password sniffing | Only configure over local AP network |
| DNS hijacking | Only active in AP mode, documented |
| Command injection | Input validation for SSID/password |

---

## Related Documentation

- `docs/RASPBERRY_PI_PRODUCT_PLAN.md` - Overall product plan
- `lacylights-rpi/docs/WIFI_SETUP.md` - Current WiFi client setup docs
