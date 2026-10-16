import Foundation

// MARK: - library.json 顶层结构（src/main/store/db.ts LibraryFile 的移植）
//
// { version, settings, comics, categories }

public let CURRENT_SCHEMA_VERSION = 5

public struct LibraryFile: Codable, Equatable, Sendable {
    public var version: Int
    public var settings: AppSettings
    public var comics: [Comic]
    public var categories: [ComicCategory]

    public init(
        version: Int = CURRENT_SCHEMA_VERSION,
        settings: AppSettings = .defaults,
        comics: [Comic] = [],
        categories: [ComicCategory] = []
    ) {
        self.version = version
        self.settings = settings
        self.comics = comics
        self.categories = categories
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? CURRENT_SCHEMA_VERSION
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .defaults
        comics = try c.decodeIfPresent([Comic].self, forKey: .comics) ?? []
        categories = try c.decodeIfPresent([ComicCategory].self, forKey: .categories) ?? []
    }
}
