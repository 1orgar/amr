//
//  ServerDiscoverySheet.swift
//  AppleMusicRemoteIOS
//
//  Bonjour zero-config Mac discovery sheet with pairing and manual IP connection
//

import SwiftUI

public struct ServerDiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: PlayerStore
    @ObservedObject public var browser: BonjourBrowser

    @State private var manualHost: String = ""
    @State private var manualPort: String = "8080"
    @State private var showManualInput: Bool = false

    public init(store: PlayerStore = .shared, browser: BonjourBrowser = .shared) {
        self.store = store
        self.browser = browser
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header Status Card
                HStack(spacing: 14) {
                    Circle()
                        .fill(store.isConnected ? Color.green : Color.orange)
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isConnected ? "Подключено к Mac" : "Поиск Mac в локальной сети...")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        if let cur = store.currentServer {
                            Text("\(cur.name) (\(cur.ipAddress):\(cur.port))")
                                .font(.system(size: 13))
                                .foregroundColor(.amrTextSecondary)
                        } else {
                            Text("Проверьте, что Mac и iPhone в одной сети Wi-Fi")
                                .font(.system(size: 13))
                                .foregroundColor(.amrTextSecondary)
                        }
                    }

                    Spacer()

                    if store.isConnected {
                        Button("Отключить") {
                            store.disconnect()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.amrRed)
                    }
                }
                .padding(16)
                .amrDarkGlass(cornerRadius: 14)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Discovered Macs list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("НАЙДЕННЫЕ УСТРОЙСТВА (BONJOUR)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.amrTextTertiary)

                        Spacer()

                        Button(action: {
                            AMRHaptics.selection()
                            browser.startDiscovery()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.amrRed)
                        }
                    }
                    .padding(.horizontal, 20)

                    if browser.discoveredServers.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.amrRed)
                                .scaleEffect(0.9)
                            Text("Сканирование сети _applemusicremote._tcp...")
                                .font(.system(size: 13))
                                .foregroundColor(.amrTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .amrDarkGlass(cornerRadius: 14)
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(browser.discoveredServers) { server in
                                Button(action: {
                                    AMRHaptics.medium()
                                    store.connect(to: server)
                                    dismiss()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "macbook.and.iphone")
                                            .font(.system(size: 20))
                                            .foregroundColor(.amrRed)
                                            .frame(width: 32)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(server.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)

                                            Text("\(server.ipAddress):\(server.port) • \(server.pingMs)ms ping")
                                                .font(.system(size: 12))
                                                .foregroundColor(.amrTextSecondary)
                                        }

                                        Spacer()

                                        if store.currentServer?.id == server.id && store.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 18))
                                        } else {
                                            Text("Подключить")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.amrRed)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Capsule().fill(Color.amrRed.opacity(0.15)))
                                        }
                                    }
                                    .padding(14)
                                    .amrDarkGlass(cornerRadius: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Manual Connection Toggle
                VStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.spring()) {
                            showManualInput.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.amrTextSecondary)
                            Text("Подключиться по IP вручную")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: showManualInput ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(.amrTextSecondary)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    if showManualInput {
                        VStack(spacing: 10) {
                            TextField("IP адрес (например 192.168.1.100)", text: $manualHost)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.amrSurfaceGlass)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundColor(.white)

                            TextField("Порт (8080)", text: $manualPort)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.amrSurfaceGlass)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundColor(.white)

                            Button("Подключить") {
                                let portInt = Int(manualPort) ?? 8080
                                store.connect(host: manualHost.isEmpty ? "localhost" : manualHost, port: portInt)
                                dismiss()
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.amrRed)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Spacer()
            }
            .background(Color.amrBackground.ignoresSafeArea())
            .navigationTitle("Выбор Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundColor(.amrRed)
                }
            }
        }
    }
}
