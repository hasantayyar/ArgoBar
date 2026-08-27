import Foundation

enum ArgoCDClientError: LocalizedError {
    case unauthorized
    case notFound(String)
    case network(Error)
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized: token expired or invalid."
        case .notFound(let name):
            return "Application '\(name)' not found."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from ArgoCD server."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

struct WorkloadImage: Equatable {
    let name: String
    let tag: String
}

struct ArgoCDApplication: Decodable {
    struct Metadata: Decodable {
        let name: String
    }

    struct Destination: Decodable {
        let namespace: String?
        let name: String?
        let server: String?
    }

    struct Spec: Decodable {
        let destination: Destination
        let project: String?
    }

    struct ResourceRef: Decodable {
        let group: String?
        let version: String?
        let kind: String?
        let namespace: String?
        let name: String?
    }

    struct SyncStatus: Decodable {
        let status: String?
    }

    struct HealthStatus: Decodable {
        let status: String?
    }

    struct ApplicationStatusPayload: Decodable {
        let sync: SyncStatus?
        let health: HealthStatus?
        let reconciledAt: String?
        let operationState: OperationState?
        let resources: [ResourceRef]?
    }

    struct OperationState: Decodable {
        let finishedAt: String?
        let phase: String?
    }

    let metadata: Metadata
    let spec: Spec
    let status: ApplicationStatusPayload?

    var firstWorkloadResource: ResourceRef? {
        status?.resources?.first { resource in
            resource.kind == "Rollout" || resource.kind == "Deployment"
        }
    }

    func toAppStatus(
        endpoint: ArgoCDEndpoint,
        project: String,
        primaryImage: WorkloadImage? = nil
    ) -> AppStatus {
        let cluster = spec.destination.name ?? spec.destination.server ?? "unknown"
        let namespace = spec.destination.namespace ?? "-"
        let argoProject = spec.project ?? project
        return AppStatus(
            name: metadata.name,
            endpointID: endpoint.id,
            endpointName: endpoint.name,
            serverHost: endpoint.serverHost,
            project: argoProject,
            syncStatus: status?.sync?.status ?? "Unknown",
            healthStatus: status?.health?.status ?? "Unknown",
            destination: "\(cluster)/\(namespace)",
            destinationNamespace: namespace,
            lastSyncedAt: Self.parseSyncDate(from: status),
            primaryImageName: primaryImage?.name,
            primaryImageTag: primaryImage?.tag
        )
    }

