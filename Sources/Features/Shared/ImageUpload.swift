import UIKit

extension UIImage {
    /// JPEG data suitable for upload: downscaled so the longest side is at most `maxDimension`
    /// (photos straight from the library are far larger than Baby Buddy needs) and re-encoded at
    /// `quality`. Returns `nil` only if encoding fails.
    func bbUploadJPEG(maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return jpegData(compressionQuality: quality) }

        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
