//  HomeView.swift
//  Projects launch screen. Large collapsing title (VERTICAL RECTANGLE beneath),
//  sort chips, and glass project cards with deterministic thumbnails.

import SwiftUI
import UIKit

struct HomeView: View {
    let onOpen: (Project) -> Void
    @State private var sort: Sort = .recent
    @State private var showSettings = false
    // Circular theme reveal: a snapshot of the OLD theme, wiped away by a hole
    // growing from the toggle button — reveals the NEW theme underneath.
    @State private var revealImage: UIImage?
    @State private var revealRadius: CGFloat = 0
    @State private var toggleCenter = CGPoint(x: UIScreen.main.bounds.width - 40, y: 70)

    enum Sort: String, CaseIterable { case recent = "Recent", name = "Name", duration = "Duration", fx = "FX" }

    private var projects: [Project] {
        switch sort {
        case .recent:   return Sample.projects
        case .name:     return Sample.projects.sorted { $0.name < $1.name }
        case .duration: return Sample.projects.sorted { $0.duration > $1.duration }
        case .fx:       return Sample.projects.sorted { $0.fxCount > $1.fxCount }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title

                newProjectButton
                    .padding(.top, 22)

                HStack {
                    Text("Recent projects").font(.label(13)).foregroundStyle(Theme.txtMuted)
                    Spacer()
                    Text("\(Sample.projects.count)").font(.num(13)).foregroundStyle(Theme.txtMuted)
                }
                .padding(.top, 26).padding(.bottom, 10)

                HStack(spacing: 6) {
                    ForEach(Sort.allCases, id: \.self) { s in
                        Chip(text: s.rawValue, on: sort == s) { sort = s }
                    }
                }
                .padding(.bottom, 14)

                LazyVStack(spacing: 11) {
                    ForEach(projects) { p in
                        Button { onOpen(p) } label: { ProjectCard(project: p) }.pressable()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AtmosphereView().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)   // Home has its own big title
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button { toggleTheme() } label: {
                    Image(systemName: Theme.light ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.txtBody).frame(width: 44, height: 44).glass(14)
                }
                .pressable()
                .background(GeometryReader { g in
                    Color.clear.onAppear {
                        let f = g.frame(in: .global); toggleCenter = CGPoint(x: f.midX, y: f.midY)
                    }
                })
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.txtBody).frame(width: 44, height: 44).glass(14)
                }.pressable()
            }
            .padding(.trailing, 18).padding(.top, 4)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        // Circular reveal: old-theme snapshot on top, a hole growing from the
        // toggle button wipes it away to show the new theme underneath.
        .overlay {
            if let img = revealImage {
                Image(uiImage: img)
                    .resizable().ignoresSafeArea()
                    .mask {
                        ZStack {
                            Rectangle().fill(.black)
                            Circle()
                                .frame(width: revealRadius * 2, height: revealRadius * 2)
                                .position(toggleCenter)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup().ignoresSafeArea()
                    }
                    .ignoresSafeArea().allowsHitTesting(false).zIndex(999)
            }
        }
    }

    /// Tap the sun/moon: snapshot the current theme, flip, then wipe the snapshot
    /// away with a circle growing from the button — the new theme reveals through it.
    private func toggleTheme() {
        guard let snap = snapshotWindow() else {
            Palette.shared.mode = Theme.light ? .dark : .light; return   // fallback: plain flip
        }
        revealRadius = 0
        revealImage = snap
        Palette.shared.mode = Theme.light ? .dark : .light   // new theme renders UNDER the snapshot
        let s = UIScreen.main.bounds.size, c = toggleCenter
        let maxR = max(hypot(c.x, c.y), hypot(s.width - c.x, c.y),
                       hypot(c.x, s.height - c.y), hypot(s.width - c.x, s.height - c.y)) + 24
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.52)) { revealRadius = maxR }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            revealImage = nil; revealRadius = 0
        }
    }

    private func snapshotWindow() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.opaque = true
        return UIGraphicsImageRenderer(bounds: window.bounds, format: fmt).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pop Maker\nStudio")
                .font(.disp(52)).tracking(-1).textCase(.uppercase)
                .foregroundStyle(Theme.txt).lineSpacing(-4)
            Text("Vertical Rectangle")
                .font(.label(15)).textCase(.uppercase).foregroundStyle(Theme.txt)
        }
    }

    private var newProjectButton: some View {
        Button {
            onOpen(Project.blank())
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .glass(13, active: true)
                Text("New Project").font(.disp(18)).textCase(.uppercase).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.txtGhost)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glass(18)
        }
        .pressable()
    }
}

