//
//  LaunchAtLoginManager.swift
//  AppleMusicRemoteMac
//
//  Modern macOS 13+ SMAppService wrapper for Launch at Login
//

import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public private(set) var isEnabled: Bool = false

    private init() {
        refreshStatus()
    }

    public func refreshStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            isEnabled = (status == .enabled)
        } else {
            isEnabled = false
        }
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled {
                        isEnabled = true
                        return true
                    }
                    try SMAppService.mainApp.register()
                    isEnabled = (SMAppService.mainApp.status == .enabled)
                    NSLog("[LaunchAtLoginManager] Registered mainApp for launch at login. Status: \(SMAppService.mainApp.status.rawValue)")
                    return isEnabled
                } else {
                    try SMAppService.mainApp.unregister()
                    isEnabled = (SMAppService.mainApp.status == .enabled)
                    NSLog("[LaunchAtLoginManager] Unregistered mainApp from launch at login. Status: \(SMAppService.mainApp.status.rawValue)")
                    return !isEnabled
                }
            } catch {
                NSLog("[LaunchAtLoginManager] Error changing launch at login to \(enabled): \(error.localizedDescription)")
                refreshStatus()
                return false
            }
        } else {
            NSLog("[LaunchAtLoginManager] SMAppService requires macOS 13.0 or later.")
            return false
        }
    }
}
