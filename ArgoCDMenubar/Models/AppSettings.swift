import Foundation
import Observation
import SwiftUI

@Observable
final class AppSettings {
    var endpoints: [ArgoCDEndpoint] {
        didSet { saveEndpoints() }
    }

    var pollIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(pollIntervalSeconds, forKey: Keys.pollIntervalSeconds) }
    }

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
            Self.persistEndpoints(migrated, to: defaults)
        } else {
            endpoints = [ArgoCDEndpoint.placeholder()]
            Self.persistEndpoints(endpoints, to: defaults)
        }
    }

    func addEndpoint() {
        let endpoint = ArgoCDEndpoint(
            name: "New Endpoint",
            serverHost: "",
            watchGroups: [WatchGroup(project: "default")]
        )
        endpoints.append(endpoint)
    }

    func removeEndpoint(id: UUID) {
        endpoints.removeAll { $0.id == id }
        if endpoints.isEmpty {
            endpoints = [ArgoCDEndpoint.placeholder()]
        }
    }

    func updateEndpoint(_ endpoint: ArgoCDEndpoint) {
        guard let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) else { return }
        endpoints[index] = endpoint
    }

    func addWatchGroup(to endpointID: UUID) {
        guard let index = endpoints.firstIndex(where: { $0.id == endpointID }) else { return }
        endpoints[index].watchGroups.append(WatchGroup(project: "default"))
    }

    func removeWatchGroup(endpointID: UUID, groupID: UUID) {
        guard let index = endpoints.firstIndex(where: { $0.id == endpointID }) else { return }
        endpoints[index].watchGroups.removeAll { $0.id == groupID }
        if endpoints[index].watchGroups.isEmpty {
            endpoints[index].watchGroups = [WatchGroup(project: "default")]
        }
    }

    private func saveEndpoints() {
        Self.persistEndpoints(endpoints, to: UserDefaults.standard)
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
