//
//  SettingsControls.swift
//  AppleMusicRemoteMac
//
//  Shared Music.app-styled AppKit controls, tabs, and dynamic color palette
//  used across SettingsWindow extensions.
//

import AppKit

public enum SettingsTab: Int, CaseIterable {
    case general = 0
    case tv = 1
    case playback = 2
    case dsp = 3
    case amplifier = 4
    case wled = 5
    case advanced = 6

    internal static var isEn: Bool {
        AMRLocalization.isEnglish
    }

    private var isEn: Bool {
        Self.isEn
    }

    internal var tabTitle: String {
        switch self {
        case .general: return isEn ? "General" : "Основные"
        case .tv: return isEn ? "TV Mode" : "ТВ-режим"
        case .playback: return isEn ? "Playback" : "Воспроизведение"
        case .dsp: return "DSP"
        case .amplifier: return isEn ? "Amplifier" : "Усилитель"
        case .wled: return isEn ? "Lighting" : "Подсветка"
        case .advanced: return isEn ? "Advanced" : "Дополнения"
        }
    }

    internal var windowTitle: String {
        switch self {
        case .general: return isEn ? "General" : "Основные"
        case .tv: return isEn ? "TV Mode" : "ТВ-режим"
        case .playback: return isEn ? "Playback" : "Воспроизведение"
        case .dsp: return isEn ? "Hybrid DSP Engine" : "Гибридный DSP"
        case .amplifier: return isEn ? "Amplifier" : "Усилитель"
        case .wled: return isEn ? "Lighting" : "Подсветка"
        case .advanced: return isEn ? "Advanced" : "Дополнения"
        }
    }

    internal var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .tv: return "tv"
        case .playback: return "play.circle"
        case .dsp: return "waveform.path.ecg"
        case .amplifier: return "dial.medium"
        case .wled: return "sparkles"
        case .advanced: return "gearshape.2"
        }
    }
}

internal enum MusicSettingsPalette {
    static let accent = NSColor(srgbRed: 0.980, green: 0.176, blue: 0.282, alpha: 1.0) // #FA2D48
    static let accentHover = NSColor(srgbRed: 0.992, green: 0.235, blue: 0.335, alpha: 1.0)
    static let accentPressed = NSColor(srgbRed: 0.855, green: 0.130, blue: 0.230, alpha: 1.0)

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static let windowBackground = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.145, green: 0.145, blue: 0.153, alpha: 1.0)
            : NSColor(srgbRed: 0.955, green: 0.955, blue: 0.962, alpha: 1.0)
    }

    static let tabBarBackground = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.129, green: 0.129, blue: 0.137, alpha: 1.0)
            : NSColor(srgbRed: 0.930, green: 0.930, blue: 0.940, alpha: 1.0)
    }

    static let hairline = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(calibratedWhite: 1.0, alpha: 0.095)
            : NSColor(calibratedWhite: 0.0, alpha: 0.095)
    }
}

internal final class MusicSurfaceView: NSView {
    private let colorProvider: () -> NSColor

    init(colorProvider: @escaping () -> NSColor) {
        self.colorProvider = colorProvider
        super.init(frame: .zero)
        wantsLayer = true
        updateLayerColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColor()
    }

    private func updateLayerColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = colorProvider().cgColor
        }
    }
}

internal final class MusicCheckboxCell: NSButtonCell {
    static let boxSize: CGFloat = 16.0
    static let textOffset: CGFloat = 23.0
    private static let placeholderImage: NSImage = {
        NSImage(size: NSSize(width: boxSize, height: boxSize))
    }()

