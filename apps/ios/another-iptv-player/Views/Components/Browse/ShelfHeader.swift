import SwiftUI

/// Title of a shelf or of a section on a detail page: label-coloured, with a grey
/// chevron when it leads somewhere.
///
/// The colours are explicit (`Color.primary`, `Color.secondary`) and not the
/// hierarchical styles: inside a button with the default style those resolve
/// against the tint and the title turns into an accent-coloured link.
///
/// Used alone (`showsChevron: false`) for a header that is not a link; the caller
/// then adds `.accessibilityAddTraits(.isHeader)` itself.
struct ShelfHeaderLabel: View {
    private let title: String
    private let showsChevron: Bool

    init(_ title: String, showsChevron: Bool = true) {
        self.title = title
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            if showsChevron {
                // `chevron.forward` mirrors in right-to-left layouts.
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Header of a browse shelf: the title is a link to the shelf's full list, an
/// optional accessory (an item count, for example) sits at the trailing edge.
///
/// The link is a button with the heading trait, so VoiceOver's Headings rotor
/// steps from shelf to shelf, and its accessibility label is the title alone.
/// The accessory is outside the link and does not get the trait.
///
/// The header has no state of its own; inside an `Equatable` shelf row it is
/// rebuilt only when the row is.
struct ShelfHeader<Destination: View, Accessory: View>: View {
    private let title: String
    private let destination: () -> Destination
    private let accessory: () -> Accessory

    init(
        _ title: String,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.destination = destination
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            NavigationLink {
                destination()
            } label: {
                // A title line is about 25 pt tall; the touch area is raised to
                // 44 pt without moving the shelf below it.
                ShelfHeaderLabel(title)
                    .minimumHitHeight()
            }
            .buttonStyle(.dimPress)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            accessory()
        }
        .padding(.horizontal, BrowseMetrics.pageMargin)
    }
}

extension ShelfHeader where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(title, destination: destination, accessory: { EmptyView() })
    }
}
