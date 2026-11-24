//
//  ExternalAmpProfile.swift
//  AppleMusicRemoteMac
//
//  Supported ASCII / Text-over-TCP Amplifier Protocols (Rotel, Denon/Marantz, Hegel, NAD, Lyngdorf)
//

import Foundation

/// Supported ASCII / Text-over-TCP amplifier protocols.
public enum ExternalAmpProfile: String, CaseIterable, Codable, Sendable {
    case rotel = "rotel"
    case denonMarantz = "denon_marantz"
    case hegel = "hegel"
    case nad = "nad"
    case lyngdorf = "lyngdorf"

    public var displayName: String {
        switch self {
        case .rotel:
            return "Rotel"
        case .denonMarantz:
            return "Denon / Marantz"
        case .hegel:
            return "Hegel"
        case .nad:
            return "NAD"
        case .lyngdorf:
            return "Lyngdorf"
        }
    }

    public var menuTitle: String {
        switch self {
        case .rotel:
            return "Rotel (ASCII TCP :9590)"
        case .denonMarantz:
            return "Denon / Marantz (ASCII TCP :23)"
        case .hegel:
            return "Hegel (ASCII TCP :50001)"
        case .nad:
            return "NAD (ASCII TCP :30000)"
        case .lyngdorf:
            return "Lyngdorf (ASCII TCP :84)"
        }
    }

    public var defaultPort: UInt16 {
        switch self {
        case .rotel:
            return 9590
        case .denonMarantz:
            return 23
        case .hegel:
            return 50001
        case .nad:
            return 30000
        case .lyngdorf:
            return 84
        }
    }

    public var nativeMaxVolume: Int {
        switch self {
        case .rotel:
            return 96
        case .denonMarantz:
            return 98
        case .hegel, .nad, .lyngdorf:
            return 100
        }
    }

    /// Builds the ASCII command to set the hardware volume to `volume`.
    public func buildSetVolumeCommand(_ volume: Int) -> String {
        let clamped = max(0, min(nativeMaxVolume, volume))
        switch self {
        case .rotel:
            return String(format: "vol_%02d!", clamped)
        case .denonMarantz:
            return String(format: "MV%02d\r", clamped)
        case .hegel:
            return "-v.\(clamped)\r"
        case .nad:
            return "Main.Volume=\(clamped)\r\n"
        case .lyngdorf:
            let dbTenths = (clamped - 100) * 8 // 0..100 -> -800..0 (-80.0dB .. 0.0dB)
            return "!VOL(\(dbTenths))\r"
        }
    }

    /// Builds the ASCII command to step volume up or down.
    public func buildStepVolumeCommand(up: Bool) -> String {
        switch self {
        case .rotel:
            return up ? "vol_up!" : "vol_dwn!"
        case .denonMarantz:
            return up ? "MVUP\r" : "MVDOWN\r"
        case .hegel:
            return up ? "-v.u\r" : "-v.d\r"
        case .nad:
            return up ? "Main.Volume+\r\n" : "Main.Volume-\r\n"
        case .lyngdorf:
            return up ? "!VOLUP\r" : "!VOLDN\r"
        }
    }

    /// Builds the ASCII command to set or toggle mute state.
    public func buildMuteCommand(muted: Bool? = nil) -> String {
        switch self {
        case .rotel:
            if let muted {
                return muted ? "mute_on!" : "mute_off!"
            }
            return "mute!"
        case .denonMarantz:
            let target = muted ?? true
            return target ? "MUON\r" : "MUOFF\r"
        case .hegel:
            if let muted {
                return muted ? "-m.1\r" : "-m.0\r"
            }
            return "-m.t\r"
        case .nad:
            let target = muted ?? true
            return target ? "Main.Mute=On\r\n" : "Main.Mute=Off\r\n"
        case .lyngdorf:
            let target = muted ?? true
            return target ? "!MUTEON\r" : "!MUTEOFF\r"
        }
    }

