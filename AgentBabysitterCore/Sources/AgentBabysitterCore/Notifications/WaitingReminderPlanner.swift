import Foundation

/// One automatic follow-up per waiting episode: if a session has sat in
/// 🟡 waiting for `interval` without the user acting, remind once. Leaving
/// the waiting state (answered, working again, ended) resets the episode, so
/// a session that waits again later earns a fresh reminder.
public struct WaitingReminderPlanner: Equatable, Sendable {

    private struct Episode: Equatable, Sendable {
        var since: Date
        var reminded: Bool
    }

    private var episodes: [String: Episode] = [:]

    public init() {}

    /// Feed every refresh; returns session ids due a reminder now (each id
    /// at most once per episode). The app layer applies its own gates
    /// (toggle, quiet hours, paused notifications) before delivering.
    public mutating func dueReminders(rows: [SessionRow], interval: TimeInterval,
                                      now: Date = Date()) -> [String] {
        var due: [String] = []
        var seen: Set<String> = []
        for row in rows {
            seen.insert(row.id)
            guard row.state == .waitingForInput else {
                episodes.removeValue(forKey: row.id)
                continue
            }
            var episode = episodes[row.id] ?? Episode(since: now, reminded: false)
            if !episode.reminded, now.timeIntervalSince(episode.since) >= interval {
                episode.reminded = true
                due.append(row.id)
            }
            episodes[row.id] = episode
        }
        // Sessions that vanished from the list are over; forget them.
        episodes = episodes.filter { seen.contains($0.key) }
        return due
    }
}
