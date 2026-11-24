# Embedded Claude Code Terminal - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an embedded Claude Code terminal and configurable backend server to the LacyLights Mac app, enabling AI-assisted lighting design from within the app.

**Architecture:** SwiftTerm provides a PTY-based terminal emulator in a split pane alongside the existing WKWebView. A new ServerConfiguration model allows pointing at local or remote backends. The Mac app auto-generates `.mcp.json` so Claude Code connects to the correct server.

**Tech Stack:** Swift/SwiftUI, SwiftTerm (SPM), Foundation.Process, UserDefaults

**Design doc:** `docs/plans/2026-03-04-embedded-claude-terminal-design.md`

---

### Task 1: Add SwiftTerm SPM Dependency

**Files:**
- Modify: `Package.swift`

**Step 1: Add SwiftTerm to Package.swift**

Edit `Package.swift` to add the SwiftTerm dependency and link it to the LacyLights target:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LacyLights",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LacyLights",
            targets: ["LacyLights"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "LacyLights",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "LacyLights",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LacyLightsTests",
            dependencies: ["LacyLights"],
            path: "Tests"
        )
    ]
)
```

**Step 2: Verify dependency resolves**

Run: `cd lacylights-mac && swift package resolve`
Expected: SwiftTerm downloads and resolves successfully.

**Step 3: Verify build still compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds with no errors.

**Step 4: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "feat: add SwiftTerm dependency for embedded terminal"
```

---

### Task 2: Create ServerConfiguration Model

**Files:**
- Create: `LacyLights/Models/ServerConfiguration.swift`
- Test: `Tests/ServerConfigurationTests.swift`

**Step 1: Write failing tests for ServerConfiguration**

Create `Tests/ServerConfigurationTests.swift`:

```swift
import XCTest
@testable import LacyLights

final class ServerConfigurationTests: XCTestCase {

    func testDefaultConfigurationIsLocal() {
        let config = ServerConfiguration()
        XCTAssertEqual(config.mode, .local)
        XCTAssertEqual(config.remoteHost, "")
        XCTAssertEqual(config.remotePort, 4000)
        XCTAssertFalse(config.useHTTPS)
    }

    func testGraphQLEndpointLocal() {
        var config = ServerConfiguration()
        config.mode = .local
        // Local mode uses provided port
        let endpoint = config.graphQLEndpoint(localPort: 5678)
        XCTAssertEqual(endpoint, "http://localhost:5678/graphql")
    }

    func testGraphQLEndpointRemote() {
        var config = ServerConfiguration()
        config.mode = .remote
        config.remoteHost = "lacylights.local"
        config.remotePort = 4000
        config.useHTTPS = false
        let endpoint = config.graphQLEndpoint(localPort: nil)
        XCTAssertEqual(endpoint, "http://lacylights.local:4000/graphql")
    }

    func testGraphQLEndpointRemoteHTTPS() {
        var config = ServerConfiguration()
        config.mode = .remote
        config.remoteHost = "lights.example.com"
        config.remotePort = 443
        config.useHTTPS = true
        let endpoint = config.graphQLEndpoint(localPort: nil)
        XCTAssertEqual(endpoint, "https://lights.example.com:443/graphql")
    }

    func testWebSocketEndpointLocal() {
        var config = ServerConfiguration()
        config.mode = .local
        let endpoint = config.webSocketEndpoint(localPort: 5678)
        XCTAssertEqual(endpoint, "ws://localhost:5678/graphql")
    }

    func testWebSocketEndpointRemoteHTTPS() {
        var config = ServerConfiguration()
        config.mode = .remote
        config.remoteHost = "lights.example.com"
        config.remotePort = 443
        config.useHTTPS = true
        let endpoint = config.webSocketEndpoint(localPort: nil)
        XCTAssertEqual(endpoint, "wss://lights.example.com:443/graphql")
    }

    func testBaseURLLocal() {
        var config = ServerConfiguration()
        config.mode = .local
        let url = config.baseURL(localPort: 9999)
        XCTAssertEqual(url, "http://localhost:9999")
    }

    func testBaseURLRemote() {
        var config = ServerConfiguration()
        config.mode = .remote
        config.remoteHost = "rpi.local"
        config.remotePort = 4000
        let url = config.baseURL(localPort: nil)
        XCTAssertEqual(url, "http://rpi.local:4000")
    }

    func testHealthEndpoint() {
        var config = ServerConfiguration()
        config.mode = .remote
        config.remoteHost = "rpi.local"
        config.remotePort = 4000
        let url = config.healthEndpoint(localPort: nil)
        XCTAssertEqual(url, "http://rpi.local:4000/health")
    }

    func testIsRemote() {
        var config = ServerConfiguration()
        config.mode = .local
        XCTAssertFalse(config.isRemote)
        config.mode = .remote
        XCTAssertTrue(config.isRemote)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd lacylights-mac && swift test --filter ServerConfigurationTests 2>&1 | tail -5`
