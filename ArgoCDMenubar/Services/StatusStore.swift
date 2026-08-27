import Foundation
import Observation

@Observable
@MainActor
final class StatusStore {
    var sections: [AppSection] = []
    var isLoading = false
    var lastRefresh: Date?
    var errorMessage: String?
    private(set) var hasCompletedInitialRefresh = false

    var isInitialLoad: Bool {
        !hasCompletedInitialRefresh || lastRefresh == nil
    }

    var loadingStatusMessage: String {
        if isInitialLoad {
            return "Fetching applications from ArgoCD…"
        }
        return "Refreshing applications…"
    }

    var totalAppCount: Int {
        sections.reduce(0) { $0 + $1.totalApps }
    }

    var hasAnyAuthentication: Bool {
        sections.contains(where: \.isAuthenticated)
    }

    var unauthenticatedSections: [AppSection] {
        sections.filter { !$0.isAuthenticated }
    }

    var aggregateStatus: AggregateStatus {
        let enabled = settings.enabledEndpoints
        if enabled.isEmpty {
            return .unknown
        }
        if !hasAnyAuthentication {
            return .unauthenticated
        }
        if errorMessage != nil && totalAppCount == 0 {
            return .error
        }
        if totalAppCount == 0 {
            return .unknown
        }

        let allApps = sections.flatMap(\.apps).filter { !$0.isSectionErrorRow }
        if allApps.contains(where: \.hasError) {
            return .error
        }
        if allApps.contains(where: \.hasWarning) {
            return .warning
        }
        if allApps.allSatisfy(\.isHealthy) {
            return .healthy
        }
        return .unknown
    }

    private let settings: AppSettings
    private let tokenReader: TokenReader
    private var pollTask: Task<Void, Never>?
    private var isRefreshing = false

    init(settings: AppSettings, tokenReader: TokenReader = TokenReader()) {
        self.settings = settings
        self.tokenReader = tokenReader
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        defer {
            isLoading = false
            isRefreshing = false
        }

        let enabledEndpoints = settings.enabledEndpoints
        guard !enabledEndpoints.isEmpty else {
            sections = []
            errorMessage = "No endpoints enabled. Add one in Settings."
            return
        }

        if totalAppCount == 0 || lastRefresh == nil {
            sections = placeholderSections(for: enabledEndpoints)
        }

        var fetchedSections: [AppSection] = []

        await withTaskGroup(of: AppSection.self) { group in
            for endpoint in enabledEndpoints {
                group.addTask {
                    await self.fetchSection(for: endpoint)
                }
            }

            for await section in group {
                fetchedSections.append(section)
            }
        }

        fetchedSections.sort { lhs, rhs in
            let leftIndex = enabledEndpoints.firstIndex { $0.id == lhs.id } ?? Int.max
            let rightIndex = enabledEndpoints.firstIndex { $0.id == rhs.id } ?? Int.max
            return leftIndex < rightIndex
        }

        sections = fetchedSections
        lastRefresh = Date()
        hasCompletedInitialRefresh = true

        if totalAppCount == 0 && !hasAnyAuthentication {
            errorMessage = "Login required for all endpoints. Open Settings for login commands."
        } else if totalAppCount == 0 {
            let hints = fetchedSections.compactMap(\.emptyMessage)
            errorMessage = hints.isEmpty
                ? "No applications found. Check project names in Settings."
                : hints.joined(separator: "\n")
        } else {
            errorMessage = nil
        }
    }

    func discoverApps(endpoint: ArgoCDEndpoint, group: WatchGroup) async throws -> [String] {
        let client = ArgoCDClient(baseURL: endpoint.baseURL, tokenReader: tokenReader)
        let apps: [AppStatus]
        if group.usesAllProjectsFetch {
            apps = try await client.listAllApplicationStatuses(endpoint: endpoint)
        } else {
            apps = try await client.listApplicationStatuses(
                inProject: group.project,
                endpoint: endpoint
            )
        }
        return applyWatchGroupFilters(apps, using: group, forDiscovery: true).map(\.name)
    }

    func discoverProjects(endpoint: ArgoCDEndpoint) async throws -> [String] {
        let client = ArgoCDClient(baseURL: endpoint.baseURL, tokenReader: tokenReader)
        return try await client.listProjects()
    }

    func testConnection(endpoint: ArgoCDEndpoint, group: WatchGroup) async throws {
        let client = ArgoCDClient(baseURL: endpoint.baseURL, tokenReader: tokenReader)
        if group.usesAllProjectsFetch {
            _ = try await client.listAllApplicationStatuses(endpoint: endpoint)
        } else {
            let project = group.project.trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else {
                throw ArgoCDClientError.invalidResponse
            }
            try await client.testConnection(project: project, endpoint: endpoint)
        }
    }

    func isAuthenticated(for endpoint: ArgoCDEndpoint) -> Bool {
        guard !endpoint.serverHost.isEmpty else { return false }
        return tokenReader.hasValidToken(forServer: endpoint.serverHost)
    }

