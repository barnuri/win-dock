//
//  ContentView.swift
//  WinDock
//
//  Created by  bar nuri on 06/07/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var runningApps: [NSRunningApplication] = []
    @State private var hoveredApp: NSRunningApplication? = nil

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ForEach(runningApps, id: \ .processIdentifier) { app in
                    if let icon = app.icon {
                        Button(action: {
                            app.activate(options: [.activateIgnoringOtherApps])
                        }) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .onHover { hovering in
                                    hoveredApp = hovering ? app : nil
                                }
                        }
                    }
                }
            }
            .padding()
            .background(Material.ultraThin)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.black.opacity(0.8))
            .overlay(
                Group {
                    if let app = hoveredApp, let icon = app.icon {
                        VStack {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(app.localizedName ?? "Unknown App")
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.9))
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .transition(.opacity)
                    }
                }, alignment: .top
            )
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear(perform: setupWindow)
    }

    private func loadRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private func setupWindow() {
        loadRunningApps()

        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(contentRect: CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 60),
                            styleMask: [.nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: self)
        panel.makeKeyAndOrderFront(nil)
    }
}

#Preview {
    ContentView()
}
