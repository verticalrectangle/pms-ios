// VisionMatte.swift — background removal on iOS via Apple's Vision person
// segmentation. This REPLACES RobustVideoMatting on this platform: RVM is
// GPL-3.0, which is incompatible with App Store distribution. Vision is
// native, hardware-accelerated, and costs zero bundle bytes.
//
// The engine receives a single-channel (OneComponent8) matte per processed
// frame through pms_submit_person_matte — downstream compositing is engine
// Metal code and identical in preview and export.
//
// Threading: NOT thread-safe — call from one dedicated worker queue, never
// the camera delivery queue (Vision inference would stall frame delivery).
import Vision
import CoreVideo

final class VisionMatte {
    // One sequence handler for the session — Vision uses it for temporal
    // stability across frames (less matte flicker than per-frame handlers).
    private let sequence = VNSequenceRequestHandler()
    private let request: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced          // .accurate for export passes
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()

    /// Returns an 8-bit alpha matte for the frame, or nil when no person.
    /// The returned buffer is owned by the request until the next perform —
    /// the caller must hand it to the engine (which retains) before returning.
    func matte(for frame: CVPixelBuffer,
               quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced)
        -> CVPixelBuffer? {
        request.qualityLevel = quality
        do {
            try sequence.perform([request], on: frame)
        } catch {
            return nil
        }
        return request.results?.first?.pixelBuffer
    }
}
