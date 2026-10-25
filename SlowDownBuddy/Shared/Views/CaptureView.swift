import SwiftUI

/// Records what another app is playing — YouTube, Spotify, a browser, anything — so it can be slowed down.
/// macOS uses ScreenCaptureKit; iOS uses a ReplayKit broadcast extension.
struct CaptureView: View {
    let onFinish: (Recording) -> Void

    var body: some View {
        #if os(macOS)
        MacCaptureView(onFinish: onFinish)
        #else
        PhoneCaptureView()
        #endif
    }
}