    private static func parseSyncDate(from status: ApplicationStatusPayload?) -> Date? {
        let candidates = [
            status?.operationState?.finishedAt,
            status?.reconciledAt,
        ]
        for candidate in candidates {
            if let candidate, let date = parseISO8601(candidate) {
                return date
            }
        }
        return nil
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct ApplicationListResponse: Decodable {
    let items: [ArgoCDApplication]?
}

private struct ResourceManifestResponse: Decodable {
    let manifest: String
}

private struct KubernetesManifest: Decodable {
    struct PodTemplate: Decodable {
        struct PodSpec: Decodable {
            struct Container: Decodable {
                let name: String?
                let image: String?
            }

            let containers: [Container]?
        }

        let spec: PodSpec?
    }

    struct Spec: Decodable {
        let template: PodTemplate?
    }

    let spec: Spec?
}

struct ProjectListResponse: Decodable {
    struct Item: Decodable {
        struct Metadata: Decodable {
            let name: String
        }

        let metadata: Metadata
    }

    let items: [Item]?
}

struct ArgoCDClient {
    let baseURL: URL
    let tokenReader: TokenReader
    let session: URLSession

    private static let ignoredContainerNames = [
        "istio-proxy",
        "istio-init",
        "proxyv2",
        "envoy",
    ]

    init(baseURL: URL, tokenReader: TokenReader = TokenReader(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenReader = tokenReader
        self.session = session
    }

    private var serverHost: String {
        baseURL.host() ?? baseURL.absoluteString
    }

    func listApplicationStatuses(
        inProject project: String,
        endpoint: ArgoCDEndpoint
    ) async throws -> [AppStatus] {
        let token = try tokenReader.readToken(forServer: serverHost)
        var components = URLComponents(
            url: baseURL.appending(path: "api/v1/applications"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "projects", value: project)]

        return try await fetchApplicationStatuses(
            url: components.url,
            token: token,
            endpoint: endpoint,
            project: project
        )
    }

    func listAllApplicationStatuses(endpoint: ArgoCDEndpoint) async throws -> [AppStatus] {
        let token = try tokenReader.readToken(forServer: serverHost)
        let url = baseURL.appending(path: "api/v1/applications")
        return try await fetchApplicationStatuses(
            url: url,
            token: token,
            endpoint: endpoint,
            project: "*"
        )
    }

    func listProjects() async throws -> [String] {
        let token = try tokenReader.readToken(forServer: serverHost)
        let url = baseURL.appending(path: "api/v1/projects")
        let data = try await performRequest(url: url, token: token)
        let response = try JSONDecoder().decode(ProjectListResponse.self, from: data)
        let names = (response.items ?? []).map(\.metadata.name)
        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func fetchApplicationStatuses(
        url: URL?,
        token: String,
        endpoint: ArgoCDEndpoint,
        project: String
    ) async throws -> [AppStatus] {
        guard let url else {
            throw ArgoCDClientError.invalidResponse
        }

        let data = try await performRequest(url: url, token: token)
        let response = try JSONDecoder().decode(ApplicationListResponse.self, from: data)
        let applications = response.items ?? []

        var results: [AppStatus] = []
        results.reserveCapacity(applications.count)

        await withTaskGroup(of: AppStatus.self) { group in
            for application in applications {
                group.addTask {
                    await self.enrichedStatus(
                        for: application,
                        endpoint: endpoint,
                        project: application.spec.project ?? project,
                        token: token
                    )
                }
            }

            for await status in group {
                results.append(status)
            }
        }

        return results.sorted {
            if $0.project != $1.project {
                return $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func listApplicationNames(inProject project: String, endpoint: ArgoCDEndpoint) async throws -> [String] {
        try await listApplicationStatuses(inProject: project, endpoint: endpoint).map(\.name)
    }

    func testConnection(project: String, endpoint: ArgoCDEndpoint) async throws {
        _ = try await listApplicationNames(inProject: project, endpoint: endpoint)
    }

    private func enrichedStatus(
        for application: ArgoCDApplication,
        endpoint: ArgoCDEndpoint,
        project: String,
        token: String
    ) async -> AppStatus {
        guard let workload = application.firstWorkloadResource else {
            return application.toAppStatus(endpoint: endpoint, project: project)
        }

        let image = try? await fetchPrimaryWorkloadImage(
            appName: application.metadata.name,
            resource: workload,
            token: token
        )
        return application.toAppStatus(
            endpoint: endpoint,
            project: project,
            primaryImage: image
        )
    }

    private func fetchPrimaryWorkloadImage(
        appName: String,
        resource: ArgoCDApplication.ResourceRef,
        token: String
    ) async throws -> WorkloadImage? {
        guard let kind = resource.kind,
              let resourceName = resource.name,
              let namespace = resource.namespace else {
            return nil
        }

        var components = URLComponents(
            url: baseURL.appending(path: "api/v1/applications/\(appName)/resource"),
            resolvingAgainstBaseURL: false
        )!

        var queryItems = [
            URLQueryItem(name: "namespace", value: namespace),
            URLQueryItem(name: "resourceName", value: resourceName),
            URLQueryItem(name: "kind", value: kind),
        ]

        if let version = resource.version {
            queryItems.append(URLQueryItem(name: "version", value: version))
        }
        if let group = resource.group {
            queryItems.append(URLQueryItem(name: "group", value: group))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ArgoCDClientError.invalidResponse
        }

        let data = try await performRequest(url: url, token: token)
        let response = try JSONDecoder().decode(ResourceManifestResponse.self, from: data)
        guard let manifestData = response.manifest.data(using: .utf8) else {
            throw ArgoCDClientError.invalidResponse
        }

        let manifest = try JSONDecoder().decode(KubernetesManifest.self, from: manifestData)
        guard let containers = manifest.spec?.template?.spec?.containers else {
            return nil
        }

        guard let container = primaryContainer(in: containers) else {
            return nil
        }

        return parseWorkloadImage(containerName: container.name, image: container.image)
    }

    private func primaryContainer(in containers: [KubernetesManifest.PodTemplate.PodSpec.Container]) -> KubernetesManifest.PodTemplate.PodSpec.Container? {
        containers.first { container in
            guard let name = container.name?.lowercased() else { return true }
            return !Self.ignoredContainerNames.contains { ignored in
                name.contains(ignored)
            }
        }
    }

    private func parseWorkloadImage(containerName: String?, image: String?) -> WorkloadImage? {
        guard let image, !image.isEmpty else { return nil }

        guard let colonIndex = image.lastIndex(of: ":") else {
            let name = containerName ?? image
            return WorkloadImage(name: name, tag: "latest")
        }

        let tag = String(image[image.index(after: colonIndex)...])
        guard !tag.contains("/") else { return nil }

        let repositoryPath = String(image[..<colonIndex])
        let repositoryName: String
        if let slashIndex = repositoryPath.lastIndex(of: "/") {
            repositoryName = String(repositoryPath[repositoryPath.index(after: slashIndex)...])
        } else {
            repositoryName = repositoryPath
        }

        let name = containerName ?? repositoryName
        return WorkloadImage(name: name, tag: tag)
    }

    private func performRequest(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ArgoCDClientError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ArgoCDClientError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw ArgoCDClientError.unauthorized
        case 404:
            throw ArgoCDClientError.notFound(url.lastPathComponent)
        default:
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArgoCDClientError.serverError(http.statusCode, body)
        }
    }
}
