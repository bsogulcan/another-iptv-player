import Foundation

enum AdultContentFilter {

    // MARK: - Keywords

    /// Kategori adında ayrı bir kelime olarak geçiyorsa yetişkin içerik sayılır.
    /// (Büyük/küçük harf duyarsız, noktalama/boşlukla çevrelenmiş token olarak eşleşir.)
    private static let adultTokens: Set<String> = [
        "XXX",
        "ADULT", "ADULTS",
        "PORN", "PORNO",
        "EROTIC", "EROTICA",
        "HENTAI",
        "NUDE", "NUDITY",
        "SEX",           // "Essex" gibi yanlış pozitifleri önlemek için token kontrolü yeterli
        "NSFW",
        "EXPLICIT",
        "X-RATED",
        "HARDCORE",
        "SOFTCORE",
        "PLAYBOY",
    ]

    /// Kategori adında herhangi bir yerde geçiyorsa yetişkin içerik sayılır.
    private static let adultSubstrings: [String] = [
        "18+",
        "18 +",
        "XVIDEOS",
        "XHAMSTER",
        "PORNHUB",
    ]

    // MARK: - Category Check

    /// Verilen kategori adının yetişkin içerik içerip içermediğini döner.
    static func isAdultCategoryName(_ name: String) -> Bool {
        let upper = name.uppercased()

        // Alfanümerik olmayan karakterlere göre böl, boş tokenları çıkar
        let tokens = upper.components(separatedBy: CharacterSet.alphanumerics.inverted)
                          .filter { !$0.isEmpty }
        if tokens.contains(where: { adultTokens.contains($0) }) {
            return true
        }

        // Özel karakterler içeren kalıplar (18+ gibi) substring olarak kontrol
        return adultSubstrings.contains(where: { upper.contains($0) })
    }

    // MARK: - Stream Checks

    /// Bir canlı yayının yetişkin içerik olup olmadığını döner.
    /// - `is_adult: 1` bayrağı varsa veya bulunduğu kategori yetişkin kategoriyse filtrele.
    static func isAdultLiveStream(_ stream: XtreamLiveStream, adultCategoryIds: Set<String>) -> Bool {
        if (stream.isAdult ?? 0) == 1 { return true }
        if let cid = stream.categoryId, adultCategoryIds.contains(cid) { return true }
        return false
    }

    /// Bir film (VOD) yayınının yetişkin içerik olup olmadığını döner.
    static func isAdultVODStream(_ stream: XtreamVODStream, adultCategoryIds: Set<String>) -> Bool {
        if (stream.isAdult ?? 0) == 1 { return true }
        if let cid = stream.categoryId, adultCategoryIds.contains(cid) { return true }
        return false
    }

    // MARK: - Helpers

    /// Kategori listesinden yetişkin kategorilerin ID'lerini çıkarır.
    static func adultCategoryIds(from categories: [XtreamCategory]) -> Set<String> {
        Set(categories.compactMap { cat in
            guard let name = cat.categoryName, isAdultCategoryName(name) else { return nil }
            return cat.categoryId
        })
    }
}
