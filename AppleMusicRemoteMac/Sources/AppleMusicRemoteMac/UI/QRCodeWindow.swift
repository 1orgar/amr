//
//  QRCodeWindow.swift
//  AppleMusicRemoteMac
//
//  Pure Swift QR Code Generator and Presenter Window
//

import AppKit
import CoreImage

public final class QRCodeWindow: NSWindowController {
    public static let shared = QRCodeWindow()

    private var qrImageView: NSImageView!
    private var urlLabel: NSTextField!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Apple Music Remote — QR Code"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let container = NSStackView(frame: contentView.bounds)
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 16
        container.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        container.autoresizingMask = [.width, .height]

        let titleLabel = NSTextField(labelWithString: "Подключение с iPhone / iPad")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.alignment = .center

        qrImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.widthAnchor.constraint(equalToConstant: 220).isActive = true
        qrImageView.heightAnchor.constraint(equalToConstant: 220).isActive = true
        qrImageView.wantsLayer = true
        qrImageView.layer?.cornerRadius = 12
        qrImageView.layer?.masksToBounds = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor

        urlLabel = NSTextField(labelWithString: "ws://localhost:8080")
        urlLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.alignment = .center
        urlLabel.isSelectable = true

        let hintLabel = NSTextField(labelWithString: "Откройте камеру или приложение Apple Music Remote на iOS в той же сети Wi-Fi")
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.cell?.wraps = true

        let copyButton = NSButton(title: "Скопировать адрес", target: self, action: #selector(copyUrlClicked))
        copyButton.bezelStyle = .rounded

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(qrImageView)
        container.addArrangedSubview(urlLabel)
        container.addArrangedSubview(hintLabel)
        container.addArrangedSubview(copyButton)

        contentView.addSubview(container)
    }

    public func show(for urlString: String) {
        urlLabel.stringValue = urlString
        if let qrImage = generateQRCode(from: urlString) {
            qrImageView.image = qrImage
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyUrlClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlLabel.stringValue, forType: .string)
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")

            if let outputImage = filter.outputImage {
                let transform = CGAffineTransform(scaleX: 10, y: 10)
                let scaledImage = outputImage.transformed(by: transform)

                let rep = NSCIImageRep(ciImage: scaledImage)
                let nsImage = NSImage(size: rep.size)
                nsImage.addRepresentation(rep)
                return nsImage
            }
        }
        return nil
    }
}
