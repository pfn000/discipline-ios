import Foundation
import XCTest

func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
        throw XCTSkip("fixture \(name) missing")
    }
    return try Data(contentsOf: url)
}

let t0 = Date(timeIntervalSince1970: 1_790_000_000) // fixed clock for tests
