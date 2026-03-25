import SwiftUI

@main
struct BreakingStandupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.meetingMonitor)
                .environmentObject(appDelegate.meetingMonitor.jinglePlayer)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let meetingMonitor = MeetingMonitor()
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager(monitor: meetingMonitor)
        meetingMonitor.start()
    }
}
