import SwiftUI

/// Shared scaffold for the Live / Movies / Series tabs: a vertical stack of
/// `CategoryShelf`s plus an empty state shown when no categories exist.
///
/// `header` is rendered above the shelves (e.g. a `ContinueWatchingShelf`)
/// and participates in the same scroll/focus container, so the empty state
/// only shows when both header and categories yield nothing.
struct CategoryListView<Item: Identifiable, Card: View, Header: View>: View {
    let categories: [DBCategory]
    let itemsForCategory: (DBCategory) -> [Item]
    let cardWidth: CGFloat
    let emptyTitle: String
    let emptyIcon: String
    let shelfEmptyMessage: String
    let isLoading: Bool
    var onCategoryTap: ((DBCategory) -> Void)? = nil
    @ViewBuilder let header: () -> Header
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 40) {
                header()
                if categories.isEmpty {
                    EmptyStateView(icon: emptyIcon, message: emptyTitle)
                } else {
                    ForEach(categories) { category in
                        CategoryShelf(
                            title: category.name,
                            items: itemsForCategory(category),
                            cardWidth: cardWidth,
                            cardSpacing: 32,
                            emptyMessage: shelfEmptyMessage,
                            isLoading: isLoading,
                            onTitleTap: onCategoryTap.map { tap in { tap(category) } }
                        ) { item in
                            card(item)
                        }
                        .id(category.id)
                    }
                }
            }
            .padding(.vertical, 24)
        }
    }
}

extension CategoryListView where Header == EmptyView {
    init(
        categories: [DBCategory],
        itemsForCategory: @escaping (DBCategory) -> [Item],
        cardWidth: CGFloat,
        emptyTitle: String,
        emptyIcon: String,
        shelfEmptyMessage: String,
        isLoading: Bool,
        onCategoryTap: ((DBCategory) -> Void)? = nil,
        @ViewBuilder card: @escaping (Item) -> Card
    ) {
        self.init(
            categories: categories,
            itemsForCategory: itemsForCategory,
            cardWidth: cardWidth,
            emptyTitle: emptyTitle,
            emptyIcon: emptyIcon,
            shelfEmptyMessage: shelfEmptyMessage,
            isLoading: isLoading,
            onCategoryTap: onCategoryTap,
            header: { EmptyView() },
            card: card
        )
    }
}

/// Minimal empty/placeholder view used inside shelves and tabs when there
/// is nothing to show.
struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
    }
}
