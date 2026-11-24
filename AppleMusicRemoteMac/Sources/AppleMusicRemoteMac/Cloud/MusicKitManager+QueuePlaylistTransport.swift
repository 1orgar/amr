//
//  MusicKitManager+QueuePlaylistTransport.swift
//  AppleMusicRemoteMac
//
//  Explicit user library song addition (`addSongsToUserLibrarySync`, ONLY on manual "+ Add to Library").
//  Automatic cloud song / playlist staging during playback or preview is PERMANENTLY DISABLED (`0` library writes).
//

import Foundation

extension MusicKitManager {

    /// Explicitly adds catalog song IDs to the user's permanent Apple Music Library (`POST /v1/me/library?ids[songs]=...`).
    /// Used ONLY when the user clicks "+ Add to Library" on a song — NEVER for playback or preview!
    @discardableResult
    public func addSongsToUserLibrary(catalogIds: [String]) async -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return true }
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return false
        }
        let validIds = Array(Set(catalogIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { Int($0) != nil && !$0.isEmpty })).prefix(25)
        guard !validIds.isEmpty else { return false }

        let idsParam = validIds.joined(separator: ",")
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/me/library",
            queryItems: [URLQueryItem(name: "ids[songs]", value: idsParam)]
        ) else { return false }

        var req = URLRequest(url: url, timeoutInterval: 4.0)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return false
        }
        return (200...299).contains(http.statusCode)
    }

    @discardableResult
    public func addSongsToUserLibrarySync(catalogIds: [String]) -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return true }
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return false
        }
        let validIds = Array(Set(catalogIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { Int($0) != nil && !$0.isEmpty })).prefix(25)
        guard !validIds.isEmpty else { return false }

        let idsParam = validIds.joined(separator: ",")
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/me/library",
            queryItems: [URLQueryItem(name: "ids[songs]", value: idsParam)]
        ) else { return false }

        var req = URLRequest(url: url, timeoutInterval: 4.0)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var ok = false
        let task = session.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                boxLock.lock()
                ok = true
                boxLock.unlock()
            }
            sema.signal()
        }
        task.resume()
        if sema.wait(timeout: .now() + 4.2) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        defer { boxLock.unlock() }
        return ok
    }

    /// Permanently disabled: cloud tracks play directly via `SystemMusicPlayerBridge` without ever mutating `/v1/me/library`.
    @discardableResult
    public func stageCloudSongsInLibrarySync(
        catalogIds: [String],
        bypassDedup: Bool = false,
        triggerMenuSyncNudge: Bool = false
    ) -> Bool {
        return false
    }

    /// Permanently disabled: never creates `"Очередь AMR"` or `"Буфер AMR"` playlists in `/v1/me/library/playlists`.
    @discardableResult
    public func stageCloudSongsInQueuePlaylistSync(
        catalogIds: [String],
        bypassDedup: Bool = false,
        triggerMenuSyncNudge: Bool = false
    ) -> Bool {
        return false
    }
}
