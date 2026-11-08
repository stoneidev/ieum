import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts (they work while another app is in front). They use the Carbon hot-key API, which
/// needs no accessibility or input-monitoring permission.
@MainActor
final class HotKeyCenter {
    struct Shortcut {
        let keyCode: Int
        let action: @MainActor () -> Void
    }

    private static let signature: OSType = 0x53545431 // 'STT1'
    private var shortcuts: [UInt32: Shortcut] = [:]
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    /// Control + Option + key.
    private static let modifiers = UInt32(controlKey | optionKey)

    init(shortcuts list: [Shortcut]) {
        for (index, shortcut) in list.enumerated() { shortcuts[UInt32(index + 1)] = shortcut }
    }

    var isEnabled: Bool { !references.isEmpty }

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard references.isEmpty else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = identifier.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.shortcuts[id]?.action() }
            }
            return noErr
        }, 1, &eventType, userData, &handler)

        for (id, shortcut) in shortcuts {
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references.append(reference) }
        }
    }

    private func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
