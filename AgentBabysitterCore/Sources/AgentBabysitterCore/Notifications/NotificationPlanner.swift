import Foundation

public struct NotificationEvent: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case waitingForInput
        case turnCompleted
        case stalled
    }
    public let sessionID: String
    public let kind: Kind

    public init(sessionID: String, kind: Kind) {
        self.sessionID = sessionID
        self.kind = kind
    }
}

/// Turns successive row snapshots into notification edges:
/// - waiting: once per waiting episode
/// - turn completed: once per turn (on the transition into done)
/// - stalled: once per stall, reset when the session resumes
/// Sessions seen for the first time never fire (launch scan would spam
/// everything the user already knows about).
public struct NotificationPlanner: Sendable {

    private var previousStates: [String: SessionState] = [:]

    public init() {}

    public mutating func events(for rows: [SessionRow]) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        var currentStates: [String: SessionState] = [:]

        for row in rows {
            currentStates[row.id] = row.state
            guard let previous = previousStates[row.id], previous != row.state else {
                continue  // first sight, or no change
            }
            switch row.state {
            case .waitingForInput:
                events.append(NotificationEvent(sessionID: row.id, kind: .waitingForInput))
            case .done where previous != .ended:
                events.append(NotificationEvent(sessionID: row.id, kind: .turnCompleted))
            case .stalled:
                events.append(NotificationEvent(sessionID: row.id, kind: .stalled))
            default:
                break
            }
        }

        // Ended (or vanished) sessions are forgotten so a resurrected id is
        // treated as a fresh first sight.
        previousStates = currentStates.filter { $0.value != .ended }
        return events
    }
}
