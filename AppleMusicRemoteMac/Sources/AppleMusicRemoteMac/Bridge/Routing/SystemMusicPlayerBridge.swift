//
//  SystemMusicPlayerBridge.swift
//  AppleMusicRemoteMac
//
//  Direct native Apple Music catalog playback inside macOS `Music.app` via `MPMusicPlayerController.systemMusicPlayer`
//  and `MPMusicPlayerStoreQueueDescriptor` (`MediaPlayer.framework`).
//  Plays exact catalog songs in 100% Bit-Perfect ALAC Lossless & Hi-Res (up to 24-bit / 192 kHz)
//  with ZERO `/v1/me/library` additions, ZERO playlists, ZERO cloud-library sync spinners,
//  zero AppleEvent polling contention, and full dynamic account storefront, locale, cross-script title, and ISRC fallback support.
//

import AppKit
import Foundation
import ObjectiveC

public final class SystemMusicPlayerBridge: @unchecked Sendable {
    public static let shared = SystemMusicPlayerBridge()

    private let bridgeLock = NSLock()
    private var didLoadFramework = false
    private var didRegisterNotifications = false
    private var cachedSystemPlayer: NSObject?
    private var cachedDescriptorClass: AnyClass?

    private let notifCondition = NSCondition()
    private let notifQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.amr.systemMusicPlayer.notifications"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private var lastPlayerInfoState: String = ""
    private var lastPlayerInfoName: String = ""
    private var lastPlayerInfoArtist: String = ""
    private var lastPlayerInfoAt: Date = .distantPast

    private typealias AllocFn = @convention(c) (AnyClass, Selector) -> Unmanaged<NSObject>
    private typealias InitStoreIDsFn = @convention(c) (NSObject, Selector, NSArray) -> Unmanaged<NSObject>
    private typealias SetStringFn = @convention(c) (AnyObject, Selector, NSString) -> Void
    private typealias SetTwoStringsFn = @convention(c) (AnyObject, Selector, NSString, NSString) -> Void
    private typealias SetObjFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias SetIntFn = @convention(c) (AnyObject, Selector, Int) -> Void
    private typealias GetIntFn = @convention(c) (AnyObject, Selector) -> Int
    private typealias VoidCmdFn = @convention(c) (AnyObject, Selector) -> Void
    private typealias PrepareCompletionBlock = @convention(block) (NSError?) -> Void
    private typealias PrepareFn = @convention(c) (AnyObject, Selector, @escaping PrepareCompletionBlock) -> Void

    private init() {}

