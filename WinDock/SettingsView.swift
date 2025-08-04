import SwiftUI
import AppKit

struct SettingsView: View {
    @StateObject private var dockManager = MacOSDockManager()
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some View {
        TabView {
            GeneralSettingsTab(dockManager: dockManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AppsSettingsTab()
                .tabItem {
                    Label("Apps", systemImage: "app.badge")
                }

            BackupSettingsTab(settingsManager: settingsManager)
                .tabItem {
                    Label("Backup", systemImage: "externaldrive.badge.icloud")
                }

            LogsSettingsTab()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 1024, minHeight: 600)
        .onAppear {
            configureSettingsWindowToStayOnTop()
        }
    }
    
    private func configureSettingsWindowToStayOnTop() {
        DispatchQueue.main.async {
            // Find any window that's likely the settings window
            for window in NSApp.windows {
                // Check if this is a settings window by looking for TabView content or similar characteristics
                if window.isVisible && 
                   window.title.isEmpty == false && 
                   window.contentViewController != nil {
                    
                    // Set window level to floating to stay on top
                    window.level = .floating
                    
                    // Ensure window is always visible and can't be hidden by other apps
                    window.hidesOnDeactivate = false
                    
                    // Make the window stay on top even when app loses focus
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    
                    AppLogger.shared.info("Settings window configured to stay on top")
                    break
                }
            }
            
            // Additional attempt with delay to catch window after it's fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                for window in NSApp.windows {
                    if window.isVisible && window.level != .floating {
                        window.level = .floating
                        window.hidesOnDeactivate = false
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                        AppLogger.shared.info("Settings window configured to stay on top (delayed attempt)")
                        break
                    }
                }
            }
        }
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .large
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("showOnAllSpaces") private var showOnAllSpaces = true
    @AppStorage("centerTaskbarIcons") private var centerTaskbarIcons = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("showTaskView") private var showTaskView = true
    @AppStorage("searchAppChoice") private var searchAppChoice: SearchAppChoice = .spotlight
    @AppStorage("use24HourClock") private var use24HourClock = true
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .ddMMyyyy
    @AppStorage("paddingVertical") private var paddingVertical: Double = 0.0
    @AppStorage("paddingHorizontal") private var paddingHorizontal: Double = 0.0
    @AppStorage("enableWindowsResize") private var enableWindowsResize: Bool = true
    
    let dockManager: MacOSDockManager
    
