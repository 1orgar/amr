//
//  MusicKitManager+CloudStagingOrchestrator.swift
//  AppleMusicRemoteMac
//
//  Read-only ISRC alternate resolution (`resolveFastIsrcBackupCatalogSongSync`),
//  read-only permanent library lookup, and launch cleanup of any historical temporary tracks.
//  Zero `/v1/me/library` writes during playback!
//

import AppKit
import Foundation

extension MusicKitManager {

    /// Resolves a fast ISRC-identical alternate catalog song (`<= 1.2s`, or `0 ms` when pre-warmed)
    /// in the user's active account storefront (`getUserStorefront()`, `getPreferredLanguageTag()`).
    internal func resolveFastIsrcBackupCatalogSongSync(
        catalogId: String,
        name: String,
        artist: String,
        excludingIds: Set<String>
    ) -> (id: String, name: String, artist: String)? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanCid = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidResourceIdentifier(cleanCid) else { return nil }

        if let preferred = preferredAlternateCatalogSong(for: cleanCid),
           !excludingIds.contains(preferred.id),
           !isUnstageableCatalogId(preferred.id) {
            return preferred
        }

        guard let devToken = getDeveloperToken() else { return nil }
        let inspection = inspectCatalogSongDirectCloudEligibilitySync(catalogId: cleanCid)
        guard let rawIsrc = inspection?.isrc?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.isValidResourceIdentifier(rawIsrc) else {
            return nil
        }

        let sf = Self.sanitizedStorefront(getUserStorefront())
        let primaryLang = getPreferredLanguageTag()
        guard let isrcUrl = Self.makeAppleMusicAPIURL(
            path: "/v1/catalog/\(sf)/songs",
            queryItems: [
                URLQueryItem(name: "filter[isrc]", value: rawIsrc),
                URLQueryItem(name: "l", value: primaryLang)
            ]
        ) else {
            return nil
        }

        var req = URLRequest(url: isrcUrl, timeoutInterval: 1.25)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(primaryLang, forHTTPHeaderField: "Accept-Language")
        if let uToken = getUserToken(), !uToken.isEmpty {
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var bestMatch: (id: String, name: String, artist: String)? = nil
        let task = session.dataTask(with: req) { [weak self] data, resp, _ in
            defer { sema.signal() }
            guard let self = self,
                  let d = data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]], !arr.isEmpty else { return }
            for item in arr {
                guard let sid = item["id"] as? String,
                      Self.isValidResourceIdentifier(sid),
                      sid != cleanCid,
                      !excludingIds.contains(sid),
                      !self.isUnstageableCatalogId(sid),
                      let attr = item["attributes"] as? [String: Any],
                      attr["playParams"] != nil else { continue }
                let sName = (attr["name"] as? String) ?? ""
                let sArtist = (attr["artistName"] as? String) ?? ""
                if !name.isEmpty && !sName.isEmpty && LibraryService.hasConflictingVersionQualifier(name, sName) {
                    continue
                }
                boxLock.lock()
                bestMatch = (id: sid, name: sName, artist: sArtist)
                boxLock.unlock()
                break
            }
        }
        task.resume()
        if sema.wait(timeout: .now() + 1.35) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        defer { boxLock.unlock() }
        return bestMatch
    }

    /// Read-only check for permanent user library tracks; never stages cloud songs in `/v1/me/library`.
    public func stageAndResolveCloudTrackInLibrarySync(
        id: String?,
        url: String?,
        name: String,
        artist: String,
        timeout: TimeInterval = 0.0,
        expectedGeneration: UInt64? = nil
    ) -> Int? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefId = id.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.flatMap { ($0 > 0 && $0 < 10_000_000) ? $0 : nil }
        guard !cleanName.isEmpty || prefId != nil else { return nil }

        let cachedVariants = cachedTitleVariants(catalogId: id)
        let altNames = cachedVariants.map(\.name).filter { !$0.isEmpty }
        let altArtists = cachedVariants.map(\.artist).filter { !$0.isEmpty }
        if let found = findTrackDatabaseIdDetailedInMusicApp(
            name: cleanName,
            artist: cleanArtist,
            preferredDbId: prefId,
            checkSubscriptionPlaylists: false,
            alternateTitles: altNames,
            alternateArtists: altArtists
        ), found.dbId > 0, found.isPermanentLibrary {
            let isTemp = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(found.dbId)
            }
            if !isTemp {
                return found.dbId
            }
        }
        return nil
    }

    /// Cleans up any legacy staged temporary tracks left over from older versions on launch.
    public func reconcilePendingStagedCatalogTracksOnLaunch() {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        let pending = PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot()
        if !pending.isEmpty && !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            for item in pending {
                if !PlaybackStateStore.shared.isTrackPermanentlySaved(id: item.catalogId, name: item.name, artist: item.artist),
                   let found = findTrackDatabaseIdDetailedInMusicApp(
                       name: item.name,
                       artist: item.artist,
                       checkSubscriptionPlaylists: false
                   ), found.dbId > 0 {
                    PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: found.dbId)
                }
                PlaybackStateStore.shared.clearPendingStagedCatalogTrack(
                    catalogId: item.catalogId,
                    name: item.name,
                    artist: item.artist
                )
            }
        }
        PlaybackStateStore.shared.cleanupStagedTemporaryTracks(keepingActiveQueue: false)
        cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false, synchronous: false)
    }
}
