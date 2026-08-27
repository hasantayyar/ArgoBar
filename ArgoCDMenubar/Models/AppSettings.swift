import Foundation
import Observation
import SwiftUI

@Observable
final class AppSettings {
    var endpoints: [ArgoCDEndpoint]
    var pollIntervalSeconds: Int

    var enabledEndpoints: [ArgoCDEndpoint] {
        endpoints.filter(\.isEnabled)
    }

    init() {
        let defaults = UserDefaults.standard
        pollIntervalSeconds = defaults.object(forKey: Keys.pollIntervalSeconds) as? Int ?? 60

        if let data = defaults.data(forKey: Keys.endpointsData),
           let decoded = try? JSONDecoder().decode([ArgoCDEndpoint].self, from: data),
           !decoded.isEmpty {
            endpoints = decoded
        } else if let migrated = Self.migrateLegacySettings(from: defaults) {
            endpoints = migrated
            Self.persist(endpoints: migrated, pollIntervalSeconds: pollIntervalSeconds, to: defaults)
        } else {
            endpoints = [ArgoCDEndpoint.placeholder()]
            Self.persist(
                endpoints: endpoints,
                pollIntervalSeconds: pollIntervalSeconds,
                to: defaults
            )
        }
    }

    func save() {
        Self.persist(
            endpoints: endpoints,
            pollIntervalSeconds: pollIntervalSeconds,
            to: UserDefaults.standard
        )
    }

    private static func persist(
        endpoints: [ArgoCDEndpoint],
        pollIntervalSeconds: Int,
        to defaults: UserDefaults
    ) {
        persistEndpoints(endpoints, to: defaults)
        defaults.set(pollIntervalSeconds, forKey: Keys.pollIntervalSeconds)
    }

    private static func persistEndpoints(_ endpoints: [ArgoCDEndpoint], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(endpoints) else { return }
        defaults.set(data, forKey: Keys.endpointsData)
    }

    private static func migrateLegacySettings(from defaults: UserDefaults) -> [ArgoCDEndpoint]? {
        let hasLegacy = defaults.string(forKey: LegacyKeys.serverHost) != nil
            || defaults.string(forKey: LegacyKeys.namespace) != nil
            || defaults.stringArray(forKey: LegacyKeys.watchedAppNames) != nil
        guard hasLegacy else { return nil }

        let serverHost = defaults.string(forKey: LegacyKeys.serverHost) ?? ""
        let project = defaults.string(forKey: LegacyKeys.namespace) ?? "default"
        let watchedAppNames = defaults.stringArray(forKey: LegacyKeys.watchedAppNames) ?? []
        let watchAllApps: Bool
        if defaults.object(forKey: LegacyKeys.watchAllAppsInProject) == nil {
            watchAllApps = true
        } else {
            watchAllApps = defaults.bool(forKey: LegacyKeys.watchAllAppsInProject)
        }

        return [
            ArgoCDEndpoint(
                name: "Default",
                serverHost: serverHost,
                watchGroups: [
                    WatchGroup(
                        project: project,
                        watchAllApps: watchAllApps,
                        watchedAppNames: watchedAppNames
                    ),
                ]
            ),
        ]
    }

    private enum Keys {
        static let endpointsData = "endpointsData"
        static let pollIntervalSeconds = "pollIntervalSeconds"
    }

    private enum LegacyKeys {
        static let serverHost = "serverHost"
        static let namespace = "namespace"
        static let watchedAppNames = "watchedAppNames"
        static let watchAllAppsInProject = "watchAllAppsInProject"
    }
}
