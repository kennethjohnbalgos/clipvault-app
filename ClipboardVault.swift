import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import Carbon
@preconcurrency import UserNotifications
import UniformTypeIdentifiers

struct ClipboardItem: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    var copiedAt: Date
    var pinnedTitle: String?

    init(text: String, copiedAt: Date = .now) {
        self.id = UUID()
        self.text = text
        self.copiedAt = copiedAt
        self.pinnedTitle = nil
    }

    private enum CodingKeys: String, CodingKey { case id, text, copiedAt, pinnedTitle }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        copiedAt = try values.decode(Date.self, forKey: .copiedAt)
        pinnedTitle = try values.decodeIfPresent(String.self, forKey: .pinnedTitle)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    @Published private(set) var items: [ClipboardItem] = []
    private let archiveURL: URL
    private var changeCount = NSPasteboard.general.changeCount
    private var internalClipboardText: String?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipboard Vault", isDirectory: true)
        archiveURL = support.appendingPathComponent("history.json")
        load()
    }

    func captureIfChanged() {
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        guard let text = board.string(forType: .string), !text.isEmpty else { return }
        // Reusing an item from Clipvault already moves the original record to the top.
        if internalClipboardText == text { internalClipboardText = nil; return }
        items.insert(ClipboardItem(text: text), at: 0)
        save()
    }

    func clearAll() { items.removeAll(); save() }

    func pin(_ item: ClipboardItem, title: String) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinnedTitle = cleanedTitle
        save()
    }

    func unpin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinnedTitle = nil
        save()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func prepareForPaste(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var reused = items.remove(at: index)
        reused.copiedAt = .now
        items.insert(reused, at: 0)
        internalClipboardText = reused.text
        save()
    }

    func exportData() throws -> Data {
        try JSONEncoder.pretty.encode(items)
    }

    func importData(from data: Data) throws {
        let imported = try JSONDecoder().decode([ClipboardItem].self, from: data)
        let existingIDs = Set(items.map(\.id))
        let additions = imported.filter { !existingIDs.contains($0.id) && !$0.text.isEmpty }
        items.append(contentsOf: additions)
        items.sort { $0.copiedAt > $1.copiedAt }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: archiveURL),
              let loaded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = loaded.sorted { $0.copiedAt > $1.copiedAt }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(items)
            try data.write(to: archiveURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        } catch { NSLog("Clipvault could not save history: %@", error.localizedDescription) }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

@main
struct ClipboardVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = PickerController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ClipboardStore.shared
        controller.install(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Open Clipvault")
            button.target = self
            button.action = #selector(openHistory)
        }
        controller.show(store: store)
    }

    @objc private func openHistory() { controller.toggle(store: ClipboardStore.shared) }
}

@MainActor
final class PickerController: NSObject, ObservableObject {
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var pasteboardTimer: Timer?
    private weak var store: ClipboardStore?
    private var standardHotKey: EventHotKeyRef?
    private var optionHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    @Published var keyboardSelectedID: UUID?
    @Published var displayResetToken = UUID()
    private var keyboardSelectionIndex = -1
    private var keyboardShortcutActive = false
    private var keyboardShortcutModifier: NSEvent.ModifierFlags?
    private var applicationToRestore: NSRunningApplication?