    private func registerNotificationObserverIfNeededLocked() {
        guard !didRegisterNotifications else { return }
        didRegisterNotifications = true
        let handler: (Notification) -> Void = { [weak self] notif in
            guard let self = self, let info = notif.userInfo else { return }
            let state = ((info["Player State"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = ((info["Name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = ((info["Artist"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.notifCondition.lock()
            self.lastPlayerInfoState = state
            self.lastPlayerInfoName = name
            self.lastPlayerInfoArtist = artist
            self.lastPlayerInfoAt = Date()
            self.notifCondition.broadcast()
            self.notifCondition.unlock()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: notifQueue,
            using: handler
        )
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil,
            queue: notifQueue,
            using: handler
        )
    }

    private func ensureSystemPlayerLoaded() -> (player: NSObject, descriptorClass: AnyClass)? {
        bridgeLock.lock()
        defer { bridgeLock.unlock() }

        registerNotificationObserverIfNeededLocked()
        if let p = cachedSystemPlayer, let d = cachedDescriptorClass {
            return (p, d)
        }
        if !didLoadFramework {
            didLoadFramework = true
            _ = dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", RTLD_NOW)
        }
        guard let ctrlClass = NSClassFromString("MPMusicPlayerController") as? NSObject.Type,
              let descClass = NSClassFromString("MPMusicPlayerStoreQueueDescriptor") else {
            return nil
        }
        let sysSel = NSSelectorFromString("systemMusicPlayer")
        guard (ctrlClass as AnyObject).responds(to: sysSel),
              let unmanaged = (ctrlClass as AnyObject).perform(sysSel),
              let playerObj = unmanaged.takeUnretainedValue() as? NSObject else {
            return nil
        }
        cachedSystemPlayer = playerObj
        cachedDescriptorClass = descClass
        return (playerObj, descClass)
    }

    private func invokeVoid(_ target: AnyObject, selectorName: String) {
        let sel = NSSelectorFromString(selectorName)
        guard let cls = object_getClass(target),
              let m = class_getInstanceMethod(cls, sel) else { return }
        let fn = unsafeBitCast(method_getImplementation(m), to: VoidCmdFn.self)
        fn(target, sel)
    }

    private func invokeSetInt(_ target: AnyObject, selectorName: String, value: Int) {
        let sel = NSSelectorFromString(selectorName)
        guard let cls = object_getClass(target),
              let m = class_getInstanceMethod(cls, sel) else { return }
        let fn = unsafeBitCast(method_getImplementation(m), to: SetIntFn.self)
        fn(target, sel, value)
    }

    /// Proactively warms up `MPMusicPlayerController.systemMusicPlayer` at launch so macOS Media Library XPC
    /// authorization is established immediately during initial setup.
    @discardableResult
    public func warmupPermissionAtLaunch() -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              !AppStorageProvider.isRunningUnderXCTest,
              PlaybackRouter.shared.urlOpener == nil else {
            return false
        }
        guard let (player, _) = ensureSystemPlayerLoaded() else {
            return false
        }
        let stateSel = NSSelectorFromString("playbackState")
        if let cls = object_getClass(player),
           let m = class_getInstanceMethod(cls, stateSel) {
            let fn = unsafeBitCast(method_getImplementation(m), to: GetIntFn.self)
            _ = fn(player, stateSel)
        }
        return true
    }

    /// Stops `Music.app` playback directly over XPC (`0` AppleEvents, `< 1 ms`).
    @discardableResult
    public func stop() -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment, PlaybackRouter.shared.urlOpener == nil else {
            return false
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty,
              let (player, _) = ensureSystemPlayerLoaded() else {
            return false
        }
        invokeVoid(player, selectorName: "stop")
        return true
    }

    /// Gentle serialized fallback probe used ONLY if `DistributedNotificationCenter` hasn't emitted `playerInfo` yet.
    /// Never contends with busy `AppleScriptExecutor` and never triggers false watchdog kills.
    private func probeLivePlayingTrackIfIdle() -> (name: String, artist: String)? {
        guard !AppleScriptExecutor.shared.isBusy else { return nil }
        let sep = "||AMR||"
        let (ok, raw) = AppleScriptExecutor.shared.execute("""
        tell application "Music"
            try
                with timeout of 0.7 seconds
                    if player state is not playing then return "not_playing"
                    set ct to current track
                    if ct is missing value then return "not_playing"
                    return "playing\(sep)" & (name of ct as string) & "\(sep)" & (artist of ct as string)
                end timeout
            on error
                return "err"
            end try
        end tell
        """, maxWait: 0.9, reportTimeout: false)
        guard ok, let out = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let parts = out.components(separatedBy: sep)
        guard parts.first == "playing", parts.count >= 3 else { return nil }
        let liveName = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let liveArtist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !liveName.isEmpty else { return nil }
        return (liveName, liveArtist)
    }

    private func dispatchStoreQueueToMusicApp(
        player: NSObject,
        descriptorClass: AnyClass,
        storeIds: [String],
        startStoreId: String,
        storefront: String,
        isRepeatOne: Bool,
        trackName: String,
        trackArtist: String
    ) -> Bool {
        guard !storeIds.isEmpty else { return false }

        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithStoreIDs:")
        guard let allocMethod = class_getClassMethod(descriptorClass, allocSel),
              let initMethod = class_getInstanceMethod(descriptorClass, initSel) else {
            return false
        }

        let allocFn = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)
        let rawObj = allocFn(descriptorClass, allocSel).takeUnretainedValue()
        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitStoreIDsFn.self)
        let descriptor = initFn(rawObj, initSel, storeIds as NSArray).takeUnretainedValue()

        let startSel = NSSelectorFromString("setStartItemID:")
        if let startMethod = class_getInstanceMethod(descriptorClass, startSel) {
            let setStartFn = unsafeBitCast(method_getImplementation(startMethod), to: SetStringFn.self)
            setStartFn(descriptor, startSel, startStoreId as NSString)
        }

        let cleanSf = MusicKitManager.sanitizedStorefront(storefront)
        let sfSel = NSSelectorFromString("setSourceStorefront:forItemWithStoreID:")
        if !cleanSf.isEmpty, let sfMethod = class_getInstanceMethod(descriptorClass, sfSel) {
            let setSfFn = unsafeBitCast(method_getImplementation(sfMethod), to: SetTwoStringsFn.self)
            for sid in storeIds {
                setSfFn(descriptor, sfSel, cleanSf as NSString, sid as NSString)
            }
        }

        let setDescSel = NSSelectorFromString("setQueueWithDescriptor:")
        guard let playerClass = object_getClass(player),
              let setDescMethod = class_getInstanceMethod(playerClass, setDescSel) else {
            return false
        }
        BitPerfectLogMonitor.shared.beginExplicitTrackSwitch()
        let setDescFn = unsafeBitCast(method_getImplementation(setDescMethod), to: SetObjFn.self)
        setDescFn(player, setDescSel, descriptor)

        // MPMusicPlayerShuffleModeOff = 1; MPMusicPlayerRepeatModeNone = 1, MPMusicPlayerRepeatModeOne = 2
        invokeSetInt(player, selectorName: "setShuffleMode:", value: 1)
        invokeSetInt(player, selectorName: "setRepeatMode:", value: isRepeatOne ? 2 : 1)

        let prepSel = NSSelectorFromString("prepareToPlayWithCompletionHandler:")
        if let prepMethod = class_getInstanceMethod(playerClass, prepSel) {
            let prepFn = unsafeBitCast(method_getImplementation(prepMethod), to: PrepareFn.self)
            let sema = DispatchSemaphore(value: 0)
            if Thread.isMainThread {
                // Never block DispatchQueue.main while MediaPlayer dispatches XPC completion on main!
                var completed = false
                prepFn(player, prepSel) { err in
                    if let err = err {
                        NSLog("[SystemMusicPlayerBridge] ⚠️ prepareToPlay error for cid=%@: %@", startStoreId, err.localizedDescription)
                    }
                    completed = true
                    sema.signal()
                }
                let deadline = Date().addingTimeInterval(1.5)
                while !completed && Date() < deadline {
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
            } else {
                prepFn(player, prepSel) { err in
                    if let err = err {
                        NSLog("[SystemMusicPlayerBridge] ⚠️ prepareToPlay error for cid=%@: %@", startStoreId, err.localizedDescription)
                    }
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + 2.0)
            }
        }

        let cleanN = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanA = trackArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalKey = !cleanN.isEmpty ? "\(cleanA.lowercased()):\(cleanN.lowercased())" : nil
        let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: cleanA, title: cleanN, catalogId: startStoreId)
        BitPerfectLogMonitor.shared.endExplicitTrackSwitch(
            trackKey: canonicalKey,
            catalogId: startStoreId,
            expectedSampleRate: cachedFmt?.sampleRate,
            expectedBitDepth: cachedFmt?.bitDepth
        )
        invokeVoid(player, selectorName: "play")
        return true
    }

    /// Resolves canonical storefront catalog ID + localized variants and starts native `Music.app` ALAC Lossless / Hi-Res
    /// playback via `MPMusicPlayerController.systemMusicPlayer` with zero library or playlist mutations.
    public func playCatalogTrackSync(
        id: String?,
        url: String?,
        name: String,
        artist: String,
        expectedGeneration: UInt64
    ) -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment, PlaybackRouter.shared.urlOpener == nil else {
            return false
        }
        MusicAppProvider.shared.ensureMusicAppRunning()
        guard let (player, descriptorClass) = ensureSystemPlayerLoaded() else {
            return false
        }

        let isGenValid: () -> Bool = {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackGeneration == expectedGeneration && !PlaybackStateStore.shared.isUserPaused
            }
        }
        guard isGenValid() else { return false }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let userSf = MusicKitManager.shared.getUserStorefront().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Resolve canonical catalog ID in the signed-in account's active storefront (`userSf`)
        var rawCid: String? = nil
        if let u = url, let comp = URLComponents(string: u) {
            if let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               let num = Int(qi), num >= 1_000_000 {
                rawCid = qi
            }
        }
        if rawCid == nil, let rid = id?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(rid), num >= 1_000_000, !ITLibraryReader.isSyntheticTrackId(num) {
            rawCid = rid
        }
        if rawCid == nil, !cleanName.isEmpty,
           let cached = MusicKitManager.shared.getCachedTrackCatalogId(name: cleanName, artist: cleanArtist, album: ""),
           let num = Int(cached), num >= 1_000_000 {
            rawCid = cached
        }
        if rawCid == nil && !cleanName.isEmpty {
            if let sfCid = awaitCatalogLookup({
                await MusicKitManager.shared.resolveCatalogSongIdInUserStorefront(name: cleanName, artist: cleanArtist)
            }), !sfCid.isEmpty {
                rawCid = sfCid
            }
        }
        guard let initialCid = rawCid, !initialCid.isEmpty else { return false }
        let originalCid = initialCid
        var targetCid = initialCid
        var triedIds: Set<String> = [originalCid]

        if let prefAlt = MusicKitManager.shared.preferredAlternateCatalogSong(for: targetCid) {
            targetCid = prefAlt.id
            triedIds.insert(prefAlt.id)
            MusicKitManager.shared.appendCachedTitleVariant(catalogId: originalCid, name: prefAlt.name, artist: prefAlt.artist)
        } else if MusicKitManager.shared.isUnstageableCatalogId(targetCid) {
            let unstageableCid = targetCid
            let excludedSnap = triedIds
            if let firstAlt = awaitCatalogLookup({
                await MusicKitManager.shared.resolveAlternateCatalogSongs(
                    catalogId: unstageableCid,
                    name: cleanName,
                    artist: cleanArtist,
                    excludingIds: excludedSnap
                ).first
            }) {
                MusicKitManager.shared.recordPreferredAlternateCatalogSong(for: originalCid, alternate: firstAlt)
                targetCid = firstAlt.id
                triedIds.insert(firstAlt.id)
            } else {
                MusicKitManager.shared.unmarkUnstageableCatalogId(targetCid)
            }
        }

        // Fast 0 ms RAM cache check before starting MPMusicPlayerController; if cached as 404 (`durationSeconds == nil`), switch storefront ID first
        var inspection = MusicKitManager.shared.cachedDirectCloudEligibility(catalogId: targetCid)
        if let info = inspection, info.durationSeconds == nil, !cleanName.isEmpty {
            let excludedSnap = triedIds
            if let sfAlt = awaitCatalogLookup({
                await MusicKitManager.shared.resolveAlternateCatalogSongs(
                    catalogId: originalCid,
                    name: cleanName,
                    artist: cleanArtist,
                    excludingIds: excludedSnap
                ).first
            }) {
                MusicKitManager.shared.recordPreferredAlternateCatalogSong(for: originalCid, alternate: sfAlt)
                targetCid = sfAlt.id
                triedIds.insert(sfAlt.id)
                inspection = MusicKitManager.shared.cachedDirectCloudEligibility(catalogId: targetCid)
            }
        }

        if let durSec = inspection?.durationSeconds, durSec > 0 {
            PlaybackStateStore.shared.withLock {
                guard PlaybackStateStore.shared.playbackGeneration == expectedGeneration else { return }
                let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                if idx >= 0 && idx < PlaybackStateStore.shared.activeCustomQueue.count {
                    if PlaybackStateStore.shared.activeCustomQueue[idx].duration <= 0 {
                        PlaybackStateStore.shared.activeCustomQueue[idx].duration = durSec
                    }
                    PlaybackStateStore.shared.activeCustomQueue[idx].catalogId = targetCid
                }
            }
        }

        // 2. Populate localized title/artist variants (`名前を呼ぶよ` <-> `Namae wo Yobuyo`) immediately from cache + concurrently via async Task while Music.app buffers
        var initialVariants = MusicKitManager.shared.cachedTitleVariants(catalogId: originalCid)
        for v in MusicKitManager.shared.cachedTitleVariants(catalogId: targetCid)
            where !initialVariants.contains(where: { $0.name == v.name && $0.artist == v.artist }) {
            initialVariants.append(v)
        }
        if let catName = inspection?.catalogName, !catName.isEmpty {
            let catArt = inspection?.catalogArtist ?? cleanArtist
            if !initialVariants.contains(where: { $0.name == catName && $0.artist == catArt }) {
                initialVariants.append((name: catName, artist: catArt))
            }
        }
        if !initialVariants.isEmpty {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == expectedGeneration {
                    PlaybackStateStore.shared.activeTrackTitleVariants = initialVariants
                }
            }
        }
        let cidForAsyncWarmup = targetCid
        Task.detached(priority: .userInitiated) { [weak self] in
            async let inspTask = MusicKitManager.shared.inspectCatalogSongDirectCloudEligibility(catalogId: cidForAsyncWarmup)
            async let varsTask = MusicKitManager.shared.resolveCatalogSongTitleVariants(catalogId: cidForAsyncWarmup)
            let (asyncInsp, fetched) = await (inspTask, varsTask)
            var didUpdateVariants = false
            PlaybackStateStore.shared.withLock {
                guard PlaybackStateStore.shared.playbackGeneration == expectedGeneration else { return }
                if let durSec = asyncInsp?.durationSeconds, durSec > 0 {
                    let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                    if idx >= 0 && idx < PlaybackStateStore.shared.activeCustomQueue.count,
                       PlaybackStateStore.shared.activeCustomQueue[idx].duration <= 0 {
                        PlaybackStateStore.shared.activeCustomQueue[idx].duration = durSec
                    }
                }
                var merged = PlaybackStateStore.shared.activeTrackTitleVariants
                if let catName = asyncInsp?.catalogName, !catName.isEmpty {
                    let catArt = asyncInsp?.catalogArtist ?? cleanArtist
                    if !merged.contains(where: { $0.name == catName && $0.artist == catArt }) {
                        merged.append((name: catName, artist: catArt))
                        didUpdateVariants = true
                    }
                }
                for v in fetched where !merged.contains(where: { $0.name == v.name && $0.artist == v.artist }) {
                    merged.append(v)
                    didUpdateVariants = true
                }
                if didUpdateVariants {
                    PlaybackStateStore.shared.activeTrackTitleVariants = merged
                }
            }
            if didUpdateVariants, let self = self {
                self.broadcastNotifCondition()
            }
        }

