import Foundation

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
        case .cannotCreateFile, .cannotWriteToFile, .cannotMoveFile:
            return L("download.error.file_write")
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

/// What a form tells the user when a save fails: a title that names the problem, a
/// sentence a person can act on, and the input to send them back to.
struct PlaylistFormFailure: Equatable {
    enum Field {
        case address
        case credentials
    }

    let title: String
    let message: String
    /// Nil when no field is at fault (offline, a file that cannot be read, the database).
    let field: Field?

    /// The one place where the forms turn an error into text. The descriptions of
    /// the panel and M3U errors wrap the Foundation text ("Network error: The data
    /// couldn't be read because…") and are shared with the refresh paths, so they
    /// are replaced here instead of changed there.
    static func describing(_ error: Error) -> PlaylistFormFailure {
        switch error {
        case let error as XtreamError:
            switch error {
            case .unauthenticated:
                return PlaylistFormFailure(
                    title: L("onboarding.error.title.sign_in"), message: L("misc.xtream.auth_error"), field: .credentials
                )
            case .networkError(let underlying):
                return connection(underlying)
            case .decodingError:
                return unreachable(L("onboarding.error.not_xtream"))
            case .serverError(let status):
                return unreachable(L("onboarding.error.http", status))
            case .invalidURL:
                return unreachable(L("onboarding.error.invalid_address"))
            }
        case let error as M3UServiceError:
            switch error {
            case .networkError(let underlying):
                return connection(underlying)
            case .serverError(let code):
                return unreachable(L("onboarding.error.http", "HTTP \(code)"))
            case .invalidURL:
                return unreachable(L("onboarding.error.invalid_address"))
            case .fileReadError, .encodingUnsupported:
                return PlaylistFormFailure(title: L("loading.error.title"), message: NetworkErrorText.describe(error), field: nil)
            }
        case let error as M3UParserError:
            // Empty, or not a playlist at all: the link or the file is the wrong one.
            return PlaylistFormFailure(title: L("loading.error.title"), message: NetworkErrorText.describe(error), field: .address)
        default:
            // Foundation and database messages follow the device language. Keep the
            // form in the app's language, as with other browse errors.
            return PlaylistFormFailure(title: L("onboarding.error.title.save"), message: NetworkErrorText.describe(error), field: nil)
        }
    }

    private static func unreachable(_ message: String) -> PlaylistFormFailure {
        PlaylistFormFailure(title: L("onboarding.error.title.connection"), message: message, field: .address)
    }

    private static func connection(_ underlying: Error) -> PlaylistFormFailure {
        switch (underlying as? URLError)?.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return PlaylistFormFailure(
                title: L("onboarding.error.title.connection"), message: L("onboarding.error.offline"), field: nil
            )
        case .timedOut:
            return unreachable(L("onboarding.error.timeout"))
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .badURL, .unsupportedURL:
            return unreachable(L("onboarding.error.unreachable"))
        default:
            return unreachable(L("onboarding.error.connection"))
        }
    }
}