Expected: Compilation failure — `ServerConfiguration` not found.

**Step 3: Implement ServerConfiguration model**

Create `LacyLights/Models/ServerConfiguration.swift`:

```swift
//
//  ServerConfiguration.swift
//  LacyLights
//
//  Model for configuring which backend server to connect to.
//

import Foundation

/// Backend server connection mode
enum ServerMode: String, CaseIterable, Identifiable {
    case local = "local"
    case remote = "remote"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Local (this Mac)"
        case .remote: return "Remote Server"
        }
    }
}

/// Configuration for the backend server connection
struct ServerConfiguration: Equatable {
    var mode: ServerMode = .local
    var remoteHost: String = ""
    var remotePort: Int = 4000
    var useHTTPS: Bool = false

    var isRemote: Bool {
        mode == .remote
    }

    /// The base URL for the backend server (no path)
    func baseURL(localPort: Int?) -> String {
        let scheme = useHTTPS ? "https" : "http"
        switch mode {
        case .local:
            let port = localPort ?? 4000
            return "\(scheme)://localhost:\(port)"
        case .remote:
            return "\(scheme)://\(remoteHost):\(remotePort)"
        }
    }

    /// The GraphQL endpoint URL
    func graphQLEndpoint(localPort: Int?) -> String {
        return "\(baseURL(localPort: localPort))/graphql"
    }

    /// The WebSocket endpoint URL for GraphQL subscriptions
    func webSocketEndpoint(localPort: Int?) -> String {
        let wsScheme = useHTTPS ? "wss" : "ws"
        switch mode {
        case .local:
            let port = localPort ?? 4000
            return "\(wsScheme)://localhost:\(port)/graphql"
        case .remote:
            return "\(wsScheme)://\(remoteHost):\(remotePort)/graphql"
        }
    }

    /// The health check endpoint URL
    func healthEndpoint(localPort: Int?) -> String {
        return "\(baseURL(localPort: localPort))/health"
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd lacylights-mac && swift test --filter ServerConfigurationTests 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add LacyLights/Models/ServerConfiguration.swift Tests/ServerConfigurationTests.swift
git commit -m "feat: add ServerConfiguration model for local/remote backend selection"
```

---

### Task 3: Add Server Configuration to UserPreferences

**Files:**
- Modify: `LacyLights/Utilities/UserPreferences.swift:17-23` (Keys enum)
- Modify: `LacyLights/Utilities/UserPreferences.swift` (add server config properties)
- Test: `Tests/ServerConfigurationTests.swift` (add persistence tests)

**Step 1: Write failing tests for server config persistence**

Add to `Tests/ServerConfigurationTests.swift`:

```swift
final class ServerConfigurationPersistenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear test keys
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "serverMode")
        defaults.removeObject(forKey: "remoteHost")
        defaults.removeObject(forKey: "remotePort")
        defaults.removeObject(forKey: "useHTTPS")
    }

    func testDefaultServerConfigIsLocal() async {
        let config = await UserPreferences.shared.serverConfiguration
        XCTAssertEqual(config.mode, .local)
    }

    func testSaveAndLoadServerConfig() async {
        var config = ServerConfiguration()
        config.mode = .remote
        config.remoteHost = "rpi.local"
        config.remotePort = 4001
        config.useHTTPS = false

        await UserPreferences.shared.setServerConfiguration(config)

        let loaded = await UserPreferences.shared.serverConfiguration
        XCTAssertEqual(loaded.mode, .remote)
        XCTAssertEqual(loaded.remoteHost, "rpi.local")
        XCTAssertEqual(loaded.remotePort, 4001)
        XCTAssertFalse(loaded.useHTTPS)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd lacylights-mac && swift test --filter ServerConfigurationPersistenceTests 2>&1 | tail -5`
Expected: Compilation failure — `serverConfiguration` property not found.

**Step 3: Add server config properties to UserPreferences**

In `LacyLights/Utilities/UserPreferences.swift`, add to the `Keys` enum (after line 22):

```swift
static let serverMode = "serverMode"
static let remoteHost = "remoteHost"
static let remotePort = "remotePort"
static let useHTTPS = "useHTTPS"
```

Add new properties after the `adminEmail` property (after line 99):