    override init(textCell string: String) {
        super.init(textCell: string)
        setupCell()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        setButtonType(.switch)
        isBordered = false
        imagePosition = .imageLeading
        imageScaling = .scaleNone
        image = Self.placeholderImage
        alternateImage = Self.placeholderImage
        alignment = .left
        lineBreakMode = .byTruncatingTail
    }

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX,
            y: round(rect.midY - Self.boxSize * 0.5),
            width: Self.boxSize,
            height: Self.boxSize
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let textFont = font ?? NSFont.systemFont(ofSize: 13, weight: .regular)
        let lineH = ceil(textFont.ascender - textFont.descender + textFont.leading)
        let y = round(rect.midY - lineH * 0.5)
        return NSRect(
            x: rect.minX + Self.textOffset,
            y: y,
            width: max(0, rect.width - Self.textOffset),
            height: lineH
        )
    }

    override var cellSize: NSSize {
        let textFont = font ?? NSFont.systemFont(ofSize: 13, weight: .regular)
        let textSize = (title as NSString).size(withAttributes: [.font: textFont])
        let width = title.isEmpty ? Self.boxSize : ceil(Self.textOffset + textSize.width + 2.0)
        let height = max(20.0, ceil(textSize.height + 2.0))
        return NSSize(width: width, height: height)
    }

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        let boxRect = NSRect(
            x: round(frame.minX),
            y: round(frame.midY - Self.boxSize * 0.5),
            width: Self.boxSize,
            height: Self.boxSize
        )
        let isDark = MusicSettingsPalette.isDark(controlView.effectiveAppearance)
        let radius: CGFloat = 4.2
        let path = NSBezierPath(roundedRect: boxRect, xRadius: radius, yRadius: radius)

        if state == .on {
            let fill: NSColor
            if !isEnabled {
                fill = MusicSettingsPalette.accent.withAlphaComponent(0.42)
            } else if isHighlighted {
                fill = MusicSettingsPalette.accentPressed
            } else {
                fill = MusicSettingsPalette.accent
            }
            fill.setFill()
            path.fill()

            let check = NSBezierPath()
            if controlView.isFlipped {
                check.move(to: NSPoint(x: boxRect.minX + 3.8, y: boxRect.minY + 8.3))
                check.line(to: NSPoint(x: boxRect.minX + 6.7, y: boxRect.minY + 11.3))
                check.line(to: NSPoint(x: boxRect.minX + 12.2, y: boxRect.minY + 4.7))
            } else {
                check.move(to: NSPoint(x: boxRect.minX + 3.8, y: boxRect.maxY - 8.3))
                check.line(to: NSPoint(x: boxRect.minX + 6.7, y: boxRect.maxY - 11.3))
                check.line(to: NSPoint(x: boxRect.minX + 12.2, y: boxRect.maxY - 4.7))
            }
            check.lineWidth = 1.85
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(isEnabled ? 1.0 : 0.65).setStroke()
            check.stroke()
        } else {
            let insetRect = boxRect.insetBy(dx: 0.5, dy: 0.5)
            let uncheckedPath = NSBezierPath(roundedRect: insetRect, xRadius: radius, yRadius: radius)
            let baseAlpha: CGFloat = isEnabled ? (isHighlighted ? 0.22 : 0.14) : 0.07
            let fill = isDark
                ? NSColor(calibratedWhite: 1.0, alpha: baseAlpha)
                : NSColor(calibratedWhite: 0.0, alpha: isEnabled ? (isHighlighted ? 0.13 : 0.07) : 0.04)
            fill.setFill()
            uncheckedPath.fill()

            let stroke = isDark
                ? NSColor(calibratedWhite: 1.0, alpha: isEnabled ? 0.15 : 0.07)
                : NSColor(calibratedWhite: 0.0, alpha: isEnabled ? 0.20 : 0.10)
            stroke.setStroke()
            uncheckedPath.lineWidth = 1.0
            uncheckedPath.stroke()
        }
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let raw = !title.string.isEmpty ? title.string : self.stringValue
        guard !raw.isEmpty else { return .zero }
        let textFont = font ?? NSFont.systemFont(ofSize: 13, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let color: NSColor = isEnabled ? .labelColor : .tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (raw as NSString).draw(in: frame, withAttributes: attrs)
        return frame
    }
}

internal final class MusicCheckboxButton: NSButton {
    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        let customCell = MusicCheckboxCell(textCell: title)
        self.cell = customCell
        self.title = title
        self.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        self.target = target
        self.action = action
        self.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

internal final class MusicPillButton: NSButton {
    private let isPrimary: Bool
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    init(title: String, isPrimary: Bool, width: CGFloat = 88, target: AnyObject?, action: Selector?) {
        self.isPrimary = isPrimary
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        self.title = title
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.target = target
        self.action = action
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = MusicSettingsPalette.isDark(effectiveAppearance)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6.0, yRadius: 6.0)

