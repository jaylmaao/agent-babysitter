import Foundation

/// Pure parsing for Lemon Squeezy's license-key API responses — in Core so
/// it's unit-tested; the app layer does the (explicit-user-action-only)
/// networking. https://docs.lemonsqueezy.com/api/license-api
public enum LicenseParsing {

    /// Pin activations to our store/product once they exist, so any random
    /// Lemon Squeezy key can't activate the app. nil skips the check (beta).
    public struct Expectation: Sendable {
        public let storeID: Int?
        public let productID: Int?
        public init(storeID: Int?, productID: Int?) {
            self.storeID = storeID
            self.productID = productID
        }
    }

    public struct Activation: Equatable, Sendable {
        public let licenseKey: String
        public let instanceID: String
        public let status: String
    }

    public enum Failure: Error, Equatable {
        case rejected(message: String)   // API said no (invalid key, limit…)
        case wrongProduct                // valid key, not our product
        case malformed                   // response shape unrecognized
    }

    /// Parses `/v1/licenses/activate`.
    public static func activation(from data: Data,
                                  expecting expectation: Expectation) -> Result<Activation, Failure> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.malformed)
        }
        if let error = root["error"] as? String, !error.isEmpty {
            return .failure(.rejected(message: error))
        }
        guard root["activated"] as? Bool == true,
              let licenseKey = (root["license_key"] as? [String: Any]),
              let key = licenseKey["key"] as? String,
              let status = licenseKey["status"] as? String,
              let instance = root["instance"] as? [String: Any],
              let instanceID = instance["id"] as? String else {
            return .failure(.malformed)
        }
        let meta = root["meta"] as? [String: Any]
        if let expected = expectation.storeID,
           (meta?["store_id"] as? Int) != expected { return .failure(.wrongProduct) }
        if let expected = expectation.productID,
           (meta?["product_id"] as? Int) != expected { return .failure(.wrongProduct) }
        return .success(Activation(licenseKey: key, instanceID: instanceID, status: status))
    }

    /// Parses `/v1/licenses/validate`. True only for a currently-valid key.
    public static func isValid(validateResponse data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        return root["valid"] as? Bool == true
    }
}
