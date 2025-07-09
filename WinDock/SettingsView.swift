import SwiftUI

struct SettingsView: View {
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @StateObject private var dockManager = MacOSDockManager()
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                dockPosition: $dockPosition,
                dockSize: $dockSize,
                autoHide: $autoHide,
                showOnAllSpaces: $showOnAllSpaces,
                dockManager: dockManager
            )
            .tabItem {
                Label("General", systemImage: "gear")
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
        .frame(width: 450, height: 400)
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
            Text("Logs Folder")
                .font(.headline)
            Text(logsDirectory.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: 12) {
                Button("Open Logs Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logsDirectory])
                }
                Button("Open app.log") {
                    NSWorkspace.shared.activateFileViewerSelecting([appLogFile])
                }
                Button("Open errors.log") {
                    NSWorkspace.shared.activateFileViewerSelecting([errorsLogFile])
                }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}
}

struct GeneralSettingsView: View {
    @Binding var dockPosition: DockPosition
    @Binding var dockSize: DockSize
    @Binding var autoHide: Bool
    @Binding var showOnAllSpaces: Bool
    @ObservedObject var dockManager: MacOSDockManager
    
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Position:", selection: $dockPosition) {
                    Text("Bottom").tag(DockPosition.bottom)
                    Text("Top").tag(DockPosition.top)
                    Text("Left").tag(DockPosition.left)
                    Text("Right").tag(DockPosition.right)
                }
                .pickerStyle(MenuPickerStyle())
                
                Picker("Size:", selection: $dockSize) {
                    Text("Small").tag(DockSize.small)
                    Text("Medium").tag(DockSize.medium)
                    Text("Large").tag(DockSize.large)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section("Behavior") {
                Toggle("Auto-hide dock", isOn: $autoHide)
                Toggle("Show on all Spaces", isOn: $showOnAllSpaces)
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
                    
                    Text("Hide the macOS dock for a cleaner experience with WinDock.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
}

struct AppsSettingsView: View {
    var body: some View {
        VStack {
            Text("App Management")
                .font(.headline)
                .padding()
            
            Text("Right-click on apps in the dock to pin/unpin them.")
                .foregroundColor(.secondary)
                .padding()
            
            Spacer()
        }
    }
}

struct AboutView: View {
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "Version \(version)"
        }
        return "Version Unknown"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Win Dock")
                .font(.title)
                .fontWeight(.bold)
            
            Text(appVersion)
                .foregroundColor(.secondary)
            
            Text("A minimal macOS taskbar that emulates Windows 11 style.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack {
                Link("GitHub", destination: URL(string: "https://github.com/barnuri/win-dock")!)
                Spacer()
                Text("MIT License")
                    .foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .padding()
    }
}

enum DockPosition: String, CaseIterable {
    case bottom = "bottom"
    case top = "top"
    case left = "left"
    case right = "right"
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
