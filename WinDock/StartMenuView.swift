import SwiftUI
import AppKit

struct StartMenuView: View {
    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Type here to search", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(8)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(6)
            .padding()
            VStack(spacing: 0) {
                Text("Pinned")
                    .font(.headline)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                    ForEach(["Finder", "Safari", "Mail", "Messages"], id: \.self) { appName in
                        PinnedAppIcon(appName: appName, dismiss: dismiss)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
            )
            Spacer()
            HStack {
                Button(action: {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                    dismiss()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
                Button(action: {
                    lockScreen()
                    dismiss()
                }) {
                    Image(systemName: "lock")
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .background(.regularMaterial)
    }
}
