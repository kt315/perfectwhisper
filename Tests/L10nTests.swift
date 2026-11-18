import XCTest

final class L10nTests: XCTestCase {
    /// Every key the code asks to translate must have a Russian variant.
    func testAllUsedKeysHaveRussianTranslation() throws {
        let sources = try sourceFiles()
        var used: Set<String> = []

        let callPattern = try NSRegularExpression(pattern: #"L10n\.t\(\s*"((?:[^"\\]|\\.)*)""#)
        let notePattern = try NSRegularExpression(pattern: #"noteKey:\s*"([^"]+)""#)

        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for expression in [callPattern, notePattern] {
                for match in expression.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    used.insert(String(text[keyRange]))
                }
            }
        }

        XCTAssertFalse(used.isEmpty, "No keys found — check the source path")
        let missing = used.filter { !L10n.hasTranslation($0) }.sorted()
        XCTAssertTrue(missing.isEmpty, "Missing Russian translations: \(missing)")
    }

    /// Swift traps on a dictionary literal with duplicate keys.
    /// Check the source so such a bug never reaches users.
    func testNoDuplicateTranslationKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = root.appendingPathComponent("Sources/Support/L10n.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let pattern = try NSRegularExpression(pattern: #"^\s*"([^"]+)":\s*""#, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var duplicates = Set<String>()

        for match in pattern.matches(in: text, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[keyRange])
            if !seen.insert(key).inserted { duplicates.insert(key) }
        }

        XCTAssertTrue(duplicates.isEmpty, "Duplicate keys: \(duplicates.sorted())")
    }

    func testLanguageSwitch() {
        let defaults = UserDefaults.standard
        let key = PrefKey.uiLanguage
        let saved = defaults.string(forKey: key)
        defer {
            if let saved {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set("ru", forKey: key)
        XCTAssertEqual(L10n.t("Start dictation"), "Начать диктовку")

        defaults.set("en", forKey: key)
        XCTAssertEqual(L10n.t("Start dictation"), "Start dictation")
    }

    /// Regression: the model catalog must store keys, not precomputed translations,
    /// otherwise descriptions stay in the old language after switching.
    func testModelNotesStayUntranslated() {
        let defaults = UserDefaults.standard
        let key = PrefKey.uiLanguage
        let saved = defaults.string(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.set("ru", forKey: key)
        let note = ModelCatalog.variants.first?.noteKey ?? ""
        XCTAssertEqual(note, "Recommended. Same model as in whisper.cpp, fastest on macOS")
        XCTAssertTrue(L10n.hasTranslation(note))
    }

    func testFormatArguments() {
        let defaults = UserDefaults.standard
        let key = PrefKey.uiLanguage
        let saved = defaults.string(forKey: key)
        defer {
            if let saved {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set("ru", forKey: key)
        XCTAssertEqual(L10n.t("Hotkey: %@", "⌥⌘D"), "Хоткей: ⌥⌘D")
    }

    // MARK: - Source lookup

    private func sourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repository root
        let sources = root.appendingPathComponent("Sources", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw XCTSkip("Sources folder not found next to the tests")
        }

        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if url.lastPathComponent == "L10n.swift" { continue }
            result.append(url)
        }
        return result
    }
}
