import XCTest
@testable import StrongClone
import StrongCloneCore

/// Test de fumée de la cible app — vérifie que le câblage App ↔ Core tient.
/// Les tests UI/FaceID/Drive (device) seront documentés et ajoutés dans leurs changes.
final class AppSmokeTests: XCTestCase {
    func testCoreTypesAreReachableFromApp() {
        let group = Group(name: "T", entries: [Entry(title: "A")])
        XCTAssertEqual(group.allEntriesRecursive.count, 1)
    }
}
