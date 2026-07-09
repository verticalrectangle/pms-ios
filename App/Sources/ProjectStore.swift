//  ProjectStore.swift
//  Project persistence = the ENGINE's binary v64 .pms (save_project /
//  load_project). This file owns only what is explicitly not .pms: sandbox
//  paths, media copying, the poster sidecar, and a display-name sidecar
//  (the engine has no project-name field — the .pms stem is always
//  "project.pms" in our layout).
//  Home-card metadata comes from the engine's read-only get_project_summary,
//  so the open project in the singleton engine is never disturbed.

import Foundation

/// Lightweight entry for the Home list. `error` non-nil = the project exists
/// on disk but its .pms could not be summarized (corrupt/unreadable) — shown,
/// never silently omitted.
struct ProjectMeta: Identifiable {
    let id: String
    let name: String
    let format: Format
    let duration: Double
    let clipCount: Int
    let fxCount: Int
    let updated: Date
    let posterURL: URL?
    var error: String? = nil
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
    static func nameURL(_ id: String) -> URL { dir(id).appendingPathComponent("name.txt") }
    static func exists(_ id: String) -> Bool { fm.fileExists(atPath: docURL(id).path) }

    /// Per-project cache dir (filmstrips etc.) — purgeable, never in Documents.
    static func cacheDir(_ id: String) -> URL {
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProjectCache", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: engine-backed persistence

    static func save(engine: EngineStore, id: String, name: String) throws {
        try fm.createDirectory(at: dir(id), withIntermediateDirectories: true)
        _ = try engine.result("save_project", ["path": docURL(id).path])
        try? name.data(using: .utf8)?.write(to: nameURL(id), options: .atomic)
    }

    static func load(engine: EngineStore, id: String) throws {
        _ = try engine.result("load_project", ["path": docURL(id).path])
    }

    static func name(_ id: String) -> String {
        (try? String(contentsOf: nameURL(id), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
    }

    static func rename(_ id: String, _ name: String) {
        try? name.data(using: .utf8)?.write(to: nameURL(id), options: .atomic)
    }

    /// Copy an imported movie into the project's media/ dir; return its ABSOLUTE URL.
    static func importMedia(_ src: URL, into id: String) -> URL {
        var dst = mediaDir(id).appendingPathComponent(src.lastPathComponent)
        // Never silently reuse a different file of the same name.
        if src != dst, fm.fileExists(atPath: dst.path) {
            let stem = src.deletingPathExtension().lastPathComponent
            dst = mediaDir(id).appendingPathComponent(
                "\(stem)-\(UUID().uuidString.prefix(6)).\(src.pathExtension)")
        }
        if src != dst { try? fm.copyItem(at: src, to: dst) }
        return dst
    }

    static func writePoster(_ jpeg: Data, id: String) {
        try? fm.createDirectory(at: dir(id), withIntermediateDirectories: true)
        try? jpeg.write(to: posterURL(id), options: .atomic)
    }

    static func delete(_ id: String) {
        try? fm.removeItem(at: dir(id))
        try? fm.removeItem(at: cacheDir(id))
    }

    // MARK: home list (engine read-only summaries)

    /// Scan Documents/Projects and summarize each .pms through the engine's
    /// read-only get_project_summary — the open project is not disturbed.
    /// Corrupt projects come back with `error` set, newest first.
    static func list(engine: EngineStore) -> [ProjectMeta] {
        guard let ids = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return ids.compactMap { id -> ProjectMeta? in
            let doc = docURL(id)
            guard fm.fileExists(atPath: doc.path) else { return nil }
            let poster = posterURL(id)
            let posterOrNil = fm.fileExists(atPath: poster.path) ? poster : nil
            let displayName = name(id)
            do {
                let s = try engine.resultObject("get_project_summary", ["path": doc.path])
                return ProjectMeta(
                    id: id,
                    name: displayName,
                    format: Format(engineFormat: s["format"] as? String ?? "vertical"),
                    duration: (s["duration"] as? Double) ?? 0,
                    clipCount: (s["clip_count"] as? Int) ?? 0,
                    fxCount: (s["fx_count"] as? Int) ?? 0,
                    updated: Date(timeIntervalSince1970: Double((s["modified_unix"] as? Int) ?? 0)),
                    posterURL: posterOrNil)
            } catch {
                let mtime = (try? fm.attributesOfItem(atPath: doc.path)[.modificationDate] as? Date)
                    .flatMap { $0 } ?? .distantPast
                return ProjectMeta(id: id, name: displayName, format: .portrait,
                                   duration: 0, clipCount: 0, fxCount: 0,
                                   updated: mtime, posterURL: posterOrNil,
                                   error: error.localizedDescription)
            }
        }
        .sorted { $0.updated > $1.updated }
    }
}
