import Foundation

/// İndirilen medya dosyaları için cihaz üzerinde path yönetir.
/// Application Support/Downloads altında tutulur — Caches gibi iOS tarafından silinmez,
/// iCloud backup dışına alınır (medya dosyaları büyük).
/// Pure FileManager namespace — used from URLSession delegate/background contexts.
/// Deleting media and asking for the free space are slow enough to be felt; those
/// three functions assert that they are not called on the main thread.
nonisolated enum DownloadStorage {
    /// Downloads kök dizini. Uygulama güncellemelerinde korunur.
    static func rootDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("Downloads", isDirectory: true)
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try markExcludedFromBackup(root)
        }
        return root
    }

    /// Belirli bir item için hedef relative path döner (DB'de saklanır).
    /// Biçim: `<playlistId>/<type>/<streamId>.<ext>`
    static func relativePath(playlistId: UUID, type: String, streamId: String, ext: String) -> String {
        let safeExt = ext.isEmpty ? "mp4" : ext
        let safeStream = streamId.replacingOccurrences(of: "/", with: "_")
        return "\(playlistId.uuidString)/\(type)/\(safeStream).\(safeExt)"
    }

    /// DB'deki `localPath`'i absolute URL'e çevirir.
    static func absoluteURL(forRelativePath relativePath: String) throws -> URL {
        try rootDirectory().appendingPathComponent(relativePath)
    }

    /// Hedef dosyanın parent klasörünü oluşturur.
    static func ensureParentDirectory(for relativePath: String) throws -> URL {
        let fullURL = try absoluteURL(forRelativePath: relativePath)
        let parent = fullURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        return fullURL
    }

    /// Bir dosyayı iCloud backup dışında tutar.
    private static func markExcludedFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(resourceValues)
    }

    /// Playlist silinince tüm dosyalarını diskten siler.
    static func removePlaylistDirectory(playlistId: UUID) {
        assert(!Thread.isMainThread, "deleting downloads blocks the calling thread")
        guard let root = try? rootDirectory() else { return }
        let dir = root.appendingPathComponent(playlistId.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Tek bir dosyayı siler.
    static func removeFile(relativePath: String) {
        assert(!Thread.isMainThread, "deleting downloads blocks the calling thread")
        guard let url = try? absoluteURL(forRelativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Önemli kullanım için kullanılabilir disk kapasitesi (iOS gerekirse purgeable
    /// alanı da hesaba katar); okunamazsa nil.
    static func availableCapacityBytes() -> Int64? {
        assert(!Thread.isMainThread, "the purgeable-space query blocks the calling thread")
        guard let root = try? rootDirectory(),
              let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Resume data

    /// Directory holding URLSession resume-data blobs for interrupted downloads.
    /// Lives under the (backup-excluded) downloads root so blobs survive relaunches.
    private static func resumeDataDirectory() throws -> URL {
        let dir = try rootDirectory().appendingPathComponent(".resume", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func resumeDataURL(forId id: String) throws -> URL {
        let safeId = id.replacingOccurrences(of: "/", with: "_")
        return try resumeDataDirectory()
            .appendingPathComponent(safeId)
            .appendingPathExtension("resume")
    }

    static func saveResumeData(_ data: Data, forId id: String) {
        guard let url = try? resumeDataURL(forId: id) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadResumeData(forId id: String) -> Data? {
        guard let url = try? resumeDataURL(forId: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func hasResumeData(forId id: String) -> Bool {
        guard let url = try? resumeDataURL(forId: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func removeResumeData(forId id: String) {
        guard let url = try? resumeDataURL(forId: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes all resume blobs belonging to a playlist (item ids embed the playlist UUID).
    static func removeResumeData(playlistId: UUID) {
        guard let dir = try? resumeDataDirectory() else { return }
        let needle = playlistId.uuidString
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.contains(needle) {
            try? fm.removeItem(at: file)
        }
    }

    static func removeAllResumeData() {
        guard let dir = try? resumeDataDirectory() else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Storage stats

    /// Belirtilen klasör altındaki tüm dosyaların toplam bayt boyutunu döner.
    /// Klasör yoksa 0.
    private static func usedBytes(at directory: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path),
              let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Tüm indirilmiş/kısmi medya dosyalarının toplam bayt boyutu.
    static func totalUsedBytes() -> Int64 {
        guard let root = try? rootDirectory() else { return 0 }
        return usedBytes(at: root)
    }

    /// Belirli bir playlist'e ait dosyaların toplam bayt boyutu.
    static func usedBytes(playlistId: UUID) -> Int64 {
        guard let root = try? rootDirectory() else { return 0 }
        let dir = root.appendingPathComponent(playlistId.uuidString, isDirectory: true)
        return usedBytes(at: dir)
    }
}
