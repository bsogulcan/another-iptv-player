import SwiftUI

/// Grid view shown when a user taps a category title from a shelf. Lays out
/// every item in the selected category as a LazyVGrid so the whole catalog for
/// that category is visible on a single page.
struct CategoryGridView<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    let cardWidth: CGFloat
    let emptyIcon: String
    let emptyMessage: String
    @ViewBuilder let card: (Item) -> Card

    private let spacing: CGFloat = 40

    var body: some View {
        ScrollView {
            if items.isEmpty {
                EmptyStateView(icon: emptyIcon, message: emptyMessage)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cardWidth), spacing: spacing, alignment: .top)],
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(items) { item in
                        card(item)
                            .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
        }
        .navigationTitle(title)
    }
}
