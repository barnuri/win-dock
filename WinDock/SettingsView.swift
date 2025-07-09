import SwiftUI

struct SettingsView: View {
    @State private var dockPosition: DockPosition = {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.dockPosition
        }
        return .bottom
    }()
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("combineTaskbarButtons") private var combineTaskbarButtons = true
    @AppStorage("useSmallTaskbarButtons") private var useSmallTaskbarButtons = false
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 0.8
    @AppStorage("showLabels") private var showLabels = false
    @AppStorage("animationSpeed") private var animationSpeed = 1.0
    @AppStorage("use24HourClock") private var use24HourClock = true
    
    @StateObject private var dockManager = MacOSDockManager()
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                dockPosition: $dockPosition,
                onDockPositionChange: { newPosition in
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.updateDockPosition(newPosition)
                    }
                },
                dockSize: $dockSize,
                autoHide: $autoHide,
                showOnAllSpaces: $showOnAllSpaces,
                centerTaskbarIcons: $centerTaskbarIcons,
                showSystemTray: $showSystemTray,
                showTaskView: $showTaskView,
                dockManager: dockManager
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            AppearanceSettingsView(
                combineTaskbarButtons: $combineTaskbarButtons,
                useSmallTaskbarButtons: $useSmallTaskbarButtons,
                taskbarTransparency: $taskbarTransparency,
                showLabels: $showLabels,
                animationSpeed: $animationSpeed
            )
            .tabItem {
                Label("Appearance", systemImage: "paintbrush")
            }

            AppsSettingsView()
                .tabItem {
                    Label("Apps", systemImage: "app.badge")
                }

            LogsSettingsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 600)
        .frame(maxWidth: .infinity) // Allow settings window to stretch if needed
    }
}

struct GeneralSettingsView: View {
    @Binding var dockPosition: DockPosition
    var onDockPositionChange: ((DockPosition) -> Void)? = nil
    @Binding var dockSize: DockSize
    @Binding var autoHide: Bool
    @Binding var showOnAllSpaces: Bool
    @Binding var centerTaskbarIcons: Bool
    @Binding var showSystemTray: Bool
    @Binding var showTaskView: Bool
    @ObservedObject var dockManager: MacOSDockManager
    
    @AppStorage("searchAppChoice") private var searchAppChoice: SearchAppChoice = .spotlight
    @AppStorage("use24HourClock") private var use24HourClock = true

