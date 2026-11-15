import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Writes a scene as an H.264 video, a poster and the frames the GIF is made from.

enum Output {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A bitmap context whose user space is the 1920 x 1200 design, top-left origin, scaled to `width` pixels.
    static func context(width: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0,
                        info: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue) -> CGContext {
        let scale = CGFloat(width) / Renderer.size.width
        let height = Int((Renderer.size.height * scale).rounded())
        let ctx = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: sRGB, bitmapInfo: info)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        return ctx
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
    }

    /// The first frame at full size, transparent outside the rounded frame.
    static func poster(_ renderer: Renderer, to url: URL) {
        let ctx = context(width: 1920)
        renderer.draw(ctx, at: 0, opaque: false)
        writePNG(ctx.makeImage()!, to: url)
    }

    /// Frames for the GIF, as PNGs named 00000.png and on, `fps` a second at `width` pixels.
    static func frames(_ renderer: Renderer, fps: Int, width: Int, into folder: URL) -> Int {
        try? FileManager.default.removeItem(at: folder)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let count = Int((renderer.scene.timeline.duration * Double(fps)).rounded())
        for i in 0..<count {
            let ctx = context(width: width)
            renderer.draw(ctx, at: Double(i) / Double(fps), opaque: false)
            writePNG(ctx.makeImage()!, to: folder.appending(path: String(format: "%05d.png", i)))
        }
        return count
    }

    /// H.264 at 1920 x 1200, `fps` a second, navy outside the rounded frame.
    static func video(_ renderer: Renderer, fps: Int, bitrate: Int, to url: URL) {
        try? FileManager.default.removeItem(at: url)
        let width = 1920, height = 1200
        let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 4,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { fatalError("could not start \(url.path): \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
        let count = Int((renderer.scene.timeline.duration * Double(fps)).rounded())
        for i in 0..<count {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { fatalError("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = context(width: width, data: CVPixelBufferGetBaseAddress(buffer),
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                              info: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            renderer.draw(ctx, at: Double(i) / Double(fps), opaque: true)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))) else {
                fatalError("could not append frame \(i): \(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(count), timescale: CMTimeScale(fps)))
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { fatalError("could not finish \(url.path): \(String(describing: writer.error))") }
    }
}