```swift
// MARK: - Server Configuration

/// Get the current server configuration
nonisolated var serverConfiguration: ServerConfiguration {
    get {
        var config = ServerConfiguration()
        if let modeString = defaults.string(forKey: Keys.serverMode),
           let mode = ServerMode(rawValue: modeString) {
            config.mode = mode
        }
        let host = defaults.string(forKey: Keys.remoteHost) ?? ""
        if !host.isEmpty {
            config.remoteHost = host
        }
        let port = defaults.integer(forKey: Keys.remotePort)
        if port > 0 {
            config.remotePort = port
        }
        config.useHTTPS = defaults.bool(forKey: Keys.useHTTPS)
        return config
    }
}

/// Save server configuration
func setServerConfiguration(_ config: ServerConfiguration) {
    defaults.set(config.mode.rawValue, forKey: Keys.serverMode)
    defaults.set(config.remoteHost, forKey: Keys.remoteHost)
    defaults.set(config.remotePort, forKey: Keys.remotePort)
    defaults.set(config.useHTTPS, forKey: Keys.useHTTPS)
    objectWillChange.send()
    ConsoleManager.shared.log(
        "Server configuration updated: \(config.mode == .local ? "Local" : "\(config.remoteHost):\(config.remotePort)")",
        level: .info, source: "Preferences"
    )
}
```

**Step 4: Run tests to verify they pass**

Run: `cd lacylights-mac && swift test --filter ServerConfiguration 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add LacyLights/Utilities/UserPreferences.swift Tests/ServerConfigurationTests.swift
git commit -m "feat: add server configuration persistence to UserPreferences"
```

---

### Task 4: Create ClaudeWorkspaceManager

**Files:**
- Create: `LacyLights/Managers/ClaudeWorkspaceManager.swift`
- Test: `Tests/ClaudeWorkspaceManagerTests.swift`

**Step 1: Write failing tests**

Create `Tests/ClaudeWorkspaceManagerTests.swift`:

```swift
import XCTest
@testable import LacyLights

final class ClaudeWorkspaceManagerTests: XCTestCase {

    func testGenerateMCPConfigJSON() {
        let mcpPath = "/Users/test/Library/Application Support/LacyLights/repos/lacylights-mcp"
        let nodePath = "/opt/homebrew/bin/node"
        let graphqlEndpoint = "http://localhost:5678/graphql"

        let json = ClaudeWorkspaceManager.generateMCPConfigJSON(
            mcpPath: mcpPath,
            nodePath: nodePath,
            graphqlEndpoint: graphqlEndpoint
        )

        // Parse and verify JSON structure
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let lacylights = servers["lacylights"] as? [String: Any] else {
            XCTFail("Invalid JSON structure")
            return
        }

        XCTAssertEqual(lacylights["command"] as? String, nodePath)

        let args = lacylights["args"] as? [String]
        XCTAssertEqual(args?.first, "\(mcpPath)/run-mcp.js")

        let env = lacylights["env"] as? [String: String]
        XCTAssertEqual(env?["LACYLIGHTS_GRAPHQL_ENDPOINT"], graphqlEndpoint)
    }

    func testGenerateMCPConfigRemoteServer() {
        let mcpPath = "/path/to/mcp"
        let nodePath = "/usr/local/bin/node"
        let graphqlEndpoint = "http://rpi.local:4000/graphql"

        let json = ClaudeWorkspaceManager.generateMCPConfigJSON(
            mcpPath: mcpPath,
            nodePath: nodePath,
            graphqlEndpoint: graphqlEndpoint
        )

        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let lacylights = servers["lacylights"] as? [String: Any],
              let env = lacylights["env"] as? [String: String] else {
            XCTFail("Invalid JSON structure")
            return
        }

        XCTAssertEqual(env["LACYLIGHTS_GRAPHQL_ENDPOINT"], "http://rpi.local:4000/graphql")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd lacylights-mac && swift test --filter ClaudeWorkspaceManagerTests 2>&1 | tail -5`
Expected: Compilation failure — `ClaudeWorkspaceManager` not found.

**Step 3: Implement ClaudeWorkspaceManager**

Create `LacyLights/Managers/ClaudeWorkspaceManager.swift`:

