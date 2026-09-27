//
//  DesignTokens.swift
//  AppleMusicRemoteIOS
//
//  Apple Music Remote Design System & Haptic Tokens (iOS 17/18 HIG)
//

import SwiftUI
import UIKit

// MARK: - Color Palette
public extension Color {
    // Brand & Vibrancy Accents
    static let amrRed = Color(hex: "#FA2D48")          // Apple Music Signature Red
    static let amrRose = Color(hex: "#FF375F")         // Secondary Vibrancy Accent
    static let amrCrimson = Color(hex: "#FF0844")      // Gradient Stop & Live Badge
    static let amrPink = Color(hex: "#FB5C74")         // Personal Station Secondary
    static let amrPurple = Color(hex: "#7928CA")       // Discovery Station Primary
    static let amrNeonPink = Color(hex: "#FF0080")     // Discovery Station Secondary
    
    // Dark Glassmorphism Surfaces
    static let amrBackground = Color(hex: "#000000")   // Pure OLED Black
    static let amrSurfaceGlass = Color(white: 0.12).opacity(0.72)
    static let amrCardSurface = Color(white: 0.18).opacity(0.45)
    static let amrCardHighlight = Color(white: 0.25).opacity(0.35)
    static let amrHairlineBorder = Color.white.opacity(0.14)
    static let amrSeparators = Color.white.opacity(0.08)
    
    // Text Hierarchies
    static let amrTextPrimary = Color.white
    static let amrTextSecondary = Color(white: 0.72)
    static let amrTextTertiary = Color(white: 0.45)
    
    // Status Indicators
    static let amrConnected = Color(hex: "#34C759")    // Apple Green
    static let amrWarning = Color(hex: "#FF9F0A")      // Apple Amber
    static let amrError = Color(hex: "#FF3B30")        // Apple Red
    
    // Helper Hex Initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Haptic Engine Specifications
public enum AMRHaptics {
    public static func buttonTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }
    
    public static func playPauseToggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
    }
    
    public static func trackSkip() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
    }
    
    public static func favoriteSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    public static func warningAlert() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    
    public static func scrubberTick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    
    public static func queueLift() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    public static func queueDrop() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - View Modifiers & Materials
public struct AMRDarkGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16
    
    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
    }
}

public extension View {
    func amrDarkGlass(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(AMRDarkGlassModifier(cornerRadius: cornerRadius))
    }
}
