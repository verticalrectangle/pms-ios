//  StillVideoWriter.swift
//  Encodes a single CVPixelBuffer as a short silent .mov. Used by photo
//  capture so still frames flow through the same video pipeline as recorded
//  takes (thumbnails, composition, export, and orientation).
import AVFoundation
import CoreVideo

final class StillVideoWriter {
    private let pixelBuffer: CVPixelBuffer
    private let url: URL
    private let duration: CMTime
    private let width: Int
    private let height: Int

    init(pixelBuffer: CVPixelBuffer, url: URL, duration: Double) {
        self.pixelBuffer = pixelBuffer
        self.url = url
        self.duration = CMTime(seconds: duration, preferredTimescale: 600)
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        self.height = CVPixelBufferGetHeight(pixelBuffer)
    }

    /// Write a 3-second H.264 video by appending the same frame at t=0 and
    /// t=duration. The duplicated end frame gives the track a non-zero duration
    /// without requiring extra frame generation.
    func write(completion: @escaping (URL?) -> Void) {
        try? FileManager.default.removeItem(at: url)

        do {
            let writer = try AVAssetWriter(url: url, fileType: .mov)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: CameraCapture.recordingBitrate(width: width, height: height)
                ]
            ]

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = false

            let sourceAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: sourceAttributes
            )

            guard writer.canAdd(videoInput) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            writer.add(videoInput)

            guard writer.startWriting() else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            writer.startSession(atSourceTime: .zero)

            let endFrame = duration
            guard videoInput.isReadyForMoreMediaData,
                  adaptor.append(pixelBuffer, withPresentationTime: .zero) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard videoInput.isReadyForMoreMediaData,
                  adaptor.append(pixelBuffer, withPresentationTime: endFrame) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            videoInput.markAsFinished()
            let w = writer
            w.finishWriting {
                let ok = w.status == .completed
                DispatchQueue.main.async { completion(ok ? w.outputURL : nil) }
            }
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
