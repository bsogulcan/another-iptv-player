import SwiftUI

/// Ortak kategori/grup seçici — hem M3U hem Xtream ekranları kullanır.
/// Aramalı liste, her satırda içerik sayısı chip'i. Seçimde `onSelect(id)` çağrılır.
/// `playlistId` + `type` verilirse satırlarda gizle/göster swipe action'ı aktif olur ve
/// gizli kategoriler ayrı bir bölümde görüntülenir.
struct CategoryPickerSheet: View {
    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
        let count: Int
    }

    let title: String
    let entries: [Entry]
    /// Gizleme özelliğini açmak için ikisinin de verilmesi gerekir (örn. M3U group picker'da nil bırakılabilir).
    var playlistId: UUID? = nil
    var type: String? = nil
    let onSelect: (String) -> Void

    @ObservedObject private var locale = LocalizationManager.shared
    @ObservedObject private var hiddenStore = HiddenCategoryStore.shared

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var hidingEnabled: Bool { playlistId != nil && type != nil }

    private var hiddenIds: Set<String> {
        guard let pid = playlistId, let t = type else { return [] }
        return hiddenStore.hiddenIds(playlistId: pid, type: t)
    }

    /// Tek geçişte filtrele + gizli/görünür ayır. `visibleEntries`/`hiddenEntries`
    /// computed'larını body içinde ayrı ayrı okumak, her tuş vuruşunda tüm listeyi
    /// iki kez normalize edip tarıyordu (binlerce M3U grubunda görünür takılma).
    private func partitionedEntries() -> (visible: [Entry], hidden: [Entry]) {
        let q = query.trimmingCharacters(in: .whitespaces)
        // Built once: the folded search words are the same for every row.
        let search = q.isEmpty ? nil : CatalogTextSearch.Query(q)
        let ids = hiddenIds
        var visible: [Entry] = []
        var hidden: [Entry] = []
        for entry in entries {
            if let search, !search.matches(entry.name) { continue }
            if hidingEnabled, ids.contains(entry.id) {
                hidden.append(entry)
            } else {
                visible.append(entry)
            }
        }
        return (visible, hidden)
    }

    var body: some View {
        let (visibleEntries, hiddenEntries) = partitionedEntries()
        NavigationStack {
            Group {
                if visibleEntries.isEmpty && hiddenEntries.isEmpty {
                    ContentUnavailableView(
                        L("category_picker.not_found.title"),
                        systemImage: "magnifyingglass",
                        description: Text(L("category_picker.not_found.message"))
                    )
                } else {
                    List {
                        if !visibleEntries.isEmpty {
                            Section {
                                ForEach(visibleEntries) { entry in
                                    row(entry, isHidden: false)
                                }
                            }
                        }

                        if !hiddenEntries.isEmpty {
                            Section(L("category_picker.hidden_section")) {
                                ForEach(hiddenEntries) { entry in
                                    row(entry, isHidden: true)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    // A category that is hidden or shown travels to its section. Scoped
                    // to this list, so the shelves behind the sheet are not animated
                    // by the same change, and typing in the search field is not either.
                    .animation(.default, value: hiddenStore.version)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L("category_picker.search_placeholder")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Regular width (iPad): the narrower form sheet instead of a page-sized one
        // for what is a short list. No effect on the compact-width bottom sheet.
        .presentationSizing(.form)
    }

    @ViewBuilder
    private func row(_ entry: Entry, isHidden: Bool) -> some View {
        Button {
            if isHidden {
                // A hidden category has no shelf to jump to, so selecting it would
                // close the sheet and show nothing. The tap brings it back instead
                // and the sheet stays open.
                setHidden(false, entry)
            } else {
                onSelect(entry.id)
            }
        } label: {
            HStack {
                Text(entry.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if isHidden {
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        // The `Text` form: the count form draws nothing for 0, and counts are 0
        // while the streams are still loading.
        .badge(Text("\(entry.count)").monospacedDigit())
        .opacity(isHidden ? 0.55 : 1)
        .accessibilityHint(isHidden ? L("category_picker.unhide") : "")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if hidingEnabled {
                visibilityButton(entry, isHidden: isHidden)
                    .tint(isHidden ? .accentColor : .gray)
            }
        }
        // The same action for those who do not find the swipe.
        .contextMenu {
            if hidingEnabled {
                visibilityButton(entry, isHidden: isHidden)
            }
        }
    }

    private func visibilityButton(_ entry: Entry, isHidden: Bool) -> some View {
        Button {
            setHidden(!isHidden, entry)
        } label: {
            if isHidden {
                Label(L("category_picker.unhide"), systemImage: "eye")
            } else {
                Label(L("category_picker.hide"), systemImage: "eye.slash")
            }
        }
    }

    private func setHidden(_ hide: Bool, _ entry: Entry) {
        guard let pid = playlistId, let t = type else { return }
        hiddenStore.setHidden(hide, playlistId: pid, type: t, categoryId: entry.id)
    }
}
