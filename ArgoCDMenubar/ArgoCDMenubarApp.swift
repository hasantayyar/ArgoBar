import SwiftUI

@main
struct ArgoCDMenubarApp: App {
    @State private var settings = AppSettings()
    @State private var store: StatusStore

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: StatusStore(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store, settings: settings)
                .onAppear {
                    store.startPolling()
                    Task { await store.refresh() }
                }
        } label: {
            MenuBarIconView(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("ArgoCD Settings", id: "settings") {
            SettingsView(settings: settings, store: store)
        }
        .defaultSize(width: 680, height: 580)
        .windowResizability(.contentSize)
    }
}
