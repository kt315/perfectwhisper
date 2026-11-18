import XCTest

final class UpdateTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(VersionCompare.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(VersionCompare.isNewer("v1.1.0", than: "1.0.9"))
        XCTAssertTrue(VersionCompare.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(VersionCompare.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(VersionCompare.isNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(VersionCompare.isNewer("1.0.0", than: "1.0.1"))
    }

    func testVersionPreReleaseSuffixIgnored() {
        XCTAssertEqual(VersionCompare.normalized("v1.2.3-beta.1"), "1.2.3")
    }

    func testGitLabReleaseParsing() throws {
        let json = """
        [{
          "tag_name": "v1.2.0",
          "name": "1.2.0",
          "description": "Что нового",
          "assets": {
            "links": [{
              "name": "PerfectWhisper-1.2.0.dmg",
              "url": "https://gitlab.com/x/-/releases/v1.2.0/downloads/file.dmg",
              "direct_asset_url": "https://gitlab.com/direct/file.dmg"
            }]
          },
          "_links": { "self": "https://gitlab.com/x/-/releases/v1.2.0" }
        }]
        """

        let releases = try JSONDecoder().decode([GitLabRelease].self, from: Data(json.utf8))
        let release = try XCTUnwrap(releases.first)

        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertEqual(release.description, "Что нового")
        XCTAssertEqual(release.resolvedDownloadURL()?.absoluteString, "https://gitlab.com/direct/file.dmg")
        XCTAssertEqual(release.resolvedPageURL(project: "x/y")?.absoluteString, "https://gitlab.com/x/-/releases/v1.2.0")
    }

    func testFallbackToReleasePageWithoutDmg() throws {
        let json = """
        [{ "tag_name": "v2.0.0", "assets": { "links": [] } }]
        """
        let releases = try JSONDecoder().decode([GitLabRelease].self, from: Data(json.utf8))
        let release = try XCTUnwrap(releases.first)

        XCTAssertNil(release.resolvedDownloadURL())
        XCTAssertEqual(release.resolvedPageURL(project: "a/b")?.absoluteString,
                       "https://gitlab.com/a/b/-/releases/v2.0.0")
    }

    func testGitHubReleaseParsing() throws {
        let json = """
        {
          "tag_name": "v1.3.0",
          "name": "1.3.0",
          "body": "Что нового",
          "html_url": "https://github.com/kt315/perfectwhisper/releases/tag/v1.3.0",
          "assets": [{
            "name": "PerfectWhisper-1.3.0.dmg",
            "browser_download_url": "https://github.com/kt315/perfectwhisper/releases/download/v1.3.0/PerfectWhisper-1.3.0.dmg"
          }]
        }
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, "1.3.0")
        XCTAssertEqual(release.body, "Что нового")
        XCTAssertEqual(
            release.resolvedDownloadURL()?.absoluteString,
            "https://github.com/kt315/perfectwhisper/releases/download/v1.3.0/PerfectWhisper-1.3.0.dmg"
        )
    }
}
