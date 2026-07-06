import XCTest
@testable import Parrocchettami

final class ModelInstallerTests: XCTestCase {
    func testModelFileValidationChecksChecksum() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrocchettami-checksum-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(
            ModelInstaller.modelFileIsValid(
                at: url,
                expectedSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
        )
        XCTAssertFalse(ModelInstaller.modelFileIsValid(at: url, expectedSHA256: "not-a-match"))
    }
}
