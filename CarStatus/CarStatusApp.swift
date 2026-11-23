import SwiftUI
import WidgetKit

@main
struct CarStatusApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onChange(of: phase) { _, new in
                    if new == .active { Task { await model.refresh() } }
                }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: Snapshot = Snapshot.cached ?? Snapshot()
    @Published var isRefreshing = false
    @Published var abrpRaw: String?
    @Published var kiaRaw: String?

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let result = await StatusStore.refresh()
        snapshot = result.snapshot
        abrpRaw = result.abrpRaw
        kiaRaw = result.kiaRaw
        isRefreshing = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}
