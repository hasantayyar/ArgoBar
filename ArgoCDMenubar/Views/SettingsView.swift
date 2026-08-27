import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var store: StatusStore

    @State private var selectedEndpointID: UUID?
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let endpoint = selectedEndpoint {
                EndpointDetailView(
                    endpoint: endpoint,
                    settings: settings,
                    store: store,
                    statusMessage: $statusMessage,
                    statusIsError: $statusIsError
                )
            } else {
                ContentUnavailableView(
                    "Select an endpoint",
                    systemImage: "server.rack",
                    description: Text("Choose an ArgoCD server from the sidebar or add a new one.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .frame(minWidth: 680, minHeight: 580)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply & Refresh") {
                    applySettings()
                }
            }
        }
        .onAppear {
            if selectedEndpointID == nil {
                selectedEndpointID = settings.endpoints.first?.id
            }
        }
        .onChange(of: settings.endpoints) { _, endpoints in
            if let selectedEndpointID,
               !endpoints.contains(where: { $0.id == selectedEndpointID }) {
                self.selectedEndpointID = endpoints.first?.id
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedEndpointID) {
            Section("Endpoints") {
                ForEach(settings.endpoints) { endpoint in
                    EndpointSidebarRow(
                        endpoint: endpoint,
                        isAuthenticated: store.isAuthenticated(for: endpoint)
                    )
                    .tag(endpoint.id)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let id = settings.endpoints[index].id
                        settings.removeEndpoint(id: id)
                    }
                }
            }

            Section {
                Stepper(
                    "Refresh every \(settings.pollIntervalSeconds)s",
                    value: $settings.pollIntervalSeconds,
                    in: 30...300,
                    step: 15
                )
            } header: {
                Text("Polling")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ArgoCD")
        .toolbar {
            ToolbarItem {
                Button {
                    settings.addEndpoint()
                    selectedEndpointID = settings.endpoints.last?.id
                } label: {
                    Label("Add endpoint", systemImage: "plus")
                }
            }
        }
        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(statusIsError ? .red : .green)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var selectedEndpoint: ArgoCDEndpoint? {
        guard let selectedEndpointID else { return nil }
        return settings.endpoints.first { $0.id == selectedEndpointID }
    }

    private func applySettings() {
        store.startPolling()
        Task { await store.refresh() }
        statusMessage = "Settings applied."
        statusIsError = false
    }
}

private struct EndpointSidebarRow: View {
    let endpoint: ArgoCDEndpoint
    let isAuthenticated: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.name)
                    .lineLimit(1)
                if !endpoint.isEnabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusColor: Color {
        if !endpoint.isEnabled { return .secondary }
        return isAuthenticated ? .green : .red
    }
}

private struct EndpointDetailView: View {
    let endpoint: ArgoCDEndpoint
    @Bindable var settings: AppSettings
    @Bindable var store: StatusStore
    @Binding var statusMessage: String?
    @Binding var statusIsError: Bool

    @State private var draft: ArgoCDEndpoint
    @State private var isTesting = false

    init(
        endpoint: ArgoCDEndpoint,
        settings: AppSettings,
        store: StatusStore,
        statusMessage: Binding<String?>,
        statusIsError: Binding<Bool>
    ) {
        self.endpoint = endpoint
        self._settings = Bindable(settings)
        self._store = Bindable(store)
        self._statusMessage = statusMessage
        self._statusIsError = statusIsError
        _draft = State(initialValue: endpoint)
    }

