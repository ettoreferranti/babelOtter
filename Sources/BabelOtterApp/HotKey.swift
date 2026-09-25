import AppKit
import Carbon.HIToolbox

/// A global hotkey through Carbon's `RegisterEventHotKey`.
///
/// FR-UI-01: this needs no Input Monitoring permission, where an `NSEvent`
/// global monitor or a `CGEventTap` would.
@MainActor
final class HotKey {

    /// `fileprivate` rather than `private`: `hotKeyCallback` below needs to
    /// reach this from outside the class (see its doc comment for why it
    /// cannot be a member), and `fileprivate` is the narrowest access level
    /// that still allows that.
    fileprivate static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false

    private var reference: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping @MainActor () -> Void) {
        Self.installHandlerOnce()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4254_4F54), id: id)  // "BTOT"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return nil }
        self.reference = reference
        Self.actions[id] = action
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, nil, nil)
    }
}

/// The Carbon event handler itself, as a plain top-level function rather than
/// a closure literal on `HotKey`.
///
/// `InstallEventHandler` wants an `EventHandlerUPP` -- a bare C function
/// pointer -- and a C function pointer cannot carry `@MainActor` isolation.
/// Written as a member of `HotKey` (a `@MainActor` type), the closure literal
/// the brief sketches would be inferred `@MainActor` by the surrounding
/// context and Swift 6 rejects the conversion to `@convention(c)`. Moving it
/// out to file scope makes it `nonisolated` by default, which is what a C
/// callback has to be; it then hops back to the main actor itself before
/// touching any main-actor state, via `DispatchQueue.main.async` +
/// `MainActor.assumeIsolated`, exactly as the task's ruling describes.
private func hotKeyCallback(
    _ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event, EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKey.actions[id]?() }
    }
    return noErr
}
