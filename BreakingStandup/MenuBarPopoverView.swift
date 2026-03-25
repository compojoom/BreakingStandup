import SwiftUI
import EventKit

struct MenuBarPopoverView: View {
    @EnvironmentObject var monitor: MeetingMonitor
    @State private var now = Date()

    private let countdownTimer = Timer.publish(
        every: 1, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Breaking Standup")
                    .font(.headline)
                Spacer()
                statusDot
            }

            Divider()

            // Current meeting
            if let current = monitor.currentEvent {
                currentEventRow(current)
            }

            // Next event
            if let event = monitor.nextEvent {
                nextEventRow(event)
            } else if monitor.currentEvent == nil {
                Label(
                    "No upcoming meetings",
                    systemImage: "calendar.badge.checkmark"
                )
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }

            Divider()

            // Quick actions
            HStack(spacing: 12) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
        }
        .padding()
        .frame(width: 280)
        .onReceive(countdownTimer) { self.now = $0 }
    }

    // MARK: - Subviews

    private func currentEventRow(_ event: EKEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("In meeting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Text(event.title ?? "Untitled")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            HStack {
                Label(
                    "\(timeString(event.startDate)) – \(timeString(event.endDate))",
                    systemImage: "clock"
                )
                Spacer()
                let remaining = event.endDate.timeIntervalSince(now)
                if remaining > 0 {
                    Text("\(formatCountdown(remaining)) left")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.red.opacity(0.08), in: RoundedRectangle(
            cornerRadius: 8
        ))
    }

    private func nextEventRow(_ event: EKEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if monitor.currentEvent != nil {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(event.title ?? "Untitled")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            HStack {
                Label(
                    timeString(event.startDate),
                    systemImage: "clock"
                )

                Spacer()

                let secs = event.startDate.timeIntervalSince(now)
                if secs > 0 {
                    Text("in \(formatCountdown(secs))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(
            cornerRadius: 8
        ))
    }

    private var statusDot: some View {
        Circle()
            .fill(monitor.isRunning ? .green : .red)
            .frame(width: 8, height: 8)
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins < 1 { return "\(secs)s" }
        if mins < 60 { return "\(mins)m \(secs)s" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}