    var body: some View {
        Form {
            Section("Taskbar Position") {
                Picker("Position:", selection: $dockPosition) {
                    Text("Bottom").tag(DockPosition.bottom)
                    Text("Top").tag(DockPosition.top)
                    Text("Left").tag(DockPosition.left)
                    Text("Right").tag(DockPosition.right)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .onChange(of: dockPosition) { oldValue, newValue in
                    onDockPositionChange?(newValue)
                }
            }
            
            Section("Icon Size") {
                Picker("Icon Size:", selection: $dockSize) {
                    Text("Small").tag(DockSize.small)
                    Text("Medium").tag(DockSize.medium)
                    Text("Large").tag(DockSize.large)
                }
                .pickerStyle(SegmentedPickerStyle())
                Text("Controls the size of the icons in the dock, not the dock height.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Taskbar Behavior") {
                Toggle("Automatically hide the taskbar", isOn: $autoHide)
                Toggle("Show taskbar on all displays", isOn: $showOnAllSpaces)
                Toggle("Center taskbar icons", isOn: $centerTaskbarIcons)
                    .disabled(dockPosition == .left || dockPosition == .right)
                Toggle("Show system tray", isOn: $showSystemTray)
                Toggle("Show Task View button", isOn: $showTaskView)
            }
            
            Section("Clock Format") {
                Picker("Time Format:", selection: $use24HourClock) {
                    Text("24-Hour").tag(true)
                    Text("12-Hour").tag(false)
                }
                .pickerStyle(SegmentedPickerStyle())
                Text("Choose whether the system tray clock uses 24-hour or 12-hour format.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Search Button") {
                Picker("Search App:", selection: $searchAppChoice) {
                    ForEach(SearchAppChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                Text("Choose which search app opens when clicking the search button in the taskbar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("macOS Dock Management") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("macOS Dock Status:")
                            .font(.subheadline)
                        Spacer()
                        if dockManager.isProcessing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Processing...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(dockManager.isDockHidden ? "Hidden" : "Visible")
                                .font(.subheadline)
                                .foregroundColor(dockManager.isDockHidden ? .orange : .green)
                                .fontWeight(.medium)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button("Hide Mac Dock") {
                            dockManager.hideMacOSDock()
                        }
                        .disabled(dockManager.isDockHidden || dockManager.isProcessing)
                        .buttonStyle(.bordered)
                        
                        Button("Restore Mac Dock") {
                            dockManager.showMacOSDock()
                        }
                        .disabled(!dockManager.isDockHidden || dockManager.isProcessing)
                        .buttonStyle(.bordered)
                    }
                    
                    if let error = dockManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                    
                    Text("Hide the macOS dock for a cleaner Windows 11-like experience.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @Binding var combineTaskbarButtons: Bool
    @Binding var useSmallTaskbarButtons: Bool
    @Binding var taskbarTransparency: Double
    @Binding var showLabels: Bool
    @Binding var animationSpeed: Double
    
    var body: some View {
        Form {
            Section("Taskbar Appearance") {
                Toggle("Combine taskbar buttons", isOn: $combineTaskbarButtons)
                Text("When taskbar is full")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                
                Toggle("Use small taskbar buttons", isOn: $useSmallTaskbarButtons)
                
                Toggle("Show labels", isOn: $showLabels)
                Text("Show app names next to icons")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            
            Section("Visual Effects") {
                VStack(alignment: .leading) {
                    Text("Taskbar transparency")
                    Slider(value: $taskbarTransparency, in: 0.3...1.0, step: 0.1)
                    Text("\(Int(taskbarTransparency * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Animation speed")
                    Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.1)
                    Text(animationSpeed < 1.0 ? "Slower" : animationSpeed > 1.0 ? "Faster" : "Normal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Taskbar Items") {
                Text("Drag and drop apps on the taskbar to reorder them")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Right-click apps to pin or unpin them")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct AppsSettingsView: View {
    @State private var pinnedApps: [String] = []
    @AppStorage("defaultBrowser") private var defaultBrowser = "com.apple.Safari"
    @AppStorage("defaultTerminal") private var defaultTerminal = "com.apple.Terminal"
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("App Management")
                .font(.headline)
                .padding(.bottom)
            
            Form {
                Section("Default Applications") {
                    Picker("Default Browser:", selection: $defaultBrowser) {
                        Text("Safari").tag("com.apple.Safari")
                        Text("Chrome").tag("com.google.Chrome")
                        Text("Firefox").tag("org.mozilla.firefox")
                        Text("Edge").tag("com.microsoft.edgemac")
                    }
                    
                    Picker("Default Terminal:", selection: $defaultTerminal) {
                        Text("Terminal").tag("com.apple.Terminal")
                        Text("iTerm").tag("com.googlecode.iterm2")
                        Text("Warp").tag("dev.warp.Warp")
                        Text("Kitty").tag("com.kittty.Kitty")
                    }
                }
                
                Section("App Grouping") {
                    Text("Apps are automatically grouped by application")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Click on a grouped icon to see all windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Tips") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Right-click on apps to pin/unpin them", systemImage: "pin")
                        Label("Drag apps to reorder them", systemImage: "arrow.left.and.right")
                        Label("Middle-click to open new instance", systemImage: "plus.square")
                        Label("Shift+Click to open app as admin", systemImage: "lock.shield")
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
    }
}

struct LogsSettingsView: View {
    var logsDirectory: URL {
        AppLogger.shared.logsDirectory
    }
    var appLogFile: URL {
        logsDirectory.appendingPathComponent("app.log")
    }
    var errorsLogFile: URL {
        logsDirectory.appendingPathComponent("errors.log")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logs")
                .font(.headline)
            
            Text("Log files location:")
                .font(.subheadline)
            
            Text(logsDirectory.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            
            HStack(spacing: 12) {
                Button("Open Logs Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logsDirectory])
                }
                .buttonStyle(.bordered)
                
                Button("View app.log") {
                    NSWorkspace.shared.open(appLogFile)
                }
                .buttonStyle(.bordered)
                
                Button("View errors.log") {
                    NSWorkspace.shared.open(errorsLogFile)
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Log Information:")
                    .font(.subheadline)
                
                Label("App events and actions are logged to app.log", systemImage: "doc.text")
                Label("Errors and warnings are logged to errors.log", systemImage: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
}

struct AboutView: View {
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return "Version \(version) (\(build))"
        }
        return "Version Unknown"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Win Dock")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(appVersion)
                .foregroundColor(.secondary)
            
            Text("A Windows 11-style taskbar for macOS")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "rectangle.3.group", text: "Windows 11 taskbar design")
                FeatureRow(icon: "arrow.up.arrow.down", text: "Drag and drop support")
                FeatureRow(icon: "eye.slash", text: "Auto-hide functionality")
                FeatureRow(icon: "rectangle.righthalf.filled", text: "Multiple position options")
                FeatureRow(icon: "sparkles", text: "Smooth animations")
            }
            .padding(.vertical)
            
            Spacer()
            
            HStack {
                Link("GitHub Repository", destination: URL(string: "https://github.com/barnuri/win-dock")!)
                    .buttonStyle(.link)
                
                Spacer()
                
                Link("Report Issue", destination: URL(string: "https://github.com/barnuri/win-dock/issues")!)
                    .buttonStyle(.link)
            }
            
            Text("© 2024 • MIT License")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 13))
        }
    }
}


enum DockSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    
    var iconSize: CGFloat {
        switch self {
        case .small: return 32
        case .medium: return 40
        case .large: return 48
        }
    }
}

#Preview {
    SettingsView()
}