```swift
//
//  ClaudeWorkspaceManager.swift
//  LacyLights
//
//  Manages the Claude Code workspace directory and MCP configuration.
//

import Foundation

/// Manages Claude Code workspace and MCP configuration
class ClaudeWorkspaceManager {
    static let shared = ClaudeWorkspaceManager()

    /// Path to the Claude Code workspace directory
    var workspacePath: URL {
        let url = PathConfiguration.shared.appSupport.appendingPathComponent("claude-workspace")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Path to the .mcp.json config file
    var mcpConfigPath: URL {
        workspacePath.appendingPathComponent(".mcp.json")
    }

    private init() {}

    /// Generate the .mcp.json content as a JSON string
    static func generateMCPConfigJSON(
        mcpPath: String,
        nodePath: String,
        graphqlEndpoint: String
    ) -> String {
        let config: [String: Any] = [
            "mcpServers": [
                "lacylights": [
                    "command": nodePath,
                    "args": ["\(mcpPath)/run-mcp.js"],
                    "env": [
                        "LACYLIGHTS_GRAPHQL_ENDPOINT": graphqlEndpoint
                    ]
                ]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }

    /// Write the .mcp.json config file for Claude Code
    func writeMCPConfig(graphqlEndpoint: String) throws {
        let mcpPath = PathConfiguration.shared.mcpDir.path
        let nodePath = findNodePath() ?? "/opt/homebrew/bin/node"

        let json = Self.generateMCPConfigJSON(
            mcpPath: mcpPath,
            nodePath: nodePath,
            graphqlEndpoint: graphqlEndpoint
        )

        try json.write(to: mcpConfigPath, atomically: true, encoding: .utf8)

        Task { @MainActor in
            ConsoleManager.shared.log(
                "MCP config written to \(mcpConfigPath.path)",
                level: .info, source: "Claude"
            )
        }
    }

    /// Update MCP config based on current server configuration and backend port
    func updateMCPConfig() {
        let serverConfig = UserPreferences.shared.serverConfiguration
        let backendPort = ProcessManager.shared.getPort(for: .backend)
        let graphqlEndpoint = serverConfig.graphQLEndpoint(localPort: backendPort)

        do {
            try writeMCPConfig(graphqlEndpoint: graphqlEndpoint)
        } catch {
            Task { @MainActor in
                ConsoleManager.shared.log(
                    "Failed to write MCP config: \(error.localizedDescription)",
                    level: .error, source: "Claude"
                )
            }
        }
    }

    /// Check if Claude Code CLI is available
    func isClaudeCodeInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.environment = PathConfiguration.shared.environmentVariables()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Find the node binary path
    private func findNodePath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["node"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.environment = PathConfiguration.shared.environmentVariables()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}

        return nil
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd lacylights-mac && swift test --filter ClaudeWorkspaceManagerTests 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add LacyLights/Managers/ClaudeWorkspaceManager.swift Tests/ClaudeWorkspaceManagerTests.swift
git commit -m "feat: add ClaudeWorkspaceManager for MCP config generation"
```

---

### Task 5: Create ClaudeTerminalView

**Files:**
- Create: `LacyLights/Views/ClaudeTerminalView.swift`

This task creates the SwiftTerm-based terminal view that runs Claude Code. This is primarily UI code and is tested manually.

**Step 1: Create ClaudeTerminalView**

Create `LacyLights/Views/ClaudeTerminalView.swift`:

```swift
//
//  ClaudeTerminalView.swift
//  LacyLights
//
//  Embedded terminal emulator for running Claude Code using SwiftTerm.
//

import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI wrapper for the SwiftTerm terminal view
struct ClaudeTerminalView: NSViewRepresentable {
    @Binding var isTerminalRunning: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.processDelegate = context.coordinator

        // Configure terminal appearance
        let fontSize: CGFloat = 13
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)

        // Get the user's default shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Set up environment for Claude Code workspace
        let workspacePath = ClaudeWorkspaceManager.shared.workspacePath.path
        var env = PathConfiguration.shared.environmentVariables()
        env["TERM"] = "xterm-256color"

        // Start the shell process in the Claude workspace directory
        terminalView.startProcess(
            executable: shell,
            args: [shell, "-l"],
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: shell,
            initialDirectory: workspacePath
        )

        context.coordinator.terminalView = terminalView

        DispatchQueue.main.async {
            isTerminalRunning = true
        }

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No dynamic updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isTerminalRunning: $isTerminalRunning)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminalView: LocalProcessTerminalView?
        var isTerminalRunning: Binding<Bool>

        init(isTerminalRunning: Binding<Bool>) {
            self.isTerminalRunning = isTerminalRunning
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized — SwiftTerm handles SIGWINCH automatically
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Could update window title if desired
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Track directory changes if needed
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async {
                self.isTerminalRunning.wrappedValue = false
            }
        }
    }
}
```

**Step 2: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds. (If there are SwiftTerm API differences, adjust delegate methods to match the actual API.)

**Step 3: Commit**

```bash
git add LacyLights/Views/ClaudeTerminalView.swift
git commit -m "feat: add ClaudeTerminalView with SwiftTerm PTY integration"
```

---

### Task 6: Add Split Pane to LacyLights Tab

**Files:**
- Modify: `LacyLights/Views/ContentView.swift:750-975` (LacyLightsWebView)
- Modify: `LacyLights/App/LacyLightsApp.swift:134-139` (AppState)

**Step 1: Add terminal visibility state to AppState**

In `LacyLights/App/LacyLightsApp.swift`, add to `AppState` (after line 139):

```swift
@Published var showClaudeTerminal = false
```

**Step 2: Modify LacyLightsWebView to include split pane**

Replace the `LacyLightsWebView` struct body in `ContentView.swift` (lines 757-975) to wrap the existing content in a split pane layout. The key changes:

1. Add an `@EnvironmentObject var appState: AppState` property
2. Add a `@State private var isTerminalRunning = false` property
3. Wrap the view body in an `HSplitView` when `appState.showClaudeTerminal` is true
4. Add a toolbar button to toggle the terminal

Replace the `LacyLightsWebView` struct (starting at line 751):

