import XCTest
@testable import Ork

final class UpdateServiceTests: XCTestCase {
    func testVersionCompareIsNumericPerSegment() {
        XCTAssertTrue(UpdateService.isNewer("0.8.0", than: "0.7.0"))
        XCTAssertTrue(UpdateService.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateService.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateService.isNewer("0.8.0", than: "0.8.0"))
        XCTAssertFalse(UpdateService.isNewer("0.7.9", than: "0.8.0"))
        // Missing segments count as zero: 0.8 == 0.8.0.
        XCTAssertFalse(UpdateService.isNewer("0.8", than: "0.8.0"))
        XCTAssertTrue(UpdateService.isNewer("0.8.1", than: "0.8"))
    }

    func testParseLatestFindsTheTagAndTheArm64Zip() {
        let json = """
        {
          "tag_name": "v0.9.0",
          "assets": [
            {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt"},
            {"name": "ork-0.9.0-macos-arm64.zip", "browser_download_url": "https://example.com/ork-0.9.0-macos-arm64.zip"}
          ]
        }
        """
        let parsed = UpdateService.parseLatest(Data(json.utf8))
        XCTAssertEqual(parsed?.version, "0.9.0")
        XCTAssertEqual(parsed?.zip.absoluteString, "https://example.com/ork-0.9.0-macos-arm64.zip")
        XCTAssertNil(UpdateService.parseLatest(Data("{}".utf8)))
        XCTAssertNil(UpdateService.parseLatest(Data("{\"tag_name\": \"v1.0\", \"assets\": []}".utf8)))
    }
}
