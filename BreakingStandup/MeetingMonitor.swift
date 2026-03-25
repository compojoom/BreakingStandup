import EventKit
import Foundation
import Combine
import SwiftUI
import UserNotifications

/// Core service: watches the calendar and fires the jingle
/// at the right moment before each meeting.
final class MeetingMonitor: ObservableObject {
    // MARK: - Published state

    @Published var nextEvent: EKEvent?
    @Published var currentEvent: EKEvent?
    @Published var isRunning = false
    @Published var lastError: String?

    // MARK: - Settings (persisted via UserDefaults)

    @AppStorage("secondsBefore") var secondsBefore: Int = 15
    @AppStorage("disabledCalendarIDs") var disabledCalendarIDsRaw = ""

    // MARK: - Private

    private let store = EKEventStore()
    let jinglePlayer = JinglePlayer()
    private var timer: Timer?
    private var playedEventIDs: Set<String> = []

    var disabledCalendarIDs: Set<String> {
        get {
            Set(
                disabledCalendarIDsRaw.split(separator: ",")
                    .map(String.init)
            )
        }
        set {
            disabledCalendarIDsRaw = newValue.joined(separator: ",")
        }
    }

    // MARK: - Calendar access

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Lifecycle

    func start() {
        isRunning = true
        refreshNextEvent()

        timer = Timer.scheduledTimer(
            withTimeInterval: 5, repeats: true
        ) { [weak self] _ in
            self?.tick()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarChanged),
            name: .EKEventStoreChanged,
            object: store
        )
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Core loop

    private func tick() {
        // Update the published nextEvent so the popover countdown refreshes
        refreshNextEvent()

        guard let event = nextEvent else { return }

        let secsUntilStart = event.startDate.timeIntervalSinceNow

        // Already played or event has passed
        guard secsUntilStart > -5,
              !playedEventIDs.contains(eventID(event)) else {
            return
        }

        // Fire when within the trigger window
        if secsUntilStart <= Double(secondsBefore) {
            playedEventIDs.insert(eventID(event))
            fireJingle(for: event)
        }
    }

    @objc private func calendarChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshNextEvent()
        }
    }

    func refreshNextEvent() {
        let now = Date()
        let end = Calendar.current.date(
            byAdding: .hour, value: 8, to: now
        )!
        let predicate = store.predicateForEvents(
            withStart: now, end: end, calendars: nil
        )

        let disabled = disabledCalendarIDs
        let allEvents = store.events(matching: predicate)
            .filter { !disabled.contains($0.calendar.calendarIdentifier) }
            .sorted { $0.startDate < $1.startDate }

        // Current event: started but not yet ended
        let current = allEvents.first {
            $0.startDate <= now && $0.endDate > now
        }

        // Next event: starts in the future, not yet played
        let next = allEvents.first {
            $0.startDate > now
            && !playedEventIDs.contains(eventID($0))
        }

        DispatchQueue.main.async {
            self.currentEvent = current
            self.nextEvent = next
        }
    }

    // MARK: - Playback

    private func fireJingle(for event: EKEvent) {
        jinglePlayer.play()
        sendNotification(for: event)
        refreshNextEvent()
    }

    // MARK: - Notifications

    private func sendNotification(for event: EKEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting: \(event.title ?? "Untitled")"
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        content.body = "Starting at \(fmt.string(from: event.startDate))"
        content.sound = .none

        let request = UNNotificationRequest(
            identifier: eventID(event),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func eventID(_ event: EKEvent) -> String {
        event.calendarItemExternalIdentifier ?? event.eventIdentifier
    }

    var allCalendars: [EKCalendar] {
        store.calendars(for: .event)
    }

    func resetPlayedEvents() {
        playedEventIDs.removeAll()
        refreshNextEvent()
    }
}
