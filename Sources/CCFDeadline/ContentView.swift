import AppKit
import DeadlineCore
import ServiceManagement
import SwiftUI

@MainActor
final class NavigationState: ObservableObject {
    @Published var section = "all"
    @Published var selectedID: String?
    @Published var search = ""
    @Published var rank = "all"
    @Published var category = "all"
    @Published var includeExpired = false
    @Published var settings = false
}

private let accent = Color(red: 0.22, green: 0.37, blue: 0.85)
private let surface = Color(nsColor: .controlBackgroundColor)

struct ContentView: View {
    @ObservedObject var store: ConferenceStore
    @ObservedObject var navigation: NavigationState

    private var filtered: [Conference] {
        let query = navigation.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return Conference.ordered(store.conferences.filter { c in
            (navigation.section != "favorites" || store.isFavorite(c)) &&
            (navigation.section == "favorites" || navigation.includeExpired || (c.deadline ?? .distantFuture) > store.now) &&
            (navigation.rank == "all" || c.rank == navigation.rank) &&
            (navigation.category == "all" || c.category == navigation.category) &&
            (query.isEmpty || "\(c.name) \(c.year) \(c.place) \(c.categoryName)".localizedCaseInsensitiveContains(query))
        }, now: store.now)
    }
    private var selected: Conference? {
        if let id = navigation.selectedID, let c = filtered.first(where: { $0.id == id }) { return c }
        return filtered.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 185)
            Divider()
            VStack(spacing: 0) {
                header
                if let message = store.storageError ?? store.syncError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.system(size: 11)).lineLimit(2)
                        Spacer()
                        Button("重试") { Task { await store.refresh() } }.disabled(store.isRefreshing)
                    }.padding(10).background(Color.orange.opacity(0.09))
                }
                HStack(spacing: 0) {
                    conferenceList.frame(width: 335)
                    Divider()
                    if let c = selected {
                        ConferenceDetail(conference: c, store: store).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { emptyDetail.frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
        }
        .tint(accent)
        .frame(minWidth: 1040, minHeight: 680)
        .sheet(isPresented: $navigation.settings) { SettingsView(store: store) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 25, weight: .medium)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CCF Deadline").font(.system(size: 15, weight: .bold))
                    Text("每一场，心中有数").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.top, 26).padding(.bottom, 34)
            Text("会议").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 10).padding(.bottom, 10)
            sidebarButton("全部会议", icon: "square.grid.2x2", key: "all", count: store.conferences.count)
            sidebarButton("我的收藏", icon: "star", key: "favorites", count: store.favorites.count)
            if store.overdueFavorites > 0 {
                Text("\(store.overdueFavorites) 场收藏已截止").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 12).padding(.top, 10)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "menubar.rectangle"); Text("常驻菜单栏").fontWeight(.medium) }.font(.system(size: 12))
                Text("收藏会议，倒计时随时可见。\n关闭窗口后仍会继续运行。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button("显示设置…") { navigation.settings = true }.buttonStyle(.link).font(.system(size: 11))
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button { navigation.settings = true } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("设置")
                Spacer()
                Link("ccfddl.cn ↗", destination: URL(string: "https://ccfddl.cn/")!).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.top, 22).padding(.bottom, 20)
        }.padding(.horizontal, 15).background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarButton(_ title: String, icon: String, key: String, count: Int) -> some View {
        Button {
            navigation.section = key; navigation.selectedID = nil
        } label: {
            HStack {
                Image(systemName: navigation.section == key && key == "favorites" ? "star.fill" : icon).frame(width: 17)
                Text(title).fontWeight(navigation.section == key ? .semibold : .regular)
                Spacer()
                Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 11).padding(.vertical, 10)
                .foregroundStyle(navigation.section == key ? accent : Color.primary)
                .background(navigation.section == key ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(navigation.section == "favorites" ? "我的收藏" : "会议截止日").font(.system(size: 25, weight: .bold))
                    Text(navigation.section == "favorites" ? "关注的会议与投稿计划，一眼掌握。" : "发现下一场会议，让每个截止日都有准备。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button { Task { await store.refresh() } } label: {
                        HStack(spacing: 5) {
                            if store.isRefreshing { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text(store.isRefreshing ? "正在同步" : "同步数据")
                        }
                    }.disabled(store.isRefreshing)
                    if let date = store.lastUpdated {
                        Text("\(store.isBundled ? "内置快照" : "已同步") · \(date.formatted(.dateTime.month().day().hour().minute()))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索会议、年份或地点", text: $navigation.search).textFieldStyle(.plain)
                    if !navigation.search.isEmpty { Button { navigation.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }.padding(9).background(Color(nsColor: .quaternaryLabelColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                Picker("评级", selection: $navigation.rank) {
                    Text("全部评级").tag("all")
                    ForEach(["A", "B", "C", "N"], id: \.self) { Text($0 == "N" ? "未评级" : "CCF \($0)").tag($0) }
                }.labelsHidden().frame(width: 108)
                Picker("领域", selection: $navigation.category) {
                    Text("全部领域").tag("all")
                    ForEach(Conference.categories.keys.sorted(), id: \.self) { Text(Conference.categories[$0] ?? $0).tag($0) }
                }.labelsHidden().frame(width: 150)
            }.font(.system(size: 12))
        }.padding(.horizontal, 24).padding(.top, 23).padding(.bottom, 20).background(surface)
    }

    private var conferenceList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filtered.count) 场会议 · 按截止时间").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if navigation.section != "favorites" {
                    Toggle("含已截止", isOn: $navigation.includeExpired).toggleStyle(.checkbox).font(.system(size: 10))
                }
            }.padding(.horizontal, 16).padding(.vertical, 14)
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: navigation.section == "favorites" ? "star" : "magnifyingglass").font(.system(size: 25)).foregroundStyle(.tertiary)
                    Text(navigation.section == "favorites" && store.favorites.isEmpty ? "还没有收藏" : "没有匹配的会议").font(.system(size: 13, weight: .medium))
                    Text(navigation.section == "favorites" && store.favorites.isEmpty ? "在全部会议中点击 ☆ 开始关注。" : "试试其他关键词或调整筛选。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("查看全部会议") {
                        navigation.section = "all"; navigation.search = ""; navigation.category = "all"; navigation.rank = "all"
                    }.font(.system(size: 11))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(filtered) { c in
                                conferenceRow(c).id(c.id)
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 15)
                    }.onChange(of: navigation.selectedID) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }.background(surface)
    }

    private func conferenceRow(_ c: Conference) -> some View {
        let isSelected = c.id == selected?.id
        let isExpired = c.deadline.map { $0 <= store.now } ?? false
        return HStack(alignment: .top, spacing: 8) {
            Button { navigation.selectedID = c.id } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(c.name).font(.system(size: 16, weight: .semibold))
                        Text(c.year).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        Badge(text: c.rankLabel, color: c.rank == "A" ? accent : .secondary)
                        Text(c.categoryName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 10))
                        Text(c.countdown(at: store.now)).font(.system(size: 11, weight: .medium, design: .monospaced))
                    }.foregroundStyle(isExpired ? Color.secondary : (c.deadline.map { $0.timeIntervalSince(store.now) < 7 * 86400 } ?? false) ? Color.orange : accent)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { store.toggleFavorite(c) } label: {
                Image(systemName: store.isFavorite(c) ? "star.fill" : "star")
                    .foregroundStyle(store.isFavorite(c) ? Color.orange : Color.secondary).font(.system(size: 14))
            }.buttonStyle(.plain).help(store.isFavorite(c) ? "取消收藏" : "收藏会议").accessibilityLabel("\(store.isFavorite(c) ? "取消收藏" : "收藏") \(c.title)")
        }
        .padding(13)
        .background(isSelected ? accent.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? accent.opacity(0.28) : .clear, lineWidth: 1))
    }

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 45, weight: .light)).foregroundStyle(accent.opacity(0.55))
            Text("下一场值得期待").font(.system(size: 21, weight: .semibold))
            Text("选择会议查看截止时间，\n收藏后即可在菜单栏查看倒计时。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
        }.padding(35)
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View { Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4)) }
}

