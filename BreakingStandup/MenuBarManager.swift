import AppKit
import SwiftUI
import Combine
import EventKit

/// Manages the menu bar status item and its popover.
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var pulseTimer: Timer?
    private weak var monitor: MeetingMonitor?

    init(monitor: MeetingMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "Breaking Standup"
            )
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hostingView = NSHostingView(
            rootView: MenuBarPopoverView()
                .environmentObject(monitor)
        )
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = hostingView
        popover.contentSize = NSSize(width: 300, height: 280)
        popover.behavior = .transient

        // React to state changes
        monitor.$nextEvent
            .combineLatest(monitor.$currentEvent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] next, current in
                self?.updateStatusBar(
                    next: next, current: current, monitor: monitor
                )
            }
            .store(in: &cancellables)

        monitor.jinglePlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.updatePlayingState(playing, monitor: monitor)
            }
            .store(in: &cancellables)

        // Bring settings window to front when it appears
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow,
               window.title.contains("Settings") {
                window.level = .floating
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    window.level = .normal
                }
            }
        }

        // Request calendar permission on first launch
        Task {
            let granted = await monitor.requestAccess()
            if !granted {
                print("Calendar access not granted")
            }
        }
    }

    // MARK: - Status bar updates

    private func updateStatusBar(
        next: EKEvent?,
        current: EKEvent?,
        monitor: MeetingMonitor
    ) {
        guard let button = statusItem?.button else { return }

        // Don't override while playing
        if monitor.jinglePlayer.isPlaying { return }

        if let current = current {
            button.image = NSImage(
                systemSymbolName: "person.wave.2",
                accessibilityDescription: "In meeting"
            )
            button.title = " \(truncate(current.title ?? "Meeting", to: 20))"
        } else if let next = next {
            let secs = next.startDate.timeIntervalSinceNow
            if secs < 300 {
                // Less than 5 min away — show the name
                button.title = " \(truncate(next.title ?? "Meeting", to: 20))"
            } else {
                button.title = ""
            }
            button.image = NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "Breaking Standup"
            )
        } else {
            button.image = NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "Breaking Standup"
            )
            button.title = ""
        }
    }

    private func updatePlayingState(
        _ playing: Bool, monitor: MeetingMonitor
    ) {
        guard let button = statusItem?.button else { return }

        if playing {
            let event = monitor.nextEvent ?? monitor.currentEvent
            let name = truncate(event?.title ?? "Meeting", to: 20)
            playingEventStart = event?.startDate
            playingEventName = name

            button.image = NSImage(
                systemSymbolName: "stop.fill",
                accessibilityDescription: "Stop music"
            )
            updatePlayingTitle()
            startPulse()
        } else {
            stopPulse()
            playingEventStart = nil
            playingEventName = nil
            button.wantsLayer = true
            button.layer?.backgroundColor = nil
            monitor.refreshNextEvent()
            updateStatusBar(
                next: monitor.nextEvent,
                current: monitor.currentEvent,
                monitor: monitor
            )
        }
    }

    // MARK: - Pulse animation

    private var playingEventStart: Date?
    private var playingEventName: String?
    private var pulsePhase = false

    private func updatePlayingTitle() {
        guard let button = statusItem?.button,
              let name = playingEventName else { return }

        if let start = playingEventStart {
            let secs = max(0, Int(start.timeIntervalSinceNow))
            let mins = secs / 60
            let sec = secs % 60
            button.title = " \(name) in \(mins):\(String(format: "%02d", sec))"
        } else {
            button.title = " \(name)"
        }
    }

    private func pulseInterval() -> TimeInterval {
        guard let start = playingEventStart else { return 0.5 }
        let secs = max(0, start.timeIntervalSinceNow)
        if secs > 5 { return 0.5 }
        if secs > 3 { return 0.25 }
        return 0.12
    }

    private func startPulse() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.masksToBounds = true
        pulsePhase = false
        schedulePulseTick()
    }

    private func schedulePulseTick() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(
            withTimeInterval: pulseInterval(), repeats: false
        ) { [weak self] _ in
            self?.pulseTick()
        }
    }

    private func pulseTick() {
        guard let button = statusItem?.button,
              let monitor = monitor,
              monitor.jinglePlayer.isPlaying else {
            stopPulse()
            return
        }

        // Auto-stop when countdown reaches 0
        if let start = playingEventStart,
           start.timeIntervalSinceNow <= 0 {
            monitor.jinglePlayer.stop()
            return
        }

        pulsePhase.toggle()
        button.layer?.backgroundColor = pulsePhase
            ? NSColor.systemRed.withAlphaComponent(0.7).cgColor
            : nil

        updatePlayingTitle()
        schedulePulseTick()
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        if let button = statusItem?.button {
            button.layer?.backgroundColor = nil
            button.layer?.cornerRadius = 0
            button.appearsDisabled = false
        }
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        // If music is playing, clicking the icon stops it
        if let monitor = monitor, monitor.jinglePlayer.isPlaying {
            monitor.jinglePlayer.stop()
            return
        }

        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor?.refreshNextEvent()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            popover.contentViewController?.view.window?
                .makeKey()
        }
    }

    // MARK: - Helpers

    private func truncate(_ text: String, to length: Int) -> String {
        if text.count <= length { return text }
        return String(text.prefix(length - 1)) + "…"
    }
}
