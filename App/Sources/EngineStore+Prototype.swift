//  EngineStore+Prototype.swift
//  Dev-only conveniences layered on top of your EngineBridge.swift (EngineStore).
//  Under ENGINE_MOCK these let the SwiftUI screens feel alive before the real
//  xcframework exists; with the real engine they're inert (the `busy` event drives
//  the bar instead). Nothing here touches the C ABI — it only nudges @Published state.

import SwiftUI

extension EngineStore {

    /// Animate the `busy` bar the way a real long-running lever (stems, matting,
    /// transcription) reports progress through pms_poll_events -> case "busy".
    func simulateBusy(label: String, duration: TimeInterval = 2.6) {
        #if ENGINE_MOCK
        busy = (label, 0)
        let steps = 40
        for i in 1...steps {
            let p = Double(i) / Double(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * p) { [weak self] in
                guard let self else { return }
                self.busy = p < 1 ? (label, p) : nil
            }
        }
        #endif
    }

    /// Mock LUFS wobble so the master meter reads as live in previews.
    func startMockMeters() {
        #if ENGINE_MOCK
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.playing else { return }
            let m = -14.0 + Double.random(in: -4...3)
            self.masterLufs = (m, -13.8)
        }
        #endif
    }
}
