import SwiftUI

/// Yatay scroll yerine sayfalama yapan shelf. **NSScrollView yok**, **LazyHStack yok**:
/// yalnızca görünür sayfanın N kartı SwiftUI tarafından render edilir → 30-50 kart × shelf
/// patlamasından kaynaklanan kasma kaybolur.
///
/// Caller `.frame(height: ...)` ile yüksekliği belirlemeli; PagedHorizontalShelf
/// `GeometryReader` ile bu yüksekliğe yayılır ve container genişliğini ölçüp sayfa
/// boyutunu (görünür slot sayısı) hesaplar. Pencere boyutu değişince sayfa boyutu
/// da otomatik güncellenir.
///
/// `onPageChange` opsiyonel callback: sayfa atlanınca yeni görünür item index aralığını
/// verir; caller bu range'i image prefetch vb. için kullanabilir.
struct PagedHorizontalShelf<Item: Identifiable, ItemView: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let itemSpacing: CGFloat
    let horizontalPadding: CGFloat
    let onPageChange: ((Range<Int>) -> Void)?
    @ViewBuilder let content: (Item) -> ItemView

    @State private var pageIndex: Int = 0
    @State private var lastDirection: SlideDirection = .forward

    init(
        items: [Item],
        itemWidth: CGFloat,
        itemSpacing: CGFloat = 12,
        horizontalPadding: CGFloat = 16,
        onPageChange: ((Range<Int>) -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> ItemView
    ) {
        self.items = items
        self.itemWidth = itemWidth
        self.itemSpacing = itemSpacing
        self.horizontalPadding = horizontalPadding
        self.onPageChange = onPageChange
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            renderContent(width: geo.size.width)
        }
    }

    @ViewBuilder
    private func renderContent(width: CGFloat) -> some View {
        let pageSize = computePageSize(width: width)
        let pageCount = items.isEmpty ? 1 : max(1, Int(ceil(Double(items.count) / Double(pageSize))))
        let safePage = max(0, min(pageIndex, pageCount - 1))
        let start = safePage * pageSize
        let end = min(items.count, start + pageSize)
        let canGoLeft = safePage > 0
        let canGoRight = safePage < pageCount - 1

        ZStack(alignment: .center) {
            if start < end {
                HStack(spacing: itemSpacing) {
                    ForEach(items[start ..< end]) { item in
                        content(item)
                            .frame(width: itemWidth, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(width: width, alignment: .leading)
                .id(safePage)
                .transition(slideTransition(direction: lastDirection))
            }

            HStack(spacing: 0) {
                ArrowButton(direction: .backward, visible: canGoLeft) {
                    goToPage(safePage - 1, direction: .backward, pageCount: pageCount, pageSize: pageSize)
                }
                .padding(.leading, 6)

                Spacer()

                ArrowButton(direction: .forward, visible: canGoRight) {
                    goToPage(safePage + 1, direction: .forward, pageCount: pageCount, pageSize: pageSize)
                }
                .padding(.trailing, 6)
            }
            .frame(width: width)
        }
    }

    private func computePageSize(width: CGFloat) -> Int {
        let usable = max(0, width - 2 * horizontalPadding)
        let slot = itemWidth + itemSpacing
        guard slot > 0 else { return 1 }
        return max(1, Int(usable / slot))
    }

    private func goToPage(_ targetIndex: Int, direction: SlideDirection, pageCount: Int, pageSize: Int) {
        let bounded = max(0, min(targetIndex, pageCount - 1))
        guard bounded != pageIndex else { return }
        lastDirection = direction
        withAnimation(.easeOut(duration: 0.22)) {
            pageIndex = bounded
        }
        if let onPageChange {
            let start = bounded * pageSize
            let end = min(items.count, start + pageSize)
            onPageChange(start ..< end)
        }
    }

    private enum SlideDirection { case forward, backward }

    private func slideTransition(direction: SlideDirection) -> AnyTransition {
        let insertion: Edge = direction == .forward ? .trailing : .leading
        let removal: Edge = direction == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }

    private struct ArrowButton: View {
        enum Direction { case backward, forward }
        let direction: Direction
        let visible: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: direction == .backward ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .animation(.easeOut(duration: 0.15), value: visible)
        }
    }
}
