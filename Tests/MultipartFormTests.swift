import XCTest
@testable import BabyBuddy

/// Byte-level coverage of the `multipart/form-data` image encoding and the kind→field mapping.
final class MultipartFormTests: XCTestCase {
    func testImageBodyExactEncoding() {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D])
        let body = MultipartForm.imageBody(
            boundary: "TESTB", field: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: data)

        var expected = Data()
        func add(_ s: String) { expected.append(Data(s.utf8)) }
        add("--TESTB\r\n")
        add("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        add("Content-Type: image/jpeg\r\n")
        add("\r\n")
        expected.append(data)
        add("\r\n")
        add("--TESTB--\r\n")

        XCTAssertEqual(body, expected)
    }

    func testFieldAndFilenameAppearInHeaders() {
        let body = MultipartForm.imageBody(
            boundary: "B", field: "picture", filename: "child.jpg", mimeType: "image/jpeg", data: Data([1, 2, 3]))
        let header = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(header.contains("name=\"picture\"; filename=\"child.jpg\""))
        XCTAssertTrue(header.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(header.hasSuffix("--B--\r\n"))
    }

    func testBinaryPayloadPreservedIncludingCRLFBytes() {
        // Bytes that look like delimiters (CRLF, a stray boundary-ish run) must pass through raw.
        let payload = Data([0x0D, 0x0A, 0x2D, 0x2D, 0x42, 0xFF, 0x00, 0x0A])
        let body = MultipartForm.imageBody(
            boundary: "B", field: "image", filename: "x.bin", mimeType: "application/octet-stream", data: payload)

        var expected = Data()
        expected.append(Data("--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"x.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        expected.append(payload)
        expected.append(Data("\r\n--B--\r\n".utf8))
        XCTAssertEqual(body, expected)
    }

    func testBoundaryIsUniqueAndPrefixed() {
        let a = MultipartForm.boundary()
        let b = MultipartForm.boundary()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("BBBoundary-"))
    }

    func testImageFieldPerKind() {
        XCTAssertEqual(EntityKind.note.imageField, "image")
        XCTAssertEqual(EntityKind.child.imageField, "picture")
        XCTAssertNil(EntityKind.feeding.imageField)
        XCTAssertNil(EntityKind.timer.imageField)
    }
}
