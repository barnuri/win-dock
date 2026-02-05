import SwiftUI
import AppKit
import UserNotifications

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

            NotificationSettingsTab()
                .tabItem {
                    Label("Notifications", systemImage: "bell.badge")
                }

            BackupSettingsTab(settingsManager: settingsManager)
                .tabItem {
                    Label("Backup", systemImage: "externaldrive.badge.icloud")
                }

            KeyboardShortcutsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
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
            VStack(alignment: .leading, spacing: 12) {
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
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manual Setup Instructions:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("If WinDock doesn't appear in Automation settings after clicking the button above:")
                            .font(.caption)
                        
                        Group {
                            Text("1. Open System Preferences > Security & Privacy > Privacy > Automation")
                            Text("2. Click the lock icon and enter your password")
                            Text("3. If WinDock is listed, enable 'System Events' and other apps")
                            Text("4. If WinDock is not listed, restart WinDock or use a Teams/Slack feature first")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                    }
                }
                
                HStack {
                    Button("Open System Preferences") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Test Permissions") {
                        testCurrentPermissions()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func requestAppleEventsPermission() {
        // This will trigger the permission dialog and make WinDock appear in the Automation list
        // We'll try multiple approaches to ensure the dialog appears
        
        let scripts = [
            // Script 1: Try to control System Events
            """
            tell application "System Events"
                get name of first process
            end tell
            """,
            
            // Script 2: Try to control Finder (more likely to trigger dialog)
            """
            tell application "Finder"
                get name
            end tell
            """,
            
            // Script 3: Try a more complex System Events operation
            """
            tell application "System Events"
                tell process "Finder"
                    get name
                end tell
            end tell
            """
        ]
        
        DispatchQueue.global(qos: .userInitiated).async {
            var permissionTriggered = false
            
            for (index, script) in scripts.enumerated() {
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    let _ = appleScript.executeAndReturnError(&error)
                    
                    if let error = error {
                        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                        
                        if errorNumber == -1743 {
                            permissionTriggered = true
                            AppLogger.shared.info("Permission dialog triggered with script \(index + 1)")
                            break
                        } else if errorNumber == -1708 {
                            // Script was successful - permission already granted
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = "Permission Already Granted"
                                alert.informativeText = "Apple Events authorization is already working correctly. WinDock can control other applications."
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                            return
                        }
                    } else {
                        // Script executed successfully - permission is granted
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Permission Already Granted"
                            alert.informativeText = "Apple Events authorization is already working correctly. WinDock can control other applications."
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                        return
                    }
                }
                
                // Small delay between attempts
                Thread.sleep(forTimeInterval: 0.5)
            }
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                
                if permissionTriggered {
                    alert.messageText = "Permission Request Initiated"
                    alert.informativeText = "WinDock should now appear in System Preferences > Security & Privacy > Privacy > Automation. Please enable WinDock to control System Events and other applications you want to integrate with.\n\nIf WinDock doesn't appear immediately, try clicking this button again or restart WinDock."
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
                    alert.messageText = "Permission Request Failed"
                    alert.informativeText = "Unable to trigger the permission dialog. Please try:\n\n1. Restart WinDock\n2. Try using WinDock features that require app control\n3. Manually add WinDock to Automation settings if needed"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Preferences")
                    alert.addButton(withTitle: "OK")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
    
    private func testCurrentPermissions() {
        let testScript = """
        tell application "System Events"
            get name of first process
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let appleScript = NSAppleScript(source: testScript) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    
                    if let error = error {
                        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
                        
                        if errorNumber == -1743 {
                            alert.messageText = "Permissions Needed"
                            alert.informativeText = "WinDock does not have Apple Events authorization. Please grant permission in System Preferences > Security & Privacy > Privacy > Automation."
                            alert.alertStyle = .warning
                        } else {
                            alert.messageText = "Permission Error"
                            alert.informativeText = "Error testing permissions: \(error)"
                            alert.alertStyle = .warning
                        }
                    } else {
                        alert.messageText = "Permissions Working"
                        alert.informativeText = "Apple Events authorization is working correctly! WinDock can control other applications."
                        alert.alertStyle = .informational
                    }
                    
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
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
    @AppStorage("themeMode") private var themeMode = "auto"
    @AppStorage("accentColor") private var accentColorName = "blue"
    
    var body: some View {
        Form {
            themeSection
            taskbarAppearanceSection
            visualEffectsSection
            taskbarItemsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
    
    private var themeSection: some View {
        Section("Theme") {
            Picker("Theme Mode", selection: $themeMode) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            
            Picker("Accent Color", selection: $accentColorName) {
                HStack {
                    Circle().fill(Color.blue).frame(width: 12, height: 12)
                    Text("Blue")
                }.tag("blue")
                HStack {
                    Circle().fill(Color.purple).frame(width: 12, height: 12)
                    Text("Purple")
                }.tag("purple")
                HStack {
                    Circle().fill(Color.pink).frame(width: 12, height: 12)
                    Text("Pink")
                }.tag("pink")
                HStack {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                    Text("Red")
                }.tag("red")
                HStack {
                    Circle().fill(Color.orange).frame(width: 12, height: 12)
                    Text("Orange")
                }.tag("orange")
                HStack {
                    Circle().fill(Color.green).frame(width: 12, height: 12)
                    Text("Green")
                }.tag("green")
            }
        }
    }
    
    private var taskbarAppearanceSection: some View {
        Section("Taskbar Appearance") {
            Toggle("Combine taskbar buttons", isOn: $combineTaskbarButtons)
            Toggle("Use small taskbar buttons", isOn: $useSmallTaskbarButtons)
            Toggle("Show labels", isOn: $showLabels)
            
            VStack(alignment: .leading) {
                Text("Icon Size")
                Picker("Icon Size", selection: $iconSize) {
                    Text("Small").tag(32)
                    Text("Medium").tag(40)
                    Text("Large").tag(48)
                    Text("Extra Large").tag(56)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            VStack(alignment: .leading) {
                Text("Icon Spacing")
                Slider(value: $iconSpacing, in: 2...20, step: 2)
                Text("\(Int(iconSpacing)) pixels")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
    
    @AppStorage("iconSize") private var iconSize = 40
    @AppStorage("iconSpacing") private var iconSpacing: Double = 8
    
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

struct NotificationSettingsTab: View {
    @StateObject private var notificationManager = NotificationPositionManager.shared
    @State private var showPermissionAlert = false
    @State private var testPosition: NotificationPosition = .topRight
    
    var body: some View {
        Form {
            enabledSection
            positionSection
            permissionSection
            testingSection
            informationSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Accessibility Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Preferences") {
                openSystemPreferences()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("WinDock needs accessibility permission to manage notification positions. Please enable accessibility access for WinDock in System Preferences > Security & Privacy > Privacy > Accessibility.")
        }
    }
    
    private var enabledSection: some View {
        Section("Notification Position Management") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Manage notification position", isOn: $notificationManager.isEnabled)
                    .onChange(of: notificationManager.isEnabled) { _, newValue in
                        updateNotificationSettings(enabled: newValue)
                    }
                
                if notificationManager.isEnabled {
                    Text("WinDock will automatically position macOS notifications based on your preference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Notifications will appear in their default position (top-right).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var positionSection: some View {
        Section("Notification Position") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose where notifications should appear:")
                    .font(.subheadline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(NotificationPosition.allCases, id: \.self) { position in
                        Button(action: {
                            updateNotificationSettings(position: position)
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: systemImageForPosition(position))
                                    .font(.title2)
                                    .foregroundColor(notificationManager.currentPosition == position ? .white : .primary)
                                
                                Text(position.displayName)
                                    .font(.caption)
                                    .foregroundColor(notificationManager.currentPosition == position ? .white : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(height: 60)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(notificationManager.currentPosition == position ? Color.accentColor : Color.gray.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(notificationManager.currentPosition == position ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!notificationManager.isEnabled)
                    }
                }
            }
        }
    }
    
    private var permissionSection: some View {
        Section("Permissions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permission")
                            .font(.headline)
                        Text("Required to detect and move notification windows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Request Permission") {
                        requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if let error = notificationManager.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup Instructions:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Group {
                        Text("1. Click 'Request Permission' above")
                        Text("2. Open System Preferences > Security & Privacy")
                        Text("3. Go to Privacy > Accessibility")
                        Text("4. Click the lock icon and enter your password")
                        Text("5. Enable WinDock in the list")
                        Text("6. Restart WinDock if needed")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var testingSection: some View {
        Section("Test Notifications") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Test your notification position settings")
                    .font(.subheadline)
                
                Button("Show Test Notification") {
                    showTestNotification()
                }
                .buttonStyle(.bordered)
                .disabled(!notificationManager.isEnabled)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("This will create a test notification to verify your position settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Note: You may need to enable notifications for WinDock in System Preferences > Notifications & Focus if this is your first time using the test feature.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var informationSection: some View {
        Section("Information") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notification position changes apply to new notifications", systemImage: "info.circle")
                Label("Existing notifications won't be moved retroactively", systemImage: "clock")
                Label("Position changes take effect immediately", systemImage: "bolt")
                Label("Works with all macOS notification styles", systemImage: "bell")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
    private func systemImageForPosition(_ position: NotificationPosition) -> String {
        switch position {
        case .topLeft: return "rectangle.lefthalf.inset.filled.arrow.left"
        case .topMiddle: return "rectangle.tophalf.inset.filled.arrow.up"
        case .topRight: return "rectangle.righthalf.inset.filled.arrow.right"
        case .middleLeft: return "rectangle.lefthalf.inset.filled"
        case .deadCenter: return "rectangle.inset.filled"
        case .middleRight: return "rectangle.righthalf.inset.filled"
        case .bottomLeft: return "rectangle.lefthalf.inset.filled.arrow.left"
        case .bottomMiddle: return "rectangle.bottomhalf.inset.filled.arrow.down"
        case .bottomRight: return "rectangle.righthalf.inset.filled.arrow.right"
        }
    }
    
    private func updateNotificationSettings(enabled: Bool? = nil, position: NotificationPosition? = nil) {
        let newEnabled = enabled ?? notificationManager.isEnabled
        let newPosition = position ?? notificationManager.currentPosition
        
        notificationManager.updateSettings(enabled: newEnabled, position: newPosition)
    }
    
    private func requestAccessibilityPermission() {
        notificationManager.requestAccessibilityPermissions()
        
        // Check permission status after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !notificationManager.checkAccessibilityPermissions() {
                showPermissionAlert = true
            }
        }
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showTestNotification() {
        // Request notification permission if needed
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    AppLogger.shared.error("Failed to request notification permission: \(error)")
                    self.showNotificationPermissionAlert(error: error)
                    return
                }
                
                guard granted else {
                    AppLogger.shared.warning("Notification permission not granted")
                    self.showNotificationPermissionAlert(error: nil)
                    return
                }
                
                // Create notification content
                let content = UNMutableNotificationContent()
                content.title = "WinDock Test Notification"
                content.body = "This is a test notification to verify your position settings."
                content.sound = .default
                
                // Create request
                let request = UNNotificationRequest(
                    identifier: "windock-test-\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: nil // Show immediately
                )
                
                // Schedule notification
                UNUserNotificationCenter.current().add(request) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            AppLogger.shared.error("Failed to schedule test notification: \(error)")
                            self.showNotificationErrorAlert(error: error)
                        } else {
                            AppLogger.shared.info("Test notification delivered for position: \(self.notificationManager.currentPosition.displayName)")
                        }
                    }
                }
            }
        }
    }
    
    private func showNotificationPermissionAlert(error: Error?) {
        let alert = NSAlert()
        alert.messageText = "Notification Permission Required"
        
        if let error = error {
            alert.informativeText = "Failed to request notification permission: \(error.localizedDescription)\n\nTo enable notifications:\n1. Open System Preferences\n2. Go to Notifications & Focus\n3. Find WinDock in the list\n4. Enable 'Allow Notifications'"
        } else {
            alert.informativeText = "WinDock needs permission to show test notifications. Please enable notifications in System Preferences:\n\n1. Open System Preferences\n2. Go to Notifications & Focus\n3. Find WinDock in the list\n4. Enable 'Allow Notifications'"
        }
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Notifications preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
        }
    }
    
    private func showNotificationErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Test Notification Failed"
        alert.informativeText = "Failed to show test notification: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Run WinDock on login", isOn: $isEnabled)
                    .disabled(isProcessing || loginItemManager.isProcessing)
                    .onChange(of: isEnabled) { _, newValue in
                        updateLoginItemStatus(enabled: newValue)
                    }
                
                if isProcessing || loginItemManager.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
            }
            
            // Show status message
            if loginItemManager.requiresApproval {
                HStack {
                    Text("⚠️ Requires approval in System Settings")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Button("Open Settings") {
                        loginItemManager.openSystemSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            
            // Show error if any
            if let error = loginItemManager.lastError {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
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

struct KeyboardShortcutsTab: View {
    @AppStorage("enableKeyboardShortcuts") private var enableKeyboardShortcuts = true
    @AppStorage("showDockShortcut") private var showDockShortcut = "⌃Space"
    @AppStorage("hideDockShortcut") private var hideDockShortcut = "⌃⌥H"
    @AppStorage("cycleAppsShortcut") private var cycleAppsShortcut = "⌘Tab"
    
    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                Toggle("Enable keyboard shortcuts", isOn: $enableKeyboardShortcuts)
                
                if enableKeyboardShortcuts {
                    VStack(alignment: .leading, spacing: 12) {
                        shortcutRow("Show/Hide Dock", shortcut: $showDockShortcut)
                        shortcutRow("Hide Dock", shortcut: $hideDockShortcut)
                        shortcutRow("Cycle Through Apps", shortcut: $cycleAppsShortcut)
                    }
                    .padding(.top, 8)
                }
            }
            
            Section("Help") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modifier Keys:")
                        .font(.headline)
                    
                    Group {
                        Text("⌘ Command")
                        Text("⌥ Option (Alt)")
                        Text("⌃ Control")
                        Text("⇧ Shift")
                        Text("⇪ Caps Lock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
    
    private func shortcutRow(_ title: String, shortcut: Binding<String>) -> some View {
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("Shortcut", text: shortcut)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .disabled(true) // For now, just show the shortcuts
        }
    }
}

#Preview {
    SettingsView()
}
