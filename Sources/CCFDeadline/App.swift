import AppKit
import DeadlineCore
import SwiftUI

@main
enum CCFDeadlineApp {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--validate-html"), arguments.count > index + 1 {
            do {
                let conferences = try WebsiteParser.parse(String(contentsOfFile: arguments[index + 1], encoding: .utf8))
                print("Parsed \(conferences.count) conferences, \(conferences.filter { $0.deadline == nil }.count) unparsed deadlines.")
                if let output = arguments.firstIndex(of: "--export-seed"), arguments.count > output + 1 {
                    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(ConferenceSnapshot(fetchedAt: Date(), conferences: conferences))
                        .write(to: URL(fileURLWithPath: arguments[output + 1]), options: .atomic)
                }
                return
            } catch { fputs("\(error)\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ConferenceStore!
    private var statusBar: StatusBarController!
    private let navigation = NavigationState()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationMenu()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--smoke-test"), args.count > i + 3 {
            Task { await smokeTest(htmlPath: args[i + 1], outputPath: args[i + 2], testPath: args[i + 3], live: args.contains("--live")) }
            return
        }
        store = ConferenceStore()
        setupStatusBar()
        // Login launches remain quiet; the first run still opens the library.
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin { showWindow() }
        Task { await store.refresh() }
    }

    private func setupStatusBar() {
        statusBar = StatusBarController(store: store)
        statusBar.showWindow = { [weak self] in self?.showWindow() }
        statusBar.showConference = { [weak self] id in
            guard let self else { return }
            self.navigation.section = "favorites"; self.navigation.search = ""
            self.navigation.category = "all"; self.navigation.rank = "all"
            self.navigation.selectedID = id; self.showWindow()
        }
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "CCF Deadline"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 1040, height: 720)
            window.contentView = NSHostingView(rootView: ContentView(store: store, navigation: navigation))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }

    private func setupApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 CCF Deadline", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 CCF Deadline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "编辑"; main.addItem(edit)
        let editMenu = NSMenu(title: "编辑"); edit.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    private func smokeTest(htmlPath: String, outputPath: String, testPath: String, live: Bool) async {
        do {
            func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
                guard condition() else { throw NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
                print("PASS: \(label)")
            }
            let directory = URL(fileURLWithPath: testPath, isDirectory: true)
            store = ConferenceStore(directory: directory, startTimers: false)
            try check(store.conferences.count > 300, "bundled offline snapshot loads")
            let parsed = try WebsiteParser.parse(String(contentsOfFile: htmlPath, encoding: .utf8))
            try store.accept(parsed, at: Date())
            try check(store.conferences.count == parsed.count, "downloaded website parses and persists")
            let demo = ["CVPR", "ACL", "AAMAS"].compactMap { name in parsed.first { $0.name == name } }
            try check(demo.count == 3, "real source data contains preview conferences")
            for c in demo { if !store.isFavorite(c) { store.toggleFavorite(c) } }
            store.pin(demo[0])
            try check(store.barConferences.first?.id == demo[0].id, "pin chooses requested conference")
            let reopened = ConferenceStore(directory: directory, startTimers: false)
            try check(reopened.preferences == store.preferences, "favorites, pin and preferences survive relaunch")
            setupStatusBar(); statusBar.update()
            try check(statusBar.itemCount == 1, "single countdown status item created")
            store.setMode(.all); statusBar.update()
            try check(statusBar.itemCount == 3, "all favorites create separate status items")
            let menu = NSMenu(); statusBar.populate(menu)
            try check(menu.items.filter { $0.submenu != nil }.count == 4, "native menu contains every favorite and settings")
            store.setMode(.rotate)
            let first = store.barConferences.first?.id; store.tick()
            try check(first != store.barConferences.first?.id, "rotation advances the displayed favorite")
            store.pin(demo[0]); store.toggleFavorite(demo[0])
            try check(store.preferences.pinnedID == nil, "removing pinned favorite clears the pin")
            store.toggleFavorite(demo[0]); store.pin(demo[0])
            try store.accept(parsed.filter { $0.id != demo[0].id }, at: Date())
            try check(store.missingIDs.contains(demo[0].id) && store.conferences.contains(demo[0]), "upstream removal preserves a saved conference")
            try store.accept(parsed, at: Date())
            try check(store.missingIDs.isEmpty, "returning source record clears archival warning")
            let before = store.conferences
            let offlineConfiguration = URLSessionConfiguration.ephemeral
            offlineConfiguration.protocolClasses = [OfflineTestProtocol.self]
            let offlineSession = URLSession(configuration: offlineConfiguration)
            await store.refresh(session: offlineSession)
            offlineSession.invalidateAndCancel()
            try check(store.syncError != nil && store.conferences == before, "network failure reports an error and preserves cached data")
            if live {
                await store.refresh()
                try check(store.syncError == nil && !store.isBundled, "live HTTPS synchronization succeeds")
            } else {
                do { _ = try WebsiteParser.parse("<html>offline or changed page</html>") }
                catch { print("PASS: changed source format rejected") }
                try check(store.conferences == before, "failed parsing leaves last good data intact")
            }
            navigation.selectedID = demo[0].id
            showWindow()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            guard let view = window?.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw NSError(domain: "Preview", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot capture app view"])
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw URLError(.cannotDecodeContentData) }
            try png.write(to: URL(fileURLWithPath: outputPath))
            try check(bitmap.pixelsWide >= 1040 && bitmap.pixelsHigh >= 680, "native SwiftUI window rendered to PNG")
            window?.performClose(nil)
            try check(statusBar.itemCount >= 1, "menu bar remains active after closing the window")
            print("SMOKE TEST PASSED")
            NSApp.terminate(nil)
        } catch { fputs("SMOKE TEST FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}

/// Used only by the opt-in smoke-test command, never by the running app.
private final class OfflineTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
