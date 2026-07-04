//  PopMakerApp.swift
//  App entry + root navigation (home ↔ editor). One EngineStore for the whole app,
//  started once; every screen reads its published state and sends levers back.
//
//  Build note: set ENGINE_MOCK in the target's Active Compilation Conditions until
//  pms_engine.xcframework exists — the screens run against the stub with canned
//  replies. Clearing the flag swaps in the real C ABI with zero screen changes.

import SwiftUI

@main
struct PopMakerApp: App {
    @StateObject private var engine = EngineStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear { engine.start() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: EngineStore
    @State private var open: Project?

    var body: some View {
        ZStack {
            AtmosphereView()
            if let project = open {
                EditorView(project: project, engine: engine) {
                    withAnimation(.easeInOut(duration: 0.3)) { open = nil }
                }
                .transition(.opacity)
            } else {
                HomeView { p in withAnimation(.easeInOut(duration: 0.3)) { open = p } }
                    .transition(.opacity)
            }
        }
    }
}
