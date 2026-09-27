//
//  DesignTokens.swift
//  AppleMusicRemoteIOS
//
//  Color tokens, glassmorphism modifiers, and haptic engine
//

import SwiftUI
import UIKit

// MARK: - Color Palette

public extension Color {
    static let amrBackground = Color(red: 10/255, green: 10/255, blue: 14/255)
    static let amrSurfaceGlass = Color.white.opacity(0.08)
    static let amrSurfaceHighlight = Color.white.opacity(0.14)
    static let amrRed = Color(red: 250/255, green: 45/255, blue: 72/255)
    static let amrRose = Color(red: 255/255, green: 55/255, blue: 95/255)
    static let amrCrimson = Color(red: 255/255, green: 8/255, blue: 68/255)
    static let amrTextSecondary = Color.white.opacity(0.65)
    static let amrTextTertiary = Color.white.opacity(0.38)
    static let amrBorderGlass = Color.white.opacity(0.12)

    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
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
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Glassmorphism View Modifier

public struct AMRGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var strokeColor: Color
    
    public init(cornerRadius: CGFloat = 16, strokeColor: Color = .amrBorderGlass) {
        self.cornerRadius = cornerRadius
        self.strokeColor = strokeColor
    }

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.amrSurfaceGlass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.8)
            )
    }
}

public extension View {
    func amrDarkGlass(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(AMRGlassModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Haptic Engine

public struct AMRHaptics {
    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Interactive Button Style

public struct AMRButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

public struct AMRActionButtonStyle: ButtonStyle {
    public let backgroundColor: Color
    public init(backgroundColor: Color) {
        self.backgroundColor = backgroundColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

