import Foundation

/// On-disk home for image bytes awaiting upload. Files are referenced by name from a
/// ``PendingImageUpload`` and double as the record's local `file://` preview until the upload
/// succeeds. Lives in Application Support (persistent — not Caches, which the system can purge and
/// take a queued offline upload with it).
enum ImageUploadStore {
    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "PendingImages", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL { directory.appending(path: filename) }

    /// Persist `data` under a fresh unique filename and return that name, or `nil` on failure.
    static func write(_ data: Data, ext: String) -> String? {
        let filename = "\(UUID().uuidString).\(ext)"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
