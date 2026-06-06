import SwiftUI

struct CategoryShelf<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    let cardWidth: CGFloat
    let cardSpacing: CGFloat
    let emptyMessage: String
    let isLoading: Bool
    var onTitleTap: (() -> Void)? = nil
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleRow
                .padding(.horizontal, 60)

            if items.isEmpty {
                if isLoading {
                    placeholderRow
                } else {
                    Text(emptyMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 60)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: cardSpacing) {
                        ForEach(items) { item in
                            card(item)
                                .frame(width: cardWidth)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)
                }
            }
        }
        .padding(.vertical, 12)
        .focusSection()
    }

    @ViewBuilder
    private var titleRow: some View {
        if let onTitleTap {
            Button(action: onTitleTap) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text("\(items.count)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text("\(items.count)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var placeholderRow: some View {
        HStack(spacing: cardSpacing) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: cardWidth, height: cardWidth * 1.5)
            }
        }
        .padding(.horizontal, 60)
    }
}