```swift
/// LacyLights WebView - Embedded frontend web interface with optional Claude terminal
struct LacyLightsWebView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var webViewState = WebViewState()
    @ObservedObject var processManager = ProcessManager.shared
    @ObservedObject var startupCoordinator = StartupCoordinator.shared
    @State private var isFrontendHealthy = false
    @State private var isTerminalRunning = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Text("LacyLights Web Interface")
                    .font(.headline)

                Spacer()

                // Claude terminal toggle button
                Button(action: {
                    appState.showClaudeTerminal.toggle()
                }) {
                    Label(
                        appState.showClaudeTerminal ? "Hide Claude" : "Show Claude",
                        systemImage: appState.showClaudeTerminal ? "terminal.fill" : "terminal"
                    )
                }
                .help("Toggle Claude Code terminal")

                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Reload button
                Button(action: {
                    webViewState.updatePortFromProcessManager()
                    webViewState.reload()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload web interface")
                .disabled(!isFrontendHealthy)

                // Open in browser button
                Button(action: {
                    if let port = processManager.getPort(for: .frontend),
                       let url = URL(string: "http://localhost:\(port)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "safari")
                }
                .help("Open in default browser")
                .disabled(!isFrontendHealthy)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main content area — split pane or full width
            if appState.showClaudeTerminal {
                HSplitView {
                    webContent
                        .frame(minWidth: 400)

                    terminalPane
                        .frame(minWidth: 300)
                }
            } else {
                webContent
            }
        }
        .task {
            await monitorFrontendHealth()
        }
    }

    /// The web content (existing WKWebView or placeholder)
    @ViewBuilder
    private var webContent: some View {
        if isFrontendHealthy {
            WebViewContainer(
                url: webViewState.url,
                isLoading: $webViewState.isLoading,
                hasError: $webViewState.hasError
            )
            .onAppear {
                webViewState.updatePortFromProcessManager()
            }
        } else if startupCoordinator.isStarting {
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(.circular)

                Text("Starting Services...")
                    .font(.title2)
                    .fontWeight(.semibold)

                if !startupCoordinator.currentStep.isEmpty {
                    Text(startupCoordinator.currentStep)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if startupCoordinator.startupProgress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: startupCoordinator.startupProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 300)

                        Text("\(Int(startupCoordinator.startupProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("This may take 30-60 seconds for first startup")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "network.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("Frontend Not Running")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Start the frontend service to use the web interface")
                    .foregroundColor(.secondary)

                Button("Start Services") {
                    Task {
                        do {
                            try await StartupCoordinator.shared.startServices(includeMCP: false)
                            await waitForFrontendHealth()
                            webViewState.updatePortFromProcessManager()
                        } catch {
                            ConsoleManager.shared.log("Failed to start services: \(error)", level: .error, source: "WebView")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(startupCoordinator.isStarting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The Claude Code terminal pane
    @ViewBuilder
    private var terminalPane: some View {
        VStack(spacing: 0) {
            // Terminal header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.blue)
                Text("Claude Code")
                    .font(.headline)

                Spacer()

                if !isTerminalRunning {
                    Text("Exited")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if !ClaudeWorkspaceManager.shared.isClaudeCodeInstalled() {
                // Claude Code not installed
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)

                    Text("Claude Code Not Found")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Install Claude Code to use the AI chat terminal.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("npm install -g @anthropic-ai/claude-code")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)

                    Button("Learn More") {
                        if let url = URL(string: "https://docs.anthropic.com/en/docs/claude-code") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Terminal emulator
                ClaudeTerminalView(isTerminalRunning: $isTerminalRunning)
            }
        }
    }

    // Keep all existing private methods unchanged:
    // waitForFrontendHealth(), monitorFrontendHealth(), statusColor, statusText

    private func waitForFrontendHealth() async {
        guard let port = ProcessManager.shared.getPort(for: .frontend) else { return }

        let healthy = await ServiceHealthCheck.waitForHealth(
            check: { await ServiceHealthCheck.checkFrontendHealth(port: port) },
            timeout: 60.0,
            interval: 1.0
        )

        await MainActor.run {
            isFrontendHealthy = healthy
            if !healthy {
                ConsoleManager.shared.log("Frontend health check timed out", level: .warning, source: "WebView")
            }
        }
    }

    private func monitorFrontendHealth() async {
        while !Task.isCancelled {
            let isRunning = await MainActor.run {
                processManager.isRunning(.frontend)
            }

            if isRunning {
                let port = await MainActor.run {
                    ProcessManager.shared.getPort(for: .frontend)
                }

                if let port = port {
                    let healthy = await ServiceHealthCheck.checkFrontendHealth(port: port)
                    await MainActor.run { isFrontendHealthy = healthy }
                } else {
                    await MainActor.run { isFrontendHealthy = false }
                }
            } else {
                await MainActor.run { isFrontendHealthy = false }
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private var statusColor: Color {
        if startupCoordinator.isStarting {
            return .orange
        } else if !isFrontendHealthy {
            return .gray
        } else if webViewState.hasError {
            return .red
        } else if webViewState.isLoading {
            return .orange
        } else {
            return .green
        }
    }

    private var statusText: String {
        if startupCoordinator.isStarting {
            return "Starting Services..."
        } else if !isFrontendHealthy {
            return "Service Stopped"
        } else if webViewState.hasError {
            return "Error Loading"
        } else if webViewState.isLoading {
            return "Loading..."
        } else {
            let port = processManager.getPort(for: .frontend) ?? 3000
            return "Connected (:\(port))"
        }
    }
}
```

