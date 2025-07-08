//
//  ContentView.swift
//  WinDock
//
//  Created by  bar nuri on 06/07/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Win Dock is running in the background")
                .font(.headline)
                .padding()
            
            Text("Look for the dock at the bottom of your screen.")
                .foregroundColor(.secondary)
                .padding(.bottom)
            
            Button("Open Settings") {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            .padding()
            
            Button("Quit Win Dock") {
                NSApplication.shared.terminate(nil)
            }
            .padding()
        }
        .frame(width: 300, height: 200)
    }
}

#Preview {
    ContentView()
}