        // 3. Collect up to 12 upcoming cloud catalog IDs (`0 ms`, zero network I/O) so `Music.app` plays tracks
        //    to their full natural end without early cutoff or inter-track re-initialization gaps.
        let (upcomingVerifiedIds, isRepeatOne): ([String], Bool) = PlaybackStateStore.shared.withLock {
            let repOne = (PlaybackStateStore.shared.repeatMode == "one")
            guard !repOne else { return ([], true) }
            let q = PlaybackStateStore.shared.activeCustomQueue
            let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
            var nextIds: [String] = []
            if curIdx >= 0 && curIdx + 1 < q.count {
                var prevCid = targetCid
                for idx in (curIdx + 1)..<min(q.count, curIdx + 13) {
                    let ut = q[idx]
                    let isDownloadedLocal = ut.isLocal == true && (
                        ut.numericId == nil || ITLibraryReader.shared.downloadedFileTrackStatus(forTrackId: ut.numericId!) != false
                    )
                    if isDownloadedLocal { break }
                    guard let rawNextCid = MusicKitManager.extractNumericCatalogId(from: ut) else { break }
                    let effNextCid = MusicKitManager.shared.preferredAlternateCatalogSong(for: rawNextCid)?.id ?? rawNextCid
                    guard effNextCid != prevCid,
                          !MusicKitManager.shared.isUnstageableCatalogId(effNextCid) else { break }
                    let cachedInfo = MusicKitManager.directInspectionCacheLock.withLock {
                        MusicKitManager.directInspectionCache[effNextCid]
                    }
                    if let ci = cachedInfo, ci.durationSeconds == nil {
                        break
                    }
                    nextIds.append(effNextCid)
                    prevCid = effNextCid
                }
            }
            return (nextIds, false)
        }