    var body: some View {
        Form {
            taskbarPositionSection
            iconSizeSection
            behaviorSection
            permissionsSection
            clockSection
            searchSection
            paddingSection
            dockManagementSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
    
    private var taskbarPositionSection: some View {
        Section("Taskbar Position") {
            Picker("Position:", selection: $dockPosition) {
                ForEach(DockPosition.allCases, id: \.self) { position in
                    Text(position.displayName).tag(position)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var iconSizeSection: some View {
        Section("Icon Size") {
            Picker("Size:", selection: $dockSize) {
                ForEach(DockSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            
            Text("Controls the size of the icons in the dock.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    private var behaviorSection: some View {
        Section("Taskbar Behavior") {
            Toggle("Automatically hide the taskbar", isOn: $autoHide)
            Toggle("Show taskbar on all displays", isOn: $showOnAllSpaces)
            Toggle("Center taskbar icons", isOn: $centerTaskbarIcons)
                .disabled(dockPosition == .left || dockPosition == .right)
            Toggle("Show system tray", isOn: $showSystemTray)
            Toggle("Show Task View button", isOn: $showTaskView)
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Prevent windows from overlapping taskbar", isOn: $enableWindowsResize)
                    .onChange(of: enableWindowsResize) { _, newValue in
                        if newValue {
                            WindowsResizeManager.shared.start()
                        } else {
                            WindowsResizeManager.shared.stop()
                        }
                    }
                
                Text("Automatically moves or resizes windows that overlap with the taskbar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Run on login toggle
            RunOnLoginToggleView()
        }
    }
    
    private var permissionsSection: some View {
        Section("Permissions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Events Authorization")
                            .font(.headline)
                        Text("Required for notification badges and app integrations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Request Permission") {
                        requestAppleEventsPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Text("Click the button above to trigger the macOS permission dialog. WinDock will then appear in System Preferences > Security & Privacy > Privacy > Automation, where you can grant it permission to control other applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func requestAppleEventsPermission() {
        // This will trigger the permission dialog and make WinDock appear in the Automation list
        let script = """
        tell application "System Events"
            get name of first process
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                let result = appleScript.executeAndReturnError(&error)
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    
                    if let error = error {
                        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                        
                        if errorNumber == -1743 {
                            alert.messageText = "Permission Request Initiated"
                            alert.informativeText = "WinDock should now appear in System Preferences > Security & Privacy > Privacy > Automation. Please enable WinDock to control System Events and other applications you want to integrate with."
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "Open System Preferences")
                            alert.addButton(withTitle: "OK")
                            
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        } else {
                            alert.messageText = "Permission Error"
                            alert.informativeText = "An unexpected error occurred: \(error)"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    } else {
                        alert.messageText = "Permission Already Granted"
                        alert.informativeText = "Apple Events authorization is already working correctly. WinDock can control other applications."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    private var clockSection: some View {
        Section("Clock Format") {
            Picker("Time Format:", selection: $use24HourClock) {
                Text("24-Hour").tag(true)
                Text("12-Hour").tag(false)
            }
            .pickerStyle(.segmented)
            
            Picker("Date Format:", selection: $dateFormat) {
                ForEach(DateFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var searchSection: some View {
        Section("Search Button") {
            Picker("Search App:", selection: $searchAppChoice) {
                ForEach(SearchAppChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var paddingSection: some View {
        Section("Taskbar Padding") {
            VStack(alignment: .leading, spacing: 12) {
                paddingSlider(title: "Vertical", value: $paddingVertical)
                paddingSlider(title: "Horizontal", value: $paddingHorizontal)
            }
            
            Text("Adjust spacing around the taskbar edges.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    private var dockManagementSection: some View {
        Section("macOS Dock Management") {
            HStack {
                Text("Status:")
                Spacer()
                
                if dockManager.isProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Processing...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(dockManager.isDockHidden ? "Hidden" : "Visible")
                        .foregroundStyle(dockManager.isDockHidden ? .orange : .green)
                        .fontWeight(.medium)
                }
            }
            
            HStack {
                Button("Hide Mac Dock") {
                    dockManager.hideMacOSDock()
                }
                .disabled(dockManager.isDockHidden || dockManager.isProcessing)
                
                Button("Restore Mac Dock") {
                    dockManager.showMacOSDock()
                }
                .disabled(!dockManager.isDockHidden || dockManager.isProcessing)
            }
            
            if let error = dockManager.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            Text("Hide the macOS dock for a cleaner Windows 11-like experience.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    private func paddingSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue))px")
            Slider(value: value, in: -100...100, step: 1)
        }
    }
}


struct AppearanceSettingsTab: View {
    @AppStorage("combineTaskbarButtons") private var combineTaskbarButtons = true
    @AppStorage("useSmallTaskbarButtons") private var useSmallTaskbarButtons = false
    @AppStorage("taskbarTransparency") private var taskbarTransparency = 1.0
    @AppStorage("showLabels") private var showLabels = false
    @AppStorage("animationSpeed") private var animationSpeed = 1.0
    
    var body: some View {
        Form {
            taskbarAppearanceSection
            visualEffectsSection
            taskbarItemsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
    
    private var taskbarAppearanceSection: some View {
        Section("Taskbar Appearance") {
            Toggle("Combine taskbar buttons", isOn: $combineTaskbarButtons)
            Toggle("Use small taskbar buttons", isOn: $useSmallTaskbarButtons)
            Toggle("Show labels", isOn: $showLabels)
        }
    }
    
    private var visualEffectsSection: some View {
        Section("Visual Effects") {
            VStack(alignment: .leading) {
                Text("Taskbar transparency")
                Slider(value: $taskbarTransparency, in: 0.0...1.0, step: 0.05)
                
                HStack {
                    Text("Solid")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Text("\(Int(taskbarTransparency * 100))%")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Text("Glass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                
                HStack {
                    Text("Preview:")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Rectangle()
                        .fill(previewMaterial)
                        .opacity(taskbarTransparency)
                        .frame(width: 60, height: 20)
                        .overlay(
                            Rectangle()
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading) {
                Text("Animation speed")
                Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.1)
                Text(animationSpeedDescription)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
    
    private var taskbarItemsSection: some View {
        Section("Tips") {
            Text("Drag and drop apps on the taskbar to reorder them")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Right-click apps to pin or unpin them")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    private var previewMaterial: some ShapeStyle {
        if taskbarTransparency >= 0.95 {
            return AnyShapeStyle(.regularMaterial)
        } else if taskbarTransparency >= 0.7 {
            return AnyShapeStyle(.thinMaterial)
        } else {
            return AnyShapeStyle(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private var animationSpeedDescription: String {
        if animationSpeed < 1.0 {
            return "Slower"
        } else if animationSpeed > 1.0 {
            return "Faster"
        } else {
            return "Normal"
        }
    }
}

struct AppsSettingsTab: View {
    @AppStorage("defaultBrowser") private var defaultBrowser = "com.apple.Safari"
    @AppStorage("defaultTerminal") private var defaultTerminal = "com.apple.Terminal"
    
    var body: some View {
        Form {
            defaultAppsSection
            groupingSection
            tipsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
    
    private var defaultAppsSection: some View {
        Section("Default Applications") {
            Picker("Browser:", selection: $defaultBrowser) {
                Text("Safari").tag("com.apple.Safari")
                Text("Chrome").tag("com.google.Chrome")
                Text("Firefox").tag("org.mozilla.firefox")
                Text("Edge").tag("com.microsoft.edgemac")
            }
            
            Picker("Terminal:", selection: $defaultTerminal) {
                Text("Terminal").tag("com.apple.Terminal")
                Text("iTerm").tag("com.googlecode.iterm2")
                Text("Warp").tag("dev.warp.Warp")
                Text("Kitty").tag("com.kittty.Kitty")
            }
        }
    }
    
    private var groupingSection: some View {
        Section("App Grouping") {
            Text("Apps are automatically grouped by application")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Click on a grouped icon to see all windows")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    private var tipsSection: some View {
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

struct LogsSettingsTab: View {
    @AppStorage("logLevel") private var logLevel: String = "info"
    private var logsDirectory: URL { AppLogger.shared.logsDirectory }
    private var appLogFile: URL { logsDirectory.appendingPathComponent("app.log") }
    private var errorsLogFile: URL { logsDirectory.appendingPathComponent("errors.log") }
    private var debugLogFile: URL { logsDirectory.appendingPathComponent("debug.log") }

    var body: some View {
        Form {
            logLevelSection
            logFilesSection
            logInformationSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
    
    private var logLevelSection: some View {
        Section("Log Level") {
            Picker("Minimum Log Level:", selection: $logLevel) {
                Text("Debug").tag("debug")
                Text("Info").tag("info") 
                Text("Warning").tag("warning")
                Text("Error").tag("error")
                Text("Critical").tag("critical")
            }
            .pickerStyle(.segmented)
            
            Text(logLevelDescription)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    private var logFilesSection: some View {
        Section("Log Files") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Log files location:")
                    .font(.subheadline)
                
                Text(logsDirectory.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
            
            HStack(spacing: 12) {
                Button("Open Logs Folder") {
                    AppLogger.shared.showLogsInFinder()
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
            
            HStack(spacing: 12) {
                Button("View debug.log") {
                    NSWorkspace.shared.open(debugLogFile)
                }
                .buttonStyle(.bordered)
                .disabled(logLevel == "info" || logLevel == "warning" || logLevel == "error" || logLevel == "critical")
                
                Spacer()
            }
        }
    }
    
    private var logInformationSection: some View {
        Section("Log Information") {
            VStack(alignment: .leading, spacing: 8) {
                Label("General app events are logged to app.log", systemImage: "doc.text")
                Label("Errors and warnings are logged to errors.log", systemImage: "exclamationmark.triangle") 
                Label("Debug information is logged to debug.log", systemImage: "ladybug")
                Label("Log files are automatically rotated when they exceed 10MB", systemImage: "arrow.clockwise")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
    private var logLevelDescription: String {
        switch logLevel {
        case "debug":
            return "Shows all messages including detailed debug information. Useful for troubleshooting."
        case "info":
            return "Shows general information, warnings, errors, and critical messages. Recommended for normal use."
        case "warning":
            return "Shows warnings, errors, and critical messages only."
        case "error":
            return "Shows only errors and critical messages."
        case "critical":
            return "Shows only critical error messages."
        default:
            return "Shows general information and above."
        }
    }
}

struct AboutTab: View {
    private var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "Version Unknown"
        }
        return "Version \(version) (\(build))"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                appIcon
                appTitle
                appFeatures
                Spacer()
                appLinks
                copyright
            }
            .padding()
        }
    }
    
    private var appIcon: some View {
        Group {
            if let customIcon = NSImage(named: "AppIcon") ?? 
               NSImage(contentsOfFile: Bundle.main.path(forResource: "icon", ofType: "png") ?? "") {
                Image(nsImage: customIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            } else {
                Image(systemName: "dock.rectangle")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
    
    private var appTitle: some View {
        VStack(spacing: 8) {
            Text("Win Dock")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(appVersion)
                .foregroundStyle(.secondary)
            
            Text("A Windows 11-style taskbar for macOS")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var appFeatures: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureRow(icon: "rectangle.3.group", text: "Windows 11 taskbar design")
            FeatureRow(icon: "arrow.up.arrow.down", text: "Drag and drop support")
            FeatureRow(icon: "eye.slash", text: "Auto-hide functionality")
            FeatureRow(icon: "rectangle.righthalf.filled", text: "Multiple position options")
            FeatureRow(icon: "sparkles", text: "Smooth animations")
        }
    }
    
    private var appLinks: some View {
        HStack {
            Link("GitHub Repository", destination: URL(string: "https://github.com/barnuri/win-dock")!)
                .buttonStyle(.link)
            
            Spacer()
            
            Link("Report Issue", destination: URL(string: "https://github.com/barnuri/win-dock/issues")!)
                .buttonStyle(.link)
        }
    }
    
    private var copyright: some View {
        Text("© 2024 • MIT License")
            .font(.caption)
            .foregroundStyle(.secondary)
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


enum SearchAppChoice: String, CaseIterable {
    case spotlight = "spotlight"
    case raycast = "raycast"
    case alfred = "alfred"
    
    var displayName: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .raycast: return "Raycast"
        case .alfred: return "Alfred"
        }
    }
}



enum DockSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    
    var height: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 56
        case .large: return 64
        }
    }

    
    var iconSize: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 48
        case .large: return 56
        }
    }
}

struct BackupSettingsTab: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var showResetConfirmation = false
    
    var body: some View {
        Form {
            exportSection
            importSection
            resetSection
            processingIndicator
            notesSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Reset Settings", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settingsManager.resetToDefaults()
            }
        } message: {
            Text("Are you sure you want to reset all settings to their default values? This action cannot be undone.")
        }
        .onAppear {
            settingsManager.clearStatus()
        }
    }
    
    private var exportSection: some View {
        Section("Export Settings") {
            Text("Save your current settings to a JSON file")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            
            Button("Export Settings...") {
                settingsManager.exportSettingsToFile()
            }
            .disabled(settingsManager.isProcessing)
            .buttonStyle(.borderedProminent)
            
            if let status = settingsManager.exportStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.contains("successfully") ? .green : .red)
            }
        }
    }
    
    private var importSection: some View {
        Section("Import Settings") {
            Text("Load settings from a previously exported JSON file")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            
            Button("Import Settings...") {
                settingsManager.importSettingsFromFile()
            }
            .disabled(settingsManager.isProcessing)
            
            if let status = settingsManager.importStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.contains("successfully") ? .green : .red)
            }
        }
    }
    
    private var resetSection: some View {
        Section("Reset to Defaults") {
            Text("Reset all settings to their default values")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            
            Button("Reset to Defaults") {
                showResetConfirmation = true
            }
            .disabled(settingsManager.isProcessing)
            .foregroundStyle(.red)
        }
    }
    
    @ViewBuilder
    private var processingIndicator: some View {
        if settingsManager.isProcessing {
            Section {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Settings files are saved in JSON format", systemImage: "doc.text")
                Label("Import will overwrite all current settings", systemImage: "exclamationmark.triangle")
                Label("The app will automatically restart dock windows after import", systemImage: "arrow.clockwise")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct RunOnLoginToggleView: View {
    @StateObject private var loginItemManager = LoginItemManager.shared
    @State private var isEnabled: Bool = false
    @State private var isProcessing: Bool = false
    
    var body: some View {
        HStack {
            Toggle("Run WinDock on login", isOn: $isEnabled)
                .disabled(isProcessing)
                .onChange(of: isEnabled) { _, newValue in
                    updateLoginItemStatus(enabled: newValue)
                }
            
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
        }
        .onAppear {
            isEnabled = loginItemManager.isLoginItemEnabled
        }
    }
    
    private func updateLoginItemStatus(enabled: Bool) {
        isProcessing = true
        
        // Perform the login item change on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            loginItemManager.isLoginItemEnabled = enabled
            
            DispatchQueue.main.async {
                isProcessing = false
                // Verify the change took effect
                let actualStatus = loginItemManager.isLoginItemEnabled
                if actualStatus != enabled {
                    // Revert UI if the change failed
                    isEnabled = actualStatus
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
