// ContentView.swift — placeholder shell proving the engine loop: render
// view + transport + a couple of levers. The real screens (Home, Record,
// Timeline, FX browser, Export) are produced by the Claude design workflow
// against docs/LEVERS.md and replace this file's body incrementally.
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: EngineStore

    var body: some View {
        VStack(spacing: 0) {
            RenderView()
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .background(Color.black)
            HStack(spacing: 24) {
                Button {
                    engine.command(engine.playing ? "pause" : "play")
                } label: {
                    Image(systemName: engine.playing ? "pause.fill" : "play.fill")
                }
                Text(String(format: "%05.2f", engine.playhead))
                    .font(.system(.body, design: .monospaced))
                if let lufs = engine.masterLufs {
                    Text(String(format: "%.1f LUFS", lufs.momentary))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let busy = engine.busy {
                    ProgressView(busy.label, value: busy.progress)
                        .frame(maxWidth: 160)
                }
            }
            .padding()
        }
    }
}