    func install(store: ClipboardStore) {
        self.store = store
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak store] _ in
            Task { @MainActor in store?.captureIfChanged() }
        }
        installStandardHotKey()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleShortcutEvent(event, store: store) ? nil : event
        }
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    func show(store: ClipboardStore) {
        self.store = store
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            applicationToRestore = frontmost
        }
        keyboardSelectedID = nil
        displayResetToken = UUID()
        if let panel { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = HistoryPicker(store: store, controller: self, onPaste: { [weak self] item in self?.paste(item) }, onClose: { [weak self] in self?.close() })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Clipvault History"
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle(store: ClipboardStore) {
        if panel?.isVisible == true { close() }
        else { show(store: store) }
    }

    private func close() { panel?.orderOut(nil); panel = nil }

    private func paste(_ item: ClipboardItem) {
        copy(item)
        close()
        notifyCopyAndPasteAttempt()
        // Pasting into the previously focused app needs macOS Accessibility permission.
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }
        applicationToRestore?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }

    private func copy(_ item: ClipboardItem) {
        store?.prepareForPaste(item)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }

    private func notifyCopyAndPasteAttempt() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Copied to Clipboard"
            content.body = "Clipvault copied your selection and attempted to paste it."
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    func select(_ item: ClipboardItem, in store: ClipboardStore) {
        keyboardSelectedID = item.id
        keyboardSelectionIndex = store.items.firstIndex(where: { $0.id == item.id }) ?? -1
    }

    private func handleShortcutEvent(_ event: NSEvent, store: ClipboardStore) -> Bool {
        if event.type == .keyDown, event.keyCode == 53, panel?.isVisible == true, NSApplication.shared.isActive {
            keyboardShortcutActive = false
            keyboardShortcutModifier = nil
            keyboardSelectionIndex = -1
            keyboardSelectedID = nil
            close()
            return true
        }
        if event.type == .keyDown, (event.keyCode == 36 || event.keyCode == 76), panel?.isVisible == true, NSApplication.shared.isActive,
           let selectedID = keyboardSelectedID, let item = store.items.first(where: { $0.id == selectedID }) {
            paste(item)
            return true
        }
        if event.type == .keyDown, (event.keyCode == 125 || event.keyCode == 126), panel?.isVisible == true, NSApplication.shared.isActive, !store.items.isEmpty {
            let movingDown = event.keyCode == 125
            if let selectedID = keyboardSelectedID, let index = store.items.firstIndex(where: { $0.id == selectedID }) {
                keyboardSelectionIndex = movingDown ? min(index + 1, store.items.count - 1) : max(index - 1, 0)
            } else {
                keyboardSelectionIndex = movingDown ? 0 : store.items.count - 1
            }
            keyboardSelectedID = store.items[keyboardSelectionIndex].id
            return true
        }
        if event.type == .keyDown, (event.keyCode == 51 || event.keyCode == 117), let selectedID = keyboardSelectedID,
           let index = store.items.firstIndex(where: { $0.id == selectedID }),
           let item = store.items.first(where: { $0.id == selectedID }), item.pinnedTitle == nil {
            store.remove(item)
            if store.items.isEmpty {
                keyboardSelectedID = nil
                keyboardSelectionIndex = -1
            } else {
                keyboardSelectionIndex = min(index, store.items.count - 1)
                keyboardSelectedID = store.items[keyboardSelectionIndex].id
            }
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shortcutModifiersAreDown = keyboardShortcutModifier.map { modifiers.contains(.command) && modifiers.contains($0) } ?? false

        if keyboardShortcutActive, event.type == .flagsChanged, !shortcutModifiersAreDown {
            finishKeyboardShortcut(store: store)
            return true
        }
        guard event.type == .keyDown, event.keyCode == 9, shortcutModifiersAreDown, keyboardShortcutActive else { return false }

        if !event.isARepeat {
            advanceKeyboardSelection(in: store)
        }
        return true
    }

    private func installStandardHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr else { return noErr }
            let controller = Unmanaged<PickerController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                if hotKeyID.id == 1 { controller.handleSelectionHotKey(store: ClipboardStore.shared, modifier: .shift) }
                if hotKeyID.id == 2 { controller.handleSelectionHotKey(store: ClipboardStore.shared, modifier: .option) }
            }
            return noErr
        }, 1, &eventType, userData, &hotKeyHandler)
        guard handlerStatus == noErr else { return }
        let options: UInt32 = 0
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x434C5056, id: 1), GetApplicationEventTarget(), options, &standardHotKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x434C5056, id: 2), GetApplicationEventTarget(), options, &optionHotKey)
    }

    private func handleSelectionHotKey(store: ClipboardStore, modifier: NSEvent.ModifierFlags) {
        if keyboardShortcutActive {
            advanceKeyboardSelection(in: store)
            return
        }
        keyboardShortcutActive = true
        keyboardShortcutModifier = modifier
        keyboardSelectionIndex = -1
        keyboardSelectedID = nil
        show(store: store)
    }

    private func advanceKeyboardSelection(in store: ClipboardStore) {
        guard !store.items.isEmpty else { return }
        keyboardSelectionIndex = (keyboardSelectionIndex + 1) % store.items.count
        keyboardSelectedID = store.items[keyboardSelectionIndex].id
    }

    private func finishKeyboardShortcut(store: ClipboardStore) {
        keyboardShortcutActive = false
        keyboardShortcutModifier = nil
        keyboardSelectionIndex = -1
        guard let id = keyboardSelectedID, let item = store.items.first(where: { $0.id == id }) else { return }
        keyboardSelectedID = nil
        paste(item)
    }
}

