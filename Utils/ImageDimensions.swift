import Foundation
import CoreGraphics
import ImageIO

/// Pixel size of an image, remembered per attachment so a preview can be laid
/// out at its final height *before* the bytes are downloaded. Reserving the
/// space keeps the feed from reflowing — and therefore from jumping — while
/// pictures stream in.
///
/// Sizes survive relaunches (one small dictionary in `UserDefaults`) and are
/// refreshed for free whenever the full image data is decoded.
final class ImageDimensions {
    static let shared = ImageDimensions()

    /// Fallback used when the real ratio is still unknown, so the placeholder
    /// is never a 35pt sliver.
    static let fallbackAspectRatio: CGFloat = 16.0 / 9.0

    private static let defaultsKey = "imageDimensions"
    private let defaults: UserDefaults
    private var sizes: [String: CGSize]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: CGSize].self, from: stored) {
            sizes = decoded
        } else {
            sizes = [:]
        }
    }

    /// Known size for a cache key, if we have seen this image before.
    func cachedSize(forKey key: String) -> CGSize? {
        sizes[key]
    }

    /// Remembers a measured size and persists the dictionary.
    func store(_ size: CGSize, forKey key: String) {
        guard size.width > 0, size.height > 0, sizes[key] != size else { return }
        sizes[key] = size
        persist()
    }

    /// Width divided by height, or the fallback when the size is unknown.
    func aspectRatio(forKey key: String) -> CGFloat {
        guard let size = sizes[key], size.height > 0 else { return Self.fallbackAspectRatio }
        return size.width / size.height
    }

    /// Runs `probe` at most once per key while callers await the same key.
    func resolveSize(forKey key: String, probe: () async -> CGSize?) async -> CGSize? {
        if let cached = sizes[key] { return cached }
        let measured = await probe()
        if let measured {
            store(measured, forKey: key)
        }
        return measured
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sizes) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Reads the pixel dimensions out of the first bytes of a JPEG/PNG stream.
/// `CGImageSource` copes with truncated data, so a small ranged response is
/// enough to learn the aspect ratio.
enum ImageDimensionProbe {
    static func size(fromPartial data: Data) -> CGSize? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}