import CoreGraphics
import AppKit
import os

/// macOS system actions triggered by gesture recognition.
///
/// Uses CGEvent keyboard shortcuts for all actions (Ctrl+Fn+Arrow).
/// This is the same approach BetterMouse uses via SkyLight SymbolicHotKey.
///
/// Key requirements (discovered through testing + RE):
///   - Event source: `.privateState` (isolated from real keyboard state)
///   - Modifier flags: `0x840000` (Control + SecondaryFn — arrow keys need Fn)
///   - Event tap: `.cghidEventTap` (injects at HID level)
///
/// Requires Accessibility permission.
enum MacActions {

    // MARK: - Actions

    /// Trigger Mission Control (Ctrl+Fn+UpArrow, SymbolicHotKey ID 32).
    static func missionControl() {
        postKeyboardShortcut(keyCode: 0x7E)  // kVK_UpArrow
        debugLog("[MacActions] Mission Control triggered")
    }

    /// Switch to the workspace on the LEFT (Ctrl+Fn+LeftArrow, SymbolicHotKey ID 79).
    static func workspaceLeft() {
        postKeyboardShortcut(keyCode: 0x7B)  // kVK_LeftArrow
        debugLog("[MacActions] Workspace Left triggered")
    }

    /// Switch to the workspace on the RIGHT (Ctrl+Fn+RightArrow, SymbolicHotKey ID 81).
    static func workspaceRight() {
        postKeyboardShortcut(keyCode: 0x7C)  // kVK_RightArrow
        debugLog("[MacActions] Workspace Right triggered")
    }

    // MARK: - CGEvent Keyboard Shortcut

    /// 0x040000 = kCGEventFlagMaskControl
    /// 0x800000 = kCGEventFlagMaskSecondaryFn (arrow keys are fn keys)
    private static let arrowModifiers = CGEventFlags(rawValue: 0x840000)

    private static func postKeyboardShortcut(keyCode: CGKeyCode) {
        guard AXIsProcessTrusted() else {
            debugLog("[MacActions] ERROR: Not trusted for accessibility")
            return
        }

        guard let source = CGEventSource(stateID: .privateState) else {
            debugLog("[MacActions] ERROR: Failed to create CGEventSource")
            return
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            debugLog("[MacActions] ERROR: Failed to create CGEvent for keyCode 0x\(String(format: "%02X", keyCode))")
            return
        }

        keyDown.flags = arrowModifiers
        keyUp.flags = arrowModifiers

        keyDown.post(tap: .cghidEventTap)
        usleep(20_000)  // 20ms gap
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility Permission

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    nonisolated(unsafe) private static var hasPromptedAccessibility = false

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        debugLog("[MacActions] AXIsProcessTrusted = \(trusted)")
        if trusted { return true }

        guard !hasPromptedAccessibility else {
            debugLog("[MacActions] Skipping duplicate accessibility prompt")
            return false
        }
        hasPromptedAccessibility = true

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        if !result {
            debugLog("[MacActions] Accessibility NOT granted.")
        }
        return result
    }
}
