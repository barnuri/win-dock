import SwiftUI
import AppKit

struct TaskViewButton: View {
    var body: some View {
        Button(action: {}) {
            Image(systemName: "rectangle.3.offgrid")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.gray.opacity(0.3)))
        }
        .buttonStyle(PlainButtonStyle())
    }
}