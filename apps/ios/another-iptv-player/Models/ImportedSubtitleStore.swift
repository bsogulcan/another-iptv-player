import Foundation

/// External subtitle files the user imported via the Files picker.
/// Stored per content (`<playlistId>_<type>_<streamId>`) under Application
/// Support/ImportedSubtitles and re-added to mpv whenever the same content is played again.
/// Downloaded content plays with the same identity triple, so no extra mapping is needed.
enum ImportedSubtitleStore {
    private static let selectionKey = "importedSubtitles.selectedFile.v1"

    static func contentKey(playlistId: UUID, type: String, streamId: String) -> String {
        sanitize("\(playlistId.uuidString)_\(type)_\(streamId)")
    }

    static func subtitleFiles(for contentKey: String) -> [URL] {
        guard let dir = try? directory(for: contentKey, create: false) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Copies the file picked in the document picker into the content folder; overwrites on name collision.
    static func importFile(at pickedURL: URL, for contentKey: String) throws -> URL {
        let accessed = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessed { pickedURL.stopAccessingSecurityScopedResource() } }
        let dir = try directory(for: contentKey, create: true)
        let destination = dir.appendingPathComponent(pickedURL.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: pickedURL, to: destination)
        return destination
    }

    static func removeFile(_ url: URL, for contentKey: String) {
        try? FileManager.default.removeItem(at: url)
        if selectedFileName(for: contentKey) == url.lastPathComponent {
            setSelectedFileName(nil, for: contentKey)
        }
    }

    /// File name of the external subtitle last selected for this content; used to auto-select on resume.
    static func selectedFileName(for contentKey: String) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String]
        return map?[contentKey]
    }

    static func setSelectedFileName(_ name: String?, for contentKey: String) {
        var map = (UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String]) ?? [:]
        if map[contentKey] == name { return }
        map[contentKey] = name
        UserDefaults.standard.set(map, forKey: selectionKey)
    }

    private static func directory(for contentKey: String, create: Bool) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let dir = appSupport
            .appendingPathComponent("ImportedSubtitles", isDirectory: true)
            .appendingPathComponent(contentKey, isDirectory: true)
        if create, !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func sanitize(_ raw: String) -> String {
        String(raw.map { ch in
            (ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == ".") ? ch : "_"
        })
    }
}
