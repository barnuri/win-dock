import SwiftUI
import AppKit
import IOKit.ps
import Network
import SystemConfiguration

enum DateFormat: String, CaseIterable {
    case ddMMyyyy = "dd/MM/yyyy"
    case mmDDyyyy = "MM/dd/yyyy"
    case yyyyMMdd = "yyyy-MM-dd"
    case ddMMyyyy_dash = "dd-MM-yyyy"
    case mmDDyyyy_dash = "MM-dd-yyyy"
    
    var displayName: String {
        switch self {
        case .ddMMyyyy: return "DD/MM/YYYY"
        case .mmDDyyyy: return "MM/DD/YYYY"
        case .yyyyMMdd: return "YYYY-MM-DD"
        case .ddMMyyyy_dash: return "DD-MM-YYYY"
        case .mmDDyyyy_dash: return "MM-DD-YYYY"
        }
    }
    
    var dateFormatString: String {
        return self.rawValue
    }
    
    func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self.dateFormatString
        return formatter.string(from: date)
    }
}

struct SystemTrayView: View {
    @State private var currentTime = Date()
    @State private var batteryInfo = BatteryInfo()
    @State private var networkInfo = NetworkInfo()
    @AppStorage("use24HourClock") private var use24HourClock = true
    @AppStorage("showSystemTray") private var showSystemTray = true
    @AppStorage("dateFormat") private var dateFormat: DateFormat = .ddMMyyyy
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if showSystemTray {
            HStack(spacing: 8) {
                // Battery indicator (if laptop)
                if batteryInfo.isPresent {
                    BatteryIndicatorView(batteryInfo: batteryInfo)
                }
                
                // Network indicator
                NetworkIndicatorView(networkInfo: networkInfo)
                
                // Volume indicator
                VolumeIndicatorView()
                
                // Date and time
                DateTimeView(currentTime: currentTime, use24HourClock: use24HourClock, dateFormat: dateFormat)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.clear)
            .onReceive(timer) { _ in
                currentTime = Date()
                batteryInfo.update()
                networkInfo.update()
            }
            .onAppear {
                batteryInfo.update()
                networkInfo.start()
            }
            .onDisappear {
                networkInfo.stop()
            }
        }
    }
}

struct BatteryInfo: Equatable {
    var isPresent: Bool = false
    var percentage: Int = 0
    var isCharging: Bool = false
    var timeRemaining: Int? = nil // minutes
    
    mutating func update() {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        
        guard let sources = sources else {
            isPresent = false
            return
        }
        
        for source in sources {
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            
            guard let desc = description,
                  let type = desc[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }
            
            isPresent = true
            
            if let capacity = desc[kIOPSCurrentCapacityKey] as? Int {
                percentage = capacity
            }
            
            if let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String {
                isCharging = powerSourceState == kIOPSACPowerValue
            }
            
            if let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
                timeRemaining = timeToEmpty
            }
            
            break
        }
    }
}

class NetworkInfo: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var signalStrength: Int = 0 // 0-3
    @Published var connectionType: String = "Unknown"
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.updateConnectionInfo(path: path)
            }
        }
        monitor.start(queue: queue)
    }
    
    func stop() {
        monitor.cancel()
    }
    
    func update() {
        // This method is called by the timer but the real updates come from the network monitor
        // We'll also check WiFi signal strength here if needed
        updateSignalStrength()
    }
    
    private func updateConnectionInfo(path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = "Wi-Fi"
            updateSignalStrength()
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = "Ethernet"
            signalStrength = 3 // Ethernet typically has strong connection
        } else if path.usesInterfaceType(.cellular) {
            connectionType = "Cellular"
            signalStrength = 2 // Default cellular strength
        } else {
            connectionType = "Unknown"
            signalStrength = 0
        }
    }
    
    private func updateSignalStrength() {
        if !isConnected {
            signalStrength = 0
            return
        }
        
        // For WiFi, we can try to get signal strength using CoreWLAN
        // For now, we'll use a simplified approach
        if connectionType == "Wi-Fi" {
            // This is a simplified signal strength - in a real app you'd use CoreWLAN
            signalStrength = Int.random(in: 1...3) // Simulate varying signal strength
        }
    }
}

