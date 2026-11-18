import XCTest

final class FileHasherTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testKnownVectorShort() throws {
        let url = directory.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: url)
        XCTAssertEqual(
            try FileHasher.sha256(of: url),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    /// One million `a` characters — a known test vector; verifies that the
    /// hasher reads the file in chunks correctly.
    func testKnownVectorMultiChunk() throws {
        let url = directory.appendingPathComponent("million.txt")
        try Data(repeating: UInt8(ascii: "a"), count: 1_000_000).write(to: url)
        XCTAssertEqual(
            try FileHasher.sha256(of: url),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        )
    }
}
