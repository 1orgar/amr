//
//  main.swift
//  MockDLNARenderer
//
//  Standalone Mock DLNA MediaRenderer Application (Emulates Bluesound NODE NANO)
//

import Foundation
import Darwin

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  📻 Mock DLNA Renderer Server (Bluesound NODE NANO)")
print("  Standalone test utility for Apple Music Remote (AMR)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

var port: UInt16 = 8095
if CommandLine.arguments.count > 1, let p = UInt16(CommandLine.arguments[1]) {
    port = p
}

let server = MockDLNARendererServer.shared
guard server.start(preferredPort: port) else {
    fputs("❌ Error: Failed to start Mock DLNA Renderer on port \(port)\n", stderr)
    exit(1)
}

print("✅ Server active on port \(server.port)")
print("📡 SSDP M-SEARCH Responder active on 239.255.255.250:1900")
print("🔗 XML Device Description: http://127.0.0.1:\(server.port)/mock/description.xml")
print("Press Ctrl+C to terminate.")

signal(SIGINT) { _ in
    print("\n⏹ Shutting down Mock DLNA Renderer...")
    MockDLNARendererServer.shared.stop()
    exit(0)
}
signal(SIGTERM) { _ in
    print("\n⏹ Shutting down Mock DLNA Renderer...")
    MockDLNARendererServer.shared.stop()
    exit(0)
}

dispatchMain()
