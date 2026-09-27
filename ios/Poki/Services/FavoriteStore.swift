import Foundation
import PokiCore

struct FavoriteStore {
    private let key = "favorite-configuration"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FavoriteConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FavoriteConfiguration.self, from: data)
    }

    func save(_ configuration: FavoriteConfiguration?) {
        guard let configuration,
              let data = try? JSONEncoder().encode(configuration) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

