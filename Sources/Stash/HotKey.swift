import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Uses the Carbon hot key API, which needs no permission from the user.
@MainActor
final class HotKey {
    var onPressed: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated { hotKey.onPressed?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Replaces the current shortcut. Returns false if the system refuses the combination.
    @discardableResult
    func register(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: 0x53_54_53_48 /* "STSH" */, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
