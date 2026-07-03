// VisionMatte.swift — background removal on iOS via Apple's Vision person
// segmentation. This REPLACES RobustVideoMatting on this platform: RVM is
// GPL-3.0, which is incompatible with App Store distribution. Vision is
// native, hardware-accelerated, and costs zero bundle bytes.
//
// The engine's bg-remove seam receives a single-channel matte texture per
// frame, exactly like the desktop RVM path produces — downstream compositing
// is engine code and identical on both platforms.
import Vision
import CoreVideo

final class VisionMatte {
    private let request: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced          // .accurate for export passes
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()

    /// Returns an 8-bit alpha matte for the frame, or nil when no person.
    /// Called from the engine's bg-remove worker cadence (not every frame —
    /// same sequential/temporal strategy as the desktop RVM integration).
    func matte(for frame: CVPixelBuffer,
               quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced)
        -> CVPixelBuffer? {
        request.qualityLevel = quality
        let handler = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
        try? handler.perform([request])
        return request.results?.first?.pixelBuffer
    }
}
