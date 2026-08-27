import SwiftUI
import AppKit

struct MenuBarIconView: View {
    @Bindable var store: StatusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(.primary)

            if let statusColor = badgeColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 1)
                    }
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            Button("Settings…") {
                openSettings()
            }

            Button("Refresh") {
                Task { await store.refresh() }
            }
            .disabled(store.isLoading)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var badgeColor: Color? {
        switch store.aggregateStatus {
        case .healthy, .unknown:
            return nil
        case .warning:
            return .orange
        case .error:
            return .red
        case .unauthenticated:
            return .gray
        }
    }

    private var accessibilityLabel: String {
        switch store.aggregateStatus {
        case .healthy:
            return "ArgoCD, all apps healthy"
        case .warning:
            return "ArgoCD, some apps need attention"
        case .error:
            return "ArgoCD, some apps have errors"
        case .unauthenticated:
            return "ArgoCD, login required"
        case .unknown:
            return "ArgoCD"
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
