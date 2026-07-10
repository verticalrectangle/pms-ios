// MakeupStudio.swift — the makeup creation studio. A MakeupSpec is the full
// parametric BeautyLook the engine's face_fx passes consume (skin, shape,
// procedural makeup, colors, plus an optional UV makeup texture); the sheet
// edits it live on the camera, and saved specs become user looks in the
// Makeup rail. This is the "compose your own filter" layer over the shared
// engine — no per-look shader or enum work anywhere.
import SwiftUI

// MARK: - Spec

struct MakeupSpec: Codable, Equatable {
    // skin
    var smooth = 0.55, brighten = 0.25, warmth = 0.1, eyePop = 0.3
    // shape (morphs)
    var eyes = 0.08, cheek = 0.05, vline = 0.10, nose = 0.10,
        lipsPlump = 0.04, chinSmooth = 0.3, jawShade = 0.0
    // procedural makeup
    var blush = 0.15, lip = 0.12, lash = 0.35, liner = 0.2, lashWing = 0.2,
        noseBlush = 0.0, freckles = 0.0, lipGrad = 1.0
    var blushColor = RGB(r: 1.0, g: 0.45, b: 0.55)
    var lipColor   = RGB(r: 0.95, g: 0.25, b: 0.35)
    // cyber extras
    var eyeGlow = 0.0, skinTint = 0.0, desat = 0.0, chrome = 0.0, scanlines = 0.0
    // painted UV texture (models/face/makeup_*.png), nil = procedural only
    var makeupTex: String?

    struct RGB: Codable, Equatable {
        var r: Double, g: Double, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    /// face_fx live-stack params (BeautyLook field names — see face_look_from
    /// in metal_render.mm).
    var params: [String: Double] {
        [
            "smooth": smooth, "brighten": brighten, "warmth": warmth, "eye_pop": eyePop,
            "eyes": eyes, "cheek": cheek, "vline": vline, "nose": nose,
            "lips_plump": lipsPlump, "chin_smooth": chinSmooth, "jaw_shade": jawShade,
            "blush": blush, "lip": lip, "lash": lash, "liner": liner,
            "lash_wing": lashWing, "nose_blush": noseBlush, "freckles": freckles,
            "lip_grad": lipGrad,
            "blush_r": blushColor.r, "blush_g": blushColor.g, "blush_b": blushColor.b,
            "lip_r": lipColor.r, "lip_g": lipColor.g, "lip_b": lipColor.b,
            "eye_glow": eyeGlow, "skin_tint": skinTint, "desat": desat,
            "chrome": chrome, "scanlines": scanlines,
        ]
    }

    /// Seed the studio from a preset look's face entry so edits start from
    /// what's on screen. Preset ints (face_filter) start from the defaults —
    /// their recipes live engine-side.
    init() {}
    init(fromLookEntry params: [String: Double], makeupTex: String?) {
        self.init()
        func take(_ k: String, _ dst: inout Double) { if let v = params[k] { dst = v } }
        take("smooth", &smooth); take("brighten", &brighten); take("warmth", &warmth)
        take("eye_pop", &eyePop)
        take("eyes", &eyes); take("cheek", &cheek); take("vline", &vline)
        take("nose", &nose); take("lips_plump", &lipsPlump)
        take("chin_smooth", &chinSmooth); take("jaw_shade", &jawShade)
        take("blush", &blush); take("lip", &lip); take("lash", &lash)
        take("liner", &liner); take("lash_wing", &lashWing)
        take("nose_blush", &noseBlush); take("freckles", &freckles)
        take("lip_grad", &lipGrad)
        take("blush_r", &blushColor.r); take("blush_g", &blushColor.g); take("blush_b", &blushColor.b)
        take("lip_r", &lipColor.r); take("lip_g", &lipColor.g); take("lip_b", &lipColor.b)
        take("eye_glow", &eyeGlow); take("skin_tint", &skinTint)
        take("desat", &desat); take("chrome", &chrome); take("scanlines", &scanlines)
        self.makeupTex = makeupTex
    }
}

// MARK: - Saved custom looks

struct SavedLook: Codable, Identifiable {
    var id: String
    var name: String
    var spec: MakeupSpec

    var asLook: Look {
        Look(id: "custom_\(id)", name: name, icon: "person.crop.circle.badge.checkmark",
             categories: [.makeup],
             stack: [.init(fx: "face_fx", params: spec.params, makeupTex: spec.makeupTex)])
    }
}

enum CustomLookStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("makeup_looks.json")
    }
    static func load() -> [SavedLook] {
        guard let data = try? Data(contentsOf: url),
              let looks = try? JSONDecoder().decode([SavedLook].self, from: data) else { return [] }
        return looks
    }
    static func save(_ looks: [SavedLook]) {
        if let data = try? JSONEncoder().encode(looks) { try? data.write(to: url) }
    }
    static func add(name: String, spec: MakeupSpec) -> SavedLook {
        var looks = load()
        let saved = SavedLook(id: UUID().uuidString, name: name, spec: spec)
        looks.append(saved)
        save(looks)
        return saved
    }
    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }
}

// MARK: - Studio sheet

