# Dev setup — accounts, machines, CI

## Apple account: free until distribution

A free Apple ID covers all development: Xcode, simulator, and installing on
your own iPhone (7-day re-sign, 3 sideloaded apps max). The $99/yr Developer
Program is only needed for TestFlight/App Store. Decision point: pay when
screens are worth sharing, not before.

## The 2020 MacBook 13"

Runs macOS 15 + Xcode 16 regardless of chip. If it's the M1: near-ideal —
arm64 like the phones, same GPU family for Metal work, fast simulator. If
Intel: builds are slower and the simulator runs x86 slices, but physical-
device debugging is identical. Either way it is the signing station and the
interactive-debug machine; CI does the heavy lifting.

**Recommended: register it as a self-hosted GitHub runner** (Settings →
Actions → Runners in the repo). Then agents push from anywhere and the
MacBook builds + runs proof gates automatically — same agent-driven loop as
the Linux rig. Label it `self-macos`; workflows can target it with
`runs-on: [self-hosted, self-macos]` when GitHub-hosted minutes or SDK
versions don't fit.

## CI (in place)

`.github/workflows/ci.yml`:
- **shaders** (Linux): re-transpiles the engine's GLSL and diffs against the
  committed MSL + checks docs/LEVERS.md freshness. Guards the
  single-source-of-truth rules.
- **app** (macOS, free on public repos): XcodeGen + simulator build with the
  engine mocked (optional-linked); uploads `PopMakerStudio-sim.zip` as an
  artifact — download it and drop it on any simulator
  (`xcrun simctl install booted PopMakerStudio.app`).

Phase 2 extends the `app` job: engine headless CMake build + `engine-smoke`
run become the gate (see AGENT_PLAYBOOK.md P2). Phase 3 adds the golden-
frame parity job.

## Debugging model

CI = builds + logs + proof gates, not stepping. Interactive debugging is
Xcode on the MacBook against a CI-built (or locally built) app. For engine
behavior, prefer the rig pattern over stepping: drive levers, read events,
diff pixels — those scripts run identically in CI.