**Step 3: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -10`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add LacyLights/Views/ContentView.swift LacyLights/App/LacyLightsApp.swift
git commit -m "feat: add split pane with Claude Code terminal on LacyLights tab"
```

---

### Task 7: Create Server Configuration View

**Files:**
- Create: `LacyLights/Views/ServerConfigurationView.swift`

**Step 1: Create ServerConfigurationView**

Create `LacyLights/Views/ServerConfigurationView.swift`:

```swift
//
//  ServerConfigurationView.swift
//  LacyLights
//
//  UI for configuring the backend server connection.
//

import SwiftUI

/// Server configuration section for Settings view
struct ServerConfigurationSection: View {
    @ObservedObject var preferences = UserPreferences.shared
    @State private var serverConfig: ServerConfiguration
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @Binding var showRestartAlert: Bool

    init(showRestartAlert: Binding<Bool>) {
        _showRestartAlert = showRestartAlert
        _serverConfig = State(initialValue: UserPreferences.shared.serverConfiguration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server Connection")
                .font(.headline)

            // Mode picker
            Picker("Mode", selection: $serverConfig.mode) {
                ForEach(ServerMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            if serverConfig.mode == .remote {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("lacylights.local", text: $serverConfig.remoteHost)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("4000", value: $serverConfig.remotePort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }

                    Toggle("Use HTTPS", isOn: $serverConfig.useHTTPS)
                        .toggleStyle(.switch)

                    // Endpoint preview
                    Text("Endpoint: \(serverConfig.graphQLEndpoint(localPort: nil))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Test connection button
                    HStack {
                        Button(action: testConnection) {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                        }
                        .disabled(serverConfig.remoteHost.isEmpty || isTestingConnection)

                        if let result = connectionTestResult {
                            HStack(spacing: 4) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? .green : .red)
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundColor(result.success ? .green : .red)
                            }
                        }
                    }
                }
            } else {
                Text("The backend server runs on this Mac, managed by the LacyLights app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Apply button
            HStack {
                Spacer()
                Button("Apply") {
                    applyConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverConfig == preferences.serverConfiguration)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func applyConfiguration() {
        preferences.setServerConfiguration(serverConfig)
        ClaudeWorkspaceManager.shared.updateMCPConfig()
        showRestartAlert = true
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        let healthURL = serverConfig.healthEndpoint(localPort: nil)

        Task {
            do {
                guard let url = URL(string: healthURL) else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 5

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    await MainActor.run {
                        connectionTestResult = ConnectionTestResult(success: true, message: "Connected")
                        isTestingConnection = false
                    }
                } else {
                    await MainActor.run {
                        connectionTestResult = ConnectionTestResult(success: false, message: "Unexpected response")
                        isTestingConnection = false
                    }
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = ConnectionTestResult(success: false, message: error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}
```

