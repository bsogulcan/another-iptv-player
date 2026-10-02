import SwiftUI

// MARK: - Empty states

/// The empty and no-result states of the catalog screens, in the system's
/// `ContentUnavailableView` layout.
///
/// Every text comes from `L()`, so the state follows the in-app language.
/// `ContentUnavailableView.search(text:)` is deliberately not used anywhere: the
/// system localises it with the device language and ignores the in-app picker.
///
/// The view fills and centres in the space it is offered. Inside a scroll view or
/// under other content the caller gives it the frame.
struct CatalogEmptyView: View {
    nonisolated enum Kind: Equatable {
        /// A tab or a picker without a single category to show.
        case noCategories(systemImage: String)
        /// A list that is empty although nothing was searched: the caller names
        /// what is missing ("No movies found") and passes the content's own symbol.
        case noItems(title: String, systemImage: String)
        /// A search or filter that matched nothing.
        case noSearchResults
        /// Anything else.
        case message(title: String, systemImage: String, description: String?)
    }

    private let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        let content = Self.content(for: kind)
        ContentUnavailableView(
            content.title,
            systemImage: content.systemImage,
            description: content.description.map { Text($0) }
        )
    }

    /// What a kind shows. Separate from `body` so the mapping can be tested.
    nonisolated static func content(for kind: Kind) -> (title: String, systemImage: String, description: String?) {
        switch kind {
        case .noCategories(let systemImage):
            return (L("category_picker.not_found.title"), systemImage, nil)
        case .noItems(let title, let systemImage):
            return (headline(title), systemImage, nil)
        case .noSearchResults:
            return (L("favorites.empty.no_result.title"), "magnifyingglass", L("category_picker.not_found.message"))
        case .message(let title, let systemImage, let description):
            return (headline(title), systemImage, description)
        }
    }

    /// The strings these states reuse were written as sentences for the inline
    /// texts they replace ("No movies found."). As the bold title of the system
    /// layout they read as a headline, which carries no full stop.
    /// An ellipsis ("Loading...") is not a full stop and stays.
    nonisolated static func headline(_ text: String) -> String {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = title.last, sentenceEnds.contains(last) else { return title }
        let body = title.dropLast()
        guard body.last != last else { return title }
        return String(body)
    }

    /// Full stops of the app's languages (Latin, CJK, Devanagari, Arabic).
    nonisolated private static let sentenceEnds: Set<Character> = [".", "。", "।", "۔"]
}

// MARK: - Inline error

/// A failure shown where the missing part would have been: one quiet line and,
/// when the caller can retry, a Try Again button. For a section of a detail page,
/// the end of a list or a `Form` row; the rest of the screen stays usable.
///
/// The text is secondary-coloured footnote. Red stays reserved for destructive
/// actions and failed-status badges.
struct InlineErrorRow: View {
    private let message: String
    private let retry: (() -> Void)?

    init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let retry {
                Button(action: retry) {
                    Text(L("common.try_again"))
                        .font(.footnote.weight(.semibold))
                        .minimumHitHeight()
                }
                // Borderless, so that inside a `Form` or `List` row only the button
                // reacts and not the whole row.
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Error text

/// Turns an error into one short sentence in the in-app language.
///
/// The app's error types used to format the system's `localizedDescription` into a
/// localised prefix ("Network error: The Internet connection appears to be
/// offline."). The system half follows the device language, so a user of the
/// in-app language picker read a sentence in two languages, and the wording was
/// technical in both. Here the cause is mapped to a sentence of the app's own.
///
/// What support needs stays visible: an HTTP status is kept in the sentence, and a
/// connection failure without a sentence of its own shows its `URLError` code.
///
/// The function only maps; it neither logs nor keeps the error. A caller that
/// stores the text and drops the error should log the error first.
///
/// An error type of the app may use this for the error it wraps
/// (`case .networkError(let error): NetworkErrorText.describe(error)`), never for
/// itself: its other cases are described by asking the type, which would recurse.
///
/// `nonisolated`: errors are also described where they are caught, off the main
/// actor.
nonisolated enum NetworkErrorText {
    static func describe(_ error: Error) -> String {
        // The app's own wrappers first: the cause they carry decides the sentence.
        // Their remaining cases already have a sentence built from `L()` alone (the
        // HTTP status included), so those keep the type's own description.
        if let error = error as? XtreamError {
            switch error {
            case .networkError(let underlying): return describe(underlying)
            case .decodingError: return L("kit.error.unexpected_response")
            default: return error.localizedDescription
            }
        }
        if let error = error as? M3UServiceError {
            switch error {
            case .networkError(let underlying): return describe(underlying)
            case .fileReadError: return L("kit.error.file_unreadable")
            default: return error.localizedDescription
            }
        }
        if let error = error as? EPGError {
            if case .network(let underlying) = error { return describe(underlying) }
            return error.localizedDescription
        }
        if let error = error as? CatchupURLError {
            if case .network(let underlying) = error { return describe(underlying) }
            return error.localizedDescription
        }

        if error is CancellationError {
            return L("kit.error.cancelled")
        }
        if let error = error as? URLError {
            return describe(error)
        }
        // Before the `LocalizedError` fallback: Foundation gives `DecodingError` a
        // description in the device language.
        if error is DecodingError {
            return L("kit.error.unexpected_response")
        }
        // Other error types of the app describe themselves with `L()`.
        if let localized = error as? LocalizedError,
           let text = localized.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return L("kit.error.generic")
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return L("kit.error.offline")
        case .networkConnectionLost:
            // Not "offline": this is also what a panel that drops the connection in
            // the middle of a large catalog produces.
            return L("kit.error.connection_lost")
        case .timedOut:
            return L("playback.error.timeout")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return L("kit.error.unreachable")
        case .secureConnectionFailed,
             .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return L("kit.error.insecure")
        case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData,
             .cannotDecodeContentData, .zeroByteResource:
            return L("kit.error.unexpected_response")
        case .cancelled:
            return L("kit.error.cancelled")
        default:
            // An error number is quoted, not counted: no grouping, ASCII digits.
            return L(plainDigits: "kit.error.connection_failed", error.code.rawValue)
        }
    }
}
