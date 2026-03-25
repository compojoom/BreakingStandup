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

    @AppStorage("secondsBefore") var secondsBefore: Int = 10
    @AppStorage("disabledCalendarIDs") var disabledCalendarIDsRaw = ""

    // MARK: - Private

    private let store = EKEventStore()
    let jinglePlayer = JinglePlayer()
    private var timer: Timer?
    private var playedEventKeys: Set<String> = []
    private var scheduledJingleTimer: Timer?

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
        requestNotificationPermission()

        timer = Timer.scheduledTimer(
            withTimeInterval: 20, repeats: true
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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error = error {
                print(
                    "Notification permission error: "
                    + error.localizedDescription
                )
            }
        }
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
              !playedEventKeys.contains(eventKey(event)) else {
            return
        }

        // Schedule jingle to fire at exactly `secondsBefore`
        let triggerAt = Double(secondsBefore)
        let delay = secsUntilStart - triggerAt
        if delay <= 20, scheduledJingleTimer == nil {
            playedEventKeys.insert(eventKey(event))
            if delay <= 0 {
                fireJingle(for: event)
            } else {
                scheduledJingleTimer = Timer.scheduledTimer(
                    withTimeInterval: delay, repeats: false
                ) { [weak self] _ in
                    self?.scheduledJingleTimer = nil
                    self?.fireJingle(for: event)
                }
            }
        }
    }

    @objc private func calendarChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.scheduledJingleTimer?.invalidate()
            self?.scheduledJingleTimer = nil
            self?.refreshNextEvent()
        }
    }

    func refreshNextEvent() {
        store.reset()
        let now = Date()
        guard let end = Calendar.current.date(
            byAdding: .hour, value: 8, to: now
        ) else { return }
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

        // Next event: starts in the future
        let next = allEvents.first {
            $0.startDate > now
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
            identifier: eventKey(event),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func eventKey(_ event: EKEvent) -> String {
        let id = event.calendarItemExternalIdentifier
            ?? event.eventIdentifier
        let ts = Int(event.startDate.timeIntervalSince1970)
        return "\(id)_\(ts)"
    }

    var allCalendars: [EKCalendar] {
        store.calendars(for: .event)
    }

    func resetPlayedEvents() {
        playedEventKeys.removeAll()
        refreshNextEvent()
    }
}
