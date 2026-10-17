import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// Borderless floating panel that can take keyboard focus without activating the app (like Spotlight).
final class FloatingPanel: NSPanel {
  var onResignKey: (() -> Void)?
  var onCancel: (() -> Void)?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 60),
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      standardWindowButton(button)?.isHidden = true
    }
    isMovableByWindowBackground = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    backgroundColor = .clear
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    event.sendEditAction() || super.performKeyEquivalent(with: event)
  }
}

/// Regular window that still gets ⌘C/⌘V etc. without an Edit menu.
final class EditableWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    event.sendEditAction() || super.performKeyEquivalent(with: event)
  }
}

extension NSEvent {
  /// Accessory apps have no Edit menu, so route the standard editing shortcuts to the responder chain.
  func sendEditAction() -> Bool {
    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
    let action: Selector? =
      switch (flags, charactersIgnoringModifiers?.lowercased()) {
      case (.command, "x"): #selector(NSText.cut(_:))
      case (.command, "c"): #selector(NSText.copy(_:))
      case (.command, "v"): #selector(NSText.paste(_:))
      case (.command, "a"): #selector(NSText.selectAll(_:))
      case (.command, "z"): Selector(("undo:"))
      case ([.command, .shift], "z"): Selector(("redo:"))
      default: nil
      }
    guard let action else { return false }
    return NSApp.sendAction(action, to: nil, from: self)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = Translator()
  private var panel: FloatingPanel!
  private var host: NSHostingController<ContentView>!
  private var statusItem: NSStatusItem!
  private var settingsWindow: NSWindow?
  private var hotKey: HotKey?
  private var showToken = 0
  private var panelTop: CGFloat = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    panel = FloatingPanel()
    host = NSHostingController(rootView: makeView())
    host.sizingOptions = [.preferredContentSize]
    panel.contentViewController = host
    panel.onCancel = { [weak self] in self?.hide() }
    panel.onResignKey = { [weak self] in
      // Keep the panel while the language download sheet is up.
      guard let self, self.model.downloadConfig == nil, self.panel.attachedSheet == nil else { return }
      self.hide()
    }
    NotificationCenter.default.addObserver(
      forName: NSWindow.didResizeNotification, object: panel, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.keepTop() }
    }

    // ⌃; toggles the panel.
    hotKey = HotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: UInt32(controlKey)) { [weak self] in
      MainActor.assumeIsolated { self?.toggle() }
    }
    setupStatusItem()
    if hotKey == nil {
      let alert = NSAlert()
      alert.messageText = "快捷键 ⌃; 已被其它应用占用"
      alert.informativeText = "可以通过菜单栏图标打开翻译窗口。"
      alert.runModal()
    }
  }

  private func makeView() -> ContentView {
    ContentView(
      model: model, showToken: showToken,
      onSubmit: { [weak self] in self?.copyAndHide() },
      onCancel: { [weak self] in self?.hide() })
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "TranMac")
    let menu = NSMenu()
    menu.delegate = self
    let show = NSMenuItem(title: "打开翻译窗口", action: #selector(showFromMenu), keyEquivalent: ";")
    show.keyEquivalentModifierMask = [.control]
    menu.addItem(show)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
    menu.addItem(NSMenuItem(title: "开机启动", action: #selector(toggleLoginItem), keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "退出 TranMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    statusItem.menu = menu
  }

  @objc private func showFromMenu() { show() }

  @objc private func openSettings() {
    hide()
    if settingsWindow == nil {
      let window = EditableWindow(
        contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "TranMac 设置"
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: SettingsView(settings: .shared))
      window.center()
      settingsWindow = window
    }
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func toggleLoginItem() {
    do {
      if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  private func toggle() {
    if panel.isVisible { hide() } else { show() }
  }

  private func show() {
    model.reset()
    showToken += 1
    host.rootView = makeView()
    host.view.layoutSubtreeIfNeeded()
    panel.setContentSize(host.view.fittingSize)

    // Center horizontally, upper third of the screen that has the mouse.
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    if let frame = screen?.visibleFrame {
      let x = frame.midX - panel.frame.width / 2
      panelTop = frame.maxY - frame.height * 0.22
      panel.setFrameOrigin(NSPoint(x: x, y: panelTop - panel.frame.height))
    }
    panel.makeKeyAndOrderFront(nil)
  }

  private func hide() {
    panel.orderOut(nil)
  }

  /// Grow downwards: keep the top edge fixed when the content height changes.
  private func keepTop() {
    guard panel.isVisible, panelTop > 0 else { return }
    let y = panelTop - panel.frame.height
    if abs(panel.frame.minY - y) > 0.5 {
      panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: y))
    }
  }

  private func copyAndHide() {
    guard !model.output.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(model.output, forType: .string)
    hide()
  }
}

extension AppDelegate: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.item(withTitle: "开机启动")?.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }
}

@main
struct Main {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }
}
