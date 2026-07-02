import XCTest

@testable import StrongCloneCore

final class DomainModelsTests: XCTestCase {
    func testAllEntriesRecursiveFlattensTree() {
        let root = Group(
            name: "Root",
            entries: [Entry(title: "A")],
            subgroups: [
                Group(name: "Sub", entries: [Entry(title: "B"), Entry(title: "C")])
            ]
        )
        let titles = root.allEntriesRecursive.map(\.title).sorted()
        XCTAssertEqual(titles, ["A", "B", "C"])
    }

    func testTotpConfigDefaults() {
        let totp = TotpConfig(secret: "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(totp.algorithm, .sha1)
        XCTAssertEqual(totp.digits, 6)
        XCTAssertEqual(totp.period, 30)
    }

    func testEntryEquatable() {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 0)
        let a = Entry(id: id, title: "X", created: created, modified: created)
        let b = Entry(id: id, title: "X", created: created, modified: created)
        XCTAssertEqual(a, b)
    }
}
