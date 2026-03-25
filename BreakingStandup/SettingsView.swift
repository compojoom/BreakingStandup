import SwiftUI
import EventKit

struct SettingsView: View {
    @EnvironmentObject var monitor: MeetingMonitor
    @EnvironmentObject var jinglePlayer: JinglePlayer

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            calendarsTab
                .tabItem { Label("Calendars", systemImage: "calendar") }
            audioTab
                .tabItem { Label("Audio", systemImage: "music.note") }
        }
        .frame(width: 420, height: 320)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker(
                    "Play jingle",
                    selection: $monitor.secondsBefore
                ) {
                    Text("5 seconds before").tag(5)
                    Text("10 seconds before").tag(10)
                    Text("15 seconds before").tag(15)
                    Text("30 seconds before").tag(30)
                    Text("60 seconds before").tag(60)
                }

                LaunchAtLoginToggle()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Calendars Tab

    private var calendarsTab: some View {
        Form {
            if monitor.authorizationStatus != .fullAccess {
                Section {
                    Label(
                        "Calendar access required",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)

                    Button("Grant Access") {
                        Task { await monitor.requestAccess() }
                    }
                }
            }

            Section("Active Calendars") {
                ForEach(
                    monitor.allCalendars, id: \.calendarIdentifier
                ) { cal in
                    CalendarToggleRow(
                        calendar: cal, monitor: monitor
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Section("Jingle") {
                HStack {
                    Image(systemName: "music.note")
                    Text(jinglePlayer.currentJingleName)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose File...") {
                        chooseAudioFile()
                    }
                }

                if jinglePlayer.hasCustomJingle {
                    Button("Reset to Default") {
                        jinglePlayer.clearCustomJingle()
                    }
                }
            }

            Section {
                Button("Preview") {
                    jinglePlayer.play()
                }
                .disabled(jinglePlayer.isPlaying)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - File picker

    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose your meeting entrance music"

        if panel.runModal() == .OK, let url = panel.url {
            _ = jinglePlayer.setCustomJingle(url: url)
        }
    }
}

// MARK: - Calendar row

private struct CalendarToggleRow: View {
    let calendar: EKCalendar
    @ObservedObject var monitor: MeetingMonitor

    private var isEnabled: Binding<Bool> {
        Binding(
            get: {
                !monitor.disabledCalendarIDs
                    .contains(calendar.calendarIdentifier)
            },
            set: { enabled in
                var ids = monitor.disabledCalendarIDs
                if enabled {
                    ids.remove(calendar.calendarIdentifier)
                } else {
                    ids.insert(calendar.calendarIdentifier)
                }
                monitor.disabledCalendarIDs = ids
                monitor.refreshNextEvent()
            }
        )
    }

    var body: some View {
        Toggle(isOn: isEnabled) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
            }
        }
    }
}

// MARK: - Launch at Login

private struct LaunchAtLoginToggle: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                LaunchAtLoginHelper.set(enabled: newValue)
            }
    }
}

enum LaunchAtLoginHelper {
    static func set(enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

import ServiceManagement
