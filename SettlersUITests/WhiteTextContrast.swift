import UIKit

/// Measures rendered white text against its dominant sRGB backing pixels.
/// The iOS 26.5 audit repeatedly flags the harvest subtitle despite an 8.3:1
/// captured ratio. An issue-specific exception must prove at least 7:1 from
/// the live element screenshot; all other native audit issues still fail.
/// See Apple's investigated-false-positive workflow: WWDC23 session 10035.
@MainActor
enum WhiteTextContrast {
    static let requiredRatio = 7.0
    private static let minimumInkPixels = 32

    static func ratio(in image: UIImage) -> Double? {
        guard let source = image.cgImage else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ratio(in: pixels) : nil
    }

    private static func ratio(in pixels: [UInt8]) -> Double? {
        var background: [Int: ColorSample] = [:]
        var ink = ColorSample()
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] == 255 {
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            let bucket = (red / 8 << 10) | (green / 8 << 5) | (blue / 8)
            background[bucket, default: ColorSample()].append(red: red, green: green, blue: blue)
            if red >= 240 && green >= 240 && blue >= 240 { ink.append(red: red, green: green, blue: blue) }
        }
        guard ink.count >= minimumInkPixels,
              let backing = background.sorted(by: {
                  $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
              }).first?.value else { return nil }
        return (ink.luminance + 0.05) / (backing.luminance + 0.05)
    }

    private struct ColorSample {
        var red = 0, green = 0, blue = 0, count = 0

        mutating func append(red: Int, green: Int, blue: Int) {
            self.red += red; self.green += green; self.blue += blue; count += 1
        }

        var luminance: Double {
            let denominator = Double(count) * 255
            return 0.2126 * linear(Double(red) / denominator)
                + 0.7152 * linear(Double(green) / denominator)
                + 0.0722 * linear(Double(blue) / denominator)
        }

        private func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
    }
}
