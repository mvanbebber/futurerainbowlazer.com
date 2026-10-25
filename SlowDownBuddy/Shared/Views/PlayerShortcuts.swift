import SwiftUI

extension View {
    /// A Transcribe!-style single-key shortcut that is switched off while a text field is being edited,
    /// so typing a marker or loop name doesn't start playback or set loop points.
    func playerShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = [], enabled: Bool) -> some View {
        keyboardShortcut(enabled ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }
}
