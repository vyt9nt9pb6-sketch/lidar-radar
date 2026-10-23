import CoreMedia
import CoreVideo
import UIKit

/// 子母畫面裡的一張卡片。只畫距離或「已暫停」，不畫相機畫面。
enum PiPCard: Equatable {
    case live(distance: String, emoji: String, level: DangerLevel)
    case paused
}

/// 把卡片畫進 CVPixelBuffer，再包成 AVSampleBufferDisplayLayer 能播的 sample。
///
/// 緩衝區要有 IOSurface，否則圖層會拒絕 enqueue。三張輪流用，避免上一張還在顯示就改到同一塊記憶體。
final class DistanceCardRenderer {
    static let width = 640
    static let height = 360

    private var buffers: [CVPixelBuffer] = []
    private var cursor = 0
    private var format: CMVideoFormatDescription?

    init() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        for _ in 0..<3 {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Self.width,
                Self.height,
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &buffer
            )
            if status == kCVReturnSuccess, let buffer {
                buffers.append(buffer)
            }
        }
        if let first = buffers.first {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: first,
                formatDescriptionOut: &format
            )
        }
    }

    func makeSample(for card: PiPCard, presentationTime: CMTime) -> CMSampleBuffer? {
        guard !buffers.isEmpty, let format else { return nil }
        let buffer = buffers[cursor % buffers.count]
        cursor += 1
        draw(card, into: buffer)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 8),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard status == noErr else { return nil }
        return sample
    }

    private func draw(_ card: PiPCard, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // 翻成 UIKit 的左上原點，文字才不會倒過來。
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1).cgColor)
        context.fill(canvas)

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        switch card {
        case .live(let distance, let emoji, let level):
            let accent = Self.color(for: level)
            context.setFillColor(accent.withAlphaComponent(0.22).cgColor)
            context.fill(canvas)
            context.setFillColor(accent.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 18, height: height))
            draw(emoji, in: CGRect(x: 36, y: 80, width: 180, height: 200), size: 112, color: .white, alignment: .center)
            draw(distance, in: CGRect(x: 210, y: 78, width: 400, height: 150), size: 104, color: .white, alignment: .left)
            draw(
                L10n.radarMeters,
                in: CGRect(x: 218, y: 230, width: 380, height: 60),
                size: 32,
                color: UIColor.white.withAlphaComponent(0.78),
                alignment: .left
            )
        case .paused:
            context.setFillColor(UIColor(white: 0.16, alpha: 1).cgColor)
            context.fill(canvas)
            draw(
                L10n.pipPausedTitle,
                in: CGRect(x: 32, y: 90, width: CGFloat(width - 64), height: 100),
                size: 64,
                color: .white,
                alignment: .center
            )
            draw(
                L10n.pipPausedHint,
                in: CGRect(x: 32, y: 200, width: CGFloat(width - 64), height: 70),
                size: 32,
                color: UIColor.white.withAlphaComponent(0.82),
                alignment: .center
            )
        }
    }

    private func draw(_ text: String, in rect: CGRect, size: CGFloat, color: UIColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
    }

    private static func color(for level: DangerLevel) -> UIColor {
        switch level {
        case .safe:
            return UIColor(red: 0.24, green: 0.86, blue: 0.59, alpha: 1)
        case .warning:
            return UIColor(red: 0.98, green: 0.76, blue: 0.28, alpha: 1)
        case .danger:
            return UIColor(red: 1, green: 0.34, blue: 0.36, alpha: 1)
        case .unknown:
            return UIColor(red: 0.62, green: 0.67, blue: 0.74, alpha: 1)
        }
    }
}
