//
//  LANSubnetGuard.swift
//  AppleMusicRemoteMac
//
//  Same-subnet unicast peer verification via getifaddrs() and a shared
//  no-redirect, size-bounded HTTP client for UPnP GENA, SOAP, and DLNA/BluOS.
//

import Darwin
import Foundation

public enum LANSubnetGuard {
    public static func normalizePeerIP(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n")).lowercased()
        if let pct = clean.firstIndex(of: "%") {
            clean = String(clean[..<pct])
        }
        if clean.hasPrefix("::ffff:") {
            clean = String(clean.dropFirst("::ffff:".count))
        }
        return clean
    }

    public static func isLoopbackIP(_ raw: String) -> Bool {
        let ip = normalizePeerIP(raw)
        if ip == "127.0.0.1" || ip == "::1" || ip == "localhost" {
            return true
        }
        var addr4 = in_addr()
        if inet_pton(AF_INET, ip, &addr4) == 1 {
            let hostOrder = UInt32(bigEndian: addr4.s_addr)
            return ((hostOrder >> 24) & 0xFF) == 127
        }
        return false
    }

    /// Returns `true` only if `remoteIP` is loopback or resides on the exact same IPv4/IPv6 subnet
    /// as an active non-loopback network interface on this Mac (rejecting WAN, cloud metadata
    /// `169.254.169.254`, multicast, broadcast, and cross-subnet enterprise/public Wi-Fi peers).
    public static func isSameSubnetOrLoopbackPeer(_ remoteIP: String) -> Bool {
        let ip = normalizePeerIP(remoteIP)
        guard !ip.isEmpty else { return false }
        if isLoopbackIP(ip) {
            return true
        }

        var peerAddr4 = in_addr()
        if inet_pton(AF_INET, ip, &peerAddr4) == 1 {
            let peer = UInt32(bigEndian: peerAddr4.s_addr)
            let b0 = Int((peer >> 24) & 0xFF)
            let b1 = Int((peer >> 16) & 0xFF)
            let b2 = Int((peer >> 8) & 0xFF)
            let b3 = Int(peer & 0xFF)

            if b0 == 0 || b0 >= 224 || peer == 0xFFFF_FFFF {
                return false
            }
            if b0 == 169 && b1 == 254 && b2 == 169 && b3 == 254 {
                return false
            }
            let isPrivateOrLinkLocal = (b0 == 10)
                || (b0 == 172 && (16...31).contains(b1))
                || (b0 == 192 && b1 == 168)
                || (b0 == 169 && b1 == 254)
            guard isPrivateOrLinkLocal else { return false }

            var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
                return false
            }
            defer { freeifaddrs(first) }

            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let ifa = cursor {
                defer { cursor = ifa.pointee.ifa_next }
                let flags = Int32(ifa.pointee.ifa_flags)
                guard (flags & IFF_UP) != 0,
                      (flags & IFF_RUNNING) != 0,
                      (flags & IFF_LOOPBACK) == 0,
                      let addr = ifa.pointee.ifa_addr,
                      let netmask = ifa.pointee.ifa_netmask,
                      addr.pointee.sa_family == sa_family_t(AF_INET),
                      netmask.pointee.sa_family == sa_family_t(AF_INET) else {
                    continue
                }

                let ifaceHost = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                let maskHost = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                guard maskHost != 0 else { continue }
                if maskHost == 0xFFFF_FFFF {
                    if peer == ifaceHost { return true }
                    continue
                }
                let hostBitsMask = ~maskHost
                // Reject subnet broadcast and network address when subnet is /30 or wider
                if hostBitsMask > 1 {
                    if (peer & hostBitsMask) == hostBitsMask || (peer & hostBitsMask) == 0 {
                        continue
                    }
                }
                if (peer & maskHost) == (ifaceHost & maskHost) {
                    return true
                }
            }
            return false
        }

