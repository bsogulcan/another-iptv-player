import StoreKit
import SwiftUI

/// "Tip the developer" row for the tip section of the settings forms.
struct TipJarRow: View {
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("settings.about.tip.title"))
                    Text(L("settings.about.tip.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.pink)
            }
        }
        .sheet(isPresented: $showingSheet) {
            TipJarSheet()
        }
    }
}

struct TipJarSheet: View {
    @ObservedObject private var store = TipStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase

    @State private var didTip = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if didTip {
                    thanksView
                } else {
                    tierList
                }
            }
            .navigationTitle(L("tip.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await store.loadProducts() }
        .alert(
            L("tip.title"),
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button(L("common.ok"), role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var tierList: some View {
        List {
            Section {
                switch store.loadState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("tip.unavailable"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(L("common.try_again")) {
                            Task { await store.loadProducts() }
                        }
                        .font(.callout.weight(.semibold))
                    }
                case .loaded:
                    ForEach(TipStore.Tier.allCases) { tier in
                        if let product = store.products[tier] {
                            tierRow(tier, product: product)
                        }
                    }
                }
            } footer: {
                Text(L("tip.footer"))
            }
        }
        // The inset-grouped default leaves a tall empty band under the sheet's nav bar.
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private func tierRow(_ tier: TipStore.Tier, product: Product) -> some View {
        HStack {
            Image(systemName: tier.symbolName)
                .foregroundColor(.pink)
                .frame(width: 28)
            Text(L(tier.titleKey))
            Spacer()
            Button {
                Task { await buy(tier) }
            } label: {
                if store.purchasingTier == tier {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("\(L(tier.titleKey)), \(product.displayPrice)")
            .disabled(store.purchasingTier != nil)
        }
    }

    private var thanksView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundColor(.pink)
            Text(L("tip.thanks.title"))
                .font(.title2.weight(.semibold))
            Text(L("tip.thanks.message"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buy(_ tier: TipStore.Tier) async {
        switch await store.purchase(tier, using: purchase) {
        case .success:
            withAnimation { didTip = true }
        case .pending:
            alertMessage = L("tip.pending")
        case .cancelled:
            break
        case .failed(let message):
            alertMessage = message
        }
    }
}

private extension TipStore.Tier {
    var titleKey: String { "tip.tier.\(rawValue)" }

    var symbolName: String {
        switch self {
        case .small: return "cup.and.saucer.fill"
        case .medium: return "chevron.left.forwardslash.chevron.right"
        case .large: return "bolt.fill"
        }
    }
}
