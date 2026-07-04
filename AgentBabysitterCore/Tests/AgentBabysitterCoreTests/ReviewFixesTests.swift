import XCTest
@testable import AgentBabysitterCore

final class HookCommandUpgradeTests: XCTestCase {

    /// An install over settings holding an OLD version of our command (same
    /// marker, different template) must upgrade the command in place.
    func testUpgradesStaleCommandInPlace() throws {
        let stale = Data("""
        {"hooks":{"Stop":[{"hooks":[{"type":"command",
        "command":"old-template #\(HooksInstaller.marker)"}]}]}}
        """.utf8)
        let updated = try HooksInstaller.settingsWithHooksInstalled(stale, eventLogPath: "/tmp/e.jsonl")
        let text = String(data: updated, encoding: .utf8)!
        XCTAssertFalse(text.contains("old-template"))
        XCTAssertTrue(text.contains("umask 077"))
        // Still exactly one of ours per event, no duplicates.
        XCTAssertEqual(text.components(separatedBy: HooksInstaller.marker).count - 1, 2)
    }

    func testForeignHooksSurviveUpgrade() throws {
        let mixed = Data("""
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-own-hook.sh"}]},
        {"hooks":[{"type":"command","command":"old #\(HooksInstaller.marker)"}]}]}}
        """.utf8)
        let updated = try HooksInstaller.settingsWithHooksInstalled(mixed, eventLogPath: "/tmp/e.jsonl")
        let text = String(data: updated, encoding: .utf8)!
        XCTAssertTrue(text.contains("my-own-hook.sh"))
        XCTAssertFalse(text.contains("\"old #"))
    }

    func testHookCommandKeepsLogPrivate() throws {
        let updated = try HooksInstaller.settingsWithHooksInstalled(nil, eventLogPath: "/tmp/e.jsonl")
        XCTAssertTrue(String(data: updated, encoding: .utf8)!.contains("umask 077"))
    }
}

final class ClaudeLiveParsingTests: XCTestCase {

    func testParsesUnifiedHeaders() {
        let snapshot = ClaudeLiveParsing.snapshot(fromHeaders: [
            "Anthropic-Ratelimit-Unified-5h-Utilization": "0.43",
            "anthropic-ratelimit-unified-5h-reset": "1783195800",
            "anthropic-ratelimit-unified-7d-utilization": "0.23",
            "anthropic-ratelimit-unified-7d-reset": "1783573200",
        ], plan: "pro")
        XCTAssertEqual(snapshot?.usedPercent ?? -1, 43, accuracy: 0.01)
        XCTAssertEqual(snapshot?.resetsAt, Date(timeIntervalSince1970: 1_783_195_800))
        XCTAssertEqual(snapshot?.weeklyUsedPercent ?? -1, 23, accuracy: 0.01)
        XCTAssertEqual(snapshot?.weeklyResetsAt, Date(timeIntervalSince1970: 1_783_573_200))
        XCTAssertEqual(snapshot?.plan, "pro")
        XCTAssertEqual(snapshot?.isLive, true)
    }

    func testMissingUtilizationYieldsNil() {
        XCTAssertNil(ClaudeLiveParsing.snapshot(fromHeaders: ["content-type": "application/json"],
                                                plan: nil))
    }

    func testFractionClamped() {
        let snapshot = ClaudeLiveParsing.snapshot(
            fromHeaders: ["anthropic-ratelimit-unified-5h-utilization": "1.7"], plan: nil)
        XCTAssertEqual(snapshot?.usedPercent, 100)
    }

    func testEnvValueExtraction() {
        let ps = "/path/to/claude --flag CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-abcdef "
               + "CLAUDE_CODE_SUBSCRIPTION_TYPE=pro HOME=/Users/x"
        XCTAssertEqual(ClaudeLiveParsing.envValue("CLAUDE_CODE_OAUTH_TOKEN", inProcessEnv: ps),
                       "sk-ant-oat01-abcdef")
        XCTAssertEqual(ClaudeLiveParsing.envValue("CLAUDE_CODE_SUBSCRIPTION_TYPE", inProcessEnv: ps),
                       "pro")
        XCTAssertNil(ClaudeLiveParsing.envValue("MISSING_VAR", inProcessEnv: ps))
    }
}

final class LicenseParsingTests: XCTestCase {

    private let success = Data("""
    {"activated":true,"error":null,
     "license_key":{"id":1,"status":"active","key":"ABC-123-DEF","activation_limit":3},
     "instance":{"id":"inst-uuid-1","name":"My Mac"},
     "meta":{"store_id":111,"product_id":222,"customer_email":"x@y.z"}}
    """.utf8)

    func testActivateSuccess() {
        let result = LicenseParsing.activation(from: success,
            expecting: .init(storeID: nil, productID: nil))
        XCTAssertEqual(try? result.get(),
                       LicenseParsing.Activation(licenseKey: "ABC-123-DEF",
                                                 instanceID: "inst-uuid-1", status: "active"))
    }

    func testActivatePinnedToRightProduct() {
        let result = LicenseParsing.activation(from: success,
            expecting: .init(storeID: 111, productID: 222))
        XCTAssertNotNil(try? result.get())
    }

    func testForeignKeyRejectedWhenPinned() {
        let result = LicenseParsing.activation(from: success,
            expecting: .init(storeID: 999, productID: nil))
        XCTAssertEqual(result, .failure(.wrongProduct))
    }

    func testAPIErrorSurfaced() {
        let rejected = Data(#"{"activated":false,"error":"license_key not found"}"#.utf8)
        let result = LicenseParsing.activation(from: rejected,
            expecting: .init(storeID: nil, productID: nil))
        XCTAssertEqual(result, .failure(.rejected(message: "license_key not found")))
    }

    func testGarbageIsMalformed() {
        let result = LicenseParsing.activation(from: Data("nope".utf8),
            expecting: .init(storeID: nil, productID: nil))
        XCTAssertEqual(result, .failure(.malformed))
        XCTAssertFalse(LicenseParsing.isValid(validateResponse: Data("nope".utf8)))
    }

    func testValidate() {
        XCTAssertTrue(LicenseParsing.isValid(
            validateResponse: Data(#"{"valid":true,"error":null}"#.utf8)))
        XCTAssertFalse(LicenseParsing.isValid(
            validateResponse: Data(#"{"valid":false,"error":"expired"}"#.utf8)))
    }
}
