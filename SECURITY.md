# Security Policy

## Architecture & Privacy Posture

- **100% Local LAN Execution**: AMR runs directly on your Mac over your local network (`HTTP / WebSocket :8080`, optional `UPnP :8090`). No audio streams, listening history, or library metadata are sent to third-party servers.
- **Zero-Keychain `AES-256-GCM` Vault**: Local credentials and MusicKit tokens are encrypted at rest via Apple `CryptoKit` (`AES-256-GCM`) with strict `0700` / `0600` POSIX permissions.
- **Per-Device Authorization**: Remote Web PWA clients can be gated with invite tokens (`?invite=<token>`) and granular per-device capability permissions (`DAC`, `DSP`, `Room EQ`, `Late-Night DRC`).
- **Signed & Apple Notarized**: Official Universal 2 `.dmg` releases are signed with an Apple Developer ID certificate and notarized by Apple.

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `3.0.x` | ✅ Yes |
| `< 3.0` | ❌ Upgrade to `v3.0.0+` |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities. Instead, use GitHub's [**Report a vulnerability**](https://github.com/1orgar/amr/security/advisories/new) private advisory form (or contact `@1orgar` via GitHub) with reproduction details and affected macOS / AMR versions.
