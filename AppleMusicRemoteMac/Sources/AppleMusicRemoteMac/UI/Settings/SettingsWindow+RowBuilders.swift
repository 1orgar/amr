//
//  SettingsWindow+RowBuilders.swift
//  AppleMusicRemoteMac
//
//  Music.app-styled two-column preference page and row layout builders.
//

import AppKit

extension SettingsWindow {
    internal func makeMusicPreferencePage(sections: [[NSView]], compactSpacing: Bool = false) -> NSView {
        let pageStack = NSStackView()
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = compactSpacing ? 8 : 13
        pageStack.edgeInsets = NSEdgeInsets(
            top: compactSpacing ? 11 : 18,
            left: 24,
            bottom: compactSpacing ? 16 : 18,
            right: 24
        )
        pageStack.translatesAutoresizingMaskIntoConstraints = false

        let nonEmptySections = sections.filter { !$0.isEmpty }
        for (secIdx, rows) in nonEmptySections.enumerated() {
            let sectionStack = NSStackView()
            sectionStack.orientation = .vertical
            sectionStack.alignment = .leading
            sectionStack.spacing = compactSpacing ? 5 : 10
            sectionStack.translatesAutoresizingMaskIntoConstraints = false

            for r in rows {
                sectionStack.addArrangedSubview(r)
                r.widthAnchor.constraint(equalTo: sectionStack.widthAnchor).isActive = true
            }

            pageStack.addArrangedSubview(sectionStack)
            sectionStack.widthAnchor.constraint(equalTo: pageStack.widthAnchor, constant: -48).isActive = true

            if secIdx < nonEmptySections.count - 1 {
                let divider = MusicSurfaceView { MusicSettingsPalette.hairline }
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                pageStack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: pageStack.widthAnchor, constant: -48).isActive = true
            }
        }
        return pageStack
    }

    internal func makeMusicTwoColumnRow(category: String, rightContent: NSView, topLabelOffset: CGFloat = 1) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let labelField = NSTextField(labelWithString: category)
        labelField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        labelField.textColor = .labelColor
        labelField.alignment = .right
        labelField.lineBreakMode = .byTruncatingTail
        labelField.translatesAutoresizingMaskIntoConstraints = false

        rightContent.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(labelField)
        container.addSubview(rightContent)

        let labelBottomGuard = labelField.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        labelBottomGuard.priority = .defaultHigh

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelField.widthAnchor.constraint(equalToConstant: Self.leftLabelColumnWidth),
            labelField.topAnchor.constraint(equalTo: container.topAnchor, constant: topLabelOffset),
            labelBottomGuard,

            rightContent.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 12),
            rightContent.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightContent.topAnchor.constraint(equalTo: container.topAnchor),
            rightContent.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    internal func makeMusicCheckboxRow(category: String, checkbox: NSButton, subtitle: String?) -> NSView {
        if let sub = subtitle, !sub.isEmpty {
            let subLabel = makeMusicSubcaption(sub)
            let indented = makeIndentedSubcaptionContainer(subLabel)
            let vStack = NSStackView(views: [checkbox, indented])
            vStack.orientation = .vertical
            vStack.alignment = .leading
            vStack.spacing = 3
            indented.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
            return makeMusicTwoColumnRow(category: category, rightContent: vStack, topLabelOffset: 1)
        }
        let holder = NSStackView(views: [checkbox])
        holder.orientation = .horizontal
        holder.alignment = .centerY
        return makeMusicTwoColumnRow(category: category, rightContent: holder, topLabelOffset: 1)
    }

    internal func makeMusicControlRow(category: String, control: NSView, subtitle: String?, topLabelOffset: CGFloat = 3) -> NSView {
        control.setContentHuggingPriority(.required, for: .horizontal)
        if let sub = subtitle, !sub.isEmpty {
            let subLabel = makeMusicSubcaption(sub)
            let vStack = NSStackView(views: [control, subLabel])
            vStack.orientation = .vertical
            vStack.alignment = .leading
            vStack.spacing = 4
            subLabel.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
            return makeMusicTwoColumnRow(category: category, rightContent: vStack, topLabelOffset: topLabelOffset)
        }
        let holder = NSStackView(views: [control])
        holder.orientation = .horizontal
        holder.alignment = .centerY
        return makeMusicTwoColumnRow(category: category, rightContent: holder, topLabelOffset: topLabelOffset)
    }

    internal func makeMusicSubcaption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    internal func makeIndentedSubcaptionContainer(_ label: NSTextField) -> NSView {
        makeIndentedViewContainer(label)
    }

    internal func makeIndentedViewContainer(_ innerView: NSView) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        innerView.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(innerView)
        NSLayoutConstraint.activate([
            innerView.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: MusicCheckboxCell.textOffset),
            innerView.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            innerView.topAnchor.constraint(equalTo: wrap.topAnchor),
            innerView.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    internal func makeCheckbox(title: String, action: Selector) -> NSButton {
        MusicCheckboxButton(title: title, target: self, action: action)
    }

    internal func makeStatusCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }

    internal func makeReadonlyMonospaceField(_ value: String, width: CGFloat) -> NSTextField {
        let field = NSTextField(string: value)
        field.isEditable = false
        field.isSelectable = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }
}
