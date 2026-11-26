//
//  SystemPermissionsManager.swift
//  AppleMusicRemoteMac
//
//  Proactive first-launch macOS TCC permission preflight for headless Mac mini deployments:
//  1. Automation (`com.apple.Music` via `AEDeterminePermissionToAutomateTarget`)
//  2. Media & Apple Music (`MPMediaLibrary.requestAuthorization:` + `ITLibrary` + `systemMusicPlayer`)
//  3. System Audio Capture (`AudioHardwareCreateProcessTap` 2-ms probe on macOS 14.2+)
//  Ensures all macOS permission prompts appear immediately on first launch while the user has
//  a display / Screen Sharing session open, rather than blocking background threads later in headless mode.
//

import AppKit
import ApplicationServices
import CoreAudio
import Foundation
import ObjectiveC

public enum AMRPermissionState: String, Sendable {
    case granted
    case denied
    case notDetermined
}

public struct AMRSystemPermissionsSnapshot: Sendable {
    public let automationMusicApp: AMRPermissionState
    public let mediaLibrary: AMRPermissionState
    public let audioProcessTap: AMRPermissionState

    public var allGranted: Bool {
        automationMusicApp == .granted && mediaLibrary == .granted && audioProcessTap == .granted
    }

    public var hasDenied: Bool {
        automationMusicApp == .denied || mediaLibrary == .denied || audioProcessTap == .denied
    }
}

public final class SystemPermissionsManager: @unchecked Sendable {
    public static let shared = SystemPermissionsManager()

    internal static let audioTapPreflightStorageKey = "amr_audio_tap_tcc_preflight_v1"

    private let lock = NSLock()
    private var isPreflightRunning = false
    private var lastAutomationState: AMRPermissionState = .notDetermined
    private var lastMediaLibraryState: AMRPermissionState = .notDetermined
    private var lastAudioTapState: AMRPermissionState = .notDetermined

    private typealias MPMediaAuthStatusFn = @convention(c) (AnyClass, Selector) -> Int
    private typealias MPMediaAuthCompletionBlock = @convention(block) (Int) -> Void
    private typealias MPMediaRequestAuthFn = @convention(c) (AnyClass, Selector, @escaping MPMediaAuthCompletionBlock) -> Void

    private init() {
        if AppStorageProvider.shared.bool(forKey: Self.audioTapPreflightStorageKey) {
            lastAudioTapState = .granted
        }
    }

    // MARK: - Non-Prompting Status Inspection (UI Refresh)

    public func currentSnapshotWithoutPrompting() -> AMRSystemPermissionsSnapshot {
        if AppStorageProvider.isRunningUnderXCTest || PlaybackRouter.shared.isTestingEnvironment {
            return AMRSystemPermissionsSnapshot(
                automationMusicApp: .granted,
                mediaLibrary: .granted,
                audioProcessTap: .granted
            )
        }

        let autoState = queryMusicAppAutomationPermission(askUserIfNeeded: false)
        let mediaState = queryMediaLibraryAuthorizationStatus()
        let tapDone = AppStorageProvider.shared.bool(forKey: Self.audioTapPreflightStorageKey)

        return lock.withLock {
            if autoState != .notDetermined || lastAutomationState == .notDetermined {
                lastAutomationState = autoState
            }
            lastMediaLibraryState = mediaState
            if tapDone {
                lastAudioTapState = .granted
            }
            return AMRSystemPermissionsSnapshot(
                automationMusicApp: lastAutomationState,
                mediaLibrary: lastMediaLibraryState,
                audioProcessTap: lastAudioTapState
            )
        }
    }

    public func formattedStatusLine(isEn: Bool) -> String {
        let snap = currentSnapshotWithoutPrompting()
        func icon(_ s: AMRPermissionState) -> String {
            switch s {
            case .granted: return "🟢"
            case .denied: return "🔴"
            case .notDetermined: return "🟠"
            }
        }
        if isEn {
            return "\(icon(snap.automationMusicApp)) Music.app  ·  \(icon(snap.mediaLibrary)) Media Library  ·  \(icon(snap.audioProcessTap)) System Audio"
        } else {
            return "\(icon(snap.automationMusicApp)) Music.app  ·  \(icon(snap.mediaLibrary)) Медиатека  ·  \(icon(snap.audioProcessTap)) Системное аудио"
        }
    }

