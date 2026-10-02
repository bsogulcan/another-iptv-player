import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The rules behind the TV-guide rows of the settings forms: what the "Last
/// updated" row says, and when the M3U guide URL field has something to save.
@Suite("EPG settings editing")
struct EPGSettingsEditingTests {

    private let english = Locale(identifier: "en")
    private let turkish = Locale(identifier: "tr")

    private func m3uPlaylist(header: String? = nil, override: String? = nil) -> Playlist {
        Playlist(
            name: "List", serverURL: "http://host/get.php?username=u&password=p",
            type: .m3u, m3uEpgURL: header, epgURLOverride: override
        )
    }

    // MARK: Last updated

    /// The row is redrawn once a minute, so it must not count seconds.
    @Test(arguments: [0.0, 20, 59])
    func firstMinuteReadsAsNow(secondsAgo: Double) {
        let date = Date().addingTimeInterval(-secondsAgo)
        #expect(EPGRefreshStatusView.lastUpdatedText(date, locale: english) == "now")
    }

    /// A timestamp slightly ahead of the device clock is not "in 3 seconds".
    @Test
    func aDateJustAheadOfTheClockReadsAsNow() {
        let date = Date().addingTimeInterval(3)
        #expect(EPGRefreshStatusView.lastUpdatedText(date, locale: english) == "now")
    }

    @Test
    func olderDatesUseWholeUnitsWithAgo() {
        let fiveMinutes = Date().addingTimeInterval(-5 * 60 - 5)
        #expect(EPGRefreshStatusView.lastUpdatedText(fiveMinutes, locale: english) == "5 minutes ago")

        let twoHours = Date().addingTimeInterval(-2 * 3600 - 60)
        #expect(EPGRefreshStatusView.lastUpdatedText(twoHours, locale: english) == "2 hours ago")
    }

    /// The value follows the language passed in (the app's), not the device's.
    @Test
    func textFollowsTheGivenLocale() {
        #expect(EPGRefreshStatusView.lastUpdatedText(Date(), locale: turkish) == "şimdi")
        let fiveMinutes = Date().addingTimeInterval(-5 * 60 - 5)
        #expect(EPGRefreshStatusView.lastUpdatedText(fiveMinutes, locale: turkish) == "5 dakika önce")
    }

    // MARK: Guide URL field

    @Test
    func theFieldShowsTheOverrideElseTheHeaderURL() {
        #expect(M3UEPGSettingsSection.storedURL(of: m3uPlaylist()) == "")
        #expect(M3UEPGSettingsSection.storedURL(of: m3uPlaylist(header: "http://h/epg.xml")) == "http://h/epg.xml")
        #expect(
            M3UEPGSettingsSection.storedURL(of: m3uPlaylist(header: "http://h/epg.xml", override: "http://o/epg.xml"))
                == "http://o/epg.xml"
        )
        // A blank override is no override.
        #expect(
            M3UEPGSettingsSection.storedURL(of: m3uPlaylist(header: "http://h/epg.xml", override: "  "))
                == "http://h/epg.xml"
        )
    }

    @Test
    func aBlankDraftStoresNoOverride() {
        #expect(M3UEPGSettingsSection.override(forDraft: "") == nil)
        #expect(M3UEPGSettingsSection.override(forDraft: " \n") == nil)
        #expect(M3UEPGSettingsSection.override(forDraft: "  http://o/epg.xml \n") == "http://o/epg.xml")
    }

    @Test
    func saveIsOfferedOnlyWhenTheEffectiveURLWouldChange() {
        let headerOnly = m3uPlaylist(header: "http://h/epg.xml")
        // The header URL shown in an untouched field is nothing to save.
        #expect(!M3UEPGSettingsSection.isDirty(draft: "http://h/epg.xml", playlist: headerOnly))
        #expect(!M3UEPGSettingsSection.isDirty(draft: " http://h/epg.xml\n", playlist: headerOnly))
        #expect(M3UEPGSettingsSection.isDirty(draft: "http://o/epg.xml", playlist: headerOnly))
        // Clearing the field is a change while a URL is in effect...
        #expect(M3UEPGSettingsSection.isDirty(draft: "", playlist: headerOnly))
        // ...and none when there is no URL at all.
        #expect(!M3UEPGSettingsSection.isDirty(draft: "", playlist: m3uPlaylist()))
        #expect(!M3UEPGSettingsSection.isDirty(draft: "   ", playlist: m3uPlaylist()))
    }

    /// Clearing the override of a playlist that has a header URL: the saved row
    /// shows the header URL again and leaves nothing to save, so the field does not
    /// stay empty with Save enabled. The save starts from the stored row, so a
    /// setting changed since the screen opened is kept.
    @Test
    func clearingTheOverrideFallsBackToTheHeaderURL() async throws {
        let database = AppDatabase.empty()
        let opened = m3uPlaylist(header: "http://h/epg.xml", override: "http://o/epg.xml")
        try await database.write { db in try opened.insert(db) }
        try await database.updatePlaylist(id: opened.id) { $0.filterAdultContent = true }

        let override = M3UEPGSettingsSection.override(forDraft: "")
        let saved = try #require(try await database.updatePlaylist(id: opened.id) { $0.epgURLOverride = override })

        #expect(saved.epgURLOverride == nil)
        #expect(saved.filterAdultContent)
        let shown = M3UEPGSettingsSection.storedURL(of: saved)
        #expect(shown == "http://h/epg.xml")
        #expect(!M3UEPGSettingsSection.isDirty(draft: shown, playlist: saved))
    }
}
