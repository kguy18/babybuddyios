import Foundation

/// Minimal `multipart/form-data` encoding for Baby Buddy's image uploads. The client is otherwise
/// JSON-only; images (child `picture`, note `image`) are the sole multipart case, and each upload
/// carries exactly one file field, so this encodes just that.
enum MultipartForm {
    /// A random boundary token safe for use in a `multipart/form-data` Content-Type.
    static func boundary() -> String { "BBBoundary-\(UUID().uuidString)" }

    /// Encode a single image file field as a multipart body:
    ///
    ///     --<boundary>\r\n
    ///     Content-Disposition: form-data; name="<field>"; filename="<filename>"\r\n
    ///     Content-Type: <mimeType>\r\n
    ///     \r\n
    ///     <raw bytes>\r\n
    ///     --<boundary>--\r\n
    static func imageBody(boundary: String, field: String, filename: String,
                          mimeType: String, data: Data) -> Data {
        var body = Data()
        func line(_ text: String = "") { body.append(Data((text + "\r\n").utf8)) }

        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"")
        line("Content-Type: \(mimeType)")
        line()
        body.append(data)
        line()
        line("--\(boundary)--")
        return body
    }
}
