import Combine
import Foundation

/// Display brightness.
///
/// **Platform limitation:** macOS has no public API to read or set the built-in display's
/// brightness on Apple Silicon (`IODisplay*` parameters are deprecated and unsupported there;
/// `DisplayServices` is private). The legitimate alternative used here is to post the standard
/// brightness-up / brightness-down key events — exactly what the keyboard does — which requires
/// Accessibility access. Because the current level cannot be read, the UI never shows a
/// fabricated level meter; macOS shows its own brightness HUD with the real value.
final class BrightnessController: ObservableObject {
    @Published private(set) var canAdjust = KeyEventPoster.isTrusted
    @Published private(set) var lastDirection: Direction?

    enum Direction { case up, down }

    func refreshPermission() {
        let trusted = KeyEventPoster.isTrusted
        if trusted != canAdjust { canAdjust = trusted }
    }

    func step(_ direction: Direction) {
        refreshPermission()
        guard canAdjust else {
            KeyEventPoster.requestTrust()
            return
        }
        KeyEventPoster.post(direction == .up ? .up : .down)
        lastDirection = direction
    }
}