    /// Builds the periodic status query command to poll current volume and mute state.
    public func buildQueryStatusCommand() -> String {
        switch self {
        case .rotel:
            return "get_volume!get_mute_status!"
        case .denonMarantz:
            return "MV?\rMU?\r"
        case .hegel:
            return "-v.?\r-m.?\r"
        case .nad:
            return "Main.Volume?\r\nMain.Mute?\r\n"
        case .lyngdorf:
            return "!VOL?\r!MUTE?\r"
        }
    }

    /// Parses a single ASCII response token (already trimmed of frame delimiters `$`, `!`, `\r`, `\n`).
    public func parseToken(_ rawToken: String) -> (volume: Int?, muted: Bool?) {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return (nil, nil) }
        let lower = token.lowercased()

        switch self {
        case .rotel:
            // Examples: "volume=45", "vol=45", "volume=min", "volume=max", "mute=on", "mute=off"
            if lower.hasPrefix("volume=") || lower.hasPrefix("vol=") {
                let parts = lower.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let valStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if valStr == "min" {
                        return (0, nil)
                    } else if valStr == "max" {
                        return (nativeMaxVolume, nil)
                    }
                    let digits = valStr.filter { $0.isNumber }
                    if let v = Int(digits) {
                        return (max(0, min(nativeMaxVolume, v)), nil)
                    }
                }
            }
            if lower.hasPrefix("mute=") {
                let parts = lower.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let valStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if valStr == "on" || valStr == "1" {
                        return (nil, true)
                    } else if valStr == "off" || valStr == "0" {
                        return (nil, false)
                    }
                }
            }
            return (nil, nil)

        case .denonMarantz:
            // Examples: "MV45", "MV455" (45.5), "MUON", "MUOFF"
            let upper = token.uppercased()
            if upper == "MUON" {
                return (nil, true)
            }
            if upper == "MUOFF" {
                return (nil, false)
            }
            if upper.hasPrefix("MV"), !upper.hasPrefix("MVMAX") {
                let digits = String(upper.dropFirst(2)).prefix(while: { $0.isNumber })
                if let rawVal = Int(digits) {
                    let normalized = digits.count >= 3 ? (rawVal / 10) : rawVal
                    return (max(0, min(nativeMaxVolume, normalized)), nil)
                }
            }
            return (nil, nil)

        case .hegel:
            // Examples: "-v.45", "-m.1", "-m.0"
            if lower.hasPrefix("-v.") {
                let digits = String(lower.dropFirst(3)).filter { $0.isNumber }
                if let v = Int(digits) {
                    return (max(0, min(nativeMaxVolume, v)), nil)
                }
            }
            if lower.hasPrefix("-m.") {
                let flag = String(lower.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if flag == "1" || flag == "on" {
                    return (nil, true)
                } else if flag == "0" || flag == "off" {
                    return (nil, false)
                }
            }
            return (nil, nil)

        case .nad:
            // Examples: "Main.Volume=45", "Main.Mute=On", "Main.Mute=Off"
            if lower.hasPrefix("main.volume=") {
                let valStr = String(lower.dropFirst("main.volume=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Int(valStr) {
                    return (max(0, min(nativeMaxVolume, v)), nil)
                }
            }
            if lower.hasPrefix("main.mute=") {
                let valStr = String(lower.dropFirst("main.mute=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if valStr == "on" || valStr == "1" {
                    return (nil, true)
                } else if valStr == "off" || valStr == "0" {
                    return (nil, false)
                }
            }
            return (nil, nil)

        case .lyngdorf:
            // Examples: "!VOL(-350)", "!MUTEON", "!MUTEOFF"
            let upper = token.uppercased()
            if upper == "!MUTEON" || upper == "!MUTE(ON)" {
                return (nil, true)
            }
            if upper == "!MUTEOFF" || upper == "!MUTE(OFF)" {
                return (nil, false)
            }
            if upper.hasPrefix("!VOL("), upper.hasSuffix(")") {
                let inner = String(upper.dropFirst(5).dropLast(1))
                if let dbTenths = Int(inner) {
                    let mapped = 100 + (dbTenths / 8)
                    return (max(0, min(nativeMaxVolume, mapped)), nil)
                }
            }
            return (nil, nil)
        }
    }
}
