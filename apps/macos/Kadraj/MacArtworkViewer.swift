import NukeUI
import SwiftUI

struct MacDetailArtwork: Identifiable {
  let url: URL
  let title: String
  let didClose: () -> Void
  var id: URL { url }

  static func url(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
    else { return nil }
    return url
  }
}

extension EnvironmentValues {
  @Entry var detailArtwork: Binding<MacDetailArtwork?> = .constant(nil)
}

/// The artwork covers this workspace, including its sidebar. Dismissing it
/// restores the detail page's navigation and scroll position.
struct MacArtworkPresentation: ViewModifier {
  @State private var artwork: MacDetailArtwork?
  func body(content: Content) -> some View {
    content
      .environment(\.detailArtwork, $artwork)
      .disabled(artwork != nil)
      .accessibilityHidden(artwork != nil)
      .overlay {
        if let artwork {
          MacArtworkViewer(artwork: artwork, close: {
            self.artwork = nil
            artwork.didClose()
          }).id(artwork.id)
        }
      }
  }
}

private struct MacArtworkViewer: View {
  let artwork: MacDetailArtwork
  let close: () -> Void
  @State private var scale: CGFloat = 1
  @GestureState private var pinch: CGFloat = 1
  @State private var retry = 0
  @State private var imageReady = false
  private func clamped(_ value: CGFloat) -> CGFloat { min(4, max(1, value)) }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Text(verbatim: artwork.title).font(.headline).lineLimit(1)
        Spacer()
        Button(ML("zoom_out"), systemImage: "minus.magnifyingglass") { scale = clamped(scale / 2) }
          .disabled(!imageReady || scale <= 1).keyboardShortcut("-", modifiers: .command)
        Button(ML("fit_artwork"), systemImage: "arrow.down.right.and.arrow.up.left") { scale = 1 }
          .disabled(!imageReady || scale == 1).keyboardShortcut("0", modifiers: .command)
        Button(ML("zoom_in"), systemImage: "plus.magnifyingglass") { scale = clamped(scale * 2) }
          .disabled(!imageReady || scale >= 4).keyboardShortcut("+", modifiers: .command)
        Button(L("common.close"), systemImage: "xmark", action: close)
          .keyboardShortcut(.cancelAction).accessibilityIdentifier("artwork.close")
      }.labelStyle(.iconOnly).padding(12).background(.bar)
      GeometryReader { box in
        LazyImage(url: artwork.url) { state in
          if let image = state.imageContainer?.image, image.size.width > 0, image.size.height > 0 {
            let fit = min(box.size.width / image.size.width, box.size.height / image.size.height)
            let factor = fit * clamped(scale * pinch)
            ScrollView([.horizontal, .vertical]) {
              Image(nsImage: image).resizable()
                .frame(width: image.size.width * factor, height: image.size.height * factor)
                .accessibilityLabel(artwork.title).accessibilityValue(Double(clamped(scale * pinch)).formatted(.percent))
                .accessibilityIdentifier("artwork.image")
                .onAppear { imageReady = true }
                .onTapGesture(count: 2) { scale = scale == 1 ? 2 : 1 }
                .frame(minWidth: box.size.width, minHeight: box.size.height)
            }
            .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in
              state = value.magnification
            }.onEnded { value in scale = clamped(scale * value.magnification) })
          } else if state.error != nil {
            ContentUnavailableView {
              Label(L("loading.error.title"), systemImage: "photo")
            } actions: {
              Button(L("common.try_again")) { retry += 1 }
            }
          } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }.id(retry)
      }.background(Color.black)
    }.environment(\.colorScheme, .dark)
  }
}