    func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                let interval = max(30, settings.pollIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func placeholderSections(for endpoints: [ArgoCDEndpoint]) -> [AppSection] {
        endpoints.map { endpoint in
            AppSection(
                id: endpoint.id,
                endpointName: endpoint.name,
                serverHost: endpoint.serverHost,
                loginCommand: endpoint.loginCommand,
                isAuthenticated: tokenReader.hasValidToken(forServer: endpoint.serverHost),
                apps: [],
                emptyMessage: nil
            )
        }
    }

    private func fetchSection(for endpoint: ArgoCDEndpoint) async -> AppSection {
        let baseSection = AppSection(
            id: endpoint.id,
            endpointName: endpoint.name,
            serverHost: endpoint.serverHost,
            loginCommand: endpoint.loginCommand,
            isAuthenticated: false,
            apps: [],
            emptyMessage: nil
        )

        guard !endpoint.serverHost.trimmingCharacters(in: .whitespaces).isEmpty else {
            return AppSection(
                id: baseSection.id,
                endpointName: baseSection.endpointName,
                serverHost: baseSection.serverHost,
                loginCommand: baseSection.loginCommand,
                isAuthenticated: false,
                apps: [],
                emptyMessage: "\(endpoint.name): server host is empty."
            )
        }

        guard tokenReader.hasValidToken(forServer: endpoint.serverHost) else {
            return AppSection(
                id: baseSection.id,
                endpointName: baseSection.endpointName,
                serverHost: baseSection.serverHost,
                loginCommand: baseSection.loginCommand,
                isAuthenticated: false,
                apps: [],
                emptyMessage: "\(endpoint.name): login required."
            )
        }

        let client = ArgoCDClient(baseURL: endpoint.baseURL, tokenReader: tokenReader)
        var apps: [AppStatus] = []
        var emptyMessages: [String] = []

        for group in endpoint.watchGroups {
            if group.usesAllProjectsFetch {
                do {
                    let fetched = try await client.listAllApplicationStatuses(endpoint: endpoint)
                    let filtered = applyWatchGroupFilters(fetched, using: group)
                    apps.append(contentsOf: filtered)
                    if filtered.isEmpty {
                        emptyMessages.append(emptyMessage(for: endpoint, group: group, fetchedCount: fetched.count))
                    }
                } catch let error as ArgoCDClientError {
                    apps.append(errorAppStatus(for: endpoint, project: groupLabel(group), error: error))
                } catch {
                    apps.append(errorAppStatus(for: endpoint, project: groupLabel(group), error: error))
                }
                continue
            }

            let project = group.project.trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else {
                emptyMessages.append("\(endpoint.name): watch group has no project name.")
                continue
            }

            do {
                let fetched = try await client.listApplicationStatuses(
                    inProject: project,
                    endpoint: endpoint
                )
                let filtered = applyWatchGroupFilters(fetched, using: group)
                apps.append(contentsOf: filtered)

                if filtered.isEmpty {
                    emptyMessages.append(emptyMessage(for: endpoint, group: group, fetchedCount: fetched.count))
                }
            } catch let error as ArgoCDClientError {
                apps.append(errorAppStatus(for: endpoint, project: project, error: error))
            } catch {
                apps.append(errorAppStatus(for: endpoint, project: project, error: error))
            }
        }

        apps.sort {
            if $0.project != $1.project {
                return $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let realApps = apps.filter { !$0.isSectionErrorRow }

        return AppSection(
            id: endpoint.id,
            endpointName: endpoint.name,
            serverHost: endpoint.serverHost,
            loginCommand: endpoint.loginCommand,
            isAuthenticated: true,
            apps: apps,
            emptyMessage: realApps.isEmpty ? emptyMessages.joined(separator: "\n") : nil
        )
    }

    private func errorAppStatus(
        for endpoint: ArgoCDEndpoint,
        project: String,
        error: Error
    ) -> AppStatus {
        AppStatus(
            name: AppStatus.sectionErrorName,
            endpointID: endpoint.id,
            endpointName: endpoint.name,
            serverHost: endpoint.serverHost,
            project: project,
            syncStatus: "Unknown",
            healthStatus: "Unknown",
            destination: "-",
            errorMessage: error.localizedDescription
        )
    }

    private func groupLabel(_ group: WatchGroup) -> String {
        if let namespace = group.trimmedNamespace {
            return "ns:\(namespace)"
        }
        if group.allProjects {
            return "all"
        }
        return group.project
    }

    private func emptyMessage(
        for endpoint: ArgoCDEndpoint,
        group: WatchGroup,
        fetchedCount: Int
    ) -> String {
        if let namespace = group.trimmedNamespace {
            if !group.watchAllApps, group.watchedAppNames.isEmpty {
                return "\(endpoint.name): no apps selected in namespace '\(namespace)'. Use Discover apps or add by name."
            }
            if !group.watchAllApps, !group.watchedAppNames.isEmpty {
                return "\(endpoint.name): selected apps not found in namespace '\(namespace)'."
            }
            if fetchedCount == 0 {
                return "\(endpoint.name): no applications deploy to namespace '\(namespace)'."
            }
        }

        if !group.watchAllApps, group.watchedAppNames.isEmpty {
            return "\(endpoint.name): no apps selected. Turn on Show all apps, or discover/add specific apps."
        }

        if !group.watchAllApps, !group.watchedAppNames.isEmpty {
            return "\(endpoint.name): none of the selected apps were found."
        }

        let project = group.project
        return "\(endpoint.name): no applications matched project '\(project)'."
    }

    private func applyWatchGroupFilters(
        _ apps: [AppStatus],
        using group: WatchGroup,
        forDiscovery: Bool = false
    ) -> [AppStatus] {
        var result = apps

        if let namespace = group.trimmedNamespace {
            result = result.filter { $0.destinationNamespace == namespace }
        }

        if group.watchAllApps || forDiscovery {
            return result
        }

        guard !group.watchedAppNames.isEmpty else {
            return []
        }

        let watched = Set(group.watchedAppNames)
        return result.filter { watched.contains($0.name) }
    }
}
