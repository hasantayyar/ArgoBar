import SwiftUI
import AppKit

private enum MenuLayout {
    static let width: CGFloat = 400
    static let maxListHeight: CGFloat = 480
    static let rowHeight: CGFloat = 68
    static let sectionHeaderHeight: CGFloat = 28
}

struct MenuContentView: View {
    @Bindable var store: StatusStore
    @Bindable var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var filterQuery = ""
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentSection
            Divider()
            actionsSection
        }
        .frame(width: MenuLayout.width)
    }

    @ViewBuilder
    private var contentSection: some View {
        if settings.enabledEndpoints.isEmpty {
            emptyEndpointsSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if store.isLoading && shouldShowGlobalLoading {
            loadingSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if !store.hasAnyAuthentication && store.totalAppCount == 0 {
            loginSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if let error = store.errorMessage, store.totalAppCount == 0 {
            errorSection(error)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if store.totalAppCount == 0 {
            emptyResultsSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            appsSection
        }
    }

    private var shouldShowGlobalLoading: Bool {
        store.totalAppCount == 0 || store.isInitialLoad
    }

    @ViewBuilder
    private var loadingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(store.loadingStatusMessage)
                    .font(.subheadline)
            }

            Text("Querying \(settings.enabledEndpoints.count) endpoint\(settings.enabledEndpoints.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(settings.enabledEndpoints) { endpoint in
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(endpoint.name)
                        .font(.caption)
                    Spacer()
                    Text(endpoint.serverHost)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyResultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No applications found.")
                .foregroundStyle(.secondary)
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Settings…") {
                openSettings()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var emptyEndpointsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No endpoints", systemImage: "server.rack")
                .font(.headline)
            Text("Add an ArgoCD server in Settings to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings…") {
                openSettings()
            }
        }
    }

    @ViewBuilder
    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Login required", systemImage: "lock.fill")
                .font(.headline)
            Text("Run in Terminal for each server:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(store.unauthenticatedSections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.endpointName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(section.loginCommand)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Button("Copy \(section.endpointName) login") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(section.loginCommand, forType: .string)
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            filterBar

            if store.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.loadingStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            if !store.unauthenticatedSections.isEmpty, !store.isLoading {
                partialAuthBanner
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    if filteredSections.isEmpty, !normalizedFilterQuery.isEmpty {
                        Text("No apps match \"\(normalizedFilterQuery)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(filteredSections) { entry in
                            sectionView(entry.section, apps: entry.apps, errorApps: entry.errorApps)
                        }
                    }
                }
            }
            .frame(height: listHeight)

            if let lastRefresh = store.lastRefresh {
                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .onAppear {
            if store.totalAppCount > 0, !store.isLoading {
                focusFilterField()
            }
        }
        .onChange(of: store.isLoading) { _, isLoading in
            if !isLoading, store.totalAppCount > 0 {
                focusFilterField()
            }
        }
        .onDisappear {
            filterQuery = ""
            isFilterFocused = false
        }
    }

    private func focusFilterField() {
        Task { @MainActor in
            // MenuBarExtra window may not be key yet on first appear.
            try? await Task.sleep(for: .milliseconds(100))
            isFilterFocused = true
        }
    }

    private struct FilteredSection: Identifiable {
        let section: AppSection
        let apps: [AppStatus]
        let errorApps: [AppStatus]

        var id: UUID { section.id }
    }

    private var normalizedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSections: [FilteredSection] {
        store.sections.filter(\.isAuthenticated).compactMap { section in
            let realApps = section.apps.filter { !$0.isSectionErrorRow }
            let errorApps = section.apps.filter(\.isSectionErrorRow)

            if normalizedFilterQuery.isEmpty {
                guard !realApps.isEmpty || !errorApps.isEmpty || section.emptyMessage != nil else {
                    return nil
                }
                return FilteredSection(section: section, apps: realApps, errorApps: errorApps)
            }

            let matchedApps = realApps
                .filter { app in
                    FuzzyFilter.matches(
                        query: normalizedFilterQuery,
                        fields: searchableFields(for: app)
                    )
                }
                .sorted { lhs, rhs in
                    let leftScore = FuzzyFilter.relevanceScore(
                        query: normalizedFilterQuery,
                        weightedFields: weightedFields(for: lhs)
                    )
                    let rightScore = FuzzyFilter.relevanceScore(
                        query: normalizedFilterQuery,
                        weightedFields: weightedFields(for: rhs)
                    )
                    if leftScore != rightScore {
                        return leftScore > rightScore
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

            guard !matchedApps.isEmpty else { return nil }
            return FilteredSection(section: section, apps: matchedApps, errorApps: [])
        }
    }

    private var filteredAppCount: Int {
        filteredSections.reduce(0) { $0 + $1.apps.count }
    }

    private func searchableFields(for app: AppStatus) -> [String] {
        [
            app.name,
            app.project,
            app.destinationNamespace,
            app.imageLabel,
        ]
    }

    private func weightedFields(for app: AppStatus) -> [(text: String, weight: Int)] {
        [
            (app.name, 4),
            (app.project, 2),
            (app.destinationNamespace, 2),
            (app.imageLabel, 1),
        ]
    }

    @ViewBuilder
    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField("Filter apps", text: $filterQuery)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($isFilterFocused)
                .onAppear {
                    focusFilterField()
                }

            if !filterQuery.isEmpty {
                Button {
                    filterQuery = ""
                    isFilterFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Group {
                if normalizedFilterQuery.isEmpty {
                    if store.isLoading {
                        Text("Refreshing…")
                    } else {
                        Text("\(store.totalAppCount) apps · \(store.sections.filter(\.isAuthenticated).count) servers")
                    }
                } else {
                    Text("\(filteredAppCount) of \(store.totalAppCount) apps")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var partialAuthBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.unauthenticatedSections) { section in
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("\(section.endpointName) needs login")
                        .font(.caption2)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(section.loginCommand, forType: .string)
                    }
                    .font(.caption2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection, apps: [AppStatus], errorApps: [AppStatus]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(section.endpointName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(apps.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: MenuLayout.sectionHeaderHeight)

            if store.isLoading && apps.isEmpty && section.isAuthenticated {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading applications…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else if apps.isEmpty, normalizedFilterQuery.isEmpty, !store.isLoading {
                VStack(alignment: .leading, spacing: 4) {
                    if let message = section.emptyMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No applications configured.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button("Open Settings…") {
                        openSettings()
                    }
                    .font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ForEach(apps) { app in
                    AppRowView(
                        app: app,
                        url: URL(string: "https://\(app.serverHost)")!.appending(path: "applications/\(app.name)")
                    )
                    Divider()
                        .padding(.leading, 12)
                }

                ForEach(errorApps) { app in
                    errorRow(app)
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func errorRow(_ app: AppStatus) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("Error in \(app.project)")
                    .font(.caption)
                    .fontWeight(.medium)
                if let error = app.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var listHeight: CGFloat {
        if !normalizedFilterQuery.isEmpty {
            return MenuLayout.maxListHeight
        }

        let authenticatedSections = store.sections.filter(\.isAuthenticated)
        let emptyRowHeight: CGFloat = 56
        let estimated = authenticatedSections.reduce(CGFloat(0)) { partial, section in
            if section.totalApps == 0 {
                return partial + emptyRowHeight
            }
            return partial + CGFloat(section.apps.count) * MenuLayout.rowHeight
        } + CGFloat(authenticatedSections.count) * MenuLayout.sectionHeaderHeight

        return min(max(estimated, MenuLayout.rowHeight), MenuLayout.maxListHeight)
    }

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: 0) {
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .disabled(store.isLoading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button("Settings…") {
                openSettings()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 4)
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AppRowView: View {
    let app: AppStatus
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(app.project) · \(app.destination)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Label(app.lastSyncedLabel, systemImage: "clock")
                        if app.primaryImageName != nil || app.primaryImageTag != nil {
                            Label(app.imageLabel, systemImage: "shippingbox")
                        } else {
                            Label("n/a", systemImage: "shippingbox")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if let error = app.errorMessage, !app.isSectionErrorRow {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    StatusBadge(text: app.syncStatus, kind: syncKind(app.syncStatus))
                    StatusBadge(text: app.healthStatus, kind: healthKind(app.healthStatus))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func syncKind(_ status: String) -> StatusBadge.Kind {
        switch status {
        case "Synced": return .good
        case "OutOfSync": return .warning
        default: return .neutral
        }
    }

    private func healthKind(_ status: String) -> StatusBadge.Kind {
        switch status {
        case "Healthy": return .good
        case "Progressing": return .warning
        case "Degraded", "Missing": return .bad
        default: return .neutral
        }
    }
}

struct StatusBadge: View {
    enum Kind {
        case good, warning, bad, neutral

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .bad: return .red
            case .neutral: return .secondary
            }
        }
    }

    let text: String
    let kind: Kind

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(kind.color)
    }
}
