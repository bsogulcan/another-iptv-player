import SwiftUI
import MessageUI
import UIKit

struct SupportSection: View {
    var body: some View {
        Section(header: Text(L("support.title"))) {
            NavigationLink {
                SupportForm(isIssue: false)
            } label: {
                Label(L("support.contact"), systemImage: "envelope")
            }
            .accessibilityIdentifier("support.contact")
            NavigationLink {
                SupportForm(isIssue: true)
            } label: {
                Label(L("support.report"), systemImage: "ladybug")
            }
            .accessibilityIdentifier("support.report")
        }
    }
}

private struct SupportForm: View {
    let isIssue: Bool
    @State private var message = ""
    @FocusState private var isMessageFocused: Bool
    @State private var includeDiagnostics = false
    @State private var snapshot: String?
    @State private var report: SupportReport?
    @State private var failed = false
    @State private var attachmentURL: URL?
    @State private var copied = false

    var body: some View {
        Form {
            Section(header: Text(L("support.message")), footer: Text(L("support.message.hint"))) {
                TextEditor(text: $message)
                    .focused($isMessageFocused)
                    .accessibilityIdentifier("support.message")
                    .frame(minHeight: 140)
                    .accessibilityLabel(L("support.message"))
            }
            if isIssue {
                Section(footer: Text(L("support.diagnostics.hint"))) {
                    Toggle(L("support.diagnostics"), isOn: $includeDiagnostics)
                    if includeDiagnostics && snapshot == nil {
                        ProgressView()
                    }
                    if includeDiagnostics, let snapshot {
                        NavigationLink(L("support.preview")) {
                            ScrollView {
                                Text(snapshot)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .navigationTitle(L("support.preview"))
                        }
                    }
                }
            }
            Section(footer: Text(L(MFMailComposeViewController.canSendMail() ? "support.send.hint" : "support.unavailable"))) {
                Button {
                    prepareReport()
                } label: {
                    Label(L(MFMailComposeViewController.canSendMail() ? "support.compose" : "support.share"), systemImage: "square.and.arrow.up")
                }
                .disabled(includeDiagnostics && snapshot == nil)
                Button {
                    UIPasteboard.general.string = SupportReport.recipient
                    copied = true
                } label: {
                    Label(L(copied ? "support.copied" : "support.copy"), systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle(L(isIssue ? "support.report" : "support.contact"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { prepareReport() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L(MFMailComposeViewController.canSendMail() ? "support.compose" : "support.share"))
                .accessibilityIdentifier("support.prepare")
                .disabled(includeDiagnostics && snapshot == nil)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("common.done")) { isMessageFocused = false }
                    .accessibilityIdentifier("support.keyboard.done")
            }
        }
        .task {
            guard snapshot == nil, isIssue else { return }
            snapshot = await Task.detached(priority: .userInitiated) {
                SupportReport.diagnosticsText(
                    current: Log.recentLines(),
                    savedAirPlay: Log.persistedLines(key: AirPlayLogExport.persistedKey),
                    savedAt: Log.persistedDate(key: AirPlayLogExport.persistedKey),
                    archive: DiagnosticArchive.shared.snapshot()
                )
            }.value
        }
        .sheet(item: $report, onDismiss: cleanAttachment) { draft in
            if MFMailComposeViewController.canSendMail() {
                SupportMailComposer(report: draft) { error in
                    report = nil
                    failed = error
                }
                .ignoresSafeArea(.container)
            } else {
                SupportShareSheet(report: draft, attachmentURL: attachmentURL)
            }
        }
        .alert(L("common.error"), isPresented: $failed) {
            Button(L("common.ok"), role: .cancel) { }
        } message: {
            Text(L("support.failed"))
        }
    }

    private func prepareReport() {
        isMessageFocused = false
        let draft = makeReport()
        do {
            if !MFMailComposeViewController.canSendMail(), let data = draft.attachment {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("support-" + draft.id.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("diagnostics.txt")
                attachmentURL = url
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            }
            report = draft
        } catch {
            cleanAttachment()
            failed = true
        }
    }

    private func cleanAttachment() {
        if let attachmentURL {
            try? FileManager.default.removeItem(at: attachmentURL.deletingLastPathComponent())
        }
        attachmentURL = nil
    }

    private func makeReport() -> SupportReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let metadata = "App: \(version) (\(build))\niOS: \(UIDevice.current.systemVersion)\nDevice: \(UIDevice.current.model)\nDate: \(ISO8601DateFormatter().string(from: Date()))"
        let description = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return SupportReport(
            subject: "[Another IPTV Player • iOS] \(L(isIssue ? "support.report" : "support.contact"))",
            body: (description.isEmpty ? L("support.message.hint") : description) + "\n\n---\n" + metadata,
            diagnostics: isIssue && includeDiagnostics ? snapshot : nil
        )
    }
}

private struct SupportMailComposer: UIViewControllerRepresentable {
    let report: SupportReport
    let completion: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([SupportReport.recipient])
        controller.setSubject(report.subject)
        controller.setMessageBody(report.body, isHTML: false)
        if let data = report.attachment {
            controller.addAttachmentData(data, mimeType: "text/plain", fileName: "diagnostics.txt")
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) { }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (Bool) -> Void
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            completion(result == .failed || error != nil)
        }
    }
}

private struct SupportShareSheet: UIViewControllerRepresentable {
    let report: SupportReport
    let attachmentURL: URL?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [report.shareText]
        if let attachmentURL { items.append(attachmentURL) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
