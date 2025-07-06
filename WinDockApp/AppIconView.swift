import SwiftUI
import AppKit

struct AppIconView: View {
    let app: NSRunningApplication

    var body: some View {
        if let nsImage = app.icon {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(radius: app.isActive ? 4 : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(app.isActive ? Color.accentColor : .clear, lineWidth: 2)
                )
                .onTapGesture {
                    _ = app.activate(options: [.activateAllWindows,
                                               .activateIgnoringOtherApps])
                }
        }
    }
}