private struct ConferenceDetail: View {
    let conference: Conference
    @ObservedObject var store: ConferenceStore
    private var remaining: TimeInterval { max(0, conference.deadline?.timeIntervalSince(store.now) ?? 0) }
    private var favorite: Bool { store.isFavorite(conference) }
    private var pinned: Bool { store.preferences.pinnedID == conference.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    Badge(text: conference.rankLabel, color: accent)
                    Text(conference.categoryName).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if pinned { Image(systemName: "pin.fill").foregroundStyle(accent).help("已固定到菜单栏") }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(conference.name).font(.system(size: 35, weight: .bold)).textSelection(.enabled)
                    Text("\(conference.year) 年会议").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("距离投稿截止").font(.system(size: 11, weight: .medium)); Spacer(); Image(systemName: "hourglass").foregroundStyle(accent) }
                    if remaining > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Int(remaining) / 86400)").font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("days").font(.system(size: 12)).foregroundStyle(.secondary).padding(.trailing, 13)
                            Text("\(Int(remaining) / 3600 % 24)").font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("hours").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.foregroundStyle(accent)
                        if remaining < 3600 { Text("不足 1 小时 · 约 \(max(1, Int(remaining / 60))) 分钟").font(.system(size: 11)).foregroundStyle(.orange) }
                    } else { Text(conference.countdown(at: store.now)).font(.system(size: 29, weight: .semibold)).foregroundStyle(.secondary) }
                    Divider()
                    if let deadline = conference.deadline {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(deadline.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())).font(.system(size: 12, weight: .medium, design: .monospaced))
                            Text("本地时间 · \(TimeZone.current.identifier)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Text("原始截止：\(conference.deadlineText) \(conference.timezone)").font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                HStack(spacing: 10) {
                    Button { store.toggleFavorite(conference) } label: {
                        Label(favorite ? "已收藏" : "收藏会议", systemImage: favorite ? "star.fill" : "star")
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent)
                    Button { store.pin(conference) } label: {
                        Label(pinned ? "取消固定" : "固定到菜单栏", systemImage: pinned ? "pin.slash" : "pin")
                            .padding(.vertical, 5)
                    }.buttonStyle(.bordered)
                }.font(.system(size: 12))
                VStack(alignment: .leading, spacing: 17) {
                    detailLine("calendar", title: "会议日期", value: conference.dates)
                    detailLine("mappin.and.ellipse", title: "举办地点", value: conference.place)
                    if !conference.acceptance.isEmpty { detailLine("chart.bar", title: "历史录用率", value: conference.acceptance) }
                    if let url = conference.websiteURL {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 18)
                            Link("访问会议官网 ↗", destination: url).font(.system(size: 12))
                        }
                    }
                }
                if favorite {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("菜单栏文字预览").font(.system(size: 10)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "hourglass").font(.system(size: 10))
                            Text(conference.statusTitle(at: store.now, compact: store.preferences.compact)).font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(2)
                        }.padding(.horizontal, 12).padding(.vertical, 9).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                if store.missingIDs.contains(conference.id) {
                    Label("此会议已不在网站最新列表中，正在保留你的收藏及上次截止信息。", systemImage: "archivebox")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                Text("感谢 ccfddl.cn 提供会议数据 · 截止信息以会议官网为准")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(27).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
    private func detailLine(_ icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var store: ConferenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack { Text("显示与偏好").font(.system(size: 22, weight: .bold)); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
            VStack(alignment: .leading, spacing: 12) {
                Text("菜单栏显示").font(.system(size: 12, weight: .semibold))
                Picker("模式", selection: Binding(get: { store.preferences.mode }, set: { store.setMode($0) })) {
                    ForEach(BarMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Text("最近截止：优先显示还未截止的收藏。轮播：每 15 秒切换。全部显示：每场收藏各占一个菜单栏位置，空间不足时 macOS 可能隐藏部分项目。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                if store.preferences.pinnedID != nil {
                    HStack { Text("当前已固定一场会议，自动切换已暂停。").font(.system(size: 11)); Button("取消固定") { store.clearPin() } }
                }
                Toggle("精简倒计时（12d 8h）", isOn: Binding(get: { store.preferences.compact }, set: { store.setCompact($0) }))
            }
            Divider()
            Toggle("登录 Mac 时启动", isOn: Binding(get: { loginEnabled }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                    loginError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许启动。" : nil
                } catch { loginError = "设置失败：\(error.localizedDescription)"; loginEnabled = SMAppService.mainApp.status == .enabled }
            }))
            if let loginError { Text(loginError).font(.system(size: 11)).foregroundStyle(.orange) }
            Text("打开 App 时同步，此后每小时自动同步。断网时保留上次数据；收藏和显示设置仅保存在这台 Mac。")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            Divider()
            HStack { Text("CCF Deadline 1.0.0 · 非官方客户端").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Link("感谢 CCFDDL ↗", destination: URL(string: "https://ccfddl.cn/")!) }
        }.padding(28).frame(width: 490).font(.system(size: 12)).tint(accent)
    }
}
