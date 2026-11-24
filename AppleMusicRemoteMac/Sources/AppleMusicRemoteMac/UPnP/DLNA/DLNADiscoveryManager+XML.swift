//
//  DLNADiscoveryManager+XML.swift
//  AppleMusicRemoteMac
//
//  ReDoS-free linear SSDP header, XML tag/attribute, and UPnP <service> block
//  extractors with strict same-origin controlURL verification.
//

import Foundation

extension DLNADiscoveryManager {
    public func extractHeader(_ name: String, from text: String) -> String? {
        let lines = text.components(separatedBy: "\r\n")
        let prefix = "\(name):".lowercased()
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    public func extractXMLTagValue(tag: String, from text: String) -> String? {
        guard !tag.isEmpty else { return nil }
        let openToken = "<\(tag)"
        let closeToken = "</\(tag)>"
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let openRange = text.range(of: openToken, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            let afterName = openRange.upperBound
            guard afterName < text.endIndex else { return nil }
            let boundaryChar = text[afterName]
            let isTagBoundary = boundaryChar == ">" || boundaryChar == " " || boundaryChar == "\t" || boundaryChar == "\r" || boundaryChar == "\n"
            guard isTagBoundary else {
                searchStart = afterName
                continue
            }
            guard let tagCloseBracket = text[afterName...].firstIndex(of: ">") else {
                return nil
            }
            let contentStart = text.index(after: tagCloseBracket)
            guard let closeRange = text.range(of: closeToken, options: .caseInsensitive, range: contentStart..<text.endIndex) else {
                return nil
            }
            let inner = text[contentStart..<closeRange.lowerBound]
            if !inner.contains("<") {
                return inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            searchStart = contentStart
        }
        return nil
    }

    public func extractXMLAttribute(attr: String, from text: String) -> String? {
        guard !attr.isEmpty else { return nil }
        let needle = "\(attr)=\""
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let attrRange = text.range(of: needle, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            if attrRange.lowerBound > text.startIndex {
                let prev = text[text.index(before: attrRange.lowerBound)]
                let isBoundary = prev.isWhitespace || prev == "<" || prev == "/" || prev == "\"" || prev == "'"
                if !isBoundary {
                    searchStart = attrRange.upperBound
                    continue
                }
            }
            let valStart = attrRange.upperBound
            guard let endQuote = text[valStart...].firstIndex(of: "\"") else {
                return nil
            }
            return text[valStart..<endQuote].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    public func extractServiceControlURL(serviceType: String, from xml: String, baseURL: URL) -> URL? {
        guard !serviceType.isEmpty else { return nil }

        var searchStart = xml.startIndex
        var matchedRawControlURL: String?

        while searchStart < xml.endIndex,
              let serviceOpen = xml.range(of: "<service", options: .caseInsensitive, range: searchStart..<xml.endIndex) {
            let afterOpen = serviceOpen.upperBound
            guard afterOpen < xml.endIndex else { break }
            let nextChar = xml[afterOpen]
            guard nextChar == ">" || nextChar.isWhitespace else {
                // Skip <serviceList>, <serviceType>, <serviceId>, <serviceStateTable>
                searchStart = afterOpen
                continue
            }
            guard let openBracketEnd = xml[afterOpen...].firstIndex(of: ">") else { break }
            let blockStart = xml.index(after: openBracketEnd)
            guard let serviceClose = xml.range(of: "</service>", options: .caseInsensitive, range: blockStart..<xml.endIndex) else {
                break
            }
            let serviceBlock = String(xml[blockStart..<serviceClose.lowerBound])
            searchStart = serviceClose.upperBound

            if let parsedServiceType = extractXMLTagValue(tag: "serviceType", from: serviceBlock),
               parsedServiceType.localizedCaseInsensitiveContains(serviceType),
               let parsedControlURL = extractXMLTagValue(tag: "controlURL", from: serviceBlock),
               !parsedControlURL.isEmpty {
                matchedRawControlURL = parsedControlURL
                break
            }
        }

        guard let relOrAbs = matchedRawControlURL else { return nil }

        let resolved: URL?
        if relOrAbs.hasPrefix("http://") || relOrAbs.hasPrefix("https://") {
            resolved = URL(string: relOrAbs)
        } else {
            resolved = URL(string: relOrAbs, relativeTo: baseURL)?.absoluteURL
        }
        guard let candidate = resolved,
              let candScheme = candidate.scheme?.lowercased(),
              let baseScheme = baseURL.scheme?.lowercased(),
              (candScheme == "http" || candScheme == "https"),
              candScheme == baseScheme,
              candidate.user == nil,
              candidate.password == nil else {
            return nil
        }

        let candHost = Self.normalizeLiteralIP(candidate.host ?? "") ?? candidate.host?.lowercased()
        let baseHost = Self.normalizeLiteralIP(baseURL.host ?? "") ?? baseURL.host?.lowercased()
        guard let ch = candHost, let bh = baseHost, ch == bh else {
            NSLog("[DLNADiscovery] 🛡️ Blocked cross-host controlURL '%@' for baseURL '%@'", candidate.absoluteString, baseURL.absoluteString)
            return nil
        }

        let defaultPort = (baseScheme == "https") ? 443 : 80
        let candPort = candidate.port ?? defaultPort
        let basePort = baseURL.port ?? defaultPort
        guard candPort == basePort else {
            NSLog("[DLNADiscovery] 🛡️ Blocked cross-port controlURL '%@' for baseURL '%@'", candidate.absoluteString, baseURL.absoluteString)
            return nil
        }

        return candidate
    }
}
