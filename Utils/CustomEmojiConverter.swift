import Foundation
import ImageIO
import CoreGraphics

enum CustomEmojiConverterError: LocalizedError {
    case unreadable
    
    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Can't read this image"
        }
    }
}

/// Prepares a user-picked image for upload via `customEmojis.create`.
///
/// The Google Chat API only accepts `.png`, `.jpg` and `.gif` payloads, so the
/// converter passes those through unchanged (preserving GIF animation) and
/// transcodes everything else (WebP, HEIC, BMP, TIFF, ICO, …) to PNG for
/// static images or to an animated GIF when the source has multiple frames.
enum CustomEmojiConverter {
    static let maxDimension: CGFloat = 512
    
    struct Result {
        let data: Data
        let filename: String
    }
    
    /// Reads basic facts about an image file: frame count and animation flag.
    static func info(at url: URL) -> (isAnimated: Bool, frameCount: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return (isAnimated: false, frameCount: 0)
        }
        let count = CGImageSourceGetCount(source)
        return (isAnimated: count > 1, frameCount: count)
    }
    
    /// Converts the file at `url` into upload-ready data plus the embedded
    /// filename matching the produced format.
    static func convert(url: URL) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CustomEmojiConverterError.unreadable
        }
        let type = CGImageSourceGetType(source) as String? ?? ""
        let isAnimated = CGImageSourceGetCount(source) > 1
        
        switch type {
        case "public.png", "public.jpeg", "com.compuserve.gif":
            // Directly supported: keep the original bytes, animation intact.
            let ext: String
            if type == "public.png" {
                ext = "png"
            } else if type == "public.jpeg" {
                ext = "jpg"
            } else {
                ext = "gif"
            }
            return Result(data: try Data(contentsOf: url), filename: "emoji.\(ext)")
        case "public.webp":
            if isAnimated {
                return Result(data: try encodeAnimatedGIF(source: source), filename: "emoji.gif")
            }
            return Result(data: try encodePNG(source: source, index: 0), filename: "emoji.png")
        default:
            if isAnimated {
                return Result(data: try encodeAnimatedGIF(source: source), filename: "emoji.gif")
            }
            return Result(data: try encodePNG(source: source, index: 0), filename: "emoji.png")
        }
    }
    
    /// A valid `:name:` derived from a raw string.  The Google Chat rules require
    /// lowercase alphanumerics, hyphens and underscores that must not repeat
    /// consecutively, wrapped in colons.
    static func sanitize(_ raw: String) -> String {
        var core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if core.hasPrefix(":") { core = String(core.dropFirst()) }
        if core.hasSuffix(":") { core = String(core.dropLast()) }
        let lower = core.lowercased()
        let allowed = lower.unicodeScalars.reduce(into: "") { out, scalar in
            let isLetter = scalar.value >= 0x61 && scalar.value <= 0x7A
            let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
            let isSeparator = scalar == "-" || scalar == "_"
            out.append(isLetter || isDigit ? Character(scalar) : isSeparator ? "-" : "-")
        }
        var cleaned = allowed.replacingOccurrences(of: "[-_]{2,}", with: "-", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let final = cleaned.isEmpty ? "emoji" : String(cleaned.prefix(64))
        return ":\(final):"
    }

    /// A valid `:name:` derived from a file name.
    static func suggestedName(from url: URL) -> String {
        sanitize(url.deletingPathExtension().lastPathComponent)
    }
    
    private static func scaledIfNeeded(_ image: CGImage) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let longest = max(w, h)
        guard longest > maxDimension else { return image }
        
        let scale = maxDimension / longest
        let newW = max(1, Int(w * scale))
        let newH = max(1, Int(h * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: newW, height: newH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }
    
    private static func encodePNG(source: CGImageSource, index: Int) throws -> Data {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            throw CustomEmojiConverterError.unreadable
        }
        let scaled = scaledIfNeeded(image)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw CustomEmojiConverterError.unreadable
        }
        CGImageDestinationAddImage(dest, scaled, nil)
        guard CGImageDestinationFinalize(dest) else { throw CustomEmojiConverterError.unreadable }
        return data as Data
    }
    
    private static func encodeAnimatedGIF(source: CGImageSource) throws -> Data {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return try encodePNG(source: source, index: 0) }
        
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, count, nil) else {
            throw CustomEmojiConverterError.unreadable
        }
        let loopProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, loopProperties as CFDictionary)
        
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                throw CustomEmojiConverterError.unreadable
            }
            let scaled = scaledIfNeeded(image)
            
            var delay = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let d = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, d > 0 {
                    delay = d
                } else if let d = gif[kCGImagePropertyGIFDelayTime] as? Double, d > 0 {
                    delay = d
                }
            }
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ]
            CGImageDestinationAddImage(dest, scaled, frameProperties as CFDictionary)
        }
        
        guard CGImageDestinationFinalize(dest) else { throw CustomEmojiConverterError.unreadable }
        return data as Data
    }
}