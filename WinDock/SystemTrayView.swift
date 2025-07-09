import SwiftUI
import AppKit

struct SystemTrayView: View {
    @State private var currentTime = Date()
    @State private var batteryPercent: Int? = nil
    @AppStorage("use24HourClock") private var use24HourClock = true

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            if let percent = batteryPercent {
                HStack(spacing: 4) {
                    Image(systemName: "battery.100")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Text("\(percent)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(currentTime, formatter: timeFormatter)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Text(currentTime, formatter: dateFormatter)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear(perform: updateBattery)
        .onReceive(timer) { _ in
            currentTime = Date()
            updateBattery()
        }
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = use24HourClock ? "HH:mm" : "h:mm a"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }

    private func updateBattery() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        for ps in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any],
               let capacity = info[kIOPSCurrentCapacityKey as String] as? Int,
               let max = info[kIOPSMaxCapacityKey as String] as? Int {
                batteryPercent = Int((Double(capacity) / Double(max)) * 100)
                return
            }
        }
        batteryPercent = nil
    }
}
