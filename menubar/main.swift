import AppKit
import AVFoundation
import ServiceManagement

// ───────────────────────────── Config ──────────────────────────────
// Locate the recorder script. Order: explicit override, then the
// Homebrew bin shim, then a path relative to this executable (for a
// dev build run straight out of the source tree).
func resolveRecordScript() -> String {
    let fm = FileManager.default
    if let env = ProcessInfo.processInfo.environment["MIRROR_RECORD_SCRIPT"],
       fm.isExecutableFile(atPath: env) { return env }
    var candidates = [
        "/opt/homebrew/bin/mirror-record",
        "/usr/local/bin/mirror-record",
    ]
    // …/Mirror.app/Contents/MacOS/Mirror -> repo root record.sh (dev builds)
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let repoRoot = exe.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    candidates.append(repoRoot.appendingPathComponent("record.sh").path)
    return candidates.first { fm.isExecutableFile(atPath: $0) } ?? candidates[0]
}
let recordScript = resolveRecordScript()
let defaultRecordingsDir = ("~/Documents/SecurityCam" as NSString).expandingTildeInPath

enum K {
    static let dir       = "recordingsDir"
    static let bitrate   = "bitrate"
    static let segment   = "segmentSeconds"
    static let retention = "retentionDays"
    static let audio     = "audioEnabled"
    static let camera    = "videoDevice"
    static let mic       = "audioDevice"
    static let maxGB     = "maxFolderGB"
}

let qualities: [(name: String, bitrate: String)] = [
    ("Low (720p-ish, small files)",  "2000k"),
    ("Medium (balanced)",            "4000k"),
    ("High (sharp, larger files)",   "8000k"),
]
let segments: [(name: String, secs: Int)] = [
    ("5 minutes", 300), ("10 minutes", 600), ("15 minutes", 900), ("30 minutes", 1800),
]
let retentions: [(name: String, days: Int)] = [
    ("1 day", 1), ("3 days", 3), ("7 days", 7), ("14 days", 14), ("Keep everything", 3650),
]
// Max folder size in GB; 0 = no limit. Oldest clips are deleted past the cap.
let maxSizes: [(name: String, gb: Int)] = [
    ("No limit", 0), ("1 GB", 1), ("5 GB", 5), ("10 GB", 10),
    ("25 GB", 25), ("50 GB", 50), ("100 GB", 100),
]

let d = UserDefaults.standard

func cfgDir() -> String       { d.string(forKey: K.dir) ?? defaultRecordingsDir }
func cfgBitrate() -> String   { d.string(forKey: K.bitrate) ?? "4000k" }
func cfgSegment() -> Int      { let v = d.integer(forKey: K.segment); return v == 0 ? 600 : v }
func cfgRetention() -> Int    { let v = d.integer(forKey: K.retention); return v == 0 ? 3 : v }
func cfgAudio() -> Bool       { d.object(forKey: K.audio) == nil ? true : d.bool(forKey: K.audio) }
func cfgCamera() -> String    { d.string(forKey: K.camera) ?? "FaceTime HD Camera" }
func cfgMic() -> String       { d.string(forKey: K.mic) ?? "MacBook Pro Microphone" }
func cfgMaxGB() -> Int        { d.integer(forKey: K.maxGB) }   // 0 (default) = no limit

// ──────────────────────────── Devices ──────────────────────────────
func videoDevices() -> [String] {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) { types += [.external, .continuityCamera] }
    return AVCaptureDevice.DiscoverySession(deviceTypes: types,
        mediaType: .video, position: .unspecified).devices.map { $0.localizedName }
}
func audioDevices() -> [String] {
    var types: [AVCaptureDevice.DeviceType] = []
    if #available(macOS 14.0, *) { types = [.microphone, .external] }
    else { types = [.builtInMicrophone] }
    return AVCaptureDevice.DiscoverySession(deviceTypes: types,
        mediaType: .audio, position: .unspecified).devices.map { $0.localizedName }
}

// ─────────────────────────── Mirror view ───────────────────────────
// Hosts a live, horizontally-flipped camera preview so you can use Mirror
// like an actual mirror to check your appearance.
final class MirrorView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        preview.frame = bounds
    }
}

