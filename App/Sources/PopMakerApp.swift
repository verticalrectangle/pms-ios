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
                .onAppear {
                    engine.start()
                    IPCServer.shared.start(engine: engine)   // dev/agent command server
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: EngineStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var openProject: Project?
    @State private var openIntoRecord = false   // Home's camera button → editor with RecordView up
    @State private var rescanToken = 0   // bumped on every editor pop → Home re-scans recents

    var body: some View {
        // Native navigation: Home is the root, the editor is a pushed detail —
        // so it gets the system nav bar (back + share) and bottom bar for free,
        // with proper Liquid Glass + safe-area handling on iOS 26.
        // NOTE: NavigationStack keeps the root alive across push/pop, so
        // HomeView.onAppear does NOT re-fire on back-navigation. The onChange
        // below is the rescan trigger (nil = popped back to Home).
        NavigationStack {
            HomeView(onOpen: { p in
                openIntoRecord = false
                openProject = p
            }, onRecord: { p in
                openIntoRecord = true
                openProject = p
            }, rescanToken: rescanToken)
            .navigationDestination(item: $openProject) { project in
                EditorView(project: project, engine: engine, autoRecord: openIntoRecord)
            }
        }
        .onChange(of: openProject) { _, p in if p == nil { rescanToken += 1 } }
        .tint(Theme.accent)
        .preferredColorScheme(Palette.shared.scheme)   // nil in system mode → iOS drives
        .onAppear { Palette.shared.systemDark = colorScheme == .dark }
        .onChange(of: colorScheme) { _, s in Palette.shared.systemDark = s == .dark }
    }
}