        guard isGenValid() else { return false }

        func waitForTrackConfirmation(since dispatchStartedAt: Date, expectedProbe: TrackInfo, waitSeconds: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(waitSeconds)
            var lastFallbackProbeAt: Date = .distantPast

            while Date() < deadline {
                guard isGenValid() else { return false }

                let alreadyConfirmed = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == expectedGeneration && PlaybackStateStore.shared.currentTrackPlaybackConfirmed
                }
                if alreadyConfirmed {
                    return true
                }

                notifCondition.lock()
                let nState = lastPlayerInfoState
                let nName = lastPlayerInfoName
                let nArtist = lastPlayerInfoArtist
                let nAt = lastPlayerInfoAt
                notifCondition.unlock()

                if nAt >= dispatchStartedAt.addingTimeInterval(-0.05),
                   nState == "playing",
                   !nName.isEmpty,
                   (expectedProbe.name.isEmpty || QueueManager.shared.matchesExpectedQueueTrack(expectedProbe, candidateName: nName, candidateArtist: nArtist)) {
                    return true
                }

                let now = Date()
                if now.timeIntervalSince(dispatchStartedAt) >= 0.85,
                   now.timeIntervalSince(lastFallbackProbeAt) >= 0.95,
                   let live = probeLivePlayingTrackIfIdle(),
                   (expectedProbe.name.isEmpty || QueueManager.shared.matchesExpectedQueueTrack(expectedProbe, candidateName: live.name, candidateArtist: live.artist)) {
                    return true
                }
                if now.timeIntervalSince(dispatchStartedAt) >= 0.85 && now.timeIntervalSince(lastFallbackProbeAt) >= 0.95 {
                    lastFallbackProbeAt = now
                }

                let waitUntil = min(deadline, Date().addingTimeInterval(0.45))
                notifCondition.lock()
                if lastPlayerInfoAt <= nAt && Date() < waitUntil {
                    _ = notifCondition.wait(until: waitUntil)
                }
                notifCondition.unlock()
            }
            return false
        }

        func attemptStartAndConfirm(storeIds: [String], primaryId: String, expectedProbe: TrackInfo, waitSeconds: TimeInterval) -> Bool {
            let dispatchStartedAt = Date()
            guard dispatchStoreQueueToMusicApp(
                player: player,
                descriptorClass: descriptorClass,
                storeIds: storeIds,
                startStoreId: primaryId,
                storefront: userSf,
                isRepeatOne: isRepeatOne,
                trackName: expectedProbe.name,
                trackArtist: expectedProbe.artist
            ) else {
                return false
            }
            return waitForTrackConfirmation(since: dispatchStartedAt, expectedProbe: expectedProbe, waitSeconds: waitSeconds)
        }

        let probe = TrackInfo(id: targetCid, numericId: nil, name: cleanName, artist: cleanArtist, album: "", duration: 0, catalogId: targetCid)
        let primaryQueueIds = [targetCid] + upcomingVerifiedIds
        let t0 = Date()
        let primaryStartedAt = Date()
        if attemptStartAndConfirm(storeIds: primaryQueueIds, primaryId: targetCid, expectedProbe: probe, waitSeconds: 4.2) {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == expectedGeneration {
                    PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds = upcomingVerifiedIds
                }
            }
            NSLog("[SystemMusicPlayerBridge] ⚡️ Playing cloud track '%@ — %@' natively in Music.app (cid=%@, sf=%@, +%d queued, %.2fs, 0 library writes)",
                  cleanArtist, cleanName, targetCid, userSf, upcomingVerifiedIds.count, Date().timeIntervalSince(t0))
            return true
        }

        // 4. ISRC / Multi-Locale Alternate Fallback for distributor-broken IDs (e.g. `6829729404` -> `6817136270`)
        guard isGenValid() else { return false }
        let alternatesSnapshot = triedIds
        let alternates = awaitCatalogLookup({
            await MusicKitManager.shared.resolveAlternateCatalogSongs(
                catalogId: originalCid,
                name: cleanName,
                artist: cleanArtist,
                excludingIds: alternatesSnapshot
            )
        }) ?? []
        for alt in alternates.prefix(2) {
            guard isGenValid() else { return false }
            triedIds.insert(alt.id)
            MusicKitManager.shared.appendCachedTitleVariant(catalogId: originalCid, name: alt.name, artist: alt.artist)
            MusicKitManager.shared.appendCachedTitleVariant(catalogId: alt.id, name: alt.name, artist: alt.artist)
            PlaybackStateStore.shared.withLock {
                guard PlaybackStateStore.shared.playbackGeneration == expectedGeneration else { return }
                var merged = PlaybackStateStore.shared.activeTrackTitleVariants
                if !alt.name.isEmpty && !merged.contains(where: { $0.name == alt.name && $0.artist == alt.artist }) {
                    merged.append((name: alt.name, artist: alt.artist))
                    PlaybackStateStore.shared.activeTrackTitleVariants = merged
                }
            }
            let altProbe = TrackInfo(
                id: alt.id,
                numericId: nil,
                name: cleanName.isEmpty ? alt.name : cleanName,
                artist: cleanArtist.isEmpty ? alt.artist : cleanArtist,
                album: "",
                duration: 0,
                catalogId: alt.id
            )
            invokeVoid(player, selectorName: "stop")
            if attemptStartAndConfirm(storeIds: [alt.id] + upcomingVerifiedIds, primaryId: alt.id, expectedProbe: altProbe, waitSeconds: 4.4) {
                MusicKitManager.shared.markUnstageableCatalogId(originalCid)
                MusicKitManager.shared.recordPreferredAlternateCatalogSong(for: originalCid, alternate: alt)
                PlaybackStateStore.shared.withLock {
                    guard PlaybackStateStore.shared.playbackGeneration == expectedGeneration else { return }
                    PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds = upcomingVerifiedIds
                    let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                    if idx >= 0 && idx < PlaybackStateStore.shared.activeCustomQueue.count {
                        PlaybackStateStore.shared.activeCustomQueue[idx].catalogId = alt.id
                    }
                }
                NSLog("[SystemMusicPlayerBridge] 🔄 Switched '%@ — %@' from %@ to ISRC/storefront alternate %@ (%.2fs, 0 library writes)",
                      cleanArtist, cleanName, originalCid, alt.id, Date().timeIntervalSince(t0))
                return true
            }
        }

        // Give slow CDN streams one extra 2.4s grace check if no alternate existed (`anifi — SPECIALZ`)
        if alternates.isEmpty && waitForTrackConfirmation(since: primaryStartedAt, expectedProbe: probe, waitSeconds: 2.4) {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == expectedGeneration {
                    PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds = upcomingVerifiedIds
                }
            }
            NSLog("[SystemMusicPlayerBridge] ⚡️ Playing cloud track '%@ — %@' after CDN buffer (cid=%@, %.2fs, 0 library writes)",
                  cleanArtist, cleanName, targetCid, Date().timeIntervalSince(t0))
            return true
        }

        return false
    }

    private func broadcastNotifCondition() {
        notifCondition.lock()
        notifCondition.broadcast()
        notifCondition.unlock()
    }

    private func awaitCatalogLookup<T>(_ operation: @escaping @Sendable () async -> T?, timeout: TimeInterval = 4.0) -> T? {
        let box = CatalogLookupWaitBox<T>()
        let task = Task.detached(priority: .userInitiated) {
            let res = await operation()
            box.complete(with: res)
        }
        let result = box.waitForResult(timeout: timeout)
        if !result.finished {
            task.cancel()
        }
        return result.value
    }
}

private final class CatalogLookupWaitBox<T>: @unchecked Sendable {
    private let cond = NSCondition()
    private var finished = false
    private var value: T?

    func complete(with result: T?) {
        cond.lock()
        value = result
        finished = true
        cond.signal()
        cond.unlock()
    }

    func waitForResult(timeout: TimeInterval) -> (finished: Bool, value: T?) {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        while !finished && Date() < deadline {
            _ = cond.wait(until: deadline)
        }
        let done = finished
        let out = value
        cond.unlock()
        return (done, out)
    }
}
