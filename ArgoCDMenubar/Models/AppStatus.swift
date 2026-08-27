import Foundation

struct AppStatus: Identifiable, Equatable {
    /// Internal sentinel for section-level fetch errors shown in the menu.
    static let sectionErrorName = "__section_error__"

    let id: String
    let name: String
    let endpointID: UUID
    let endpointName: String
    let serverHost: String
    let project: String
    let syncStatus: String
    let healthStatus: String
    let destination: String
    let destinationNamespace: String
    let lastSyncedAt: Date?
    let primaryImageName: String?
    let primaryImageTag: String?
    let lastUpdated: Date
    let errorMessage: String?

    init(
        name: String,
        endpointID: UUID,
        endpointName: String,
        serverHost: String,
        project: String,
        syncStatus: String,
        healthStatus: String,
        destination: String,
        destinationNamespace: String = "-",
        lastSyncedAt: Date? = nil,
        primaryImageName: String? = nil,
        primaryImageTag: String? = nil,
        lastUpdated: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = Self.makeID(endpointID: endpointID, project: project, name: name)
        self.name = name
        self.endpointID = endpointID
        self.endpointName = endpointName
        self.serverHost = serverHost
        self.project = project
        self.syncStatus = syncStatus
        self.healthStatus = healthStatus
        self.destination = destination
        self.destinationNamespace = destinationNamespace
        self.lastSyncedAt = lastSyncedAt
        self.primaryImageName = primaryImageName
        self.primaryImageTag = primaryImageTag
        self.lastUpdated = lastUpdated
        self.errorMessage = errorMessage
    }

    static func makeID(endpointID: UUID, project: String, name: String) -> String {
        "\(endpointID.uuidString)|\(project)|\(name)"
    }

    func applicationURL(baseURL: URL) -> URL {
        baseURL.appending(path: "applications/\(name)")
    }

    static func notFound(
        name: String,
        endpoint: ArgoCDEndpoint,
        project: String
    ) -> AppStatus {
        AppStatus(
            name: name,
            endpointID: endpoint.id,
            endpointName: endpoint.name,
            serverHost: endpoint.serverHost,
            project: project,
            syncStatus: "Unknown",
            healthStatus: "Unknown",
            destination: "-",
            destinationNamespace: "-",
            errorMessage: "Application not found"
        )
    }

    var lastSyncedLabel: String {
        guard let lastSyncedAt else { return "Never synced" }
        return Self.syncDateFormatter.string(from: lastSyncedAt)
    }

    var imageLabel: String {
        switch (primaryImageName, primaryImageTag) {
        case let (name?, tag?):
            return "\(name):\(tag)"
        case let (name?, nil):
            return name
        case let (nil, tag?):
            return tag
        default:
            return "n/a"
        }
    }

    var isSectionErrorRow: Bool {
        name == Self.sectionErrorName
    }

    var isHealthy: Bool {
        syncStatus == "Synced" && healthStatus == "Healthy"
    }

    var hasWarning: Bool {
        syncStatus == "OutOfSync" || healthStatus == "Progressing"
    }

    var hasError: Bool {
        errorMessage != nil ||
            healthStatus == "Degraded" ||
            healthStatus == "Missing" ||
            (healthStatus == "Unknown" && syncStatus == "Unknown")
    }

    private static let syncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

struct AppSection: Identifiable, Equatable {
    let id: UUID
    let endpointName: String
    let serverHost: String
    let loginCommand: String
    let isAuthenticated: Bool
    let apps: [AppStatus]
    let emptyMessage: String?

    var totalApps: Int { apps.filter { !$0.isSectionErrorRow }.count }
}

enum AggregateStatus {
    case unknown
    case healthy
    case warning
    case error
    case unauthenticated
}
