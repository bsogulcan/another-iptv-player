import SwiftUI

struct DiagnosticLogPreview: View {
    let preview: DiagnosticPreview
    @State private var pageIndex: Int

    init(preview: DiagnosticPreview) {
        self.preview = preview
        _pageIndex = State(initialValue: preview.pages.count - 1)
    }

    var body: some View {
        ScrollView {
            Text(verbatim: preview.pages[pageIndex])
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityIdentifier("support.preview.page")
        }
        // Replacing only this bounded page also resets its scroll position.
        .id(pageIndex)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Text(L("support.preview.full_attachment"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L("support.preview.older")) { pageIndex -= 1 }
                        .disabled(pageIndex == 0)
                        .accessibilityIdentifier("support.preview.older")
                    Spacer()
                    Text("\(pageIndex + 1) / \(preview.pages.count)")
                        .monospacedDigit()
                        .accessibilityIdentifier("support.preview.position")
                    Spacer()
                    Button(L("support.preview.newer")) { pageIndex += 1 }
                        .disabled(pageIndex == preview.pages.count - 1)
                        .accessibilityIdentifier("support.preview.newer")
                }
                .font(.subheadline)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(L("support.preview"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
