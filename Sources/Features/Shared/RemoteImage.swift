import SwiftUI
import UIKit
import CryptoKit

/// Fetches and caches Baby Buddy media (child pictures, note images) and renders it.
///
/// Baby Buddy serves uploads under `/media/` **without** token auth by default (Django's
/// `static()` in DEBUG, the web server in production), so most fetches need no `Authorization`
/// header. Two cases are handled anyway: the serialized URL can come back as `http://` from a
/// server behind a TLS-terminating proxy (which iOS ATS blocks), so a same-host `http` URL is
/// upgraded to `https`; and a deployment that *does* lock down `/media/` still works because the
/// auth token is attached **only when the image host matches the configured server host**
/// (same-origin — never leaked to a third-party host).
///
/// Images are cached in memory and on disk keyed by URL, so a thumbnail isn't re-fetched on every
/// scroll. `file://` URLs (used by demo seed data) load directly with no network or caching.
actor ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("BBImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL, token: String?) async -> UIImage? {
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }

        let key = url.absoluteString as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let fileURL = directory.appendingPathComponent(Self.filename(for: url))
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key)
            return image
        }

        var request = URLRequest(url: url)
        if let token { request.setValue("Token \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let image = UIImage(data: data) else { return nil }

        memory.setObject(image, forKey: key)
        try? data.write(to: fileURL, options: .atomic)
        return image
    }

    private static func filename(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Asynchronously loads media at `urlString` (resolved against the active server) and renders it
/// scaled-to-fill, falling back to `placeholder` while loading or when there's no image. The
/// caller sets the frame and clip shape.
struct RemoteImage<Placeholder: View>: View {
    let urlString: String?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(AppSession.self) private var session
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: urlString ?? "") { await load() }
    }

    private func load() async {
        image = nil
        guard let resolved = Self.resolve(urlString, config: session.config) else { return }
        image = await ImageLoader.shared.image(for: resolved.url, token: resolved.token)
    }

    /// Resolve a serialized media URL into a fetchable URL plus the token to send (if any). Handles
    /// absolute http/https (same-host `http`→`https` upgrade, same-host token), `file://` (demo),
    /// and server-relative paths. Returns `nil` for empty/unusable input.
    static func resolve(_ urlString: String?, config: ServerConfig?) -> (url: URL, token: String?)? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        if var comps = URLComponents(string: raw), let scheme = comps.scheme?.lowercased() {
            if scheme == "file" { return comps.url.map { ($0, nil) } }
            let sameHost = comps.host != nil && comps.host == config?.baseURL.host
            if scheme == "http", sameHost { comps.scheme = "https" }
            guard let url = comps.url else { return nil }
            return (url, sameHost ? config?.token : nil)
        }

        // Server-relative path (e.g. "/media/child/picture/x.jpg").
        guard let base = config?.baseURL, let url = URL(string: raw, relativeTo: base)?.absoluteURL else { return nil }
        return (url, config?.token)
    }
}

/// A circular child avatar: the child's `picture` if set, otherwise a brand-colored initial.
struct ChildAvatar: View {
    let pictureURL: String?
    let initial: String
    var size: CGFloat = 42

    var body: some View {
        RemoteImage(urlString: pictureURL) {
            Circle()
                .fill(BBColor.brand)
                .overlay(Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
