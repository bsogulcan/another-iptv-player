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

    private var filtered: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { CatalogTextSearch.matches(search: q, text: $0.name) }
    }

    private var visibleEntries: [Entry] {
        filtered.filter { !hiddenIds.contains($0.id) }
    }

    private var hiddenEntries: [Entry] {
        guard hidingEnabled else { return [] }
        return filtered.filter { hiddenIds.contains($0.id) }
    }

    var body: some View {
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
    }

    @ViewBuilder
    private func row(_ entry: Entry, isHidden: Bool) -> some View {
        Button {
            onSelect(entry.id)
        } label: {
            HStack {
                Text(entry.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text("\(entry.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
            }
        }
        .opacity(isHidden ? 0.55 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if hidingEnabled, let pid = playlistId, let t = type {
                Button {
                    hiddenStore.setHidden(!isHidden, playlistId: pid, type: t, categoryId: entry.id)
                } label: {
                    if isHidden {
                        Label(L("category_picker.unhide"), systemImage: "eye")
                    } else {
                        Label(L("category_picker.hide"), systemImage: "eye.slash")
                    }
                }
                .tint(isHidden ? .accentColor : .gray)
            }
        }
    }
}
