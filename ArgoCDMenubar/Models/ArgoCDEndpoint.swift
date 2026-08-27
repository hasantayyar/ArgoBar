import Foundation

struct WatchGroup: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var project: String
    var allProjects: Bool
    var destinationNamespace: String
    var watchAllApps: Bool
    var watchedAppNames: [String]

    init(
        id: UUID = UUID(),
        project: String = "default",
        allProjects: Bool = false,
        destinationNamespace: String = "",
        watchAllApps: Bool = true,
        watchedAppNames: [String] = []
    ) {
        self.id = id
        self.project = project
        self.allProjects = allProjects
        self.destinationNamespace = destinationNamespace
        self.watchAllApps = watchAllApps
        self.watchedAppNames = watchedAppNames
    }

    var trimmedNamespace: String? {
        let value = destinationNamespace.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Namespace filters span ArgoCD projects, so fetch all apps when set.
    var usesAllProjectsFetch: Bool {
        allProjects || trimmedNamespace != nil
    }
}

struct ArgoCDEndpoint: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var serverHost: String
    var isEnabled: Bool
    var watchGroups: [WatchGroup]

    init(
        id: UUID = UUID(),
        name: String,
        serverHost: String,
        isEnabled: Bool = true,
        watchGroups: [WatchGroup] = []
    ) {
        self.id = id
        self.name = name
        self.serverHost = serverHost
        self.isEnabled = isEnabled
        self.watchGroups = watchGroups
    }

    var baseURL: URL {
        URL(string: "https://\(serverHost)")!
    }

    var loginCommand: String {
        "argocd login \(serverHost)"
    }

    func applicationURL(for appName: String) -> URL {
        baseURL.appending(path: "applications/\(appName)")
    }

    static func placeholder() -> ArgoCDEndpoint {
        ArgoCDEndpoint(
            name: "ArgoCD",
            serverHost: "",
            watchGroups: [
                WatchGroup(project: "default"),
            ]
        )
    }
}