// ─────────────────────────── App Delegate ──────────────────────────
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var process: Process?
    var startedAt: Date?
    var ticker: Timer?
    weak var elapsedItem: NSMenuItem?
    var previewWindow: NSWindow?
    var previewSession: AVCaptureSession?

    var isRecording: Bool { process != nil }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    // MARK: Menu bar icon + live timer
    func refreshIcon() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        if isRecording {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let img = NSImage(systemSymbolName: "record.circle.fill",
                              accessibilityDescription: "Recording")?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = false
            button.image = img
            button.title = " " + shortElapsed()
            button.toolTip = "Mirror — recording"
        } else {
            let img = NSImage(systemSymbolName: "circle.righthalf.filled",
                              accessibilityDescription: "Mirror")
            img?.isTemplate = true
            button.image = img
            button.title = ""
            button.toolTip = "Mirror — idle"
        }
    }

    func elapsed() -> TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }
    func shortElapsed() -> String {
        let t = Int(elapsed()); let h = t/3600, m = (t%3600)/60, s = t%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    @objc func tick() {
        refreshIcon()
        elapsedItem?.title = "Recording — " + shortElapsed()
    }

    // MARK: Build menu (rebuilt each time it opens)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status header
        let header = NSMenuItem(
            title: isRecording ? "Recording — " + shortElapsed() : "Idle",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        let dot = NSImage(systemSymbolName: isRecording ? "record.circle.fill" : "circle",
                          accessibilityDescription: nil)
        if isRecording {
            dot?.isTemplate = false
            header.image = dot?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        } else { header.image = dot }
        menu.addItem(header)
        elapsedItem = isRecording ? header : nil

        // Stats line
        let (count, bytes) = folderStats()
        let stats = NSMenuItem(title: "\(count) clip\(count == 1 ? "" : "s") · \(humanSize(bytes))",
                               action: nil, keyEquivalent: "")
        stats.isEnabled = false
        menu.addItem(stats)

        menu.addItem(.separator())

        // Start / Stop
        let toggle = NSMenuItem(title: isRecording ? "Stop Recording" : "Start Recording",
                                action: #selector(toggleRecording), keyEquivalent: "r")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: isRecording ? "stop.fill" : "record.circle",
                               accessibilityDescription: nil)
        menu.addItem(toggle)

        // Hard stop: kills any stray recorder/ffmpeg holding the camera, even
        // ones this app instance didn't launch (crash leftovers, LaunchAgent).
        let force = NSMenuItem(title: "Force Stop & Release Camera",
                               action: #selector(forceStopAll), keyEquivalent: "")
        force.target = self
        force.image = NSImage(systemSymbolName: "camera.badge.ellipsis",
                              accessibilityDescription: nil)
        menu.addItem(force)

        let mirror = NSMenuItem(title: "Show Mirror",
                                action: #selector(showMirror), keyEquivalent: "m")
        mirror.target = self
        mirror.image = NSImage(systemSymbolName: "person.crop.rectangle",
                               accessibilityDescription: nil)
        menu.addItem(mirror)

        let open = NSMenuItem(title: "Open Recordings Folder",
                              action: #selector(openFolder), keyEquivalent: "o")
        open.target = self
        open.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(open)

        menu.addItem(.separator())

        // Settings submenu
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settings.submenu = buildSettingsMenu()
        menu.addItem(settings)

        let changeDir = NSMenuItem(title: "Change Recordings Folder…",
                                   action: #selector(changeFolder), keyEquivalent: "")
        changeDir.target = self
        changeDir.image = NSImage(systemSymbolName: "folder.badge.gearshape",
                                  accessibilityDescription: nil)
        menu.addItem(changeDir)

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = loginEnabled() ? .on : .off
        menu.addItem(login)

        // Only relevant when the KeepAlive recorder service is installed.
        if agentInstalled() {
            let agent = NSMenuItem(title: "Auto-Record Service",
                                   action: #selector(toggleAgent), keyEquivalent: "")
            agent.target = self
            agent.state = agentLoaded() ? .on : .off
            agent.toolTip = "Background recorder that auto-starts at login (com.temery.mirror)"
            menu.addItem(agent)
        }

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Mirror",
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Mirror", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuDidClose(_ menu: NSMenu) { elapsedItem = nil }

    func buildSettingsMenu() -> NSMenu {
        let m = NSMenu()

        func section(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false
            m.addItem(i)
        }

        section("Quality")
        for q in qualities {
            let i = NSMenuItem(title: q.name, action: #selector(selectQuality(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = q.bitrate
            i.state = (q.bitrate == cfgBitrate()) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())

        section("Segment Length")
        for s in segments {
            let i = NSMenuItem(title: s.name, action: #selector(selectSegment(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = s.secs
            i.state = (s.secs == cfgSegment()) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())

        section("Keep Recordings")
        for r in retentions {
            let i = NSMenuItem(title: r.name, action: #selector(selectRetention(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = r.days
            i.state = (r.days == cfgRetention()) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())

        section("Max Folder Size")
        for s in maxSizes {
            let i = NSMenuItem(title: s.name, action: #selector(selectMaxSize(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = s.gb
            i.state = (s.gb == cfgMaxGB()) ? .on : .off
            m.addItem(i)
        }
        m.addItem(.separator())

        let audio = NSMenuItem(title: "Record Audio", action: #selector(toggleAudio), keyEquivalent: "")
        audio.target = self; audio.state = cfgAudio() ? .on : .off
        m.addItem(audio)
        m.addItem(.separator())

        let cam = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        let camMenu = NSMenu()
        for name in videoDevices() {
            let i = NSMenuItem(title: name, action: #selector(selectCamera(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = name
            i.state = (name == cfgCamera()) ? .on : .off
            camMenu.addItem(i)
        }
        cam.submenu = camMenu
        m.addItem(cam)

        let mic = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let micMenu = NSMenu()
        for name in audioDevices() {
            let i = NSMenuItem(title: name, action: #selector(selectMic(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = name
            i.state = (name == cfgMic()) ? .on : .off
            micMenu.addItem(i)
        }
        mic.submenu = micMenu
        m.addItem(mic)

        return m
    }

    // MARK: Settings actions
    func applyChange() { if isRecording { stop(); start() } }

    @objc func selectQuality(_ s: NSMenuItem)   { d.set(s.representedObject as! String, forKey: K.bitrate); applyChange() }
    @objc func selectSegment(_ s: NSMenuItem)   { d.set(s.representedObject as! Int, forKey: K.segment); applyChange() }
    @objc func selectRetention(_ s: NSMenuItem) { d.set(s.representedObject as! Int, forKey: K.retention); applyChange() }
    @objc func selectCamera(_ s: NSMenuItem)    { d.set(s.representedObject as! String, forKey: K.camera); applyChange() }
    @objc func selectMic(_ s: NSMenuItem)       { d.set(s.representedObject as! String, forKey: K.mic); applyChange() }
    @objc func selectMaxSize(_ s: NSMenuItem)   { d.set(s.representedObject as! Int, forKey: K.maxGB); applyChange() }
    @objc func toggleAudio()                    { d.set(!cfgAudio(), forKey: K.audio); applyChange() }

    // MARK: Recording control
    @objc func toggleRecording() { isRecording ? stop() : start() }

    func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [recordScript]
        var env = ProcessInfo.processInfo.environment
        env["MIRROR_DIR"]            = cfgDir()
        env["MIRROR_BITRATE"]        = cfgBitrate()
        env["MIRROR_SEGMENT"]        = String(cfgSegment())
        env["MIRROR_RETENTION_DAYS"] = String(cfgRetention())
        env["MIRROR_MAX_GB"]         = String(cfgMaxGB())
        env["MIRROR_VIDEO"]          = cfgCamera()
        env["MIRROR_AUDIO"]          = cfgAudio() ? cfgMic() : ""
        env["MIRROR_PID"]            = String(ProcessInfo.processInfo.processIdentifier)
        p.environment = env
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.process = nil; self?.stopTicker(); self?.refreshIcon() }
        }
        do {
            try p.run()
            process = p
            startedAt = Date()
            ticker = Timer.scheduledTimer(timeInterval: 1, target: self,
                        selector: #selector(tick), userInfo: nil, repeats: true)
        } catch {
            let a = NSAlert(); a.messageText = "Could not start recording"
            a.informativeText = error.localizedDescription; a.runModal()
        }
        refreshIcon()
    }

    func stop() {
        process?.terminate()      // SIGTERM → record.sh trap finalizes the clip
        process = nil
        stopTicker()
        refreshIcon()
    }

    func stopTicker() { ticker?.invalidate(); ticker = nil; startedAt = nil }

    // Nuke every recorder process that could be holding the camera, including
    // orphans this app instance didn't launch. Each pattern is matched against
    // the full command line via `pkill -f`.
    @objc func forceStopAll() {
        stop()  // graceful stop for our own tracked process, if any
        // Boot out the KeepAlive login agent FIRST, otherwise launchd respawns
        // the recorder the instant we kill it.
        setAgent(loaded: false)
        let patterns = [
            recordScript,             // the supervising record.sh, by full path
            cfgDir() + "/cam_",       // the ffmpeg encoder, by its output path
        ]
        for pat in patterns {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-TERM", "-f", pat]   // TERM lets ffmpeg finalize the clip
            try? p.run()
            p.waitUntilExit()
        }
        refreshIcon()
    }

    // MARK: Live mirror preview
    func deviceForConfiguredCamera() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) { types += [.external, .continuityCamera] }
        let devs = AVCaptureDevice.DiscoverySession(deviceTypes: types,
            mediaType: .video, position: .unspecified).devices
        return devs.first { $0.localizedName == cfgCamera() } ?? devs.first
    }

    @objc func showMirror() {
        if let w = previewWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            openMirror()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { if ok { self?.openMirror() } }
            }
        default:
            let a = NSAlert()
            a.messageText = "Camera access is off"
            a.informativeText = "Enable camera access for Mirror in System Settings → Privacy & Security → Camera."
            a.runModal()
        }
    }

    func openMirror() {
        guard let device = deviceForConfiguredCamera(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            let a = NSAlert()
            a.messageText = "Couldn't open the camera"
            a.informativeText = "The selected camera may be unavailable. Pick a different camera in Settings."
            a.runModal()
            return
        }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }

        let view = MirrorView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        view.preview.session = session
        if let conn = view.preview.connection {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true          // flip like a real mirror
        }

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Mirror"
        w.contentView = view
        w.contentAspectRatio = NSSize(width: 4, height: 3)
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        previewWindow = w
        previewSession = session

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === previewWindow else { return }
        previewSession?.stopRunning()
        previewSession = nil
        previewWindow = nil
    }

    // MARK: Folder + stats
    @objc func openFolder() {
        let dir = cfgDir()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Choose"; panel.message = "Choose where Mirror saves recordings"
        panel.directoryURL = URL(fileURLWithPath: cfgDir())
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        d.set(url.path, forKey: K.dir)
        applyChange()
    }

    func folderStats() -> (Int, Int64) {
        let dir = cfgDir()
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return (0, 0) }
        var count = 0; var bytes: Int64 = 0
        for f in items where f.hasPrefix("cam_") && f.hasSuffix(".mp4") {
            count += 1
            if let attr = try? FileManager.default.attributesOfItem(atPath: dir + "/" + f),
               let sz = attr[.size] as? Int64 { bytes += sz }
        }
        return (count, bytes)
    }

    func humanSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    // MARK: Auto-record LaunchAgent (com.temery.mirror, KeepAlive)
    // This is the login-time recorder service. Its KeepAlive will respawn the
    // recorder after any kill, so Force Stop must boot it out, and we expose a
    // toggle to bring it back.
    let agentLabel = "com.temery.mirror"
    var agentPlistPath: String {
        ("~/Library/LaunchAgents/\(agentLabel).plist" as NSString).expandingTildeInPath
    }
    func agentInstalled() -> Bool { FileManager.default.fileExists(atPath: agentPlistPath) }
    func agentLoaded() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/\(agentLabel)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }
    func setAgent(loaded: Bool) {
        let uid = String(getuid())
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        if loaded {
            guard agentInstalled() else { return }
            p.arguments = ["bootstrap", "gui/\(uid)", agentPlistPath]
        } else {
            p.arguments = ["bootout", "gui/\(uid)/\(agentLabel)"]
        }
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
    @objc func toggleAgent() {
        setAgent(loaded: !agentLoaded())
        refreshIcon()
    }

    // MARK: Launch at login
    func loginEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @objc func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert(); a.messageText = "Couldn't change Login Item"
            a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    // MARK: About / Quit
    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Mirror",
            .applicationVersion: "1.3.0",
            .credits: NSAttributedString(string:
                "Continuous security-camera recorder.\nSaves rolling clips with audio to your chosen folder.\n\nNote: the green camera light is hardware-controlled and cannot be turned off.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    @objc func quit() { stop(); NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