        let bgColor: NSColor
        let textColor: NSColor
        if isPrimary {
            if !isEnabled {
                bgColor = MusicSettingsPalette.accent.withAlphaComponent(0.42)
                textColor = NSColor.white.withAlphaComponent(0.6)
            } else if isHighlighted {
                bgColor = MusicSettingsPalette.accentPressed
                textColor = .white
            } else if isHovered {
                bgColor = MusicSettingsPalette.accentHover
                textColor = .white
            } else {
                bgColor = MusicSettingsPalette.accent
                textColor = .white
            }
            bgColor.setFill()
            path.fill()
        } else {
            if isDark {
                let alpha: CGFloat = !isEnabled ? 0.06 : (isHighlighted ? 0.22 : (isHovered ? 0.17 : 0.13))
                bgColor = NSColor(calibratedWhite: 1.0, alpha: alpha)
                NSColor(calibratedWhite: 1.0, alpha: isEnabled ? 0.08 : 0.04).setStroke()
            } else {
                let alpha: CGFloat = !isEnabled ? 0.04 : (isHighlighted ? 0.14 : (isHovered ? 0.10 : 0.07))
                bgColor = NSColor(calibratedWhite: 0.0, alpha: alpha)
                NSColor(calibratedWhite: 0.0, alpha: isEnabled ? 0.14 : 0.06).setStroke()
            }
            bgColor.setFill()
            path.fill()
            path.lineWidth = 1.0
            path.stroke()
            textColor = isEnabled ? .labelColor : .tertiaryLabelColor
        }

        let font = NSFont.systemFont(ofSize: 13, weight: isPrimary ? .medium : .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let sz = (title as NSString).size(withAttributes: attrs)
        let pt = NSPoint(
            x: round((bounds.width - sz.width) * 0.5),
            y: round((bounds.height - sz.height) * 0.5) - 0.5
        )
        (title as NSString).draw(at: pt, withAttributes: attrs)
    }
}

internal final class MusicTabButtonView: NSView {
    let tab: SettingsTab
    var onSelect: ((SettingsTab) -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isSelectedTab: Bool = false
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    init(tab: SettingsTab) {
        self.tab = tab
        super.init(frame: NSRect(x: 0, y: 0, width: 84, height: 54))
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        if let img = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.tabTitle) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            iconView.image = img.withSymbolConfiguration(cfg) ?? img
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = tab.tabTitle
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        titleLabel.alignment = .center
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            heightAnchor.constraint(equalToConstant: 54),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -11),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        isSelectedTab = selected
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: selected ? .medium : .regular)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(tab)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = MusicSettingsPalette.isDark(effectiveAppearance)
            if isSelectedTab {
                layer?.backgroundColor = (isDark
                    ? NSColor(calibratedWhite: 1.0, alpha: 0.065)
                    : NSColor(calibratedWhite: 0.0, alpha: 0.055)).cgColor
                layer?.borderWidth = 1.0
                layer?.borderColor = (isDark
                    ? NSColor(calibratedWhite: 1.0, alpha: 0.16)
                    : NSColor(calibratedWhite: 0.0, alpha: 0.13)).cgColor
                iconView.contentTintColor = MusicSettingsPalette.accent
                titleLabel.textColor = MusicSettingsPalette.accent
            } else {
                layer?.backgroundColor = isHovered
                    ? (isDark
                        ? NSColor(calibratedWhite: 1.0, alpha: 0.035)
                        : NSColor(calibratedWhite: 0.0, alpha: 0.03)).cgColor
                    : NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                layer?.borderColor = NSColor.clear.cgColor
                iconView.contentTintColor = .secondaryLabelColor
                titleLabel.textColor = .secondaryLabelColor
            }
        }
    }
}

internal final class SettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = MusicSettingsPalette.isDark(effectiveAppearance)
            layer?.backgroundColor = (isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.04)
                : NSColor(calibratedWhite: 0.0, alpha: 0.03)).cgColor
            layer?.borderWidth = 1.0
            layer?.borderColor = MusicSettingsPalette.hairline.cgColor
        }
    }
}

internal final class FlippedTabDocumentView: NSView {
    override var isFlipped: Bool { true }
}

internal final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
