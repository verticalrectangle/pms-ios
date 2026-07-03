// PMSApp.swift — app entry. Owns the engine lifecycle; everything else
// observes EngineStore. Screens are designed by the Claude design workflow
// against docs/LEVERS.md and speak engine commands only.
import SwiftUI

@main
struct PMSApp: App {
    @StateObject private var engine = EngineStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear { engine.start() }
        }
    }
}
