import AVFoundation
import Foundation
import SwiftUI

/// Handles audio playback for the meeting jingle.
final class JinglePlayer: ObservableObject {
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var playbackDelegate: PlaybackDelegate?
    private var activeSecurityScope: URL?

    /// URL of the user-selected custom jingle, persisted in UserDefaults.
    @AppStorage("customJingleBookmark")
    private var customJingleBookmark: Data = Data()

    @AppStorage("customJingleName")
    private var storedJingleName: String = ""

    /// Plays the jingle: custom file if set, otherwise the bundled default.
    func play() {
        stop()

        guard let url = resolveJingleURL() else {
            print("No jingle URL available")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            playbackDelegate = PlaybackDelegate(owner: self)
            player?.delegate = playbackDelegate
            player?.play()
            isPlaying = true
        } catch {
            print("Audio error: \(error.localizedDescription)")
            stopSecurityScope()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playbackDelegate = nil
        isPlaying = false
        stopSecurityScope()
    }

    /// Sets a user-chosen audio file via security-scoped bookmark.
    /// Must be called with a URL from NSOpenPanel while it's still valid.
    func setCustomJingle(url: URL) -> Bool {
        // NSOpenPanel URLs are already security-scoped — access first
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            customJingleBookmark = bookmark
            storedJingleName = url.lastPathComponent
            objectWillChange.send()
            return true
        } catch {
            print("Bookmark error: \(error.localizedDescription)")
            // Fallback: copy file to app support directory
            return copyToAppSupport(url: url)
        }
    }

    func clearCustomJingle() {
        customJingleBookmark = Data()
        storedJingleName = ""
        // Also clean up any copied file
        if let copied = appSupportJingleURL() {
            try? FileManager.default.removeItem(at: copied)
        }
        objectWillChange.send()
    }

    var hasCustomJingle: Bool {
        !customJingleBookmark.isEmpty || appSupportJingleURL() != nil
    }

    var currentJingleName: String {
        if !storedJingleName.isEmpty {
            return storedJingleName
        }
        return "Default Jingle"
    }

    // MARK: - Private

    private func resolveJingleURL() -> URL? {
        // Try security-scoped bookmark first
        if let url = resolveBookmarkURL() {
            return url
        }
        // Try app support copy
        if let url = appSupportJingleURL(),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Fall back to bundled default
        return Bundle.main.url(
            forResource: "default_jingle", withExtension: "mp3"
        )
    }

    private func resolveBookmarkURL() -> URL? {
        guard !customJingleBookmark.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: customJingleBookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        activeSecurityScope = url

        if stale {
            _ = setCustomJingle(url: url)
        }

        return url
    }

    private func stopSecurityScope() {
        activeSecurityScope?.stopAccessingSecurityScopedResource()
        activeSecurityScope = nil
    }

    // MARK: - Fallback: copy to App Support

    private func copyToAppSupport(url: URL) -> Bool {
        guard let dir = appSupportDir() else { return false }
        let dest = dir.appendingPathComponent("custom_jingle.mp3")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            storedJingleName = url.lastPathComponent
            return true
        } catch {
            print("Copy error: \(error.localizedDescription)")
            return false
        }
    }

    private func appSupportJingleURL() -> URL? {
        guard let dir = appSupportDir() else { return nil }
        let url = dir.appendingPathComponent("custom_jingle.mp3")
        return FileManager.default.fileExists(atPath: url.path)
            ? url : nil
    }

    private func appSupportDir() -> URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("BreakingStandup") else {
            return nil
        }
        try? fm.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }
}

private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    weak var owner: JinglePlayer?

    init(owner: JinglePlayer) {
        self.owner = owner
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully: Bool
    ) {
        DispatchQueue.main.async {
            self.owner?.stop()
        }
    }
}