**Step 2: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add LacyLights/Views/ServerConfigurationView.swift
git commit -m "feat: add ServerConfigurationSection view for backend server settings"
```

---

### Task 8: Integrate Server Configuration into Settings and Setup

**Files:**
- Modify: `LacyLights/Views/ContentView.swift:340-465` (SettingsView)
- Modify: `LacyLights/Views/SetupView.swift:68-116` (setupForm)

**Step 1: Add ServerConfigurationSection to SettingsView**

In `ContentView.swift`, in the `SettingsView` struct body, add the `ServerConfigurationSection` after the "Backend Server" section (after line 378, before the Authentication Settings section):

```swift
// Server Connection
ServerConfigurationSection(showRestartAlert: $showRestartAlert)
```

**Step 2: Add server selection to SetupView**

In `SetupView.swift`, add a server mode picker to `setupForm` (after the "Backend Server" section, around line 93). Add a `@State` property at the top of `SetupView`:

```swift
@State private var serverMode: ServerMode = .local
@State private var remoteHost = ""
@State private var remotePort = 4000
```

Add to `setupForm` (after line 93, before the GitHub org field):

```swift
// Server Connection
VStack(alignment: .leading, spacing: 8) {
    Text("Server Connection")
        .font(.subheadline)
        .fontWeight(.medium)

    Picker("", selection: $serverMode) {
        ForEach(ServerMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
        }
    }
    .pickerStyle(.radioGroup)

    if serverMode == .remote {
        HStack(spacing: 12) {
            TextField("Host (e.g., lacylights.local)", text: $remoteHost)
                .textFieldStyle(.roundedBorder)

            TextField("Port", value: $remotePort, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}
```

In the `runSetup()` method, save server configuration before running setup (add before the `Task` block, around line 277):

```swift
// Save server configuration
var serverConfig = ServerConfiguration()
serverConfig.mode = serverMode
serverConfig.remoteHost = remoteHost
serverConfig.remotePort = remotePort
UserPreferences.shared.setServerConfiguration(serverConfig)
```

**Step 3: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add LacyLights/Views/ContentView.swift LacyLights/Views/SetupView.swift
git commit -m "feat: integrate server configuration into Settings and Setup views"
```

---

### Task 9: Wire Up MCP Config Generation on Startup

**Files:**
- Modify: `LacyLights/Managers/StartupCoordinator.swift:91-99` (after startup complete)
- Modify: `LacyLights/Views/ContentView.swift` (LacyLightsWebView — use server config for frontend URL)
- Modify: `LacyLights/Views/WebViewContainer.swift:59-107` (WebViewState — use server config)

**Step 1: Trigger MCP config generation after backend starts**

In `StartupCoordinator.swift`, after the "All services started successfully" log message (line 98), add:

```swift
// Generate Claude Code MCP config with the current backend endpoint
ClaudeWorkspaceManager.shared.updateMCPConfig()
```

**Step 2: Update StartupCoordinator to respect server configuration**

In `StartupCoordinator.swift`, modify `startServices` to check if we're in remote mode. If so, skip backend startup. At the beginning of `startServices` (after line 51), add a check:

```swift
let serverConfig = UserPreferences.shared.serverConfiguration
```

Then wrap the backend-related steps (Steps 1-5) in a condition:

```swift
if !serverConfig.isRemote {
    // Steps 1-5: only needed for local backend
    // ... existing code for checkRequirements, ensureDependencies, allocatePorts, etc.
} else {
    // Remote mode: generate MCP config immediately with remote server details
    ClaudeWorkspaceManager.shared.updateMCPConfig()
}
```

The frontend startup (Step 6) should use the server configuration to set `GRAPHQL_URL`:

In `startFrontend` (line 396-400), replace the hardcoded localhost URLs:

```swift
let serverConfig = UserPreferences.shared.serverConfiguration
let backendPort_: Int? = serverConfig.isRemote ? nil : backendPort
let customEnv = [
    "PORT": String(port),
    "GRAPHQL_URL": serverConfig.graphQLEndpoint(localPort: backendPort_),
    "GRAPHQL_WS_URL": serverConfig.webSocketEndpoint(localPort: backendPort_)
]
```

**Step 3: Update WebViewState to use server config for frontend URL**

In `WebViewContainer.swift`, update `WebViewState.init()` and `updatePortFromProcessManager()` to handle the case where the frontend might point to a remote server. For now, the frontend always runs locally (even when the backend is remote), so the existing localhost logic is correct. No change needed here — the frontend is always local.

**Step 4: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 5: Run all tests**

Run: `cd lacylights-mac && swift test 2>&1 | tail -10`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add LacyLights/Managers/StartupCoordinator.swift LacyLights/Views/ContentView.swift
git commit -m "feat: wire up MCP config generation and server config into startup flow"
```

---

### Task 10: Add PathConfiguration claudeWorkspace Path

**Files:**
- Modify: `LacyLights/Utilities/PathConfiguration.swift`

**Step 1: Add claudeWorkspace path**

In `PathConfiguration.swift`, add a new computed property after `mcpDir` (after line 85):

```swift
/// Claude Code workspace: ~/Library/Application Support/LacyLights/claude-workspace/
var claudeWorkspace: URL {
    let url = appSupport.appendingPathComponent("claude-workspace")
    createDirectoryIfNeeded(url)
    return url
}
```

**Step 2: Update pathSummary to include Claude workspace**

In the `pathSummary()` method (around line 240), add after the MCP Server line:

```swift
- Claude Workspace: \(claudeWorkspace.path)
```

**Step 3: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add LacyLights/Utilities/PathConfiguration.swift
git commit -m "feat: add claudeWorkspace path to PathConfiguration"
```

---

### Task 11: Add Keyboard Shortcut for Terminal Toggle

**Files:**
- Modify: `LacyLights/App/LacyLightsApp.swift:24-37` (commands section)

**Step 1: Add keyboard shortcut command**

In `LacyLightsApp.swift`, add a new command group inside the `commands` block (after line 36):

```swift
CommandGroup(after: .sidebar) {
    Button("Toggle Claude Terminal") {
        appState.showClaudeTerminal.toggle()
    }
    .keyboardShortcut("t", modifiers: [.command, .shift])
}
```

Note: `appState` needs to be accessible here. Since `appState` is a `@StateObject` inside `LacyLightsApp`, you may need to make the toggle action available via a notification or shared state. If `appState` is not directly accessible in the `commands` block, use `NotificationCenter`:

In `AppState`, add a static method:

```swift
static func toggleClaudeTerminal() {
    NotificationCenter.default.post(name: .toggleClaudeTerminal, object: nil)
}
```

Add notification name extension:

```swift
extension Notification.Name {
    static let toggleClaudeTerminal = Notification.Name("toggleClaudeTerminal")
}
```

And listen for it in `LacyLightsWebView` with `.onReceive`.

The exact approach depends on how SwiftUI command groups interact with `@StateObject`. Test and adjust as needed.

**Step 2: Verify build compiles**

Run: `cd lacylights-mac && swift build 2>&1 | tail -5`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add LacyLights/App/LacyLightsApp.swift
git commit -m "feat: add Cmd+Shift+T keyboard shortcut for Claude terminal toggle"
```

---

### Task 12: Final Integration Testing and Cleanup

**Files:**
- All modified files
- Modify: `LacyLights/Utilities/Version.swift` (bump version)

**Step 1: Run full test suite**

Run: `cd lacylights-mac && swift test 2>&1`
Expected: All tests pass.

**Step 2: Run build**

Run: `cd lacylights-mac && swift build -c release 2>&1 | tail -5`
Expected: Release build succeeds.

**Step 3: Manual testing checklist**

Run the app and verify:
- [ ] App launches successfully
- [ ] Settings view shows "Server Connection" section
- [ ] Server mode defaults to "Local (this Mac)"
- [ ] Switching to "Remote Server" shows host/port fields
- [ ] "Test Connection" button works for a running remote server
- [ ] "Apply" saves configuration and shows restart alert
- [ ] LacyLights tab shows "Show Claude" button in header
- [ ] Clicking "Show Claude" opens split pane with terminal
- [ ] Terminal starts user's shell in the claude-workspace directory
- [ ] `.mcp.json` is generated in `~/Library/Application Support/LacyLights/claude-workspace/`
- [ ] `.mcp.json` contains correct GraphQL endpoint
- [ ] Typing `claude` in terminal launches Claude Code
- [ ] Claude Code picks up lacylights MCP tools
- [ ] Cmd+Shift+T toggles terminal visibility
- [ ] Terminal pane is resizable
- [ ] Closing terminal pane returns to full-width web view
- [ ] Setup wizard shows server selection on Step 1
- [ ] App quit cleanly shuts down terminal process

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "fix: integration testing cleanup"
```

---

## Task Summary

| Task | Description | New Files | Modified Files |
|------|-------------|-----------|----------------|
| 1 | Add SwiftTerm dependency | — | Package.swift |
| 2 | Create ServerConfiguration model | ServerConfiguration.swift, ServerConfigurationTests.swift | — |
| 3 | Add server config to UserPreferences | — | UserPreferences.swift, ServerConfigurationTests.swift |
| 4 | Create ClaudeWorkspaceManager | ClaudeWorkspaceManager.swift, ClaudeWorkspaceManagerTests.swift | — |
| 5 | Create ClaudeTerminalView | ClaudeTerminalView.swift | — |
| 6 | Add split pane to LacyLights tab | — | ContentView.swift, LacyLightsApp.swift |
| 7 | Create ServerConfigurationView | ServerConfigurationView.swift | — |
| 8 | Integrate server config into Settings/Setup | — | ContentView.swift, SetupView.swift |
| 9 | Wire MCP config into startup flow | — | StartupCoordinator.swift |
| 10 | Add claudeWorkspace path | — | PathConfiguration.swift |
| 11 | Add keyboard shortcut | — | LacyLightsApp.swift |
| 12 | Final integration testing | — | All |

## Dependencies Between Tasks

```
Task 1 (SwiftTerm dep)
    └── Task 5 (ClaudeTerminalView) ── depends on SwiftTerm
        └── Task 6 (Split pane) ── depends on ClaudeTerminalView

Task 2 (ServerConfiguration model)
    ├── Task 3 (UserPreferences) ── depends on model
    │   ├── Task 7 (ServerConfigurationView) ── depends on persistence
    │   │   └── Task 8 (Settings/Setup integration)
    │   └── Task 9 (Startup wiring) ── depends on persistence
    └── Task 4 (ClaudeWorkspaceManager) ── depends on model
        └── Task 9 (Startup wiring) ── depends on workspace manager

Task 10 (PathConfiguration) ── independent, do anytime
Task 11 (Keyboard shortcut) ── depends on Task 6
Task 12 (Integration testing) ── depends on all
```

**Parallelizable groups:**
- Tasks 1 + 2 can run in parallel (no dependencies)
- Tasks 3 + 4 + 5 can run in parallel (each depends on different prior tasks)
- Tasks 7 + 10 can run in parallel
