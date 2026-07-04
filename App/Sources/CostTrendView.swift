import SwiftUI

/// Seven tiny bars — enough to see the week's shape at a glance.
struct CostTrendView: View {
    let history: [(day: Date, dollars: Double)]

    var body: some View {
        let peak = max(history.map(\.dollars).max() ?? 1, 0.01)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(history, id: \.day) { entry in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Calendar.current.isDateInToday(entry.day)
                              ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: 18, height: max(4, 36 * entry.dollars / peak))
                        .help(String(format: "%@: $%.2f", Self.dayLabel(entry.day), entry.dollars))
                    Text(Self.dayLabel(entry.day))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private static func dayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EE"
        return String(formatter.string(from: day).prefix(2))
    }
}
