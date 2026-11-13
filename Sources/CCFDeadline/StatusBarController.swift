import AppKit
import Combine
import DeadlineCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let store: ConferenceStore
    private var items: [NSStatusItem] = []
    private var subscriptions: Set<AnyCancellable> = []
    var showWindow: (() -> Void)?
    var showConference: ((String) -> Void)?
    var itemCount: Int { items.count }

    init(store: ConferenceStore) {
        self.store = store
        super.init()
        store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &subscriptions)
        update()
    }

    func update() {
        let shown = store.barConferences
        let count = max(1, shown.count)
        while items.count > count { NSStatusBar.system.removeStatusItem(items.removeLast()) }
        while items.count < count {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu(); menu.delegate = self; item.menu = menu
            items.append(item)
        }
        for (index, item) in items.enumerated() {
            guard let button = item.button else { continue }
            let conference = shown.indices.contains(index) ? shown[index] : nil
            button.title = conference?.statusTitle(at: store.now, compact: store.preferences.compact) ?? "CCF DDL ☆"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.image = NSImage(systemSymbolName: conference == nil ? "calendar" : "hourglass", accessibilityDescription: "会议截止倒计时")
            button.imagePosition = .imageLeading
            button.toolTip = conference.map { "\($0.title)\n\($0.deadlineText) \($0.timezone)\n点击查看全部收藏" }
                ?? "点击打开会议库，收藏你关注的会议"
            button.setAccessibilityLabel(button.title)
        }
    }

    func menuWillOpen(_ menu: NSMenu) { populate(menu) }

    func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("打开会议库…", to: menu, action: #selector(openLibrary), key: "o")
        menu.addItem(.separator())
        heading("我的收藏 · \(store.favorites.count)", to: menu)
        if store.favorites.isEmpty { heading("在会议库点 ☆，这里就会显示倒计时", to: menu) }
        for conference in store.favorites {
            let item = NSMenuItem(title: conference.statusTitle(at: Date(), compact: false), action: nil, keyEquivalent: "")
            if store.preferences.pinnedID == conference.id { item.state = .on }
            let submenu = NSMenu()
            add("查看会议详情", to: submenu, action: #selector(openDetail), represented: conference.id)
            add(store.preferences.pinnedID == conference.id ? "取消固定" : "固定到菜单栏", to: submenu, action: #selector(pinConference), represented: conference.id)
            if conference.websiteURL != nil { add("打开会议官网 ↗", to: submenu, action: #selector(openWebsite), represented: conference.id) }
            submenu.addItem(.separator())
            add("取消收藏", to: submenu, action: #selector(removeFavorite), represented: conference.id)
            item.submenu = submenu; menu.addItem(item)
        }
        menu.addItem(.separator())
        let modes = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in BarMode.allCases {
            let item = add(mode.label, to: modeMenu, action: #selector(setMode), represented: mode.rawValue)
            item.state = store.preferences.mode == mode && store.preferences.pinnedID == nil ? .on : .off
        }
        if store.preferences.pinnedID != nil { add("取消固定，恢复自动显示", to: modeMenu, action: #selector(clearPin)) }
        modeMenu.addItem(.separator())
        let compact = add("精简格式（12d 8h）", to: modeMenu, action: #selector(toggleCompact))
        compact.state = store.preferences.compact ? .on : .off
        modes.submenu = modeMenu; menu.addItem(modes)
        if let error = store.syncError { heading(String(error.prefix(65)), to: menu) }
        if let updated = store.lastUpdated {
            let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm"
            heading("\(store.isBundled ? "内置快照" : "已同步") · \(formatter.string(from: updated))", to: menu)
        }
        let refresh = add(store.isRefreshing ? "正在同步…" : "立即同步", to: menu, action: #selector(refreshData), key: "r")
        refresh.isEnabled = !store.isRefreshing
        menu.addItem(.separator())
        add("退出 CCF Deadline", to: menu, action: #selector(quit), key: "q")
    }

    private func heading(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item)
    }
    @discardableResult
    private func add(_ title: String, to menu: NSMenu, action: Selector, represented: String? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.representedObject = represented; menu.addItem(item); return item
    }
    private func conference(_ sender: NSMenuItem) -> Conference? {
        guard let id = sender.representedObject as? String else { return nil }
        return store.conferences.first { $0.id == id }
    }
    @objc private func openLibrary() { showWindow?() }
    @objc private func openDetail(_ sender: NSMenuItem) { if let c = conference(sender) { showConference?(c.id) } }
    @objc private func pinConference(_ sender: NSMenuItem) { if let c = conference(sender) { store.pin(c) } }
    @objc private func removeFavorite(_ sender: NSMenuItem) { if let c = conference(sender) { store.toggleFavorite(c) } }
    @objc private func openWebsite(_ sender: NSMenuItem) { if let url = conference(sender)?.websiteURL { NSWorkspace.shared.open(url) } }
    @objc private func setMode(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let mode = BarMode(rawValue: raw) { store.setMode(mode) } }
    @objc private func clearPin() { store.clearPin() }
    @objc private func toggleCompact() { store.setCompact(!store.preferences.compact) }
    @objc private func refreshData() { Task { await store.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }
}
