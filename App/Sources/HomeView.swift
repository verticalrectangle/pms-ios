//  HomeView.swift
//  Projects launch screen. Large collapsing title (VERTICAL RECTANGLE beneath),
//  sort chips, and glass project cards with deterministic thumbnails.

import SwiftUI

struct HomeView: View {
    let onOpen: (Project) -> Void
    @State private var sort: Sort = .recent

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
                    Text("Recent projects").font(.label(9)).tracking(2).foregroundStyle(Theme.txtMuted)
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
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pop Maker\nStudio")
                .font(.disp(52)).tracking(-1).textCase(.uppercase)
                .foregroundStyle(Theme.txt).lineSpacing(-4)
            Text("Vertical Rectangle")
                .font(.label(10)).tracking(1.8).foregroundStyle(Theme.txtMuted)
        }
    }

    private var newProjectButton: some View {
        Button {
            onOpen(Sample.projects[0])
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
        .glass(Theme.rCard)
    }
}

// MARK: - small controls

struct Chip: View {
    let text: String; var on: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.label(10)).tracking(1.2)
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
        Text(text).font(.label(9)).tracking(1)
            .foregroundStyle(Color.black.opacity(0.55))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.18), lineWidth: 1))
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
