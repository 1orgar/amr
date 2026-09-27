//
//  main.swift
//  AppleMusicRemoteMac
//
//  Entry point for Apple Music Remote pure Swift daemon
//

import AppKit

@main
public struct AppleMusicRemoteApp {
    private static var strongDelegate: AppDelegate?

    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.strongDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
