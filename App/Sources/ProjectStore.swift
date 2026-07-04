//  ProjectStore.swift
//  Real .pms persistence, ported from pop-maker-studio's project.cpp design:
//  a versioned document (monotonic version, additive + version-gated on read),
//  Track::kind persisted while managed/transient state is not, markers-as-chapters,
//  and media collected into a media/ folder beside the .pms (desktop collect_project).
//  iOS twist: media is referenced by RELATIVE filename and resolved at load, because
//  the app container's absolute path changes between launches.

import Foundation

/// The serialized project — mirrors project.cpp's top level (version, format, bpm,
/// duration, tracks[], markers/chapters). JSON here (vs the desktop's binary blob),
/// same additive/version-gated design so old files keep loading as fields are added.
struct ProjectDoc: Codable {
    static let currentVersion = 1     // monotonic; bump + gate new fields on read

    var version = ProjectDoc.currentVersion
    var name: String
    var format: Format
    var bpm: Double
    var duration: Double
    var tracks: [Track]
    var chapters: [ChapterMarker]
    var updated: Date = Date()
}

/// Lightweight entry for the Home list, scanned from disk.
struct ProjectMeta: Identifiable {
    let id: String
    let name: String
    let format: Format
    let duration: Double
    let clipCount: Int
    let fxCount: Int
    let updated: Date
    let posterURL: URL?
}

enum ProjectStore {
    private static let fm = FileManager.default

    static var root: URL {
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    static func mediaDir(_ id: String) -> URL {
        let d = dir(id).appendingPathComponent("media", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func docURL(_ id: String) -> URL { dir(id).appendingPathComponent("project.pms") }
    static func posterURL(_ id: String) -> URL { dir(id).appendingPathComponent("poster.jpg") }
    static func exists(_ id: String) -> Bool { fm.fileExists(atPath: docURL(id).path) }

    static func save(_ doc: ProjectDoc, id: String) {
        try? fm.createDirectory(at: dir(id), withIntermediateDirectories: true)
        var d = doc; d.updated = Date()
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(d) { try? data.write(to: docURL(id), options: .atomic) }
    }

    /// Load + relink: resolve each clip's `mediaFile` to an ABSOLUTE URL under this
    /// project's media/ dir at the CURRENT container path (the iOS relink the desktop lacks).
    static func load(_ id: String) -> ProjectDoc? {
        guard let data = try? Data(contentsOf: docURL(id)),
              var doc = try? JSONDecoder().decode(ProjectDoc.self, from: data) else { return nil }
        let media = mediaDir(id)
        for ti in doc.tracks.indices {
            for ci in doc.tracks[ti].clips.indices where doc.tracks[ti].clips[ci].mediaFile != nil {
                doc.tracks[ti].clips[ci].sourceURL =
                    media.appendingPathComponent(doc.tracks[ti].clips[ci].mediaFile!)
            }
        }
        return doc
    }

    /// Copy an imported movie into the project's media/ dir; return its ABSOLUTE URL.
    static func importMedia(_ src: URL, into id: String) -> URL {
        let dst = mediaDir(id).appendingPathComponent(src.lastPathComponent)
        if src != dst, !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: src, to: dst) }
        return dst
    }

    static func writePoster(_ jpeg: Data, id: String) {
        try? fm.createDirectory(at: dir(id), withIntermediateDirectories: true)
        try? jpeg.write(to: posterURL(id), options: .atomic)
    }

    static func delete(_ id: String) { try? fm.removeItem(at: dir(id)) }

    /// Scan Documents/Projects for saved projects, newest first.
    static func list() -> [ProjectMeta] {
        guard let ids = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return ids.compactMap { id -> ProjectMeta? in
            guard let doc = load(id) else { return nil }
            let clips = doc.tracks.filter { $0.kind == .video }.reduce(0) { $0 + $1.clips.count }
            let fx = doc.tracks.reduce(0) { $0 + $1.bricks.count }
            let poster = posterURL(id)
            return ProjectMeta(id: id, name: doc.name, format: doc.format, duration: doc.duration,
                               clipCount: clips, fxCount: fx, updated: doc.updated,
                               posterURL: fm.fileExists(atPath: poster.path) ? poster : nil)
        }.sorted { $0.updated > $1.updated }
    }
}
