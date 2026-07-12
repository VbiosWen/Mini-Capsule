import Testing
import Foundation

@Suite struct MetaCoverageTests {
    /// Toggle flipped to `true` in Plan 4 once every feature is covered.
    static let requireAllCovered = true

    struct Feature: Decodable {
        let id: Int
        let name: String
        let tier: [String]
        let tests: [String]
        let checklist: [String]
        let status: String
        let plan: String?
    }
    struct Manifest: Decodable { let features: [Feature] }

    static func manifestURL(file: StaticString = #filePath) -> URL {
        // <repo>/Mini CapsuleTests/MetaCoverageTests.swift → walk up to repo root.
        var url = URL(fileURLWithPath: "\(file)")
        url.deleteLastPathComponent() // Mini CapsuleTests/
        url.deleteLastPathComponent() // repo root
        return url.appendingPathComponent("docs/testing/coverage-manifest.json")
    }

    static func load() throws -> Manifest {
        let data = try Data(contentsOf: manifestURL())
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    @Test func everyFeatureIsCoveredOrExplicitlyPending() throws {
        let m = try Self.load()
        #expect(!m.features.isEmpty)
        for f in m.features {
            switch f.status {
            case "covered":
                #expect(f.tests.count + f.checklist.count >= 1,
                        "Feature #\(f.id) '\(f.name)' is covered but links no test/checklist")
            case "pending":
                #expect(f.plan != nil && !(f.plan ?? "").isEmpty,
                        "Feature #\(f.id) '\(f.name)' is pending but names no plan")
            default:
                Issue.record("Feature #\(f.id) '\(f.name)' has invalid status '\(f.status)'")
            }
        }
    }

    @Test func noFeatureRemainsPending() throws {
        guard Self.requireAllCovered else { return }
        let m = try Self.load()
        #expect(m.features.allSatisfy { $0.status == "covered" })
    }

    @Test func featureIDsAreUniqueAndComplete() throws {
        let m = try Self.load()
        let ids = Set(m.features.map(\.id))
        #expect(ids.count == m.features.count, "duplicate feature ids")
        #expect(ids == Set(1...18), "manifest must enumerate features 1...18 from the spec inventory")
    }
}
