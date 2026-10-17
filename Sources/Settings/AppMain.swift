import AppKit

@main
enum OceanSettingsMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = OceanAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class OceanAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var scene: OceanMetalView?
    private var settings: SettingsWindowController?
    private var refresher: LocationRefreshService?
    private var smokeTimer: Timer?
    private var smokeStart = Date()
    private var receivedFrame = false
    private var smokeFinishing = false
    private let arguments = CommandLine.arguments

    private func argument(_ key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if arguments.contains("--refresh-location") {
            NSApp.setActivationPolicy(.prohibited)
            refresher = LocationRefreshService { NSApp.terminate(nil) }
            refresher?.start()
            return
        }
        NSApp.setActivationPolicy(.regular)
        installMenu()
        let isSmoke = argument("--snapshot") != nil
        let width = Double(argument("--width") ?? "1100") ?? 1100
        let height = Double(argument("--height") ?? "700") ?? 700
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ocean"
        window.delegate = self
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false
        self.window = window
        let scene = OceanMetalView(frame: window.contentView!.bounds, bundle: .main, preview: false)
        scene.autoresizingMask = [.width, .height]
        if let value = argument("--date") { scene.diagnosticDate = ISO8601DateFormatter().date(from: value) }
        if let lat = argument("--latitude").flatMap(Double.init), let lon = argument("--longitude").flatMap(Double.init) {
            scene.diagnosticCoordinate = GeographicCoordinate(latitude: lat, longitude: lon)
        }
        scene.onEvent = { [weak self] event, message in
            guard let self else { return }
            if isSmoke { print("Ocean event: \(event) \(message ?? "")") }
            if event == "frame" { self.receivedFrame = true }
            if event == "error" && isSmoke { self.finishSmoke(code: 1, message: message ?? "Renderer failed") }
        }
        window.contentView?.addSubview(scene)
        self.scene = scene
        if !isSmoke {
            let toolbar = NSToolbar(identifier: "OceanToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconAndLabel
            window.toolbar = toolbar
            refreshStatus()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        scene.start()
        if isSmoke {
            smokeStart = Date()
            smokeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkSmoke() }
        } else if arguments.contains("--settings") || OceanPreferences.load().coordinateSource == .timeZone {
            openSettings()
        }
    }

    @objc private func openSettings() {
        // Recreate the draft each time, including fixes saved by a background refresh.
        settings = SettingsWindowController { [weak self] in
            self?.scene?.updateSun()
            self?.refreshStatus()
        }
        settings?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatus() {
        let preferences = OceanPreferences.load()
        window?.subtitle = preferences.sourceDescription
    }

    private func installMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let menu = NSMenu()
        menu.addItem(withTitle: "Ocean Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ocean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = menu
        bar.addItem(appItem)
        NSApp.mainMenu = bar
    }

    private func checkSmoke() {
        guard !smokeFinishing else { return }
        if Date().timeIntervalSince(smokeStart) > 60 {
            finishSmoke(code: 1, message: "Timed out waiting for a rendered Metal frame")
            return
        }
        guard receivedFrame, Date().timeIntervalSince(smokeStart) >= 4 else { return }
        smokeFinishing = true
        scene?.diagnostics { [weak self] result, error in
            guard let self else { return }
            if let error { self.finishSmoke(code: 1, message: error.localizedDescription); return }
            if let result { print("Ocean diagnostics: \(result)") }
            guard let destination = self.argument("--snapshot") else { return }
            self.scene?.snapshot(to: URL(fileURLWithPath: destination)) { error in
                if let error { self.finishSmoke(code: 1, message: error.localizedDescription) }
                else { self.finishSmoke(code: 0, message: "Rendered snapshot: \(destination)") }
            }
        }
    }

    private func finishSmoke(code: Int32, message: String) {
        smokeTimer?.invalidate()
        smokeTimer = nil
        print(message)
        scene?.tearDown()
        fflush(stdout)
        exit(code)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { scene?.tearDown() }
}

extension OceanAppDelegate: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("settings")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("settings")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier.rawValue == "settings" else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Settings"
        item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Ocean Settings")
        item.target = self
        item.action = #selector(openSettings)
        return item
    }
}
