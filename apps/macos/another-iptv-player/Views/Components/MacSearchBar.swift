import SwiftUI

/// `.searchable` modifier'ı yerine inline arama bar — SwiftUI'nin .searchable
/// toolbar item'ı NSWindow'a propagate ediyor ve birden fazla NSHostingController
/// (sekmeli container) crash veriyor. Inline bar window toolbar'a dokunmaz.
///
/// Görsel: list'in/grid'in üstüne küçük, native görünümlü search field. macOS'ta
/// pek çok app (Mail, Music) bu pattern'i kullanır.
struct MacSearchBar: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        )
    }
}

extension View {
    /// `.searchable` muadili — view'in üstüne inline search bar koyar.
    func macSearchable(text: Binding<String>, prompt: String) -> some View {
        VStack(spacing: 0) {
            MacSearchBar(text: text, prompt: prompt)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
            self
        }
    }
}

/// Toolbar içinde kullanılacak compact search field — `.searchable` modifier'ı yerine.
/// Conditional ToolbarItem içinde gösterilebilir, view identity churn olmaz.
struct ToolbarSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(width: 220)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        )
    }
}