// MARK: - Settings (theme mode + accent)

struct SettingsSheet: View {
    @Bindable private var palette = Palette.shared
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.adaptive(minimum: 52), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("THEME") {
                        Picker("", selection: $palette.mode) {
                            Text("System").tag(Palette.Mode.system)
                            Text("Light").tag(Palette.Mode.light)
                            Text("Dark").tag(Palette.Mode.dark)
                        }
                        .pickerStyle(.segmented)
                    }
                    section("ACCENT") {
                        LazyVGrid(columns: cols, spacing: 16) {
                            ForEach(Palette.presets, id: \.name) { p in
                                Button { palette.accent = p.color } label: {
                                    Circle().fill(p.color).frame(width: 44, height: 44)
                                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Palette.matches(palette.accent, p.color) ? 3 : 0))
                                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                                        .shadow(color: p.color.opacity(0.55), radius: 8)
                                }.pressable()
                            }
                        }
                        ColorPicker("Custom color", selection: $palette.accent, supportsOpacity: false)
                            .font(.disp(15)).foregroundStyle(Theme.txt).padding(.top, 8)
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
            .background(AtmosphereView().ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(palette.scheme)
    }

    @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.label(10)).foregroundStyle(Theme.txtMuted)
            content()
        }
    }
}

struct ProjectCard: View {
    let project: Project
    var body: some View {
        HStack(spacing: 13) {
            AsyncImage(url: project.thumbURL) { img in
                img.resizable().scaledToFill()
            } placeholder: { Theme.line }
            .frame(width: 52, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
            .overlay(alignment: .bottomLeading) {
                Text(timecode(project.duration))
                    .font(.num(10.5)).foregroundStyle(.white)
                    .shadow(color: .black, radius: 2).padding(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    if project.live {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                            .shadow(color: Theme.accent, radius: 4)
                    }
                    Text(project.name).font(.disp(17)).textCase(.uppercase).foregroundStyle(.white)
                }
                Text(project.sub).font(.num(13)).foregroundStyle(Theme.txtMuted).lineLimit(1)
                HStack(spacing: 8) {
                    MetaChip(project.format.rawValue)
                    MetaChip("\(project.clipCount) CLIPS")
                    MetaChip("\(project.fxCount) FX")
                }
                .padding(.top, 7)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing) {
                Image(systemName: "ellipsis").foregroundStyle(Theme.txtGhost).font(.system(size: 15))
                Spacer()
                Text(project.updated).font(.num(11)).foregroundStyle(Theme.txtGhost)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .glass(Theme.rCard, sheer: true)   // depth: orbs glow through the card
    }
}

// MARK: - small controls

struct Chip: View {
    let text: String; var on: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.label(10))
                .foregroundStyle(on ? Theme.accent : Color.black.opacity(0.55))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(on ? Theme.accentA(0.08) : .clear))
                .overlay(Capsule().strokeBorder(on ? Theme.accentA(0.5) : Color.black.opacity(0.18), lineWidth: 1))
        }
    }
}

struct MetaChip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.label(9))
            .foregroundStyle(Theme.txtBody)   // was black-on-dark → invisible
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

func timecode(_ t: Double) -> String {
    let m = Int(t) / 60, s = Int(t) % 60
    return String(format: "%d:%02d", m, s)
}
func fullTC(_ t: Double) -> String {
    let m = Int(t) / 60, s = Int(t) % 60, f = Int((t.truncatingRemainder(dividingBy: 1)) * 30)
    return String(format: "%02d:%02d:%02d", m, s, f)
}
