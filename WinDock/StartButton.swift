import SwiftUI
import AppKit

struct StartButton: View {
    @Binding var showMenu: Bool
    var body: some View {
        Button(action: { showMenu.toggle() }) {
            Image(systemName: "windows")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.blue))
        }
        .buttonStyle(PlainButtonStyle())
    }
}