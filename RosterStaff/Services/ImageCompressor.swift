import UIKit

/// Produces JPEG data guaranteed to fit the Firebase Storage budget
/// (free tier — every upload must stay under `maxBytes`).
enum ImageCompressor {
    static let maxBytes = 2 * 1024 * 1024 // 2 MB
    static let maxDimension: CGFloat = 1600

    /// Downscale to `maxDimension`, then step JPEG quality down until the
    /// payload fits. Returns nil only if the image can't be encoded at all.
    static func jpegData(from image: UIImage, maxBytes: Int = maxBytes) -> Data? {
        let scaled = downscale(image, maxDimension: maxDimension)
        var quality: CGFloat = 0.7
        while quality >= 0.1 {
            if let data = scaled.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.15
        }
        // Last resort: halve dimensions at minimum quality.
        let tiny = downscale(scaled, maxDimension: maxDimension / 2)
        if let data = tiny.jpegData(compressionQuality: 0.1), data.count <= maxBytes {
            return data
        }
        return nil
    }

    static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