    var body: some View {
        Form {
            Section("Server") {
                Toggle("Enabled", isOn: $draft.isEnabled)

                TextField("Display name", text: $draft.name)

                TextField("Server host", text: $draft.serverHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                LabeledContent("Login command") {
                    Text(draft.loginCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    authIndicator
                    Spacer()
                    Button("Copy login command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft.loginCommand, forType: .string)
                    }
                    Button("Test connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || draft.serverHost.isEmpty || draft.watchGroups.isEmpty)
                }
            }

            Section {
                ForEach($draft.watchGroups) { $group in
                    WatchGroupEditor(
                        group: $group,
                        endpoint: draft,
                        store: store,
                        onRemove: draft.watchGroups.count > 1 ? {
                            draft.watchGroups.removeAll { $0.id == group.id }
                        } : nil
                    )
                }

                Button {
                    draft.watchGroups.append(WatchGroup(project: "default"))
                } label: {
                    Label("Add watch group", systemImage: "plus.circle")
                }
            } header: {
                Text("Watch groups")
            } footer: {
                Text("ArgoCD project and Kubernetes destination namespace are different fields. Use the namespace field when you want to filter by destination namespace across projects.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.name)
        .onChange(of: endpoint) { _, newValue in
            draft = newValue
        }
        .onChange(of: draft) { _, newValue in
            settings.updateEndpoint(newValue)
        }
    }

    @ViewBuilder
    private var authIndicator: some View {
        if store.isAuthenticated(for: draft) {
            Label("Authenticated", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Label("Not authenticated", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func testConnection() async {
        isTesting = true
        statusMessage = nil
        defer { isTesting = false }

        guard let group = draft.watchGroups.first else {
            statusMessage = "Add a watch group first."
            statusIsError = true
            return
        }

        settings.updateEndpoint(draft)

        do {
            try await store.testConnection(endpoint: draft, group: group)
            statusMessage = "Connection to \(draft.name) successful."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}

private struct WatchGroupEditor: View {
    @Binding var group: WatchGroup
    let endpoint: ArgoCDEndpoint
    @Bindable var store: StatusStore
    let onRemove: (() -> Void)?

    @State private var newAppName = ""
    @State private var discoveredApps: [String] = []
    @State private var discoveredProjects: [String] = []
    @State private var discoverSearch = ""
    @State private var isDiscovering = false
    @State private var isDiscoveringProjects = false
    @State private var discoverMessage: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if group.allProjects || group.trimmedNamespace != nil {
                        Text(group.allProjects ? "All projects" : "All projects (namespace filter)")
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("ArgoCD project", text: $group.project)
                            .textFieldStyle(.roundedBorder)
                    }
                    if let onRemove {
                        Button(role: .destructive, action: onRemove) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove watch group")
                    }
                }

                HStack {
                    TextField("Destination namespace", text: $group.destinationNamespace)
                        .textFieldStyle(.roundedBorder)
                    if !group.destinationNamespace.isEmpty {
                        Button("Clear") {
                            group.destinationNamespace = ""
                        }
                    }
                }

                if group.trimmedNamespace != nil {
                    Text("Namespace filter searches all ArgoCD projects on the server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("All projects on server", isOn: $group.allProjects)
                    .disabled(group.trimmedNamespace != nil)
                    .onChange(of: group.allProjects) { _, enabled in
                        if enabled {
                            discoverMessage = nil
                        }
                    }

                if !group.allProjects, group.trimmedNamespace == nil {
                    HStack {
                        Button("Discover projects") {
                            Task { await discoverProjects() }
                        }
                        .disabled(isDiscoveringProjects)

                        if isDiscoveringProjects {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if !discoveredProjects.isEmpty {
                        Picker("Available projects", selection: $group.project) {
                            ForEach(discoveredProjects, id: \.self) { project in
                                Text(project).tag(project)
                            }
                        }
                    }
                }

                Toggle("Show all apps", isOn: $group.watchAllApps)

                if !group.watchAllApps {
                    watchedAppsList
                }

                HStack {
                    Button("Discover apps") {
                        Task { await discoverApps() }
                    }
                    .disabled(isDiscovering || !canDiscoverApps)

                    if isDiscovering {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let discoverMessage {
                    Text(discoverMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !discoveredApps.isEmpty, !group.watchAllApps {
                    discoverToggles
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text(groupLabel)
                .font(.headline)
        }
    }

    private var canDiscoverApps: Bool {
        group.usesAllProjectsFetch
            || !group.project.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var groupLabel: String {
        if let namespace = group.trimmedNamespace {
            return "namespace: \(namespace)"
        }
        if group.allProjects {
            return "All projects"
        }
        return group.project.isEmpty ? "New project" : group.project
    }

    private var filteredDiscoveredApps: [String] {
        let query = discoverSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return discoveredApps }
        return discoveredApps.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private var watchedAppsList: some View {
        if group.watchedAppNames.isEmpty {
            Text("No apps selected. Discover or add by name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(group.watchedAppNames, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Button(role: .destructive) {
                        group.watchedAppNames.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        HStack {
            TextField("App name", text: $newAppName)
                .onSubmit { addApp() }
            Button("Add") { addApp() }
                .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var discoverToggles: some View {
        Divider()
        HStack {
            Text("Discovered apps (\(discoveredApps.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        TextField("Search apps", text: $discoverSearch)
            .textFieldStyle(.roundedBorder)
        ForEach(filteredDiscoveredApps, id: \.self) { name in
            Toggle(
                name,
                isOn: Binding(
                    get: { group.watchedAppNames.contains(name) },
                    set: { enabled in
                        if enabled {
                            if !group.watchedAppNames.contains(name) {
                                group.watchedAppNames.append(name)
                            }
                        } else {
                            group.watchedAppNames.removeAll { $0 == name }
                        }
                    }
                )
            )
        }
        if filteredDiscoveredApps.isEmpty, !discoverSearch.isEmpty {
            Text("No apps match \"\(discoverSearch)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func addApp() {
        let name = newAppName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !group.watchedAppNames.contains(name) else { return }
        group.watchedAppNames.append(name)
        newAppName = ""
    }

    private func discoverApps() async {
        isDiscovering = true
        discoverMessage = nil
        defer { isDiscovering = false }

        if !group.allProjects, !group.usesAllProjectsFetch {
            let project = group.project.trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else { return }
        }

        do {
            discoveredApps = try await store.discoverApps(endpoint: endpoint, group: group)
            discoverSearch = ""
            discoverMessage = discoveredApps.isEmpty
                ? "No applications found."
                : "Found \(discoveredApps.count) applications."
        } catch {
            discoverMessage = error.localizedDescription
            discoveredApps = []
        }
    }

    private func discoverProjects() async {
        isDiscoveringProjects = true
        discoverMessage = nil
        defer { isDiscoveringProjects = false }

        do {
            discoveredProjects = try await store.discoverProjects(endpoint: endpoint)
            if discoveredProjects.isEmpty {
                discoverMessage = "No projects found."
            } else if !discoveredProjects.contains(group.project) {
                group.project = discoveredProjects[0]
                discoverMessage = "Found \(discoveredProjects.count) projects."
            } else {
                discoverMessage = "Found \(discoveredProjects.count) projects."
            }
        } catch {
            discoverMessage = error.localizedDescription
            discoveredProjects = []
        }
    }
}
