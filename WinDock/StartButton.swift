import SwiftUI
import AppKit

struct StartButton: View {
    @State private var showStartMenu = false
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: { showStartMenu.toggle() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundFill)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isHovered ? Color.blue.opacity(0.4) : Color.clear, 
                                lineWidth: 0.5
                            )
                    )
                    .shadow(
                        color: showStartMenu ? Color.blue.opacity(0.15) : Color.clear,
                        radius: showStartMenu ? 4 : 0,
                        x: 0,
                        y: 1
                    )
                
                Image(systemName: "apple.logo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)
                    .brightness(isHovered ? 0.1 : 0.0)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.08)) {
                isPressed = pressing
            }
        }, perform: {})
        .help("Start Menu")
        .popover(isPresented: $showStartMenu, arrowEdge: .top) {
            StartMenuView()
        }
    }
    
    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(Color.blue.opacity(0.25))
        }
        if showStartMenu {
            return AnyShapeStyle(Color.blue.opacity(0.2))
        }
        if isHovered {
            return AnyShapeStyle(Color.blue.opacity(0.12))
        }
        return AnyShapeStyle(Color.clear)
    }
}

#Preview {
    StartButton()
        .preferredColorScheme(.light)
}
