import AppKit
import ObjectiveC

/// ⚠️ PRIVATE API — the only place in the app that uses one.
///
/// Showing a Touch Bar while *another* app is frontmost is not possible with public APIs.
/// macOS implements it internally with undocumented `NSTouchBar` class methods and the
/// private `DFRFoundation` framework (the same mechanism tools like Pock and MTMR use).
///
/// This bridge is used **only** by the opt-in "Always-on" mode (off by default). Every symbol
/// is looked up dynamically at runtime — nothing is linked — so if a future macOS removes or
/// renames anything, `isAvailable` becomes false and the app silently falls back to the
/// public, summon-only behaviour. It does not inject code into other apps; it only asks the
/// Touch Bar server to show this app's own bar.
///
/// Verified on macOS 26.3 / MacBookPro17,1: present (placement 0 → 685 pt next to the
/// Control Strip, placement 1 → full 1004 pt), minimize and dismiss all work while another
/// app is frontmost.
enum SystemTouchBarBridge {
    private typealias PresentFunction = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString) -> Void
    private typealias BarFunction = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
    private typealias ItemFunction = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
    private typealias PresenceFunction = @convention(c) (NSString, Bool) -> Void

    private static let presentSelector = Selector(("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"))
    private static let minimizeSelector = Selector(("minimizeSystemModalTouchBar:"))
    private static let dismissSelector = Selector(("dismissSystemModalTouchBar:"))
    private static let addTraySelector = Selector(("addSystemTrayItem:"))
    private static let removeTraySelector = Selector(("removeSystemTrayItem:"))

    private static let dfrHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private static func classMethod(_ cls: AnyClass, _ selector: Selector) -> IMP? {
        guard let method = class_getClassMethod(cls, selector) else { return nil }
        return method_getImplementation(method)
    }

    private static var presenceFunction: PresenceFunction? {
        guard let dfrHandle, let symbol = dlsym(dfrHandle, "DFRElementSetControlStripPresenceForIdentifier") else { return nil }
        return unsafeBitCast(symbol, to: PresenceFunction.self)
    }

    /// True when every private entry point this mode needs exists on the running macOS.
    static let isAvailable: Bool = {
        let ok = classMethod(NSTouchBar.self, presentSelector) != nil
            && classMethod(NSTouchBar.self, minimizeSelector) != nil
            && classMethod(NSTouchBar.self, dismissSelector) != nil
            && classMethod(NSTouchBarItem.self, addTraySelector) != nil
            && classMethod(NSTouchBarItem.self, removeTraySelector) != nil
            && presenceFunction != nil
        Log.touchBar.info("System-modal Touch Bar API available: \(ok)")
        return ok
    }()

    /// Shows `bar` over the frontmost app. `coverControlStrip` uses the full Touch Bar width.
    static func present(_ bar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier, coverControlStrip: Bool) {
        guard isAvailable, let imp = classMethod(NSTouchBar.self, presentSelector) else { return }
        unsafeBitCast(imp, to: PresentFunction.self)(NSTouchBar.self, presentSelector, bar, coverControlStrip ? 1 : 0, trayIdentifier.rawValue as NSString)
    }

    /// Returns the Touch Bar to the frontmost app's own controls (our tray icon stays).
    static func minimize(_ bar: NSTouchBar) {
        guard isAvailable, let imp = classMethod(NSTouchBar.self, minimizeSelector) else { return }
        unsafeBitCast(imp, to: BarFunction.self)(NSTouchBar.self, minimizeSelector, bar)
    }

    static func dismiss(_ bar: NSTouchBar) {
        guard isAvailable, let imp = classMethod(NSTouchBar.self, dismissSelector) else { return }
        unsafeBitCast(imp, to: BarFunction.self)(NSTouchBar.self, dismissSelector, bar)
    }

    /// Adds/removes our small button in the Control Strip.
    static func setTrayItem(_ item: NSTouchBarItem, installed: Bool) {
        let selector = installed ? addTraySelector : removeTraySelector
        guard isAvailable, let imp = classMethod(NSTouchBarItem.self, selector) else { return }
        unsafeBitCast(imp, to: ItemFunction.self)(NSTouchBarItem.self, selector, item)
        presenceFunction?(item.identifier.rawValue as NSString, installed)
    }
}
