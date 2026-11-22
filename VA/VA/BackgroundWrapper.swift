import SwiftUI

/// Puts the app's background image behind one tab's content. Wrap each tab's content in it, not the
/// `TabView`, because an opaque tab screen would hide a background on the `TabView`.
struct BackgroundWrapper<Content: View>: View {
  /// Opacity of the background image, from 0 (invisible) to 1 (opaque).
  var opacity: Double = 0.35
  var blur: CGFloat = 0
  @ViewBuilder var content: Content

  var body: some View {
    ZStack {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        content
    }
    .background {
      Image("wilderness-background")
        .resizable()
        .scaledToFill()
        .blur(radius: blur)
        .opacity(opacity)
        .ignoresSafeArea()
    }
  }
}
