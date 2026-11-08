import AppKit
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct MacSupportPreferences: View {
  @Environment(\.purchase) private var purchase
  @ObservedObject private var tips = TipStore.shared
  @State private var message = ""
  @State private var includeDiagnostics = false
  @State private var preview: String?
  @State private var feedback: String?
  @State private var preparing = false

  var body: some View {
    Section(L("support.report")) {
      TextField(L("support.message"), text: $message, axis: .vertical).lineLimit(3...8)
      Toggle(L("support.diagnostics"), isOn: $includeDiagnostics)
      if includeDiagnostics {
        Button(L("support.preview")) { Task { preview = await diagnostics() } }
      }
      HStack {
        Button(L("support.compose"), systemImage: "envelope") { prepareEmail() }.disabled(preparing)
        Button(L("support.copy"), systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(SupportReport.recipient, forType: .string)
        }
      }
      if let preview, includeDiagnostics {
        DisclosureGroup(L("support.diagnostics"), isExpanded: .constant(true)) {
          ScrollView {
            Text(verbatim: preview).font(.system(.caption, design: .monospaced)).textSelection(
              .enabled
            ).frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 160)
        }
      }
    }
    Section(L("tip.title")) {
      switch tips.loadState {
      case .idle, .loading: ProgressView().controlSize(.small)
      case .failed:
        Text(L("tip.unavailable"))
        Button(L("common.try_again")) { Task { await tips.loadProducts() } }
      case .loaded:
        if tips.products.isEmpty { Text(L("tip.unavailable")) }
        ForEach(TipStore.Tier.allCases) { tier in
          if let product = tips.products[tier] {
            LabeledContent(L("tip.tier." + tier.rawValue)) {
              Button(product.displayPrice) { Task { await buy(tier) } }.disabled(
                tips.purchasingTier != nil)
            }
          }
        }
      }
    }
    .task { await tips.loadProducts() }
    .alert(
      L("support.title"),
      isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })
    ) {
      Button(L("common.ok")) {}
    } message: {
      Text(feedback ?? "")
    }
  }
  private func diagnostics() async -> String {
    await Task.detached(priority: .utility) {
      SupportReport.diagnosticsText(
        current: Log.recentLines(), savedAirPlay: Log.persistedLines(key: "airplay.lastSessionLog"),
        savedAt: Log.persistedDate(key: "airplay.lastSessionLog"),
        archive: DiagnosticArchive.shared.snapshot())
    }.value
  }
  private func prepareEmail() {
    preparing = true
    Task {
      defer { preparing = false }
      let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
      let report = SupportReport(
        subject: "Another IPTV Player · macOS " + version,
        body: message + "\n\n" + ProcessInfo.processInfo.operatingSystemVersionString,
        diagnostics: includeDiagnostics ? await diagnostics() : nil)
      do {
        var items: [Any] = [report.body]
        if let data = report.attachment {
          let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            report.id.uuidString, isDirectory: true)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let url = folder.appendingPathComponent("diagnostics.txt")
          try data.write(to: url, options: .atomic)
          items.append(url)
        }
        if let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: items) {
          mail.recipients = [SupportReport.recipient]
          mail.subject = report.subject
          mail.perform(withItems: items)
        } else {
          let panel = NSSavePanel()
          panel.allowedContentTypes = [.plainText]
          panel.nameFieldStringValue = "Another IPTV Player.txt"
          if await panel.begin() == .OK, let url = panel.url {
            try (report.shareText + "\n\n" + (report.diagnostics ?? "")).write(
              to: url, atomically: true, encoding: .utf8)
          }
        }
      } catch { feedback = L("support.failed") }
    }
  }
  private func buy(_ tier: TipStore.Tier) async {
    switch await tips.purchase(tier, using: purchase) {
    case .success: feedback = L("tip.thanks.message")
    case .pending: feedback = L("tip.pending")
    case .failed(let text): feedback = text
    case .cancelled: break
    }
  }
}
