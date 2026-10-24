import AVFoundation
import SwiftUI

@main
struct SlowDownApp: App {
    @State private var library = Library()

    init() {
        #if os(iOS)
        // Keep playing with the silent switch on and in the background, like a music player.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}
