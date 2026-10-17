import Carbon

/// A system-wide hotkey registered through Carbon (no Accessibility permission needed).
final class HotKey {
  private static var handlers: [UInt32: () -> Void] = [:]
  private static var nextID: UInt32 = 1
  private static var installed = false

  private var ref: EventHotKeyRef?
  private let id: UInt32

  /// Returns nil if the combination is already taken by another app.
  init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
    HotKey.installHandlerIfNeeded()
    id = HotKey.nextID
    HotKey.nextID += 1
    let hotKeyID = EventHotKeyID(signature: OSType(0x5452_4E4D), id: id)  // "TRNM"
    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    guard status == noErr else { return nil }
    HotKey.handlers[id] = handler
  }

  deinit {
    if let ref { UnregisterEventHotKey(ref) }
    HotKey.handlers[id] = nil
  }

  private static func installHandlerIfNeeded() {
    guard !installed else { return }
    installed = true
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        HotKey.handlers[hotKeyID.id]?()
        return noErr
      }, 1, &spec, nil, nil)
  }
}
