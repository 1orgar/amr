import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var serverProcess: Process?
    var qrWindow: NSWindow?
    var qrImageView: NSImageView?
    var timer: Timer?
    var currentTrackTitle: String = "Apple Music Remote"
    var currentArtist: String = ""
    var isPlaying: Bool = false
    var serverPort: Int = 8080
    var primaryUrl: String = "http://localhost:8080"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Setup Status Item in Menu Bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Apple Music Remote")
            } else {
                button.title = "🎵"
            }
        }
        
        // 2. Start Python server process
        startServer()
        
        // 3. Build Menu
        rebuildMenu()
        
        // 4. Start update timer
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
        pollStatus()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopServer()
    }
    
    // MARK: - Server Management
    func startServer() {
        stopServer()
        
        let bundlePath = Bundle.main.bundlePath
        var scriptPath = "\(bundlePath)/Contents/Resources/server/server.py"
        var workingDir = "\(bundlePath)/Contents/Resources"
        
        if !FileManager.default.fileExists(atPath: scriptPath) {
            // Development fallback
            scriptPath = "/Users/1orgar/Desktop/amr/server/server.py"
            workingDir = "/Users/1orgar/Desktop/amr"
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [scriptPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        
        do {
            try proc.run()
            self.serverProcess = proc
            print("[Sidecar] Server process started PID: \(proc.processIdentifier)")
        } catch {
            print("[Sidecar] Failed to start server: \(error)")
        }
    }
    
    func stopServer() {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            serverProcess = nil
        }
    }
    
    // MARK: - Menu Construction
    func rebuildMenu() {
        let menu = NSMenu()
        
        // Now Playing Section
        let trackItem = NSMenuItem(title: currentTrackTitle, action: nil, keyEquivalent: "")
        trackItem.attributedTitle = NSAttributedString(
            string: currentTrackTitle,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(trackItem)
        
        if !currentArtist.isEmpty {
            let artistItem = NSMenuItem(title: currentArtist, action: nil, keyEquivalent: "")
            artistItem.attributedTitle = NSAttributedString(
                string: currentArtist,
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
            )
            menu.addItem(artistItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Playback Controls
        let playTitle = isPlaying ? "⏸ Пауза" : "▶️ Воспроизведение"
        menu.addItem(NSMenuItem(title: playTitle, action: #selector(togglePlayPause), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "⏭ Следующий трек", action: #selector(nextTrack), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "⏮ Предыдущий трек", action: #selector(prevTrack), keyEquivalent: "b"))
        
        menu.addItem(NSMenuItem.separator())
        
        // Remote URL & Status
        let remoteHeader = NSMenuItem(title: "🟢 Веб-пульт активен:", action: nil, keyEquivalent: "")
        remoteHeader.isEnabled = false
        menu.addItem(remoteHeader)
        
        let copyUrlItem = NSMenuItem(title: "  \(primaryUrl)", action: #selector(copyRemoteUrl), keyEquivalent: "c")
        copyUrlItem.toolTip = "Нажмите, чтобы скопировать адрес"
        menu.addItem(copyUrlItem)
        
        menu.addItem(NSMenuItem(title: "🌐 Открыть веб-пульт в браузере", action: #selector(openWebRemote), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "📱 Показать QR-код для телефона...", action: #selector(showQrCodeWindow), keyEquivalent: "q"))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "🔄 Перезапустить сервер", action: #selector(restartServer), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "❌ Завершить", action: #selector(quitApp), keyEquivalent: ""))
        
        statusItem.menu = menu
    }
    
    // MARK: - Status Polling
    func pollStatus() {
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/api/status") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let state = json["player_state"] as? String ?? "stopped"
                    let isPlay = (state == "playing")
                    var title = "Ничего не играет"
                    var artist = ""
                    
                    if let track = json["track"] as? [String: Any] {
                        title = track["name"] as? String ?? "Без названия"
                        artist = track["artist"] as? String ?? ""
                    }
                    
                    DispatchQueue.main.async {
                        if self.isPlaying != isPlay || self.currentTrackTitle != title || self.currentArtist != artist {
                            self.isPlaying = isPlay
                            self.currentTrackTitle = title
                            self.currentArtist = artist
                            self.rebuildMenu()
                        }
                    }
                }
            } catch {}
        }
        task.resume()
        
        // Fetch Primary URL
        if let infoUrl = URL(string: "http://127.0.0.1:\(serverPort)/api/info") {
            let infoTask = URLSession.shared.dataTask(with: infoUrl) { [weak self] data, _, _ in
                guard let self = self, let data = data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pUrl = json["primary_url"] as? String {
                    DispatchQueue.main.async {
                        if self.primaryUrl != pUrl {
                            self.primaryUrl = pUrl
                            self.rebuildMenu()
                        }
                    }
                }
            }
            infoTask.resume()
        }
    }
    
    // MARK: - Actions
    @objc func togglePlayPause() {
        postAction(endpoint: isPlaying ? "/api/pause" : "/api/play")
    }
    
    @objc func nextTrack() {
        postAction(endpoint: "/api/next")
    }
    
    @objc func prevTrack() {
        postAction(endpoint: "/api/prev")
    }
    
    func postAction(endpoint: String) {
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)\(endpoint)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.pollStatus()
            }
        }.resume()
    }
    
    @objc func copyRemoteUrl() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryUrl, forType: .string)
    }
    
    @objc func openWebRemote() {
        if let url = URL(string: primaryUrl) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func showQrCodeWindow() {
        if qrWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Apple Music Remote"
            window.center()
            window.isReleasedWhenClosed = false
            
            let container = NSView(frame: window.contentView!.bounds)
            
            let titleLabel = NSTextField(labelWithString: "Сканируйте камерой телефона:")
            titleLabel.frame = NSRect(x: 10, y: 340, width: 300, height: 24)
            titleLabel.alignment = .center
            titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
            container.addSubview(titleLabel)
            
            let imgView = NSImageView(frame: NSRect(x: 35, y: 70, width: 250, height: 250))
            imgView.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(imgView)
            self.qrImageView = imgView
            
            let urlLabel = NSTextField(labelWithString: primaryUrl)
            urlLabel.frame = NSRect(x: 10, y: 24, width: 300, height: 24)
            urlLabel.alignment = .center
            urlLabel.textColor = NSColor.systemPink
            urlLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            container.addSubview(urlLabel)
            
            window.contentView = container
            self.qrWindow = window
        }
        
        // Load QR Code SVG/Image
        if let qrUrl = URL(string: "http://127.0.0.1:\(serverPort)/api/qrcode") {
            URLSession.shared.dataTask(with: qrUrl) { [weak self] data, _, _ in
                guard let data = data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.qrImageView?.image = img
                }
            }.resume()
        }
        
        qrWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func restartServer() {
        startServer()
        rebuildMenu()
    }
    
    @objc func quitApp() {
        stopServer()
        NSApplication.shared.terminate(nil)
    }
}

// Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