struct HistoryPicker: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var controller: PickerController
    let onPaste: (ClipboardItem) -> Void
    let onClose: () -> Void
    @State private var query = ""
    @State private var selectedTab: HistoryTab = .recent
    @State private var itemAwaitingTitle: ClipboardItem?
    @State private var pinTitle = ""
    @State private var isRenamingPin = false
    @AppStorage("openAtLogin") private var openAtLogin = false
    @State private var showQuitConfirmation = false
    @State private var loginError: String?
    @State private var dataTransferError: String?

    private enum HistoryTab: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case pinned = "Pinned"
        var id: Self { self }
    }

    private var visible: [ClipboardItem] {
        let base = selectedTab == .recent ? store.items : store.items.filter { $0.pinnedTitle != nil }
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.text.localizedCaseInsensitiveContains(query) ||
            ($0.pinnedTitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("History", selection: $selectedTab) {
                ForEach(HistoryTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 14)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(selectedTab.rawValue.lowercased())", text: $query).textFieldStyle(.plain)
                Text("\(visible.count)").font(.caption).foregroundStyle(.secondary)
            }.padding(14)
            Divider()
            if visible.isEmpty {
                ContentUnavailableView(selectedTab == .pinned ? "No pinned items" : "No clipboard items", systemImage: selectedTab == .pinned ? "pin" : "clipboard", description: Text(query.isEmpty ? (selectedTab == .pinned ? "Pin an item from Recent to keep it here." : "Copy text anywhere, then press ⌘⇧V.") : "Try a different search."))
            } else {
                ScrollViewReader { proxy in
                    List(visible, selection: $controller.keyboardSelectedID) { item in
                        HStack(spacing: 10) {
                            itemSummary(item)
                                .contentShape(Rectangle())
                                .onTapGesture { controller.select(item, in: store) }
                                .onTapGesture(count: 2) {
                                    controller.select(item, in: store)
                                    onPaste(item)
                                }
                            if item.pinnedTitle == nil {
                                Button { isRenamingPin = false; itemAwaitingTitle = item; pinTitle = "" } label: {
                                    Image(systemName: "pin").frame(width: 26, height: 26)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.orange)
                                .help("Pin with a title")
                            } else {
                                Button { store.unpin(item) } label: {
                                    Image(systemName: "pin.fill").frame(width: 26, height: 26)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.orange)
                                .help("Remove pin")
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(item.id)
                        .contextMenu {
                            if item.pinnedTitle == nil {
                                Button("Pin") { isRenamingPin = false; itemAwaitingTitle = item; pinTitle = "" }
                            } else {
                                Button("Rename") { isRenamingPin = true; itemAwaitingTitle = item; pinTitle = item.pinnedTitle ?? "" }
                                Button("Unpin") { store.unpin(item) }
                            }
                            if item.pinnedTitle == nil {
                                Divider()
                                Button("Delete", role: .destructive) { store.remove(item) }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .onAppear { scrollToNewest(using: proxy) }
                    .onChange(of: controller.displayResetToken) { _, _ in
                        selectedTab = .recent
                        query = ""
                        DispatchQueue.main.async { scrollToNewest(using: proxy) }
                    }
                    .onChange(of: controller.keyboardSelectedID) { _, selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Menu {
                    Button("Import…") { importHistory() }
                    Button("Export…") { exportHistory() }
                    Divider()
                    Toggle("Start at login", isOn: $openAtLogin)
                        .onChange(of: openAtLogin) { _, enabled in setOpenAtLogin(enabled) }
                    Divider()
                    Button("Quit", role: .destructive) { showQuitConfirmation = true }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .help("Clipvault settings")
                Spacer()
                Text("Enter or double-click to paste").font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
        .frame(minWidth: 620, minHeight: 480)
        .sheet(item: $itemAwaitingTitle) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text(isRenamingPin ? "Rename pinned item" : "Pin clipboard item").font(.headline)
                Text(isRenamingPin ? "Choose a new title for this pinned item." : "Give this item a title so it is easy to find later.").foregroundStyle(.secondary)
                TextField("Title", text: $pinTitle).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { itemAwaitingTitle = nil }
                    Button(isRenamingPin ? "Rename" : "Pin") { store.pin(item, title: pinTitle); itemAwaitingTitle = nil }
                        .keyboardShortcut(.defaultAction)
                        .disabled(pinTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
        .alert("Quit Clipvault?", isPresented: $showQuitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
        } message: {
            Text("Clipvault will stop capturing clipboard history until you open it again.")
        }
        .alert("Could not update Open at login", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            Button("OK") { loginError = nil }
        } message: { Text(loginError ?? "") }
        .alert("Could not transfer clipboard history", isPresented: Binding(get: { dataTransferError != nil }, set: { if !$0 { dataTransferError = nil } })) {
            Button("OK") { dataTransferError = nil }
        } message: { Text(dataTransferError ?? "") }
    }

    @ViewBuilder
    private func itemSummary(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title = item.pinnedTitle { Text(title).font(.headline).lineLimit(1) }
            Text(item.text).lineLimit(2).multilineTextAlignment(.leading)
            Text(item.copiedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            openAtLogin = !enabled
            loginError = error.localizedDescription
        }
    }

    private func importHistory() {
        let panel = NSOpenPanel()
        panel.title = "Import Clipvault History"
        panel.message = "Choose a Clipvault JSON export. Imported records are merged with your current history."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importData(from: Data(contentsOf: url))
        } catch {
            dataTransferError = "The selected file is not a valid Clipvault export.\n\n\(error.localizedDescription)"
        }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.title = "Export Clipvault History"
        panel.nameFieldStringValue = "Clipvault-history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
        } catch {
            dataTransferError = "Clipvault could not export your history.\n\n\(error.localizedDescription)"
        }
    }

    private func scrollToNewest(using proxy: ScrollViewProxy) {
        guard let newest = store.items.first else { return }
        proxy.scrollTo(newest.id, anchor: .top)
    }
}
