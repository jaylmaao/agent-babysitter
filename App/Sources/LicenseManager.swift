import Foundation
import AgentBabysitterCore

/// License activation via Lemon Squeezy's license-key API. Network happens
/// ONLY when the user presses Activate/Deactivate in Settings — never in the
/// background — keeping the app's "no network unless you ask" contract.
/// Once activated, the license is honored offline indefinitely.
///
/// During the free beta every feature works without a key; the section in
/// Settings just lets early buyers register. Before charging, set the real
/// store/product IDs below so foreign Lemon Squeezy keys can't activate.
@MainActor
final class LicenseManager: ObservableObject {

    /// Fill in once the Lemon Squeezy store exists; nil skips pinning (beta).
    static let expectation = LicenseParsing.Expectation(storeID: nil, productID: nil)
    static let isBeta = true

    enum State: Equatable {
        case unlicensed
        case activated(maskedKey: String)
    }

    @Published private(set) var state: State = .unlicensed
    @Published private(set) var lastError: String?
    @Published private(set) var busy = false

    private let session: URLSession
    private let defaults = UserDefaults.standard

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        if let key = defaults.string(forKey: "licenseKey"), !key.isEmpty {
            state = .activated(maskedKey: Self.mask(key))
        }
    }

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        busy = true
        lastError = nil
        defer { busy = false }

        let instanceName = Host.current().localizedName ?? "Mac"
        guard let data = await post("activate", body: [
            "license_key": key, "instance_name": instanceName,
        ]) else {
            lastError = "Couldn't reach the license server — check your connection and try again."
            return
        }
        switch LicenseParsing.activation(from: data, expecting: Self.expectation) {
        case .success(let activation):
            defaults.set(activation.licenseKey, forKey: "licenseKey")
            defaults.set(activation.instanceID, forKey: "licenseInstanceID")
            state = .activated(maskedKey: Self.mask(activation.licenseKey))
        case .failure(.rejected(let message)):
            lastError = message
        case .failure(.wrongProduct):
            lastError = "That key belongs to a different product."
        case .failure(.malformed):
            lastError = "Unexpected response from the license server."
        }
    }

    func deactivate() async {
        guard let key = defaults.string(forKey: "licenseKey"),
              let instance = defaults.string(forKey: "licenseInstanceID") else {
            clearLocal()
            return
        }
        busy = true
        defer { busy = false }
        // Best effort: free the activation seat; clear locally regardless.
        _ = await post("deactivate", body: ["license_key": key, "instance_id": instance])
        clearLocal()
    }

    private func clearLocal() {
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "licenseInstanceID")
        state = .unlicensed
        lastError = nil
    }

    private func post(_ endpoint: String, body: [String: String]) async -> Data? {
        var request = URLRequest(
            url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return (try? await session.data(for: request))?.0
    }

    private static func mask(_ key: String) -> String {
        key.count > 4 ? "…\(key.suffix(4))" : key
    }
}