struct MakeupStudioSheet: View {
    @Binding var spec: MakeupSpec
    let onChange: () -> Void
    let onSave: (String, MakeupSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saveName = ""
    @State private var showSave = false

    /// Textures painted by tools/gen_makeup_elements.py + the douyin classic.
    static let textures: [(String?, String)] = [
        (nil, "None"),
        ("makeup_douyin.png", "Douyin"),
        ("makeup_doll_pink.png", "Doll Pink"),
        ("makeup_egirl.png", "E-Girl"),
        ("makeup_glam_contour.png", "Glam"),
        ("makeup_coquette.png", "Coquette"),
        ("makeup_goth.png", "Goth"),
        ("makeup_peach.png", "Peach"),
        ("makeup_cold_beauty.png", "Cold"),
        ("makeup_sunset.png", "Sunset"),
        ("makeup_angel.png", "Angel"),
        ("makeup_baddie.png", "Baddie"),
        ("makeup_cyber_chrome.png", "Chrome"),
        ("makeup_hearts_freckles.png", "Freckles"),
        ("makeup_clean_girl.png", "Clean Girl"),
        ("makeup_soft_glam_nude.png", "Soft Glam Nude"),
        ("makeup_bronze_sculpt.png", "Bronze Sculpt"),
        ("makeup_latte.png", "Latte"),
        ("makeup_rosewood.png", "Rosewood"),
        ("makeup_champagne_glow.png", "Champagne Glow"),
        ("makeup_peach_sorbet.png", "Peach Sorbet"),
        ("makeup_berry_bitten.png", "Berry Bitten"),
        ("makeup_cherry_gloss.png", "Cherry Gloss"),
        ("makeup_terracotta_smoke.png", "Terracotta Smoke"),
        ("makeup_emerald_smoke.png", "Emerald Smoke"),
        ("makeup_sapphire_night.png", "Sapphire Night"),
        ("makeup_plum_velvet.png", "Plum Velvet"),
        ("makeup_mocha_siren.png", "Mocha Siren"),
        ("makeup_romantic_rose.png", "Romantic Rose"),
        ("makeup_ballet_pink.png", "Ballet Pink"),
        ("makeup_sunkissed_freckles.png", "Sunkissed Freckles"),
        ("makeup_grunge_smoke.png", "Grunge Smoke"),
        ("makeup_midnight_goth.png", "Midnight Goth"),
        ("makeup_opal_fantasy.png", "Opal Fantasy"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Makeup Plate") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.textures, id: \.1) { tex, label in
                                Button {
                                    spec.makeupTex = tex; onChange()
                                } label: {
                                    Text(label)
                                        .font(.label(11))
                                        .foregroundStyle(spec.makeupTex == tex ? .black : Theme.txt)
                                        .padding(.horizontal, 11).padding(.vertical, 7)
                                        .background(Capsule().fill(spec.makeupTex == tex ?
                                            AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12))))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Skin") {
                    row("Smooth", $spec.smooth)
                    row("Brighten", $spec.brighten, max: 0.6)
                    row("Warmth", $spec.warmth)
                    row("Eye Pop", $spec.eyePop)
                }
                Section("Shape") {
                    row("Doll Eyes", $spec.eyes, max: 0.3)
                    row("Cheek Slim", $spec.cheek, max: 0.25)
                    row("V-Line Jaw", $spec.vline, max: 0.4)
                    row("Nose Slim", $spec.nose, max: 0.35)
                    row("Lip Plump", $spec.lipsPlump, max: 0.2)
                    row("Chin Retouch", $spec.chinSmooth)
                }
                Section("Makeup") {
                    row("Blush", $spec.blush)
                    ColorPicker("Blush Color", selection: colorBinding(\.blushColor),
                                supportsOpacity: false)
                    row("Lip Tint", $spec.lip)
                    ColorPicker("Lip Color", selection: colorBinding(\.lipColor),
                                supportsOpacity: false)
                    row("Bitten Lip", $spec.lipGrad)
                    row("Lashes", $spec.lash)
                    row("Eyeliner", $spec.liner)
                    row("Wing", $spec.lashWing)
                    row("Nose Blush", $spec.noseBlush)
                    row("Freckles", $spec.freckles)
                    row("Contour Shade", $spec.jawShade)
                }
                Section("Cyber") {
                    row("Eye Glow", $spec.eyeGlow)
                    row("Chrome Skin", $spec.chrome)
                    row("Desaturate", $spec.desat)
                    row("Scanlines", $spec.scanlines)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AtmosphereView().ignoresSafeArea())
            .navigationTitle("Makeup Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSave = true } label: {
                        Label("Save Look", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .alert("Save Look", isPresented: $showSave) {
                TextField("Look name", text: $saveName)
                Button("Save") {
                    let name = saveName.trimmingCharacters(in: .whitespaces)
                    onSave(name.isEmpty ? "My Look" : name, spec)
                    saveName = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Adds this look to your Makeup rail.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .large))   // camera stays live behind
    }

    private func row(_ label: String, _ value: Binding<Double>, max: Double = 1.0) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.label(12)).foregroundStyle(Theme.txt)
                .frame(width: 104, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = $0; onChange() }),
                   in: 0...max)
                .tint(Theme.accent)
            Text("\(Int(value.wrappedValue / max * 100))")
                .font(.num(10)).foregroundStyle(Theme.txtMuted)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func colorBinding(_ path: WritableKeyPath<MakeupSpec, MakeupSpec.RGB>) -> Binding<Color> {
        Binding(
            get: { spec[keyPath: path].color },
            set: { new in
                let ui = UIColor(new)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                spec[keyPath: path] = MakeupSpec.RGB(r: r, g: g, b: b)
                onChange()
            })
    }
}