        var peerAddr6 = in6_addr()
        if inet_pton(AF_INET6, ip, &peerAddr6) == 1 {
            let peerBytes = withUnsafeBytes(of: &peerAddr6) { Array($0) }
            guard peerBytes.count == 16 else { return false }
            if peerBytes.allSatisfy({ $0 == 0 }) || peerBytes[0] == 0xFF {
                return false
            }
            let isULA = (peerBytes[0] & 0xFE) == 0xFC
            let isLinkLocal = peerBytes[0] == 0xFE && (peerBytes[1] & 0xC0) == 0x80
            guard isULA || isLinkLocal else { return false }

            var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
                return false
            }
            defer { freeifaddrs(first) }

            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let ifa = cursor {
                defer { cursor = ifa.pointee.ifa_next }
                let flags = Int32(ifa.pointee.ifa_flags)
                guard (flags & IFF_UP) != 0,
                      (flags & IFF_RUNNING) != 0,
                      (flags & IFF_LOOPBACK) == 0,
                      let addr = ifa.pointee.ifa_addr,
                      let netmask = ifa.pointee.ifa_netmask,
                      addr.pointee.sa_family == sa_family_t(AF_INET6),
                      netmask.pointee.sa_family == sa_family_t(AF_INET6) else {
                    continue
                }

                let ifaceBytes = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr -> [UInt8] in
                    var a = ptr.pointee.sin6_addr
                    return withUnsafeBytes(of: &a) { Array($0) }
                }
                let maskBytes = netmask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr -> [UInt8] in
                    var m = ptr.pointee.sin6_addr
                    return withUnsafeBytes(of: &m) { Array($0) }
                }
                guard ifaceBytes.count == 16, maskBytes.count == 16,
                      (maskBytes[0] != 0 || maskBytes[1] != 0) else {
                    continue
                }
                var matches = true
                for idx in 0..<16 {
                    if (peerBytes[idx] & maskBytes[idx]) != (ifaceBytes[idx] & maskBytes[idx]) {
                        matches = false
                        break
                    }
                }
                if matches {
                    return true
                }
            }
            return false
        }

        return false
    }

    /// Returns `true` if `remoteIP` is loopback, resides on the same interface subnet, or is a valid
    /// unicast RFC1918 / IPv6 ULA private LAN peer (supporting multi-VLAN home networks such as
    /// `10.10.10.0/24` <-> `10.10.20.0/24` <-> `10.10.30.0/24` while rejecting WAN, CGNAT, cloud metadata
    /// `169.254.0.0/16`, multicast, and broadcast addresses).
    public static func isPrivateLANOrLoopbackPeer(_ remoteIP: String) -> Bool {
        if isSameSubnetOrLoopbackPeer(remoteIP) {
            return true
        }
        let ip = normalizePeerIP(remoteIP)
        guard !ip.isEmpty else { return false }

        var peerAddr4 = in_addr()
        if inet_pton(AF_INET, ip, &peerAddr4) == 1 {
            let peer = UInt32(bigEndian: peerAddr4.s_addr)
            let b0 = Int((peer >> 24) & 0xFF)
            let b1 = Int((peer >> 16) & 0xFF)
            let b3 = Int(peer & 0xFF)

            if b0 == 0 || b0 == 127 || b0 >= 224 || peer == 0xFFFF_FFFF {
                return false
            }
            // Reject common /24 network & broadcast host octets on routed VLANs unless matched above
            if b3 == 0 || b3 == 255 {
                return false
            }
            let isRFC1918 = (b0 == 10)
                || (b0 == 172 && (16...31).contains(b1))
                || (b0 == 192 && b1 == 168)
            return isRFC1918
        }

        var peerAddr6 = in6_addr()
        if inet_pton(AF_INET6, ip, &peerAddr6) == 1 {
            let peerBytes = withUnsafeBytes(of: &peerAddr6) { Array($0) }
            guard peerBytes.count == 16 else { return false }
            if peerBytes.allSatisfy({ $0 == 0 }) || peerBytes[0] == 0xFF {
                return false
            }
            // Unique Local Address (fc00::/7)
            return (peerBytes[0] & 0xFE) == 0xFC
        }

        return false
    }
}

/// Dedicated HTTP client for UPnP / DLNA / BluOS LAN traffic that strictly blocks all HTTP
/// redirects (`301`/`302`/`307`/`308`) and enforces a hard upper bound on response body size.
public final class BoundedNoRedirectHTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public static let shared = BoundedNoRedirectHTTPClient()

    private struct TaskAccumulation {
        let maxBytes: Int
        var buffer: Data
        var response: HTTPURLResponse?
        var overflowError: Error?
        let completion: @Sendable (Data?, HTTPURLResponse?, Error?) -> Void
    }

    private let stateLock = NSLock()
    private var tasks: [Int: TaskAccumulation] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 22.0
        let opQueue = OperationQueue()
        opQueue.name = "org.ksholokhov.amr.upnp.http-client"
        opQueue.qualityOfService = .utility
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: opQueue)
    }

    @discardableResult
    public func fetch(
        request: URLRequest,
        maxBytes: Int = 256 * 1024,
        completion: @escaping @Sendable (Data?, HTTPURLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        let boundedMax = max(1024, maxBytes)
        stateLock.lock()
        tasks[task.taskIdentifier] = TaskAccumulation(
            maxBytes: boundedMax,
            buffer: Data(),
            response: nil,
            overflowError: nil,
            completion: completion
        )
        stateLock.unlock()
        task.resume()
        return task
    }

    public func fetchAsync(
        request: URLRequest,
        maxBytes: Int = 256 * 1024
    ) async throws -> (Data, HTTPURLResponse) {
        let taskBox = UnsafeTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = self.fetch(request: request, maxBytes: maxBytes) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data, let response = response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                taskBox.set(task)
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Never follow redirects on UPnP GENA NOTIFY, SOAP, SSDP description, or BluOS endpoints.
        completionHandler(nil)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        stateLock.lock()
        guard var entry = tasks[dataTask.taskIdentifier] else {
            stateLock.unlock()
            completionHandler(.cancel)
            return
        }
        entry.response = response as? HTTPURLResponse
        if response.expectedContentLength > Int64(entry.maxBytes) {
            entry.overflowError = URLError(.dataLengthExceedsMaximum)
            tasks[dataTask.taskIdentifier] = entry
            stateLock.unlock()
            completionHandler(.cancel)
            return
        }
        tasks[dataTask.taskIdentifier] = entry
        stateLock.unlock()
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock()
        guard var entry = tasks[dataTask.taskIdentifier] else {
            stateLock.unlock()
            dataTask.cancel()
            return
        }
        if entry.buffer.count + data.count > entry.maxBytes {
            entry.overflowError = URLError(.dataLengthExceedsMaximum)
            tasks[dataTask.taskIdentifier] = entry
            stateLock.unlock()
            dataTask.cancel()
            return
        }
        entry.buffer.append(data)
        tasks[dataTask.taskIdentifier] = entry
        stateLock.unlock()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        guard let entry = tasks.removeValue(forKey: task.taskIdentifier) else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        if let overflow = entry.overflowError {
            entry.completion(nil, entry.response, overflow)
        } else if let error = error {
            entry.completion(nil, entry.response, error)
        } else {
            entry.completion(entry.buffer, entry.response, nil)
        }
    }
}

private final class UnsafeTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func set(_ newTask: URLSessionDataTask) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            newTask.cancel()
            return
        }
        task = newTask
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }
}