    // MARK: - Proactive Launch Preflight (Prompts Immediately on Clean Install)

    public func runLaunchPreflightAsync(forceAudioTapProbe: Bool = false, completion: (@Sendable (AMRSystemPermissionsSnapshot) -> Void)? = nil) {
        guard !AppStorageProvider.isRunningUnderXCTest && !PlaybackRouter.shared.isTestingEnvironment else {
            completion?(AMRSystemPermissionsSnapshot(automationMusicApp: .granted, mediaLibrary: .granted, audioProcessTap: .granted))
            return
        }

        let shouldStart: Bool = lock.withLock {
            if isPreflightRunning { return false }
            isPreflightRunning = true
            return true
        }
        guard shouldStart else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let snapshot = self.performSequentialPreflight(forceAudioTapProbe: forceAudioTapProbe)
            self.lock.withLock {
                self.isPreflightRunning = false
            }
            DispatchQueue.main.async {
                SettingsWindow.refreshIfVisible()
                MenuManager.shared.updateMenuState()
                completion?(snapshot)
            }
        }
    }

    @discardableResult
    internal func performSequentialPreflight(forceAudioTapProbe: Bool = false) -> AMRSystemPermissionsSnapshot {
        NSLog("[SystemPermissionsManager] 🛡️ Running launch macOS TCC permissions preflight...")

        // 1. Ensure Music.app is running quietly in background so AEDeterminePermissionToAutomateTarget
        //    can immediately evaluate/prompt Automation (`com.apple.Music`) on first launch.
        ensureMusicAppRunningInBackground()

        // 2. Request Automation permission (`NSAppleEventsUsageDescription` -> `com.apple.Music`)
        let autoState = queryMusicAppAutomationPermission(askUserIfNeeded: true)
        lock.withLock { lastAutomationState = autoState }
        NSLog("[SystemPermissionsManager] • Automation (com.apple.Music): %@", autoState.rawValue)

        // 3. Request Media Library & Apple Music permission (`NSAppleMusicUsageDescription` / `kTCCServiceMediaLibrary`)
        let prevMediaState = queryMediaLibraryAuthorizationStatus()
        let mediaState = requestMediaLibraryPermissionIfNeeded()
        let itLibOk = ITLibraryReader.shared.warmupPermissionAtLaunch()
        _ = SystemMusicPlayerBridge.shared.warmupPermissionAtLaunch()
        let resolvedMedia: AMRPermissionState = (mediaState == .granted || itLibOk) ? .granted : mediaState
        lock.withLock { lastMediaLibraryState = resolvedMedia }
        if prevMediaState != .granted && resolvedMedia == .granted {
            LibraryService.shared.invalidatePlaylistsCache()
        }
        NSLog("[SystemPermissionsManager] • Media Library & Apple Music: %@ (ITLibrary: %d)", resolvedMedia.rawValue, itLibOk ? 1 : 0)

        // 4. Request System Audio Capture (`NSAudioCaptureUsageDescription` / `AudioHardwareCreateProcessTap`)
        let tapState = requestAudioProcessTapPermissionIfNeeded(forceProbe: forceAudioTapProbe)
        lock.withLock { lastAudioTapState = tapState }
        NSLog("[SystemPermissionsManager] • System Audio Process Tap: %@", tapState.rawValue)

        return AMRSystemPermissionsSnapshot(
            automationMusicApp: autoState,
            mediaLibrary: resolvedMedia,
            audioProcessTap: tapState
        )
    }

    public func recheckOrOpenPrivacySettings() {
        let before = currentSnapshotWithoutPrompting()
        runLaunchPreflightAsync(forceAudioTapProbe: before.audioProcessTap != .granted) { after in
            guard after.hasDenied || !after.allGranted else { return }
            let paneURLString: String
            if after.mediaLibrary != .granted {
                paneURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
            } else if after.automationMusicApp != .granted {
                paneURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            } else {
                paneURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            }
            if let url = URL(string: paneURLString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Individual TCC Subsystems

    private func ensureMusicAppRunningInBackground() {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            return
        }
        guard let musicURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return
        }
        let sema = DispatchSemaphore(value: 0)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: musicURL, configuration: config) { _, _ in
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 3.0)
    }

    internal func queryMusicAppAutomationPermission(askUserIfNeeded: Bool) -> AMRPermissionState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return .notDetermined
        }
        guard let bundleData = "com.apple.Music".data(using: .utf8) else {
            return .notDetermined
        }
        var targetDesc = AEDesc()
        let createErr: OSErr = bundleData.withUnsafeBytes { raw in
            AECreateDesc(typeApplicationBundleID, raw.baseAddress, raw.count, &targetDesc)
        }
        guard createErr == noErr else {
            return .notDetermined
        }
        defer { AEDisposeDesc(&targetDesc) }

        let status = AEDeterminePermissionToAutomateTarget(&targetDesc, typeWildCard, typeWildCard, askUserIfNeeded)
        switch Int(status) {
        case Int(noErr):
            return .granted
        case Int(errAEEventNotPermitted): // -1743
            return .denied
        default: // procNotFound (-600), -1744 (would require user consent when askUserIfNeeded == false)
            return .notDetermined
        }
    }

    internal func queryMediaLibraryAuthorizationStatus() -> AMRPermissionState {
        _ = dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", RTLD_NOW)
        guard let cls: AnyClass = NSClassFromString("MPMediaLibrary") else {
            return .notDetermined
        }
        let statusSel = NSSelectorFromString("authorizationStatus")
        guard let m = class_getClassMethod(cls, statusSel) else {
            return .notDetermined
        }
        let fn = unsafeBitCast(method_getImplementation(m), to: MPMediaAuthStatusFn.self)
        let raw = fn(cls, statusSel)
        // MPMediaLibraryAuthorizationStatus: 0 = NotDetermined, 1 = Denied, 2 = Restricted, 3 = Authorized
        switch raw {
        case 3:
            return .granted
        case 1, 2:
            return .denied
        default:
            return .notDetermined
        }
    }

    internal func requestMediaLibraryPermissionIfNeeded() -> AMRPermissionState {
        let initial = queryMediaLibraryAuthorizationStatus()
        if initial != .notDetermined {
            return initial
        }
        guard let cls: AnyClass = NSClassFromString("MPMediaLibrary") else {
            return .notDetermined
        }
        let reqSel = NSSelectorFromString("requestAuthorization:")
        guard let m = class_getClassMethod(cls, reqSel) else {
            return .notDetermined
        }
        let fn = unsafeBitCast(method_getImplementation(m), to: MPMediaRequestAuthFn.self)
        let sema = DispatchSemaphore(value: 0)
        var resultingRaw: Int = 0
        let block: MPMediaAuthCompletionBlock = { newStatus in
            resultingRaw = newStatus
            sema.signal()
        }
        fn(cls, reqSel, block)
        // Wait up to 60s in case macOS displays the interactive TCC alert to the user at first launch
        _ = sema.wait(timeout: .now() + 60.0)
        switch resultingRaw {
        case 3:
            return .granted
        case 1, 2:
            return .denied
        default:
            return queryMediaLibraryAuthorizationStatus()
        }
    }

    internal func requestAudioProcessTapPermissionIfNeeded(forceProbe: Bool) -> AMRPermissionState {
        if !forceProbe && AppStorageProvider.shared.bool(forKey: Self.audioTapPreflightStorageKey) {
            return .granted
        }
        if AudioProcessTapService.shared.isCapturing {
            AppStorageProvider.shared.set(true, forKey: Self.audioTapPreflightStorageKey)
            return .granted
        }
        guard #available(macOS 14.2, *) else {
            return .granted
        }

        let probeDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        probeDesc.name = "AMR Permission Preflight"
        probeDesc.muteBehavior = .unmuted
        var probeTapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(probeDesc, &probeTapID)
        if status == noErr && probeTapID != 0 {
            AudioHardwareDestroyProcessTap(probeTapID)
            AppStorageProvider.shared.set(true, forKey: Self.audioTapPreflightStorageKey)
            return .granted
        }
        NSLog("[SystemPermissionsManager] ⚠️ AudioHardwareCreateProcessTap preflight returned OSStatus %d", status)
        return .denied
    }
}