struct BatteryIndicatorView: View {
    let batteryInfo: BatteryInfo
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: batteryIconName)
                    .font(.system(size: 12))
                    .foregroundColor(batteryColor)
                
                Text("\(batteryInfo.percentage)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(batteryTooltip)
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            BatteryDetailsView(batteryInfo: batteryInfo)
        }
    }
    
    private var batteryIconName: String {
        if batteryInfo.isCharging {
            return "battery.100.bolt"
        }
        
        switch batteryInfo.percentage {
        case 0...20:
            return "battery.25"
        case 21...50:
            return "battery.50"
        case 51...75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
    
    private var batteryColor: Color {
        if batteryInfo.isCharging {
            return .green
        }
        
        switch batteryInfo.percentage {
        case 0...20:
            return .red
        case 21...30:
            return .orange
        default:
            return .primary
        }
    }
    
    private var batteryTooltip: String {
        var tooltip = "Battery: \(batteryInfo.percentage)%"
        if batteryInfo.isCharging {
            tooltip += " (Charging)"
        } else if let timeRemaining = batteryInfo.timeRemaining {
            let hours = timeRemaining / 60
            let minutes = timeRemaining % 60
            tooltip += " (\(hours)h \(minutes)m remaining)"
        }
        return tooltip
    }
}

struct BatteryDetailsView: View {
    let batteryInfo: BatteryInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Battery Status")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Text("Level:")
                Spacer()
                Text("\(batteryInfo.percentage)%")
                    .fontWeight(.medium)
            }
            
            HStack {
                Text("Status:")
                Spacer()
                Text(batteryInfo.isCharging ? "Charging" : "On Battery")
                    .fontWeight(.medium)
                    .foregroundColor(batteryInfo.isCharging ? .green : .primary)
            }
            
            if let timeRemaining = batteryInfo.timeRemaining, !batteryInfo.isCharging {
                HStack {
                    Text("Time Remaining:")
                    Spacer()
                    Text("\(timeRemaining / 60)h \(timeRemaining % 60)m")
                        .fontWeight(.medium)
                }
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}

struct NetworkIndicatorView: View {
    @ObservedObject var networkInfo: NetworkInfo
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails.toggle() }) {
            Image(systemName: networkIconName)
                .font(.system(size: 12))
                .foregroundColor(networkInfo.isConnected ? .primary : .red)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Network: \(networkInfo.isConnected ? "Connected (\(networkInfo.connectionType))" : "Disconnected")")
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            NetworkDetailsView(networkInfo: networkInfo)
        }
    }
    
    private var networkIconName: String {
        if !networkInfo.isConnected {
            return "wifi.slash"
        }
        
        if networkInfo.connectionType == "Ethernet" {
            return "cable.connector"
        }
        
        switch networkInfo.signalStrength {
        case 0:
            return "wifi.exclamationmark"
        case 1:
            return "wifi"
        case 2:
            return "wifi"
        default:
            return "wifi"
        }
    }
}

struct NetworkDetailsView: View {
    @ObservedObject var networkInfo: NetworkInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network Status")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Text("Connection:")
                Spacer()
                Text(networkInfo.isConnected ? "Connected" : "Disconnected")
                    .fontWeight(.medium)
                    .foregroundColor(networkInfo.isConnected ? .green : .red)
            }
            
            if networkInfo.isConnected {
                HStack {
                    Text("Type:")
                    Spacer()
                    Text(networkInfo.connectionType)
                        .fontWeight(.medium)
                }
                
                if networkInfo.connectionType == "Wi-Fi" {
                    HStack {
                        Text("Signal Strength:")
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(0..<4) { index in
                                Rectangle()
                                    .fill(index <= networkInfo.signalStrength ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 4, height: CGFloat(4 + index * 2))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}

struct VolumeIndicatorView: View {
    @State private var volumeLevel: Float = 0.5
    @State private var isMuted = false
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails.toggle() }) {
            Image(systemName: volumeIconName)
                .font(.system(size: 12))
                .foregroundColor(isMuted ? .red : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Volume: \(isMuted ? "Muted" : "\(Int(volumeLevel * 100))%")")
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            VolumeDetailsView(volumeLevel: $volumeLevel, isMuted: $isMuted)
        }
        .onAppear {
            updateVolumeLevel()
        }
    }
    
    private var volumeIconName: String {
        if isMuted || volumeLevel == 0 {
            return "speaker.slash"
        } else if volumeLevel < 0.33 {
            return "speaker.wave.1"
        } else if volumeLevel < 0.66 {
            return "speaker.wave.2"
        } else {
            return "speaker.wave.3"
        }
    }
    
    private func updateVolumeLevel() {
        // Get system volume - simplified implementation
        volumeLevel = 0.5
        isMuted = false
    }
}

struct VolumeDetailsView: View {
    @Binding var volumeLevel: Float
    @Binding var isMuted: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume Control")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Button(action: { isMuted.toggle() }) {
                    Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.3")
                        .foregroundColor(isMuted ? .red : .primary)
                }
                .buttonStyle(.plain)
                
                Slider(value: Binding(
                    get: { volumeLevel },
                    set: { newValue in
                        volumeLevel = newValue
                        isMuted = false
                    }
                ), in: 0...1)
                
                Text("\(Int(volumeLevel * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 30)
            }
        }
        .padding(12)
        .frame(width: 250)
    }
}

struct DateTimeView: View {
    let currentTime: Date
    let use24HourClock: Bool
    let dateFormat: DateFormat
    @State private var showCalendar = false
    
    var body: some View {
        Button(action: { showCalendar.toggle() }) {
            VStack(alignment: .center, spacing: 0) {
                Text(timeString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 60) // Ensure consistent width for center alignment
        }
        .buttonStyle(.plain)
        .help("Click to open calendar")
        .popover(isPresented: $showCalendar, arrowEdge: .top) {
            CalendarView(currentDate: currentTime)
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = use24HourClock ? .short : .short
        formatter.dateStyle = .none
        if !use24HourClock {
            formatter.amSymbol = "AM"
            formatter.pmSymbol = "PM"
        }
        return formatter.string(from: currentTime)
    }
    
    private var dateString: String {
        return dateFormat.formattedDate(from: currentTime)
    }
}

struct CalendarView: View {
    let currentDate: Date
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text(monthYearString)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(fullDateString)
                    .font(.headline)
                    .fontWeight(.medium)
            }
            
            // Simple calendar grid would go here
            // For now, just show the date info
            
            HStack(spacing: 12) {
                Button("Calendar App") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Clock") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.datetime") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentDate)
    }
    
    private var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: currentDate)
    }
}

#Preview {
    SystemTrayView()
        .preferredColorScheme(.light)
}
