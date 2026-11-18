import XCTest

final class ModelResolverTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfectwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testRecognizesCoreMLFolder() throws {
        let folder = temporaryDirectory.appendingPathComponent("openai_whisper-small", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        XCTAssertTrue(ModelResolver.isModelFolder(folder))
    }

    func testRejectsEmptyFolder() throws {
        let folder = temporaryDirectory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertFalse(ModelResolver.isModelFolder(folder))
    }

    func testDetectsGGMLFolder() throws {
        let folder = temporaryDirectory.appendingPathComponent("ggml", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin"))

        XCTAssertTrue(ModelResolver.looksLikeGGML(folder))
        XCTAssertFalse(ModelResolver.isModelFolder(folder))
    }

    func testFindsNestedModelFolder() throws {
        let nested = temporaryDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-small", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested.appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "{}".write(to: nested.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let found = ModelResolver.findDownloadedModel(in: temporaryDirectory)
        XCTAssertEqual(found?.standardizedFileURL, nested.standardizedFileURL)
    }

    func testReturnsNilWhenNoModels() {
        XCTAssertNil(ModelResolver.findDownloadedModel(in: temporaryDirectory))
    }
}
