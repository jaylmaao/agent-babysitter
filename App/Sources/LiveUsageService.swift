import Foundation
import AgentBabysitterCore

/// Opt-in online usage fetcher. OFF by default — the app makes no network
/// calls unless the user enables "Live usage". Only ever talks to each
/// vendor's canonical host using the user's own existing credential, so a
/// token can never be sent anywhere unintended. Any failure (offline, no
/// credential, unexpected shape) yields a reason string instead of data —
/// shown in Settings so the toggle never fails silently.
///
/// Claude Code: the subscription windows ride on the response headers of a
/// successful `/v1/messages` call (`anthropic-ratelimit-unified-*`), so the
/// probe is the smallest valid request — one haiku token. That token counts
/// against the very quota being measured (disclosed in the toggle copy).
actor LiveUsageService {

    enum Outcome {
        case snapshot(UsageLimitSnapshot)
        case unavailable(reason: String)
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    /// Live snapshots per agent id, plus a user-readable reason when a
    /// fetch produced nothing.
    func fetch(enabled: Bool) async -> (limits: [String: UsageLimitSnapshot], failure: String?) {
        guard enabled else { return ([:], nil) }
        switch await fetchClaudeCode() {
        case .snapshot(let snapshot):
            return (["claude-code": snapshot], nil)
        case .unavailable(let reason):
            BabysitterLog.process.info("live Claude usage unavailable: \(reason, privacy: .public)")
            return ([:], reason)
        }
    }

    // MARK: - Claude Code

    private func fetchClaudeCode() async -> Outcome {
        guard let (credential, planHint) = ClaudeCredential.resolve() else {
            return .unavailable(reason: "No Claude login found. Open the Claude app, "
                + "or run /login in the claude CLI, then try again.")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        credential.apply(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ])

        guard let (_, response) = try? await session.data(for: request) else {
            return .unavailable(reason: "Couldn't reach api.anthropic.com — check your connection.")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return .unavailable(reason: "Anthropic returned an error (\(code)). "
                + "Your login may have expired — open the Claude app once and retry.")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        guard let snapshot = ClaudeLiveParsing.snapshot(fromHeaders: headers, plan: planHint) else {
            return .unavailable(reason: "The response had no usage headers — "
                + "these appear for Pro/Max subscriptions only.")
        }
        return .snapshot(snapshot)
    }
}

/// A usable Claude credential, resolved without ever printing or storing it.
private enum ClaudeCredential {
    case apiKey(String)
    case oauth(String)

    func apply(to request: inout URLRequest) {
        switch self {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case .oauth(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
    }

    /// Prompt-free source first: the desktop app's own claude process carries
    /// the OAuth token in env (reading env of the user's own processes is
    /// local). The CLI keychain item is second — reading it can show a
    /// one-time macOS keychain prompt. An API key is last: it authenticates
    /// but usually has no subscription windows.
    static func resolve() -> (ClaudeCredential, plan: String?)? {
        if let found = runningProcessOAuth() { return (.oauth(found.token), found.plan) }
        if let token = keychainOAuthToken() { return (.oauth(token), nil) }
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return (.apiKey(key), nil)
        }
        return nil
    }

    private static func runningProcessOAuth() -> (token: String, plan: String?)? {
        guard let pids = shell("/usr/bin/pgrep", ["-x", "claude"]) else { return nil }
        for pid in pids.split(separator: "\n").prefix(8) {
            guard let env = shell("/bin/ps", ["eww", "-o", "command=", "-p", String(pid)]),
                  let token = ClaudeLiveParsing.envValue("CLAUDE_CODE_OAUTH_TOKEN",
                                                         inProcessEnv: env),
                  token.count > 20 else { continue }
            return (token, ClaudeLiveParsing.envValue("CLAUDE_CODE_SUBSCRIPTION_TYPE",
                                                      inProcessEnv: env))
        }
        return nil
    }

    /// The Claude Code CLI stores its OAuth token in the login keychain under
    /// this service; read the access_token only.
    private static func keychainOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    }

    private static func shell(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
