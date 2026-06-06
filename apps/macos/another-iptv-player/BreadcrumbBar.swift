import SwiftUI

/// Finder / Safari path bar muadili: NavigationSplitView'in altında current selection'a
/// göre breadcrumb gösterir. HIG: small caption-text, ayraçlar chevron, son crumb vurgulu,
/// ara crumb'lar tıklanabilir → o seviyeye navigate.
struct BreadcrumbCrumb: Identifiable, Hashable {
    let id: UUID = UUID()
    let title: String
    /// Tıklanabilirse `nil` değil. Son crumb (mevcut konum) genelde non-nil olsa da display-only
    /// gösterimi için isteğe bağlı `nil`'lenebilir.
    let target: SidebarSelection?

    static func == (lhs: BreadcrumbCrumb, rhs: BreadcrumbCrumb) -> Bool {
        lhs.title == rhs.title && lhs.target == rhs.target
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(target)
    }
}

struct BreadcrumbBar: View {
    let crumbs: [BreadcrumbCrumb]
    let onTap: (BreadcrumbCrumb) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if crumbs.isEmpty {
                Text(" ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(crumbs.indices, id: \.self) { index in
                    let crumb = crumbs[index]
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    let isLast = (index == crumbs.count - 1)
                    if isLast || crumb.target == nil {
                        Text(crumb.title)
                            .font(.caption)
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .lineLimit(1)
                    } else {
                        Button {
                            onTap(crumb)
                        } label: {
                            Text(crumb.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
